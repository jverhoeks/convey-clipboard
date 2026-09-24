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
plutil -lint "$app/Contents/Info.plist"

signing=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then signing+=(--timestamp --options runtime); fi
codesign "${signing[@]}" "$app/Contents/MacOS/convey"
codesign "${signing[@]}" "$app"
codesign --verify --deep --strict "$app"

# Keep the previous local build recoverable until the new bundle is verified.
if [[ -e Convey.app ]]; then
    backup=$(mktemp -d .build/previous-bundle.XXXXXX)
    mv Convey.app "$backup/Convey.app"
    echo "Previous bundle preserved at $backup/Convey.app"
fi
mv "$app" Convey.app
rmdir "$stage"
echo "Built Convey.app ($version), signing identity: $identity"
