# Design: clipboard type filter bar

Date: 2026-07-23

## Overview

Add a multi-select type filter to the top of the menu-bar clipboard picker so
the user can narrow the history to **HTML**, **Text**, or **Image** entries.
The filter is pure view state over the existing `history.entries` — no
persistence, no changes to capture/storage.

## Categories

Every `ClipboardKind` maps to exactly one of three categories:

| Category | ClipboardKinds |
|----------|----------------|
| HTML     | `.html`        |
| Text     | `.plainText`, `.rtf`, `.markdown`, `.mermaid` |
| Image    | `.image`       |

(rtf counts as Text, per the request. Markdown and Mermaid are text-based and
also land in Text, so there is no "Other" bucket — three categories cover all
kinds.)

## 1. `EntryCategory` (new, pure, in ConveyKit)

```swift
public enum EntryCategory: String, CaseIterable, Sendable {
    case html, text, image
}
```

- `public var label: String` — display label: `HTML` / `Text` / `Image`.
- `public static func of(_ kind: ClipboardKind) -> EntryCategory` — the mapping
  table above. Total over all `ClipboardKind` cases (exhaustive switch, no
  `default`).
- `public static func filter(_ entries: [ClipboardEntry], selected: Set<EntryCategory>) -> [ClipboardEntry]`
  — if `selected` is empty, return `entries` unchanged (empty = show all);
  otherwise keep entries whose `EntryCategory.of(entry.kind)` is in `selected`.
  Order preserved. Pure and unit-testable.

## 2. Chip bar in `PickerView`

- A horizontal row of three toggle chips (**HTML / Text / Image**) placed
  between the header row (`Convey` title + `Clear All`) and the `Divider`.
- State: `@State private var selected: Set<EntryCategory> = []` — ephemeral,
  resets on each launch, not persisted.
- Each chip is a capsule button: filled/tinted (accent) with primary-contrast
  text when active, subtle outline/secondary when inactive. Tapping toggles the
  category's membership in `selected`.
- The list renders `EntryCategory.filter(history.entries, selected: selected)`
  instead of `history.entries` directly.
- Empty states:
  - history empty → existing "Clipboard history is empty…" message (unchanged).
  - history non-empty but filtered result empty → "No items match the filter."

## 3. No other files change

`AppDelegate` and `EntryRowView` are untouched. The filter is entirely view
state in `PickerView` derived from the existing `history.entries`.

## 4. Testing

- `EntryCategory.of(_:)` — all six `ClipboardKind` cases map to the correct
  category (pure unit test), including rtf/markdown/mermaid → `.text`.
- `EntryCategory.filter(_:selected:)` — empty set returns all; single category
  filters correctly; multi-category is a union; order preserved.
- Chip toggle visuals and layout — build + manual smoke test.

## Out of scope

- No per-chip counts (e.g. "HTML 3").
- No persisted filter selection across launches.
- No "Other" category, no search-text field.
- No changes to clipboard capture, conversion, save, or delete.
