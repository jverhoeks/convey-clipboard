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
packager validates the staged signature before replacing `Convey.app` in place
(no backup copies: each would register as a duplicate "Convey" with macOS). Explicit `BIN_DIR` skips the
build and must point at freshly built products. `make run` instead creates a
native-architecture debug bundle and opens it.

`Packaging/Convey.icns` includes 16, 32, 128, 256, and 512-point artwork at 1×/2×.
The vector source is `Packaging/GenerateIcon.swift`; regenerate with `make icon`.
The PNG in Packaging is a preview, not an additional runtime dependency.

## Permissions and install identity

Install and launch `/Applications/Convey.app`, then grant Screen Recording in
System Settings. The bundle declares `org.verhoeks.convey` and `Convey.icns` so
macOS can resolve its app name/icon. A bare `swift run convey-app` process can
be attributed to a terminal or development host instead. Existing permission
entries may refer to an old path or cached icon; the bundle change does not
rewrite the user's TCC database. Confirm the installed app in System Settings
and follow macOS's restart prompt if shown.

Start on login registers Convey.app as a Login Item (`SMAppService`), so it
follows the app if moved. Toggling it removes the `convey-app.plist`
LaunchAgent written by older builds. Settings from the old
`com.jverhoeks.convey` domain are copied over on first launch.

Ad-hoc signatures change with every build, so macOS forgets the Screen Recording
and menu-bar grants after each rebuild. A Developer ID signature fixes this.

## Signing and public release

No usable code-signing identities were found on the preparation machine. The
candidate and default CI release are **ad-hoc signed, not notarized**. This is
suitable for local testing, not a completed Gatekeeper-compatible public release.

With a Developer ID Application certificate installed, locally:

```sh
xcrun notarytool store-credentials convey   # one-time: Apple ID, team ID, app-specific password
make bundle VERSION=0.2.0 CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
make verify-bundle
make notarize          # submit, staple, spctl-assess, then re-archive into dist/
```

The signing branch enables hardened runtime and secure timestamps. No
entitlements are required (ScreenCaptureKit, WKWebView, Carbon hotkeys, Vision;
no sandbox).

In CI, add these repository secrets and tagged releases are signed, notarized
and stapled automatically; without them the release stays ad-hoc:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12` | `base64 -i DeveloperID.p12` (certificate + private key) |
| `DEVELOPER_ID_P12_PASSWORD` | export password of that .p12 |
| `APPLE_ID` | Apple ID email |
| `APPLE_TEAM_ID` | 10-character team ID |
| `APPLE_APP_PASSWORD` | app-specific password from appleid.apple.com |

Once releases are notarized, drop the quarantine caveat from
`Packaging/convey.rb.tmpl` and the `--no-quarantine` install hint in the README.

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
