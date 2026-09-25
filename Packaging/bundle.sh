#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift_command="${SWIFT:-swift}"
version="${VERSION:-0.0.0}"
configuration="${CONFIGURATION:-release}"
identity="${CODE_SIGN_IDENTITY:--}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be a numeric major.minor.patch version" >&2
    exit 1
fi

if [[ -z "${BIN_DIR:-}" ]]; then
    args=(-c "$configuration")
    read -r -a architectures <<< "${ARCHS:-arm64 x86_64}"
    for architecture in "${architectures[@]}"; do args+=(--arch "$architecture"); done
    "$swift_command" build "${args[@]}"
    bin_dir=$("$swift_command" build "${args[@]}" --show-bin-path)
else
    # Explicit prebuilt products, used by release CI after its universal build.
    bin_dir="$BIN_DIR"
fi
test -x "$bin_dir/convey"
test -x "$bin_dir/convey-app"
test -d "$bin_dir/Convey_ConveyCore.bundle"
test -s Packaging/Convey.icns

mkdir -p .build
stage=$(mktemp -d .build/bundle.XXXXXX)
app="$stage/Convey.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/convey-app" "$bin_dir/convey" "$app/Contents/MacOS/"
cp -R "$bin_dir/Convey_ConveyCore.bundle" "$app/Contents/Resources/"
cp Packaging/Convey.icns "$app/Contents/Resources/"
sed "s/@VERSION@/$version/g" Packaging/Info.plist > "$app/Contents/Info.plist"
if [[ -n "${BUNDLE_ID:-}" ]]; then  # dev builds: separate identity for TCC, Launch Services and Login Items
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$app/Contents/Info.plist"
fi
if [[ -n "${APP_NAME:-}" ]]; then
    plutil -replace CFBundleName -string "$APP_NAME" "$app/Contents/Info.plist"
    plutil -replace CFBundleDisplayName -string "$APP_NAME" "$app/Contents/Info.plist"
fi
plutil -lint "$app/Contents/Info.plist"

signing=(--force --sign "$identity")
# Timestamp + hardened runtime are for Developer ID/notarization; a local self-signed identity skips them.
if [[ "$identity" == "Developer ID"* ]]; then signing+=(--timestamp --options runtime); fi
codesign "${signing[@]}" "$app/Contents/MacOS/convey"
codesign "${signing[@]}" "$app"
codesign --verify --deep --strict "$app"

# New bundle is already signed and verified; replace in place. Backups would each
# register with LaunchServices and show up as duplicate "Convey" apps in System Settings.
rm -rf Convey.app
mv "$app" Convey.app
rmdir "$stage"
# Same bundle id as an installed Convey but a different signature: if LaunchServices knows
# this copy, System Settings may record the Screen Recording grant against it, and the
# installed app then fails TCC's code-requirement check on every launch. `open` re-registers it.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/Convey.app" 2>/dev/null || true
echo "Built Convey.app ($version), signing identity: $identity"
