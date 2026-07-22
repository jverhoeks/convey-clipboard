# Convey

Smart clipboard format conversion for macOS — read whatever is on the
clipboard, detect its format, and rewrite it into the format you need.

This repository (Plan 1) ships:

- **ConveyCore** — a headless Swift package: flavor detection, a composable
  conversion graph, and converters for HTML↔Markdown, RTF→Markdown,
  image→base64 data-URI, and Mermaid→SVG/PNG.
- **convey** — a CLI over the core.

The menu-bar app (history, hotkey, picker UI) is Plan 2.

## CLI usage

    convey list                     # show detected flavors + valid targets
    convey html2md                  # clipboard HTML -> Markdown -> clipboard
    echo '<b>hi</b>' | convey html2md   # stdin -> stdout
    convey md2html
    convey rtf2md
    convey img2b64
    convey mmd2svg | convey mmd2png
    convey version                  # print the convey version

## Menu-bar app (Plan 2)

Run: `swift run convey-app`

A menu-bar ⇄ icon opens a visual clipboard list. Each entry shows a type
badge, a preview (text snippet / image thumbnail), and the valid convert
options for that entry — click one to rewrite the clipboard, then ⌘V. Press
⌥⌘V to open the picker from anywhere. History persists across launches;
password-manager entries (concealed/transient) are never captured.

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
publishes a `tar.gz` + `sha256` checksum to GitHub Releases.

Cut a release by bumping the semver tag (computed from the latest `v*` tag)
and pushing it:

    make patch      # v0.1.0 -> v0.1.1
    make minor      # v0.1.0 -> v0.2.0
    make major      # v0.1.0 -> v1.0.0
    make next-version   # preview the next versions without tagging

Or tag manually:

    git tag v1.2.3 && git push origin v1.2.3

The binaries are unsigned — after downloading, clear the quarantine
attribute before running them:

    xattr -d com.apple.quarantine convey convey-app

A signed/notarized `.app` bundle is future work.
