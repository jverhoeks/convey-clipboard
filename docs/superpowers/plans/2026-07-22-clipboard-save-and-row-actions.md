# Clipboard Save + Row Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-format "save to file" download icons, a notification-card row restyle with hover-highlighted actions, and per-item delete to the Convey menu-bar clipboard picker.

**Architecture:** Reuse the existing `Convey.graph` conversion engine to decide which file formats each entry can export to. A new pure `ExportFormat` helper (ConveyKit) maps formats to file types; a new pure `ImageTranscoder` (ConveyKit) converts TIFF image bytes to PNG. The SwiftUI rows (`EntryRowView`) are restyled as cards and gain save/delete controls wired through closures to `AppDelegate`, which runs the `NSSavePanel` and writes files. A shared `RowActionButtonStyle` gives every row control a hover highlight.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI + AppKit, XCTest, macOS 13+.

## Global Constraints

- Swift tools version: 5.9; platform floor: macOS 13 (`.macOS(.v13)`).
- Tests use **XCTest** (not swift-testing). ConveyKit tests live in `Tests/ConveyKitTests`, use `@testable import ConveyKit` and `import ConveyCore`.
- `@MainActor` types (e.g. `HistoryStore`) require `@MainActor` test classes (see existing `HistoryStoreTests`).
- ConveyKit may `import AppKit` and `import UniformTypeIdentifiers` (macOS-only target).
- Follow the existing closure-wiring pattern between `EntryRowView` → `PickerView` → `AppDelegate` (mirror `onConvert` / `targetsFor`).
- Error handling on user actions uses `NSSound.beep()` (matches existing `convert`).
- Full build check: `swift build`. Full test run: `swift test`.

---

### Task 1: `HistoryStore.remove(id:)`

**Files:**
- Modify: `Sources/ConveyKit/HistoryStore.swift`
- Test: `Tests/ConveyKitTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: existing `ClipboardEntry` (has `id: UUID`).
- Produces: `public func remove(id: UUID)` on `HistoryStore`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ConveyKitTests/HistoryStoreTests.swift` inside the class:

```swift
func testRemoveByIdRemovesMatchingEntry() {
    let s = HistoryStore()
    let a = entry("a"); let b = entry("b")
    s.add(a); s.add(b)                       // entries: [b, a]
    s.remove(id: a.id)
    XCTAssertEqual(s.entries.map(\.text), ["b"])
}

func testRemoveUnknownIdIsNoOp() {
    let s = HistoryStore()
    s.add(entry("a"))
    s.remove(id: UUID())
    XCTAssertEqual(s.entries.map(\.text), ["a"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HistoryStoreTests`
Expected: FAIL — `value of type 'HistoryStore' has no member 'remove'`.

- [ ] **Step 3: Implement `remove(id:)`**

In `Sources/ConveyKit/HistoryStore.swift`, add after `clear()`:

```swift
    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HistoryStoreTests`
