# Deployment

The local candidate is version **0.2.0**, prepared after the existing `v0.1.0`
tag. Preparing it does not create a tag, commit, or public release.

## Local build and verification

```sh
swift test
make bundle VERSION=0.2.0
make verify-bundle
make archive
```

The default release build contains Apple Silicon and Intel executables. The
packager validates the staged signature before replacing `Convey.app`, retaining
the old bundle beneath `.build/previous-bundle.*`. Explicit `BIN_DIR` skips the
build and must point at freshly built products. `make run` instead creates a
native-architecture debug bundle and opens it.

`Packaging/Convey.icns` includes 16, 32, 128, 256, and 512-point artwork at 1×/2×.
The vector source is `Packaging/GenerateIcon.swift`; regenerate with `make icon`.
The PNG in Packaging is a preview, not an additional runtime dependency.

## Permissions and install identity

Install and launch `/Applications/Convey.app`, then grant Screen Recording in
System Settings. The bundle declares `com.jverhoeks.convey` and `Convey.icns` so
macOS can resolve its app name/icon. A bare `swift run convey-app` process can
be attributed to a terminal or development host instead. Existing permission
entries may refer to an old path or cached icon; the bundle change does not
rewrite the user's TCC database. Confirm the installed app in System Settings
and follow macOS's restart prompt if shown.

Enable start on login after moving the bundle to its final path. The LaunchAgent
records that executable path; re-enable it if you later move the app.

## Signing and public release

No usable code-signing identities were found on the preparation machine. The
candidate and default CI release are **ad-hoc signed, not notarized**. This is
suitable for local testing, not a completed Gatekeeper-compatible public release.

With a Developer ID Application certificate installed:

```sh
make bundle VERSION=0.2.0 CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
make verify-bundle
make archive
xcrun notarytool submit dist/Convey-0.2.0-macos-universal.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple Convey.app
xcrun stapler validate Convey.app
spctl --assess --type execute --verbose Convey.app
make archive
```

Do not distribute until notarization is accepted. Re-archiving after stapling
ensures the ZIP and checksum include the ticket. The signing branch enables
hardened runtime and timestamps; Developer ID/notary credentials and a notarized
build still require validation on a configured release machine. The GitHub
workflow does not yet import a signing certificate or submit to notarization.

Apple references: [Developer ID](https://developer.apple.com/developer-id/),
[notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Manual release checks

- Capture full-screen, area, and window; cancel and retry; test Retina and an
  external display. Verify output dimensions and absence of overlay lines.
- Open text/Markdown/HTML and image editors. Edit, blur, highlight, undo/redo,
  copy, and save; check the exported image at full resolution.
- OCR a real screenshot; verify empty images produce an error.
- Remove an entry, restart, and confirm it stays removed.
- Check the installed app icon in Finder and Screen Recording settings.
- Verify login launch from the installed path on next login.

Automated tests cover conversion, OCR, history, editor state, annotation pixels,
drag geometry, and basic native window construction. They do not replace the
physical-display, System Settings, or login checks above.
