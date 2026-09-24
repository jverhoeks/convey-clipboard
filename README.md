# Convey

<img src="Packaging/Convey.png" width="96" alt="Convey icon">

Smart clipboard format conversion for macOS — read whatever is on the
clipboard, detect its format, and rewrite it into the format you need.

This repository ships:

- **ConveyCore** — a headless Swift package: flavor detection, a composable
  conversion graph, and converters for HTML↔Markdown, RTF→Markdown,
  image→text (on-device OCR), image→base64 data-URI, and Mermaid→SVG/PNG.
- **convey** — a CLI over the core.
- **Convey.app** — a menu-bar clipboard history, screenshot tool, and editor.

## CLI usage

    convey list                     # show detected flavors + valid targets
    convey html2md                  # clipboard HTML -> Markdown -> clipboard
    echo '<b>hi</b>' | convey html2md   # stdin -> stdout
    convey md2html
    convey rtf2md
    convey img2b64
    convey mmd2svg
    echo 'graph TD; A-->B' | convey mmd2png > diagram.png
    convey version                  # print the convey version

## Menu-bar app

Run: `make run`. It rebuilds the app, quits an older instance launched from this
checkout, and opens the fresh bundle so macOS sees the Convey icon and bundle
identity in permission UI.

<img src="docs/images/history.png" width="380" alt="Clipboard history. Rows show a type badge, a preview, remove, and an actions menu. A Mermaid diagram is rendered in place, and a credential is concealed.">

A menu-bar ⇄ icon opens a visual clipboard list. Each entry shows a type
badge, a preview (text snippet / image thumbnail), and the valid convert
options for that entry — click one to rewrite the clipboard, then ⌘V. Press
⌥⌘V to open the picker from anywhere. History persists across launches;
password-manager entries (concealed/transient) are never captured.
The circled × beside a row's type label removes that entry and persists the change.

Screenshots (Greenshot-style): ⇧⌘0 full screen, ⇧⌘1 area, ⇧⌘2 then click a window
(Escape cancels). The PNG
is saved to `~/Pictures/Convey/Convey yyyy-MM-dd HH_mm_ss-<uuid>.png` and put on the
clipboard (so it lands in history too). The gear in the picker opens
Preferences: rebind hotkeys, filename prefix, folder, copy/save toggles,
start on login (LaunchAgent), and a button to grant Screen Recording.

<img src="docs/images/preferences.png" width="440" alt="Preferences: start on login, global hotkeys, and where screenshots are copied and saved.">

Area capture uses a crosshair cursor with horizontal/vertical guides. Drag in
any direction and release to capture; Escape cancels. Selections stay within
the display where the drag started.

<img src="docs/images/area-capture.png" width="720" alt="Area capture. Crosshair guides follow the pointer, and the dragged rectangle stays undimmed.">

Each history row has a ⋯ menu: convert the clipboard, save as any target
format, or open in the default app. Entries that look like credentials
(`sk-…`, `ghp_…`, AWS keys, private keys, JWTs, `TOKEN=…`) are masked, need
Touch ID / password to reveal, and are never written to disk.

For images, choose **Convert clipboard to → Text** to copy recognized text, or
**Save as… → Text (.txt)** to save it. OCR runs on demand, locally with Apple's
Vision framework; no extra model download or automatic background scanning.
The original image stays in history. Images without readable text report an
error without replacing the clipboard or writing an empty text file.

Click an entry's text or image to open the built-in editor (also available as
**Edit…** in its menu). Text, Markdown, and HTML are edited as source with native
undo/redo. For images, drag to blur, highlight, or draw a square, circle, or arrow;
click to place text. The color well sets the color, and Fill paints a square, circle,
or the background behind text. Click a shape and drag a
corner to resize it, or press Delete. Undo and redo are in the toolbar.
**Copy to Clipboard** and **Save As…**
export the edited result in the selected format, including image OCR to text.
Image annotations are flattened into the exported full-resolution PNG. The
original history entry remains unchanged; closing with unexported edits asks
before discarding them. RTF entries open as plain text for editing.

<img src="docs/images/editor-text.png" width="720" alt="Markdown editor. Edit the source, then copy or save it as Markdown, HTML, or plain text.">

<img src="docs/images/editor-image.png" width="720" alt="Image editor. Blur and highlight are painted onto the image, then copied or saved.">

### Install

```bash
brew install --cask --no-quarantine jverhoeks/tap/convey   # Convey.app + `convey` CLI
```

Or build it yourself: `make bundle VERSION=0.2.0` produces an ad-hoc signed,
universal `Convey.app` (menu-bar app, CLI, icon, and the ConveyCore resource bundle).
It rebuilds from current sources; `BIN_DIR` is only for explicitly supplied
prebuilt products. `make verify-bundle` checks it; `make archive` creates a ZIP
and SHA-256 checksum under `dist/`. Install the app in `/Applications` before
granting permissions or enabling start on login. Releases are cut with
`make patch|minor|major`; afterwards `make cask` regenerates the cask in the
sibling `homebrew-tap` checkout.

### Known limitations / follow-ups

- Mermaid rows render the diagram as a PNG preview (via `Mermaid → PNG`),
  loaded asynchronously per row; the diagram source text is shown briefly
  until the render completes (first render may take a moment while the
  WebKit-backed engine warms up). Once rendered, the image is memoized in a
  persistent `PreviewCache` keyed by entry id, so scrolling a row off/on
  screen in the picker's `LazyVStack` reuses the cached image instead of
  re-decoding a thumbnail or re-rendering the diagram.

## Build & test

    swift build
    swift test

Requires macOS 13+ and a window server session (WebKit-backed conversions).

## Releases

Pushing a `v*` tag triggers a GitHub Actions workflow that builds a universal
(arm64 + x86_64) release of `convey` and `convey-app`, stamps in the tag's
version (`convey version` / `convey --version` / `convey -v` prints it), and
publishes a `.zip` + `.sha256` checksum to GitHub Releases. Tests must pass before
packaging. Both architectures, bundle resources, icon, version, and signatures
are verified before publication.

Cut a release by bumping the semver tag (computed from the latest `v*` tag)
and pushing it:

    make patch      # v0.1.0 -> v0.1.1
    make minor      # v0.1.0 -> v0.2.0
    make major      # v0.1.0 -> v1.0.0
    make next-version   # preview the next versions without tagging

Or tag manually:

    git tag v1.2.3 && git push origin v1.2.3

Local bundles and the current CI release use ad-hoc signing, not Developer ID
notarization. For public Gatekeeper-compatible distribution, build with
`CODE_SIGN_IDENTITY="Developer ID Application: …"`, notarize with Apple, staple
the ticket, and then create the archive. See [deployment notes](docs/deployment.md).