Expected: PASS (all HistoryStore tests, including the two new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/HistoryStore.swift Tests/ConveyKitTests/HistoryStoreTests.swift
git commit -m "feat: HistoryStore.remove(id:) for per-item delete"
```

---

### Task 2: `ExportFormat` helper

**Files:**
- Create: `Sources/ConveyKit/ExportFormat.swift`
- Test: `Tests/ConveyKitTests/ExportFormatTests.swift`

**Interfaces:**
- Consumes: `Format` (from ConveyCore).
- Produces:
  - `public struct ExportFormat: Equatable, Sendable` with `let format: Format`, `let label: String`, `let fileExtension: String`, `let utTypeIdentifier: String`, `let isText: Bool`.
  - `public static func fileType(for: Format) -> ExportFormat?`
  - `public static func options(nativeFormat: Format, reachable: [Format]) -> [ExportFormat]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ConveyKitTests/ExportFormatTests.swift`:

```swift
import XCTest
import ConveyCore
@testable import ConveyKit

final class ExportFormatTests: XCTestCase {
    func testBase64IsNotAFileType() {
        XCTAssertNil(ExportFormat.fileType(for: .base64DataURI))
    }

    func testImageResolvesToPNG() {
        let ef = ExportFormat.fileType(for: .image)
        XCTAssertEqual(ef?.format, .png)
        XCTAssertEqual(ef?.fileExtension, "png")
        XCTAssertEqual(ef?.isText, false)
    }

    func testHTMLFileType() {
        let ef = ExportFormat.fileType(for: .html)
        XCTAssertEqual(ef?.fileExtension, "html")
        XCTAssertEqual(ef?.isText, true)
    }

    func testHTMLOptions() {
        let opts = ExportFormat.options(nativeFormat: .html, reachable: [.markdown, .plainText])
        XCTAssertEqual(opts.map(\.label), ["HTML", "MD", "TXT"])
    }

    func testImageOptionsAreSinglePNG() {
        let opts = ExportFormat.options(nativeFormat: .image, reachable: [.base64DataURI])
        XCTAssertEqual(opts.map(\.format), [.png])
    }

    func testPlainTextOptions() {
        let opts = ExportFormat.options(nativeFormat: .plainText, reachable: [])
        XCTAssertEqual(opts.map(\.label), ["TXT"])
    }

    func testMermaidOptions() {
        let opts = ExportFormat.options(nativeFormat: .mermaid, reachable: [.svg, .png])
        XCTAssertEqual(opts.map(\.label), ["Mermaid", "SVG", "PNG"])
    }

    func testMarkdownOptionsDedupNativeFirst() {
        let opts = ExportFormat.options(nativeFormat: .markdown, reachable: [.html, .plainText])
        XCTAssertEqual(opts.map(\.label), ["MD", "HTML", "TXT"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ExportFormatTests`
Expected: FAIL — `cannot find 'ExportFormat' in scope`.

- [ ] **Step 3: Implement `ExportFormat`**

Create `Sources/ConveyKit/ExportFormat.swift`:

```swift
import ConveyCore

/// Describes a file type a clipboard entry can be exported/saved as.
/// Pure value type — all file-type knowledge lives here so it is testable
/// without any UI or save panel.
public struct ExportFormat: Equatable, Sendable {
    public let format: Format          // conversion target the save flow should produce
    public let label: String           // short UI label, e.g. "PNG"
    public let fileExtension: String   // e.g. "png"
    public let utTypeIdentifier: String
    public let isText: Bool            // text payload vs. raw bytes

    public init(format: Format, label: String, fileExtension: String,
                utTypeIdentifier: String, isText: Bool) {
        self.format = format; self.label = label; self.fileExtension = fileExtension
        self.utTypeIdentifier = utTypeIdentifier; self.isText = isText
    }

    /// Maps a `Format` to its file type, or `nil` if it is not savable as a file.
    /// `.image` and `.png` both resolve to PNG; `.base64DataURI` is not a file.
    public static func fileType(for format: Format) -> ExportFormat? {
        switch format {
        case .html:
            return ExportFormat(format: .html, label: "HTML", fileExtension: "html",
                                utTypeIdentifier: "public.html", isText: true)
        case .markdown:
            return ExportFormat(format: .markdown, label: "MD", fileExtension: "md",
                                utTypeIdentifier: "net.daringfireball.markdown", isText: true)
        case .plainText:
            return ExportFormat(format: .plainText, label: "TXT", fileExtension: "txt",
                                utTypeIdentifier: "public.plain-text", isText: true)
        case .mermaid:
            return ExportFormat(format: .mermaid, label: "Mermaid", fileExtension: "mmd",
                                utTypeIdentifier: "public.plain-text", isText: true)
        case .svg:
            return ExportFormat(format: .svg, label: "SVG", fileExtension: "svg",
                                utTypeIdentifier: "public.svg-image", isText: true)
        case .rtf:
            return ExportFormat(format: .rtf, label: "RTF", fileExtension: "rtf",
                                utTypeIdentifier: "public.rtf", isText: false)
        case .png, .image:
            return ExportFormat(format: .png, label: "PNG", fileExtension: "png",
                                utTypeIdentifier: "public.png", isText: false)
        case .base64DataURI:
            return nil
        }
    }

    /// The ordered, de-duplicated list of savable formats for an entry:
    /// native format first, then graph-reachable formats, filtered to file types.
    public static func options(nativeFormat: Format, reachable: [Format]) -> [ExportFormat] {
        var orderedFormats: [Format] = []
        for f in [nativeFormat] + reachable where !orderedFormats.contains(f) {
            orderedFormats.append(f)
        }
        var result: [ExportFormat] = []
        var seen: Set<Format> = []
        for f in orderedFormats {
            guard let ef = fileType(for: f), !seen.contains(ef.format) else { continue }
            seen.insert(ef.format)
            result.append(ef)
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ExportFormatTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/ExportFormat.swift Tests/ConveyKitTests/ExportFormatTests.swift
git commit -m "feat: ExportFormat helper mapping formats to file types"
```

---

### Task 3: `ImageTranscoder` (TIFF → PNG)

**Files:**
- Create: `Sources/ConveyKit/ImageTranscoder.swift`
- Test: `Tests/ConveyKitTests/ImageTranscoderTests.swift`

**Interfaces:**
- Produces: `public enum ImageTranscoder { public static func pngData(from data: Data) -> Data? }`

- [ ] **Step 1: Write the failing test**

Create `Tests/ConveyKitTests/ImageTranscoderTests.swift`:

```swift
import XCTest
import AppKit
@testable import ConveyKit

final class ImageTranscoderTests: XCTestCase {
    private func sampleTIFF() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.tiffRepresentation!
    }

    func testTIFFConvertsToPNG() {
        let png = ImageTranscoder.pngData(from: sampleTIFF())
        XCTAssertNotNil(png)
        // PNG magic number: 0x89 'P' 'N' 'G'
        XCTAssertEqual(Array(png!.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ImageTranscoder.pngData(from: Data([0x00, 0x01, 0x02])))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImageTranscoderTests`
Expected: FAIL — `cannot find 'ImageTranscoder' in scope`.

- [ ] **Step 3: Implement `ImageTranscoder`**

Create `Sources/ConveyKit/ImageTranscoder.swift`:

```swift
import Foundation
import AppKit

/// Transcodes raster image bytes (e.g. TIFF from the pasteboard) to PNG.
public enum ImageTranscoder {
    /// Returns PNG-encoded bytes for the given image data, or `nil` if the
    /// data is not a decodable image.
    public static func pngData(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ImageTranscoderTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/ImageTranscoder.swift Tests/ConveyKitTests/ImageTranscoderTests.swift
git commit -m "feat: ImageTranscoder for TIFF to PNG export"
```

---

### Task 4: `RowActionButtonStyle` (hover highlight)

**Files:**
- Create: `Sources/ConveyApp/RowActionButtonStyle.swift`

**Interfaces:**
- Produces: `struct RowActionButtonStyle: ButtonStyle` with `var tint: Color` (default `.accentColor`).

This is UI; it has no unit test. Verify by building.

- [ ] **Step 1: Implement the button style**

Create `Sources/ConveyApp/RowActionButtonStyle.swift`:

```swift
import SwiftUI

/// A compact button style for clipboard-row actions (convert, save, delete).
/// Lights up on hover with a tinted background + brighter foreground.
struct RowActionButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, tint: tint)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? tint.opacity(0.18) : Color.clear)
                )
                .foregroundStyle(hovering ? tint : Color.secondary)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeInOut(duration: 0.12), value: hovering)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build complete, no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ConveyApp/RowActionButtonStyle.swift
git commit -m "feat: RowActionButtonStyle for hover-highlighted row actions"
```

---

### Task 5: `AppDelegate` save + delete logic

**Files:**
- Modify: `Sources/ConveyApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `ExportFormat.fileType(for:)` (Task 2), `ImageTranscoder.pngData(from:)` (Task 3), `HistoryStore.remove(id:)` (Task 1), existing `convey.convert`, `Payload`.
- Produces (private methods used by Task 6's closures):
  - `private func save(_ entry: ClipboardEntry, to target: Format)`
  - `private func delete(_ entry: ClipboardEntry)`

These involve `NSSavePanel` (UI) and are not unit-tested; verify by building. They are added unused in this task and wired up in Task 6.

- [ ] **Step 1: Add the UniformTypeIdentifiers import**

In `Sources/ConveyApp/AppDelegate.swift`, add to the imports at the top (after `import ConveyKit`):

```swift
import UniformTypeIdentifiers
```

- [ ] **Step 2: Add save/delete helpers**

In `AppDelegate`, add these methods after the existing `convert(_:to:)` method:

```swift
    private func data(from payload: Payload) -> Data? {
        switch payload {
        case .text(let s): return Data(s.utf8)
        case .bytes(let b): return b
        }
    }

    private func exportData(for entry: ClipboardEntry, to target: Format,
                            payload: Payload) async throws -> Data? {
        // Image → PNG has no graph edge; transcode the stored bytes.
        if target == .png, entry.primaryFormat == .image {
            guard let bytes = payload.bytes else { return nil }
            return ImageTranscoder.pngData(from: bytes)
        }
        if target == entry.primaryFormat {
            return data(from: payload)
        }
        let result = try await convey.convert(payload, from: entry.primaryFormat, to: target)
        return data(from: result)
    }

    private func runSavePanel(_ exportType: ExportFormat, for entry: ClipboardEntry) -> URL? {
        let panel = NSSavePanel()
        if let contentType = UTType(exportType.utTypeIdentifier) {
            panel.allowedContentTypes = [contentType]
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue =
            "Convey-\(exportType.label)-\(df.string(from: entry.createdAt)).\(exportType.fileExtension)"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func save(_ entry: ClipboardEntry, to target: Format) {
        guard let payload = entry.payload,
              let exportType = ExportFormat.fileType(for: target) else {
            NSSound.beep(); return
        }
        Task { @MainActor in
            do {
                guard let bytes = try await exportData(for: entry, to: target, payload: payload) else {
                    NSSound.beep(); return
                }
                guard let url = runSavePanel(exportType, for: entry) else { return } // user cancelled
                try bytes.write(to: url)
                popover.performClose(nil)
            } catch {
                NSSound.beep()
            }
        }
    }

    private func delete(_ entry: ClipboardEntry) {
        history.remove(id: entry.id)
        let snapshot = history.entries
        let persistence = self.persistence
        saveQueue.async { try? persistence.save(snapshot) }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build complete. (Swift may warn that `save`/`delete` are unused — acceptable; they are wired in Task 6.)

- [ ] **Step 4: Commit**

```bash
git add Sources/ConveyApp/AppDelegate.swift
git commit -m "feat: AppDelegate save-to-file and delete-entry logic"
```

---

### Task 6: Row restyle + wire save/delete into the UI

**Files:**
- Modify: `Sources/ConveyApp/EntryRowView.swift`
- Modify: `Sources/ConveyApp/PickerView.swift`
- Modify: `Sources/ConveyApp/AppDelegate.swift:50-59` (`makePickerController`)

**Interfaces:**
- Consumes: `RowActionButtonStyle` (Task 4), `ExportFormat` (Task 2), `AppDelegate.save`/`delete` (Task 5).
- Produces:
  - `EntryRowView` init gains `saveFormats: [ExportFormat]`, `onSave: (ClipboardEntry, Format) -> Void`, `onDelete: (ClipboardEntry) -> Void`.
  - `PickerView` init gains `saveFormatsFor: (ClipboardEntry) -> [ExportFormat]`, `onSave: (ClipboardEntry, Format) -> Void`, `onDelete: (ClipboardEntry) -> Void`.

This is UI. Verify by building, running the existing test suite (must stay green), and a manual smoke test.

- [ ] **Step 1: Rewrite `EntryRowView` as a card with save/delete/hover**

Replace the entire contents of `Sources/ConveyApp/EntryRowView.swift` with:

```swift
import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

struct EntryRowView: View {
    let entry: ClipboardEntry
    let targets: [Format]
    let saveFormats: [ExportFormat]
    let onConvert: (ClipboardEntry, Format) -> Void
    let onSave: (ClipboardEntry, Format) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let cache: PreviewCache

    @State private var image: NSImage?

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "HH:mm"; return df
    }()

    private var sourceCaption: String? {
        guard entry.sources.count > 1 else { return nil }
        return entry.sources.map { $0.rawValue.uppercased() }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.kind.badge).font(.headline)
                Spacer()
                Text(Self.timeFormatter.string(from: entry.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
                Button { onDelete(entry) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(RowActionButtonStyle(tint: .red))
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(entry.previewText.map { PreviewText.snippet($0) } ?? "(no preview)")
                    .font(.system(.body, design: .rounded))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }

            if let sourceCaption {
                Text(sourceCaption)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if !targets.isEmpty {
                HStack {
                    ForEach(targets, id: \.self) { target in
                        Button("→ \(target.rawValue)") { onConvert(entry, target) }
                            .buttonStyle(RowActionButtonStyle())
                    }
                }
            }

            if !saveFormats.isEmpty {
                HStack {
                    ForEach(saveFormats, id: \.format) { fmt in
                        Button { onSave(entry, fmt.format) } label: {
                            Label(fmt.label, systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(RowActionButtonStyle())
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .task(id: entry.id) {
            image = await cache.image(for: entry)
        }
    }
}
```

- [ ] **Step 2: Update `PickerView` to pass save/delete + "Clear All"**

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
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if history.entries.isEmpty {
                        Text("Clipboard history is empty.\nCopy something to get started.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.top, 40)
                    }
                    ForEach(history.entries) { entry in
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

- [ ] **Step 3: Wire the closures in `AppDelegate.makePickerController`**

In `Sources/ConveyApp/AppDelegate.swift`, replace the `makePickerController()` body (the `PickerView(...)` initializer call) with:

```swift
    private func makePickerController() -> NSViewController {
        let view = PickerView(
            history: history,
            targetsFor: { [convey] entry in convey.graph.validTargets(from: [entry.primaryFormat]) },
            saveFormatsFor: { [convey] entry in
                let reachable = convey.graph.validTargets(from: [entry.primaryFormat])
                return ExportFormat.options(nativeFormat: entry.primaryFormat, reachable: reachable)
            },
            onConvert: { [weak self] entry, target in self?.convert(entry, to: target) },
            onSave: { [weak self] entry, target in self?.save(entry, to: target) },
            onDelete: { [weak self] entry in self?.delete(entry) },
            onClear: { [weak self] in self?.history.clear() },
            cache: previewCache
        )
        return NSHostingController(rootView: view)
    }
```

- [ ] **Step 4: Build and run the full test suite**

Run: `swift build && swift test`
Expected: Build succeeds; all tests pass (no regressions).

- [ ] **Step 5: Manual smoke test**

Run: `swift run convey-app`
Verify:
- Rows render as cards with a bold title, `HH:mm` time, and a trash icon.
- Hovering a `→ format`, save icon, or the trash icon highlights it (trash turns red).
- Clicking a save icon opens a save panel pre-named `Convey-<LABEL>-<date>.<ext>`; saving writes a valid file (open a saved PNG / HTML / TXT to confirm).
- Copy an image, confirm a PNG save icon appears and produces a valid PNG.
- Clicking the trash icon removes that entry; it stays gone after relaunch (persistence).
- "Clear All" empties the list.

- [ ] **Step 6: Commit**

```bash
git add Sources/ConveyApp/EntryRowView.swift Sources/ConveyApp/PickerView.swift Sources/ConveyApp/AppDelegate.swift
git commit -m "feat: notification-card rows with save icons, delete, and hover"
```

---

## Self-Review

**Spec coverage:**
- Savable-format rule (native + reachable, base64 excluded) → Task 2 (`options`), wired Task 6.
- Per-kind option table → Task 2 tests.
- Image PNG / TIFF transcode caveat → Task 3 + Task 5 (`exportData`).
- `ExportFormat` helper → Task 2.
- Save flow (`NSSavePanel`, filename, convert vs. native vs. transcode, beep on error) → Task 5.
- Hover `RowActionButtonStyle` → Task 4, adopted Task 6.
- Per-item delete (`HistoryStore.remove`, trash icon, persist) → Task 1 + Task 5 (`delete`) + Task 6.
- Visual design (card, bold title, `HH:mm`, source caption, action rows, "Clear All") → Task 6.
- Testing approach → per-task TDD (1–3) + build/manual (4–6).

No gaps found.

**Placeholder scan:** No TBD/TODO/"handle edge cases" placeholders; every code step contains complete code.

**Type consistency:** `ExportFormat` fields (`format`, `label`, `fileExtension`, `utTypeIdentifier`, `isText`) and methods (`fileType(for:)`, `options(nativeFormat:reachable:)`) are used identically in Tasks 2, 5, 6. `save(_:to:)` / `delete(_:)` signatures match their closure call sites. `saveFormats` / `saveFormatsFor` / `onSave` / `onDelete` names are consistent across `EntryRowView`, `PickerView`, and `AppDelegate`.
