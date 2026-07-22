# Design: Save clipboard item + row actions (hover, delete)

Date: 2026-07-22

## Overview

Add three related enhancements to the menu-bar clipboard picker, all on the
`EntryRowView`:

1. **Save to file** — per-format download icons that export a clipboard item to
   disk (PNG, HTML, Markdown, plain text, and — free from the conversion graph —
   SVG, RTF, and Mermaid `.mmd`).
2. **Hover highlight** — a shared button style so every row action (convert,
   save, delete) lights up on mouseover.
3. **Per-item delete** — a trash icon to remove a single entry from history.

These reuse the existing `Convey.graph` conversion engine and follow the
established closure-based wiring between `EntryRowView` and `AppDelegate`
(`onConvert`).

## 1. Savable formats

### Rule

For an entry, the savable formats are its **native format (`primaryFormat`) plus
everything `graph.validTargets(from:)` can reach**, filtered to formats that map
to a real file type. `validTargets` is transitive (BFS), so no manual chaining is
needed. `base64DataURI` is excluded (it is a text encoding, not a file).

### Resulting per-kind options

| Item kind  | Save options              |
|------------|---------------------------|
| Image      | PNG                       |
| HTML       | HTML, MD, TXT             |
| RTF        | RTF, HTML, MD, TXT        |
| Markdown   | MD, HTML, TXT             |
| Mermaid    | Mermaid (`.mmd`), SVG, PNG|
| Plain text | TXT                       |

Decision: keep SVG/RTF/`.mmd` — they are produced by the graph at no extra cost.

### Image PNG caveat

Image bytes are stored as `public.png` when available, else `public.tiff`
(`PasteboardReader.payload(for: .image)`). There is **no `image → png` converter**
in the graph. So "Save as PNG" for an image entry:

- If the stored bytes are already PNG → write them directly.
- If TIFF → transcode TIFF→PNG via `NSBitmapImageRep` before writing.

## 2. `ExportFormat` helper (new, pure, in ConveyKit)

A small value type that isolates all file-type knowledge and is unit-testable
without any UI or AppKit save panel.

```swift
public struct ExportFormat: Equatable, Sendable {
    public let format: Format      // e.g. .html, .png
    public let label: String       // e.g. "HTML", "PNG"
    public let fileExtension: String  // e.g. "html", "png"
    public let utTypeIdentifier: String // e.g. "public.html", "public.png"
    public let isText: Bool        // text payload vs. bytes
}
```

- `static func fileType(for: Format) -> ExportFormat?` — the mapping table.
  Returns `nil` for non-file formats (`base64DataURI`; `image` maps to the PNG
  entry). Text formats: html, markdown (`md`), plainText (`txt`), mermaid
  (`mmd`), svg. Byte formats: png, rtf.
- `static func options(nativeFormat: Format, reachable: [Format]) -> [ExportFormat]`
  — dedups `[nativeFormat] + reachable`, filters through `fileType(for:)`,
  returns a stable ordered list (native first, then reachable in graph order).
  The `image` native format resolves to the PNG `ExportFormat`.

`EntryRowView` computes its save icons from `options(nativeFormat:reachable:)`,
where `reachable` comes from the same `graph.validTargets` call already used for
the convert buttons (passed in from `AppDelegate`).

## 3. Save flow (`AppDelegate.save(_:to:)`)

Mirrors the existing `convert(_:to:)`:

1. Guard `entry.payload`.
2. Produce export bytes/text:
   - If `target == entry.primaryFormat`: use the payload directly. For an image
     target, ensure PNG (transcode from TIFF if needed).
   - Else: `graph.convert(payload, from: primaryFormat, to: target)`.
   - Special case image→PNG (no graph edge): transcode the stored image bytes.
3. Present `NSSavePanel` with `allowedContentTypes = [UTType(exportFormat)]` and a
   suggested filename `Convey-<LABEL>-<yyyy-MM-dd-HHmm>.<ext>`.
4. On confirm, write text (`String.write(to:)`) or bytes (`Data.write(to:)`).
5. On any failure: `NSSound.beep()` (matches existing convert error handling).

