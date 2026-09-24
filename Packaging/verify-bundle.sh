#!/bin/bash
set -euo pipefail
app="${1:-Convey.app}"
plist="$app/Contents/Info.plist"
plutil -lint "$plist"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")" = com.jverhoeks.convey
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$plist")" = Convey.icns
test -s "$app/Contents/Resources/Convey.icns"
resources="$app/Contents/Resources/Convey_ConveyCore.bundle"
# SwiftPM can emit flat bundles or Contents/Resources bundles depending on toolchain.
if [[ -d "$resources/Contents/Resources" ]]; then resources="$resources/Contents/Resources"; fi
for name in runtime.html bridge.js mermaid.min.js marked.min.js turndown.js; do
    test -s "$resources/web/$name"
done
for executable in convey convey-app; do
    test -x "$app/Contents/MacOS/$executable"
    for architecture in arm64 x86_64; do
        lipo "$app/Contents/MacOS/$executable" -verify_arch "$architecture"
    done
done
test "$("$app/Contents/MacOS/convey" version)" = "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")"
codesign --verify --deep --strict "$app"
echo "Verified universal bundle, version, icon, web resources, and code signatures."
