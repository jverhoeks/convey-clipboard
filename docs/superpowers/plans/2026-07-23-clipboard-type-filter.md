# Clipboard Type Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a multi-select HTML / Text / Image chip filter to the top of the clipboard picker.

**Architecture:** A new pure `EntryCategory` enum (ConveyKit) maps each `ClipboardKind` to one of three categories and filters entry lists. `PickerView` gains a chip row and ephemeral selection state, rendering the filtered list. No other files change.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI + AppKit, XCTest, macOS 13+.

## Global Constraints

- Swift tools version: 5.9; platform floor: macOS 13.
- Tests use **XCTest** (not swift-testing). ConveyKit tests live in `Tests/ConveyKitTests`, use `@testable import ConveyKit` and `import ConveyCore`.
- `ClipboardKind` cases: `html, rtf, markdown, plainText, mermaid, image`. `ClipboardEntry` has `public let kind: ClipboardKind`.
- Category mapping is fixed: `.html → .html`; `.image → .image`; `.plainText/.rtf/.markdown/.mermaid → .text`.
- Empty selection set means "show all" (no filter).
- Filter is ephemeral view state — not persisted.
- Full build check: `swift build`. Test run for this branch: `swift test --filter ConveyKitTests`.

---

### Task 1: `EntryCategory` (mapping + filter)

**Files:**
- Create: `Sources/ConveyKit/EntryCategory.swift`
- Test: `Tests/ConveyKitTests/EntryCategoryTests.swift`

**Interfaces:**
- Consumes: `ClipboardKind`, `ClipboardEntry` (both ConveyKit).
- Produces:
  - `public enum EntryCategory: String, CaseIterable, Sendable { case html, text, image }`
  - `public var label: String`
  - `public static func of(_ kind: ClipboardKind) -> EntryCategory`
  - `public static func filter(_ entries: [ClipboardEntry], selected: Set<EntryCategory>) -> [ClipboardEntry]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ConveyKitTests/EntryCategoryTests.swift`:

```swift
import XCTest
import ConveyCore
@testable import ConveyKit

final class EntryCategoryTests: XCTestCase {
    private func entry(_ kind: ClipboardKind) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: [], kind: kind, primaryFormat: .plainText,
                       text: "x", imageData: nil, previewText: "x",
                       createdAt: Date(timeIntervalSince1970: 0))
    }

    func testOfMapping() {
        XCTAssertEqual(EntryCategory.of(.html), .html)
        XCTAssertEqual(EntryCategory.of(.image), .image)
        XCTAssertEqual(EntryCategory.of(.plainText), .text)
        XCTAssertEqual(EntryCategory.of(.rtf), .text)
        XCTAssertEqual(EntryCategory.of(.markdown), .text)
        XCTAssertEqual(EntryCategory.of(.mermaid), .text)
    }

    func testFilterEmptyReturnsAll() {
        let es = [entry(.html), entry(.image)]
        XCTAssertEqual(EntryCategory.filter(es, selected: []).count, 2)
    }

    func testFilterSingleCategory() {
        let es = [entry(.html), entry(.rtf), entry(.image)]
        let r = EntryCategory.filter(es, selected: [.text])
        XCTAssertEqual(r.map(\.kind), [.rtf])
    }

    func testFilterMultiCategoryUnionPreservesOrder() {
        let es = [entry(.html), entry(.plainText), entry(.image)]
        let r = EntryCategory.filter(es, selected: [.html, .image])
        XCTAssertEqual(r.map(\.kind), [.html, .image])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EntryCategoryTests`
Expected: FAIL — `cannot find 'EntryCategory' in scope`.

- [ ] **Step 3: Implement `EntryCategory`**

Create `Sources/ConveyKit/EntryCategory.swift`:

```swift
/// A coarse type bucket used by the picker's filter bar.
/// Every `ClipboardKind` maps to exactly one category.
public enum EntryCategory: String, CaseIterable, Sendable {
    case html, text, image

    public var label: String {
        switch self {
        case .html: return "HTML"
        case .text: return "Text"
        case .image: return "Image"
        }
    }

    /// Maps a `ClipboardKind` to its category. rtf/markdown/mermaid are Text.
    public static func of(_ kind: ClipboardKind) -> EntryCategory {
        switch kind {
        case .html: return .html
        case .image: return .image
        case .plainText, .rtf, .markdown, .mermaid: return .text
        }
    }

    /// Filters entries by selected categories. An empty selection returns all
    /// entries unchanged (empty = show all). Order is preserved.
    public static func filter(_ entries: [ClipboardEntry],
                              selected: Set<EntryCategory>) -> [ClipboardEntry] {
        guard !selected.isEmpty else { return entries }
        return entries.filter { selected.contains(of($0.kind)) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EntryCategoryTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/EntryCategory.swift Tests/ConveyKitTests/EntryCategoryTests.swift
git commit -m "feat: EntryCategory mapping and filter for picker type filter"
```

