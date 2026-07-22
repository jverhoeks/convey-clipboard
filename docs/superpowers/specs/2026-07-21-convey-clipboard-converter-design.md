# Convey — Clipboard Format Converter (Design)

**Date:** 2026-07-21
**Status:** Approved design, pending spec review → implementation plan
**Working name:** Convey *(placeholder — rename freely)*

## Summary

A macOS menu-bar app plus a CLI that reads whatever is on the clipboard,
detects its format, and rewrites it into the format you actually need to
paste. Canonical use case: copy rich content from Confluence (which lands on
the clipboard as HTML), convert it to Markdown, and paste it as plain text
anywhere.

The product is one headless conversion engine (`ConveyCore`, a Swift package)
consumed by two thin frontends: a SwiftUI/AppKit menu-bar app and a `convey`
CLI. Neither frontend knows how to convert — they only call the core.

macOS first; Windows is deliberately deferred (accepted cost of choosing a
native Swift stack for best-in-class `NSPasteboard` access and paste UX).

## The core loop

```
copy in Confluence
  → clipboard holds: public.html (rich) + public.utf8-plain-text (fallback)
  → Convey reads the HTML flavor
  → converts HTML → Markdown
  → writes Markdown back as public.utf8-plain-text
  → user presses ⌘V into any target as text
```

Everything else (history, more formats, auto-detect) hangs off this loop.

## Architecture — one engine, three faces

```
┌───────────────────────────────────────────────┐
│  ConveyCore  (Swift package, headless, no UI)   │
│   • PasteboardReader   UTI → logical type       │
│   • ConversionGraph    registry of edges + paths│
│   • Converter protocol one unit per edge        │
│   • PasteboardWriter   result → NSPasteboard    │
│   • WebRuntime         hidden WKWebView (JS)     │
└───────────────────────────────────────────────┘
        ▲                    ▲                 ▲
        │                    │                 │
   Menu-bar app          CLI (convey)      Unit tests
   (SwiftUI+AppKit)    stdin/stdout/clip   golden files
```

### ConveyCore units

- **PasteboardReader** — snapshots `NSPasteboard`, enumerates available flavors
  (UTIs), maps them to logical source types via a lookup table.
- **ConversionGraph** — a registry of edges (`sourceType → targetType →
  Converter`). Given the detected source type(s), it computes the set of valid
  targets, and can find multi-hop paths (see composition below).
- **Converter** (protocol) — one unit per edge. `func convert(_ input) throws
  -> Output`. Implementations are either pure Swift or delegate to WebRuntime.
- **PasteboardWriter** — writes the result back to `NSPasteboard` in the
  correct flavor (e.g. Markdown written as `public.utf8-plain-text`).
- **WebRuntime** — a hidden `WKWebView` hosting bundled JS libraries; used by
  the heavy conversion edges.

## Conversion runtime — the load-bearing decision

Converters split into two kinds:

- **Pure Swift** for trivial/native edges:
  - *Any → Plain text* (strip formatting)
  - *Image → base64 / data-URI*
  - *RTF → HTML* via `NSAttributedString` (macOS reads RTF and emits HTML
    natively — free)
- **JS-in-a-hidden-`WKWebView`** (WebRuntime) for the heavy, well-solved edges,
  reusing the same libraries Lucent already trusts:
  - *HTML → Markdown* via `turndown.js`
  - *Markdown → HTML* via `marked.js`
  - *Mermaid → SVG / PNG / other targets* via `mermaid.js`

**Consequence — edges compose.** `RTF → Markdown` is not a bespoke converter;
it is the path `RTF → HTML` (Swift/AppKit) → `HTML → Markdown` (turndown). The
ConversionGraph finds the path. This keeps the converter set small and
orthogonal.

Rejected: bundling Pandoc (≈150 MB, GPL, external-process friction — wrong fit
for a lightweight sandboxable menu-bar app).

## Flavor detection — the "many formats" concern

A lookup table maps clipboard flavors to logical source types:

| Clipboard flavor (UTI)          | Logical type                    |
|---------------------------------|---------------------------------|
| `public.html`                   | html                            |
| `public.rtf`                    | rtf                             |
| `public.utf8-plain-text`        | text (+ maybe **mermaid**)      |
| `public.png` / `public.tiff`    | image                           |

The graph computes valid targets from the detected source(s). **Mermaid**
appears as a target when clipboard text *looks* like Mermaid (starts with
`graph`, `flowchart`, `sequenceDiagram`, `classDiagram`, etc.) — offered, never
forced.

Adding a new format = a new table row plus new edge(s). **v1 does not need a
large catalog**; the catalog grows incrementally, each edge independently
testable.

## v1 conversion catalog

- HTML → Markdown
- Any → Plain text (strip formatting)
- RTF → Markdown (via RTF → HTML → Markdown)
- Markdown → HTML (paste rich back into Confluence/email)
- Image → base64 / data-URI
- Mermaid → SVG, PNG, and Lucent's other targets (Excalidraw / whiteboard /
  Atlassian JSON)

## Interaction & history

- **Triggers (both, sharing one picker):**
  - Menu-bar `NSStatusItem` (`LSUIElement`, no dock icon) — click to open.
  - Global hotkey **⌥⌘V** — opens the same picker panel.
- **Picker panel:** current clipboard at the top with its valid conversions,
  then a scrollable **history** of recent copies. Any past item can be
  converted, not just the current one.
- **History store:** capped ring buffer (count + total-size limits), persisted
  to Application Support, with a clear-on-quit option.
- **Privacy:** honor the `org.nspasteboard.ConcealedType` and
  `org.nspasteboard.TransientType` conventions (nspasteboard.org). Password
  managers mark clipboard items concealed/transient; Convey **skips storing**
  those.
- **Permissions:** **no Accessibility permission required in v1** — Convey
  writes to the clipboard and the user presses ⌘V. (Auto-paste, which *would*
  require Accessibility, is deliberately v2.)

## CLI

`convey` reads the clipboard or stdin and writes the clipboard or stdout:

```
convey html2md            # current clipboard HTML → Markdown, back to clipboard
convey html2md < in.html  # stdin → stdout
convey list               # show detected flavors + valid targets
```

**Known v1 limit:** the HTML/MD/Mermaid edges need WebRuntime, which wants an
app run-loop. The CLI can spin up an offscreen `WKWebView`; if that proves
painful, **v1 CLI ships the pure-Swift + AppKit edges and defers the JS ones**,
documented as a known limit.

## Icon

A two-way arrow motif (**⇄ / ⟷**), rendered as a monochrome template image
(SF Symbol style, e.g. `arrow.left.arrow.right`) so it adapts to menu-bar
light/dark automatically.

## Testing

- ConveyCore is headless → **golden-file unit tests** per edge: real Confluence
  HTML fixture → expected Markdown; RTF samples; Mermaid samples.
- Flavor detection tested against synthetic `NSPasteboard` contents.
- WebRuntime edges tested via async integration tests.

## Non-goals (v1)

- Windows support (deferred; documented tradeoff of the native-Swift choice).
- Auto-paste / simulated ⌘V (v2; requires Accessibility permission).
- A large conversion catalog (grows incrementally after the v1 set).

## Open items

- Final product name.
- Repo location: new standalone repo vs. sub-project inside Lucent.
- Final app-icon asset.
- CLI Mermaid support (offscreen `WKWebView`) vs. documented deferral.