The `NSSavePanel` interaction and transcode live in `AppDelegate` (AppKit,
main actor). `EntryRowView` only invokes `onSave(entry, format)`.

## 4. Hover highlight (`RowActionButtonStyle`, new)

A reusable `ButtonStyle` adopted by all row action buttons (convert, save,
trash). Its `makeBody` returns a small view holding `@State private var
hovering` updated via `.onHover`. On hover: a subtle background fill + brighter
foreground; the cursor becomes `.pointingHand`. The trash button passes a red
tint variant.

This replaces the current bare `.borderless` styling on the convert buttons so
all row controls behave consistently.

## 5. Per-item delete

- `HistoryStore.remove(id: UUID)` — removes the matching entry from `entries`.
  Pure list op, unit-testable.
- `EntryRowView` gains `onDelete: (ClipboardEntry) -> Void`.
- The delete control is the **circular close button (`xmark` in a circle)** in the
  card's top-right corner (see Visual design), styled with `RowActionButtonStyle`.
  It is normally dim and brightens on hover.
- `AppDelegate` implements delete: `history.remove(id:)`, then persist the new
  snapshot on the existing `saveQueue` (same pattern as `pollClipboard`).
- No confirmation dialog — deleting a history entry is low-stakes and cheap.

## 6. Visual design (notification-card style)

Restyle each row as an elevated notification-style card, modeled on the macOS
Notification Center list.

**Card**
- Rounded rectangle, `cornerRadius: 10`, generous inner padding (~12–14).
- Elevated fill that respects light/dark mode: `.background(.quaternary)` /
  `Color(nsColor: .controlBackgroundColor)` with a hairline border
  (`.stroke(.separator)` at low opacity) for definition against the popover.
- Card spacing ~8–10 in the `LazyVStack`.

**Header row**
- Left: the kind badge as a bold **title** (e.g. **HTML**, **Image**).
- Right: a timestamp caption from `createdAt`, formatted `HH:mm` (secondary
  color).
- Far right: the circular **×** close button (delete), dim → bright on hover.

**Body**
- Preview text (secondary color, `lineLimit(2)`) or the image thumbnail, as today.

**Footer (source caption)**
- A small uppercase caption showing the detected source formats joined, e.g.
  `HTML · TEXT` — the analogue of the "CONVEY"/"SQE" source label in the
  reference. Purely informational; omit if `sources` is a single format equal to
  the badge.

**Action rows** (below the body/footer)
- Convert buttons (`→ markdown`, …) and save icons (`⤓MD`, …), all using
  `RowActionButtonStyle` so they light up on hover.

**Top bar**
- Keep the "Convey" title; restyle the existing `Clear` button as a pill labeled
  **Clear All** on the right (matching the reference's "Clear All").

### Layout mockup

```
┌───────────────────────────────────────────┐
│  HTML                        21:57    ( × ) │   title · time · delete
│  preview text / image thumbnail…            │
│  HTML · TEXT                                │   source caption
│  → markdown   → plainText                   │   convert (hover)
│  ⤓MD  ⤓HTML  ⤓TXT                           │   save (hover)
└───────────────────────────────────────────┘
```

## 7. Testing

- `ExportFormat.fileType(for:)` and `.options(nativeFormat:reachable:)` — pure
  unit tests: correct extensions/UTTypes, `base64DataURI` excluded, image→PNG
  resolution, native-first ordering, per-kind option sets.
- TIFF→PNG transcode — unit test on bytes (valid TIFF in → PNG magic bytes out).
- `HistoryStore.remove(id:)` — unit test (removes correct entry, no-op on unknown
  id, leaves others intact).
- Conversions themselves — already covered by existing `ConversionGraph` /
  converter tests; not duplicated.
- `NSSavePanel` interaction and `RowActionButtonStyle` visuals — manual/UI, not
  unit-tested.

## Out of scope

- No sync / cloud / mobile (tracked separately).
- No batch/multi-select save or delete.
- No "reveal in Finder" or default-location preference — always via save panel.
- No delete confirmation dialog.