---

### Task 2: Chip filter bar in `PickerView`

**Files:**
- Modify: `Sources/ConveyApp/PickerView.swift`

**Interfaces:**
- Consumes: `EntryCategory` (Task 1). No change to `PickerView`'s initializer — the filter is internal `@State`, so `AppDelegate` needs no change.

This is UI. Verify with `swift build`, the ConveyKit test suite (no regressions), and a manual smoke test.

- [ ] **Step 1: Replace `PickerView` with the filtered version**

Replace the entire contents of `Sources/ConveyApp/PickerView.swift` with:

```swift
import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

struct PickerView: View {
    @ObservedObject var history: HistoryStore
    let targetsFor: (ClipboardEntry) -> [Format]
    let saveFormatsFor: (ClipboardEntry) -> [ExportFormat]
    let onConvert: (ClipboardEntry, Format) -> Void
    let onSave: (ClipboardEntry, Format) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let onClear: () -> Void
    let cache: PreviewCache

    @State private var selected: Set<EntryCategory> = []

    private var visibleEntries: [ClipboardEntry] {
        EntryCategory.filter(history.entries, selected: selected)
    }

    private func chip(_ category: EntryCategory) -> some View {
        let isOn = selected.contains(category)
        return Button {
            if isOn { selected.remove(category) } else { selected.insert(category) }
        } label: {
            Text(category.label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Convey").font(.headline)
                Spacer()
                Button("Clear All", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            HStack(spacing: 6) {
                ForEach(EntryCategory.allCases, id: \.self) { category in
                    chip(category)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if history.entries.isEmpty {
                        Text("Clipboard history is empty.\nCopy something to get started.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.top, 40)
                    } else if visibleEntries.isEmpty {
                        Text("No items match the filter.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.top, 40)
                    }
                    ForEach(visibleEntries) { entry in
                        EntryRowView(
                            entry: entry,
                            targets: targetsFor(entry),
                            saveFormats: saveFormatsFor(entry),
                            onConvert: onConvert,
                            onSave: onSave,
                            onDelete: onDelete,
                            cache: cache
                        )
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 380, height: 480)
    }
}
```

- [ ] **Step 2: Build and run the ConveyKit test suite**

Run: `swift build && swift test --filter ConveyKitTests`
Expected: Build succeeds; ConveyKit tests pass (including the new `EntryCategoryTests`), no regressions.

- [ ] **Step 3: Manual smoke test**

Run: `swift run convey-app`
Verify:
- Three chips (HTML / Text / Image) appear below the "Convey" header.
- With no chip active, all history entries show (unchanged behavior).
- Tapping a chip fills it (accent) and narrows the list to that category; tapping again clears it.
- Multiple active chips show the union.
- rtf/markdown/mermaid entries appear under **Text**; images under **Image**; html under **HTML**.
- With chips active but no matching entries, "No items match the filter." shows.

- [ ] **Step 4: Commit**

```bash
git add Sources/ConveyApp/PickerView.swift
git commit -m "feat: type filter chip bar in clipboard picker"
```

---

## Self-Review

**Spec coverage:**
- Category mapping (html/text/image, rtf+md+mermaid→text) → Task 1 `of(_:)` + tests.
- Empty = show all, order preserved, union filter → Task 1 `filter(_:selected:)` + tests.
- Chip bar placement, toggle visuals, ephemeral `@State` → Task 2.
- Empty-filter message vs empty-history message → Task 2 body.
- No changes to AppDelegate/EntryRowView/capture → confirmed: Task 2 keeps the `PickerView` initializer unchanged, so `AppDelegate.makePickerController` needs no edit.
- Testing approach → Task 1 TDD, Task 2 build + manual.

No gaps.

**Placeholder scan:** No TBD/TODO; every code step is complete.

**Type consistency:** `EntryCategory` (`of(_:)`, `filter(_:selected:)`, `label`, `allCases`) is used identically in Task 1's definition and Task 2's `visibleEntries`/`chip`. `EntryCategory` is `String, CaseIterable, Sendable` → `Hashable` (String raw value) so `Set<EntryCategory>` and `ForEach(id: \.self)` are valid. `ClipboardKind` is a `String` raw enum → `Equatable`, so `XCTAssertEqual(r.map(\.kind), [...])` compiles.
