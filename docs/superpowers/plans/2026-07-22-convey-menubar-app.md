# Convey Menu-Bar App Implementation Plan (Plan 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Convey menu-bar app over `ConveyCore`: a visual clipboard-history list where each entry shows a type badge, a preview, and the valid convert options, plus a global hotkey and privacy-aware clipboard monitoring.

**Architecture:** Two new SPM targets in the existing package. `ConveyKit` (library, depends on `ConveyCore`) holds all headless, testable app logic — `ClipboardEntry`, `HistoryStore` (capped, deduped, persisted), `ClipboardMonitor` (change-detection + entry building, concealed/transient aware), and preview-text derivation. `ConveyApp` (executable) is the thin AppKit/SwiftUI shell: a `LSUIElement`/accessory menu-bar `NSStatusItem`, an `NSPopover` hosting a SwiftUI list, a Carbon global hotkey, and the timer that drives `ClipboardMonitor`. The shell contains no conversion or history logic — it calls `ConveyKit` and `ConveyCore`.

**Tech Stack:** Swift 5.9+, SPM, AppKit (`NSStatusItem`, `NSPopover`, `NSPasteboard`, `NSImage`), SwiftUI (`NSHostingView`), Carbon (`RegisterEventHotKey`), WebKit (reused via `ConveyCore.WebRuntime` for Mermaid/SVG previews), XCTest.

## Global Constraints

- Platform: macOS 13+ (matches Plan 1 `Package.swift`).
- No external Swift package dependencies. Reuse `ConveyCore` (`Format`, `Payload`, `ConversionGraph`, `Convey`, `PasteboardReader`, `PasteboardWriter`, `WebRuntime`, `SystemPasteboard`, `PasteboardSnapshot`).
- No Accessibility permission required (v1): the app writes to the clipboard; the user presses ⌘V. The global hotkey uses Carbon `RegisterEventHotKey` (does not need Accessibility). Auto-paste stays out of scope.
- Privacy: entries whose pasteboard carries `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType` are NEVER captured, previewed, or persisted.
- The menu-bar icon is a monochrome template image: SF Symbol `arrow.left.arrow.right` via `NSImage(systemSymbolName:accessibilityDescription:)` with `.isTemplate = true`.
- `Format` gains `Codable` conformance (needed to persist entries); this is the only change to a Plan 1 source file and must not alter its raw values.
- Testable logic lives in `ConveyKit` and is TDD'd. The `ConveyApp` executable target is verified by `swift build` + a launch smoke test (`swift run ConveyApp` starts, creates the status item, exits cleanly on SIGTERM) — its interactive UI/hotkey behavior is manually verified by the user.
- Each task ends with a passing `swift test` (or `swift build` for shell tasks) and a commit.

## File Structure

```
Package.swift                                  (modified: + ConveyKit lib, + ConveyApp exe, + ConveyKitTests)
Sources/ConveyCore/Format.swift                (modified: + Codable)
Sources/ConveyKit/
  ClipboardEntry.swift        entry model (Codable, Identifiable)
  ClipboardKind.swift         display classification + badge label
  HistoryStore.swift          capped/deduped in-memory ring + observable
  HistoryPersistence.swift    Codable load/save to Application Support
  ClipboardMonitor.swift      change detection + entry building (snapshot-driven)
  PreviewText.swift           text-snippet derivation for a row preview
  Concealment.swift           concealed/transient detection over a snapshot
Sources/ConveyApp/
  main.swift                  NSApplication bootstrap (accessory policy)
  AppDelegate.swift           status item, popover, monitor timer, hotkey owner
  HotKey.swift                Carbon RegisterEventHotKey wrapper
  PickerView.swift            SwiftUI: the visual entry list
  EntryRowView.swift          SwiftUI: one row (badge + preview + convert buttons)
  PreviewImageLoader.swift    NSImage thumbnail + Mermaid/SVG render for a row
Tests/ConveyKitTests/
  ClipboardEntryTests.swift
  HistoryStoreTests.swift
  HistoryPersistenceTests.swift
  ClipboardMonitorTests.swift
  PreviewTextTests.swift
  ConcealmentTests.swift
```

---

### Task 1: ConveyKit scaffold + Format Codable + Concealment + ClipboardKind

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/ConveyCore/Format.swift`
- Create: `Sources/ConveyKit/Concealment.swift`
- Create: `Sources/ConveyKit/ClipboardKind.swift`
- Test: `Tests/ConveyKitTests/ConcealmentTests.swift`

**Interfaces:**
- Produces: `ConveyKit` library target; `Format: Codable`; `enum Concealment { static func isConcealedOrTransient(_ snapshot: PasteboardSnapshot) -> Bool }`; `enum ClipboardKind: String, Codable { case html, rtf, markdown, plainText, mermaid, image; var badge: String; init(sources: [Format]) }`.
- Consumes: `ConveyCore` (`Format`, `PasteboardSnapshot`).

- [ ] **Step 1: Add targets to Package.swift**

Add to `targets:` (keep existing targets intact):

```swift
        .target(name: "ConveyKit", dependencies: ["ConveyCore"]),
        .executableTarget(name: "ConveyApp", dependencies: ["ConveyCore", "ConveyKit"]),
        .testTarget(name: "ConveyKitTests", dependencies: ["ConveyKit"]),
```

Add to `products:`:

```swift
        .library(name: "ConveyKit", targets: ["ConveyKit"]),
        .executable(name: "convey-app", targets: ["ConveyApp"]),
```

- [ ] **Step 2: Make Format Codable**

In `Sources/ConveyCore/Format.swift`, add `Codable` (raw values unchanged):

```swift
public enum Format: String, CaseIterable, Sendable, Codable {
```

- [ ] **Step 3: Write the failing Concealment test**

`Tests/ConveyKitTests/ConcealmentTests.swift`:

```swift
import XCTest
import ConveyCore
@testable import ConveyKit

private struct FakeSnapshot: PasteboardSnapshot {
    var availableTypes: [String]
    func data(forType type: String) -> Data? { nil }
    func string(forType type: String) -> String? { nil }
}

final class ConcealmentTests: XCTestCase {
    func testDetectsConcealed() {
        let s = FakeSnapshot(availableTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        XCTAssertTrue(Concealment.isConcealedOrTransient(s))
    }
    func testDetectsTransient() {
        let s = FakeSnapshot(availableTypes: ["org.nspasteboard.TransientType"])
        XCTAssertTrue(Concealment.isConcealedOrTransient(s))
    }
    func testOrdinaryIsNotConcealed() {
        let s = FakeSnapshot(availableTypes: ["public.html", "public.utf8-plain-text"])
        XCTAssertFalse(Concealment.isConcealedOrTransient(s))
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `swift test --filter ConcealmentTests`
Expected: FAIL — `Concealment` / `ConveyKit` undefined.

- [ ] **Step 5: Implement Concealment and ClipboardKind**

`Sources/ConveyKit/Concealment.swift`:

```swift
import ConveyCore

public enum Concealment {
    static let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]

    public static func isConcealedOrTransient(_ snapshot: PasteboardSnapshot) -> Bool {
        let types = Set(snapshot.availableTypes)
        return markers.contains { types.contains($0) }
    }
}
```

`Sources/ConveyKit/ClipboardKind.swift`:

```swift
import ConveyCore

public enum ClipboardKind: String, Codable, Sendable {
    case html, rtf, markdown, plainText, mermaid, image

    public var badge: String {
        switch self {
        case .html: return "HTML"
        case .rtf: return "RTF"
        case .markdown: return "Markdown"
        case .plainText: return "Text"
        case .mermaid: return "Mermaid"
        case .image: return "Image"
        }
    }

    // Pick the most specific/richest kind from detected sources.
    public init(sources: [Format]) {
        if sources.contains(.html) { self = .html }
        else if sources.contains(.rtf) { self = .rtf }
        else if sources.contains(.image) { self = .image }
        else if sources.contains(.mermaid) { self = .mermaid }
        else if sources.contains(.markdown) { self = .markdown }
        else { self = .plainText }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ConcealmentTests`
Expected: PASS (3 tests). Then `swift build` to confirm the new `ConveyApp` target compiles (it has no sources yet — add a placeholder if SPM complains: `Sources/ConveyApp/main.swift` with `// placeholder, replaced in Task 6` and `import Foundation`).

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ConveyCore/Format.swift Sources/ConveyKit Sources/ConveyApp Tests/ConveyKitTests/ConcealmentTests.swift
git commit -m "feat(app): ConveyKit scaffold + Format Codable + concealment + ClipboardKind"
```

---

### Task 2: ClipboardEntry model

**Files:**
- Create: `Sources/ConveyKit/ClipboardEntry.swift`
- Test: `Tests/ConveyKitTests/ClipboardEntryTests.swift`

**Interfaces:**
- Produces: `struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable` with `id: UUID`, `sources: [Format]`, `kind: ClipboardKind`, `text: String?`, `imageData: Data?`, `createdAt: Date`; `var payload: Payload?` (derives `.text`/`.bytes`); `func sameContent(as:) -> Bool` (dedup by text/imageData).
- Consumes: `ConveyCore` (`Format`, `Payload`), `ClipboardKind`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyKitTests/ClipboardEntryTests.swift`:

```swift
import XCTest
import ConveyCore
@testable import ConveyKit

final class ClipboardEntryTests: XCTestCase {
    private func entry(text: String?, image: Data? = nil, sources: [Format]) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: sources, kind: ClipboardKind(sources: sources),
                       text: text, imageData: image, createdAt: Date(timeIntervalSince1970: 0))
    }

    func testTextPayload() {
        XCTAssertEqual(entry(text: "hi", sources: [.plainText]).payload, .text("hi"))
    }
    func testImagePayload() {
        let d = Data([1, 2]); XCTAssertEqual(entry(text: nil, image: d, sources: [.image]).payload, .bytes(d))
    }
    func testSameContentDedupByText() {
        XCTAssertTrue(entry(text: "x", sources: [.html]).sameContent(as: entry(text: "x", sources: [.plainText])))
        XCTAssertFalse(entry(text: "x", sources: [.html]).sameContent(as: entry(text: "y", sources: [.html])))
    }
    func testRoundTripsCodable() throws {
        let e = entry(text: "hi", sources: [.html])
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(ClipboardEntry.self, from: data), e)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipboardEntryTests`
Expected: FAIL — `ClipboardEntry` undefined.

- [ ] **Step 3: Implement ClipboardEntry**

`Sources/ConveyKit/ClipboardEntry.swift`:

```swift
import Foundation
import ConveyCore

public struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let sources: [Format]
    public let kind: ClipboardKind
    public let text: String?
    public let imageData: Data?
    public let createdAt: Date

    public init(id: UUID, sources: [Format], kind: ClipboardKind, text: String?, imageData: Data?, createdAt: Date) {
        self.id = id
        self.sources = sources
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.createdAt = createdAt
    }

    public var payload: Payload? {
        if let text { return .text(text) }
        if let imageData { return .bytes(imageData) }
        return nil
    }

    public func sameContent(as other: ClipboardEntry) -> Bool {
        if let a = text, let b = other.text { return a == b }
        if let a = imageData, let b = other.imageData { return a == b }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipboardEntryTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/ClipboardEntry.swift Tests/ConveyKitTests/ClipboardEntryTests.swift
git commit -m "feat(app): ClipboardEntry model"
```

---

### Task 3: HistoryStore (capped, deduped ring)

**Files:**
- Create: `Sources/ConveyKit/HistoryStore.swift`
- Test: `Tests/ConveyKitTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces: `@MainActor final class HistoryStore: ObservableObject` with `@Published private(set) var entries: [ClipboardEntry]`, `init(capacity: Int = 50)`, `func add(_ entry: ClipboardEntry)` (newest first; if the incoming entry `sameContent(as:)` an existing one, move it to front instead of duplicating; drop oldest beyond capacity), `func clear()`.
- Consumes: `ClipboardEntry`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyKitTests/HistoryStoreTests.swift`:

```swift
import XCTest
import ConveyCore
@testable import ConveyKit

@MainActor
final class HistoryStoreTests: XCTestCase {
    private func entry(_ text: String) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: [.plainText], kind: .plainText,
                       text: text, imageData: nil, createdAt: Date(timeIntervalSince1970: 0))
    }

    func testAddNewestFirst() {
        let s = HistoryStore()
        s.add(entry("a")); s.add(entry("b"))
        XCTAssertEqual(s.entries.map(\.text), ["b", "a"])
    }
    func testDuplicateContentMovesToFront() {
        let s = HistoryStore()
        s.add(entry("a")); s.add(entry("b")); s.add(entry("a"))
        XCTAssertEqual(s.entries.map(\.text), ["a", "b"])
    }
    func testCapacityDropsOldest() {
        let s = HistoryStore(capacity: 2)
        s.add(entry("a")); s.add(entry("b")); s.add(entry("c"))
        XCTAssertEqual(s.entries.map(\.text), ["c", "b"])
    }
    func testClear() {
        let s = HistoryStore(); s.add(entry("a")); s.clear()
        XCTAssertTrue(s.entries.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HistoryStoreTests`
Expected: FAIL — `HistoryStore` undefined.

- [ ] **Step 3: Implement HistoryStore**

`Sources/ConveyKit/HistoryStore.swift`:

```swift
import Foundation

@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var entries: [ClipboardEntry] = []
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    public func add(_ entry: ClipboardEntry) {
        entries.removeAll { $0.sameContent(as: entry) }
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    public func replaceAll(_ newEntries: [ClipboardEntry]) {
        entries = Array(newEntries.prefix(capacity))
    }

    public func clear() {
        entries.removeAll()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HistoryStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/HistoryStore.swift Tests/ConveyKitTests/HistoryStoreTests.swift
git commit -m "feat(app): HistoryStore capped/deduped ring"
```

---

### Task 4: History persistence

**Files:**
- Create: `Sources/ConveyKit/HistoryPersistence.swift`
- Test: `Tests/ConveyKitTests/HistoryPersistenceTests.swift`

**Interfaces:**
- Produces: `struct HistoryPersistence { init(directory: URL); func save(_ entries: [ClipboardEntry]) throws; func load() -> [ClipboardEntry] }`; `static var defaultDirectory: URL` (Application Support/Convey).
- Consumes: `ClipboardEntry`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyKitTests/HistoryPersistenceTests.swift`:

```swift
import XCTest
import ConveyCore
@testable import ConveyKit

final class HistoryPersistenceTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("convey-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func entry(_ t: String) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: [.plainText], kind: .plainText, text: t, imageData: nil, createdAt: Date(timeIntervalSince1970: 0))
    }

    func testSaveThenLoadRoundTrips() throws {
        let p = HistoryPersistence(directory: tempDir())
        try p.save([entry("a"), entry("b")])
        XCTAssertEqual(p.load().map(\.text), ["a", "b"])
    }
    func testLoadMissingReturnsEmpty() {
        XCTAssertTrue(HistoryPersistence(directory: tempDir()).load().isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HistoryPersistenceTests`
Expected: FAIL — `HistoryPersistence` undefined.

- [ ] **Step 3: Implement HistoryPersistence**

`Sources/ConveyKit/HistoryPersistence.swift`:

```swift
import Foundation

public struct HistoryPersistence {
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("history.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Convey", isDirectory: true)
    }

    public func save(_ entries: [ClipboardEntry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HistoryPersistenceTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/HistoryPersistence.swift Tests/ConveyKitTests/HistoryPersistenceTests.swift
git commit -m "feat(app): history persistence to Application Support"
```

---

### Task 5: ClipboardMonitor entry-building + PreviewText

**Files:**
- Create: `Sources/ConveyKit/ClipboardMonitor.swift`
- Create: `Sources/ConveyKit/PreviewText.swift`
- Test: `Tests/ConveyKitTests/ClipboardMonitorTests.swift`
- Test: `Tests/ConveyKitTests/PreviewTextTests.swift`

**Interfaces:**
- Produces: `struct ClipboardMonitor { init(reader: PasteboardReader = .init()); func makeEntry(from snapshot: PasteboardSnapshot, id: UUID, now: Date) -> ClipboardEntry? }` — returns `nil` when concealed/transient or when no capturable payload; picks `text` from the richest text flavor, else image bytes. `enum PreviewText { static func snippet(_ text: String, limit: Int = 140) -> String }` (collapses whitespace/newlines to single spaces, truncates with `…`).
- Consumes: `ConveyCore` (`PasteboardReader`, `PasteboardSnapshot`, `Format`), `Concealment`, `ClipboardKind`, `ClipboardEntry`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyKitTests/PreviewTextTests.swift`:

```swift
import XCTest
@testable import ConveyKit

final class PreviewTextTests: XCTestCase {
    func testCollapsesWhitespace() {
        XCTAssertEqual(PreviewText.snippet("a\n\n  b\tc"), "a b c")
    }
    func testTruncatesWithEllipsis() {
        let s = PreviewText.snippet(String(repeating: "x", count: 200), limit: 10)
        XCTAssertEqual(s.count, 11) // 10 + ellipsis
        XCTAssertTrue(s.hasSuffix("…"))
    }
}
```

`Tests/ConveyKitTests/ClipboardMonitorTests.swift`:

```swift
import XCTest
import ConveyCore
@testable import ConveyKit

private struct FakeSnapshot: PasteboardSnapshot {
    var availableTypes: [String]
    var strings: [String: String] = [:]
    var datas: [String: Data] = [:]
    func data(forType type: String) -> Data? { datas[type] }
    func string(forType type: String) -> String? { strings[type] }
}

final class ClipboardMonitorTests: XCTestCase {
    let monitor = ClipboardMonitor()
    let id = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func testBuildsTextEntry() {
        let s = FakeSnapshot(availableTypes: ["public.html", "public.utf8-plain-text"],
                             strings: ["public.html": "<b>x</b>", "public.utf8-plain-text": "x"])
        let e = monitor.makeEntry(from: s, id: id, now: now)
        XCTAssertEqual(e?.kind, .html)
        XCTAssertEqual(e?.text, "x")   // prefers plain text for the stored/reconvertible payload
    }
    func testSkipsConcealed() {
        let s = FakeSnapshot(availableTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                             strings: ["public.utf8-plain-text": "secret"])
        XCTAssertNil(monitor.makeEntry(from: s, id: id, now: now))
    }
    func testSkipsEmpty() {
        XCTAssertNil(monitor.makeEntry(from: FakeSnapshot(availableTypes: []), id: id, now: now))
    }
    func testBuildsImageEntry() {
        let png = Data([0x89, 0x50])
        let s = FakeSnapshot(availableTypes: ["public.png"], datas: ["public.png": png])
        let e = monitor.makeEntry(from: s, id: id, now: now)
        XCTAssertEqual(e?.kind, .image)
        XCTAssertEqual(e?.imageData, png)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClipboardMonitorTests`
Expected: FAIL — `ClipboardMonitor` / `PreviewText` undefined.

- [ ] **Step 3: Implement PreviewText and ClipboardMonitor**

`Sources/ConveyKit/PreviewText.swift`:

```swift
import Foundation

public enum PreviewText {
    public static func snippet(_ text: String, limit: Int = 140) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
```

`Sources/ConveyKit/ClipboardMonitor.swift`:

```swift
import Foundation
import ConveyCore

public struct ClipboardMonitor {
    private let reader: PasteboardReader

    public init(reader: PasteboardReader = PasteboardReader()) {
        self.reader = reader
    }

    public func makeEntry(from snapshot: PasteboardSnapshot, id: UUID, now: Date) -> ClipboardEntry? {
        if Concealment.isConcealedOrTransient(snapshot) { return nil }
        let sources = reader.sources(from: snapshot)
        guard !sources.isEmpty else { return nil }

        let kind = ClipboardKind(sources: sources)
        var text: String? = snapshot.string(forType: "public.utf8-plain-text")
        var imageData: Data?

        if text == nil, sources.contains(.image) {
            imageData = reader.payload(for: .image, from: snapshot)?.bytes
        }
        // HTML/RTF-only clipboards without plain text: capture the rich text so it stays reconvertible.
        if text == nil, imageData == nil {
            if let html = snapshot.string(forType: "public.html") { text = html }
        }
        guard text != nil || imageData != nil else { return nil }

        return ClipboardEntry(id: id, sources: sources, kind: kind, text: text, imageData: imageData, createdAt: now)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipboardMonitorTests` then `swift test --filter PreviewTextTests`
Expected: PASS (4 + 2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyKit/ClipboardMonitor.swift Sources/ConveyKit/PreviewText.swift Tests/ConveyKitTests/ClipboardMonitorTests.swift Tests/ConveyKitTests/PreviewTextTests.swift
git commit -m "feat(app): ClipboardMonitor entry-building + preview text"
```

---

### Task 6: App shell — status item + empty popover

**Files:**
- Modify/Create: `Sources/ConveyApp/main.swift`
- Create: `Sources/ConveyApp/AppDelegate.swift`

**Interfaces:**
- Produces: a launchable menu-bar app. `AppDelegate` owns an `NSStatusItem` (template ⇄ icon) and an `NSPopover`; clicking the status item toggles the popover (empty content for now).
- Consumes: AppKit.

- [ ] **Step 1: Write main.swift (bootstrap)**

`Sources/ConveyApp/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar only, no dock icon
app.run()
```

- [ ] **Step 2: Write AppDelegate**

`Sources/ConveyApp/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Convey")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = NSViewController() // replaced in Task 7
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds `convey-app` with no errors.

- [ ] **Step 4: Launch smoke test**

Run (launches, waits, terminates):
```bash
.build/debug/convey-app & APP=$!; sleep 3; kill $APP 2>/dev/null; wait $APP 2>/dev/null; echo "launched pid $APP, exit $?"
```
Expected: process starts and stays alive ~3s (no crash), then is terminated. A menu-bar ⇄ icon appears while running. (If run over SSH without a window server, the status bar may be unavailable — note it; the build succeeding is the CI-verifiable part.)

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyApp/main.swift Sources/ConveyApp/AppDelegate.swift
git commit -m "feat(app): menu-bar status item + toggleable popover shell"
```

---

### Task 7: PickerView + EntryRowView (visual list + convert options)

**Files:**
- Create: `Sources/ConveyApp/PickerView.swift`
- Create: `Sources/ConveyApp/EntryRowView.swift`
- Modify: `Sources/ConveyApp/AppDelegate.swift`

**Interfaces:**
- Produces: `struct PickerView: View` bound to a `HistoryStore` and a converter closure; renders the current entry pinned on top, then history. `struct EntryRowView: View` shows the kind badge, a text-preview snippet, and one button per valid target (computed from `Convey().graph.validTargets(from: entry.sources)`); tapping a target runs the conversion for that entry and writes the result to the clipboard.
- Consumes: SwiftUI, `ConveyKit` (`HistoryStore`, `ClipboardEntry`, `PreviewText`), `ConveyCore` (`Convey`, `Format`, `PasteboardWriter`).

- [ ] **Step 1: Implement EntryRowView**

`Sources/ConveyApp/EntryRowView.swift`:

```swift
import SwiftUI
import ConveyCore
import ConveyKit

struct EntryRowView: View {
    let entry: ClipboardEntry
    let targets: [Format]
    let onConvert: (ClipboardEntry, Format) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.kind.badge)
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
            }
            Text(entry.text.map { PreviewText.snippet($0) } ?? "(image)")
                .font(.system(.body, design: .rounded))
                .lineLimit(3)
                .foregroundStyle(.primary)
            if !targets.isEmpty {
                HStack {
                    ForEach(targets, id: \.self) { target in
                        Button("→ \(target.rawValue)") { onConvert(entry, target) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Implement PickerView**

`Sources/ConveyApp/PickerView.swift`:

```swift
import SwiftUI
import ConveyCore
import ConveyKit

struct PickerView: View {
    @ObservedObject var history: HistoryStore
    let targetsFor: (ClipboardEntry) -> [Format]
    let onConvert: (ClipboardEntry, Format) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Convey").font(.headline)
                Spacer()
                Button("Clear", action: onClear).buttonStyle(.borderless).font(.caption)
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
                        EntryRowView(entry: entry, targets: targetsFor(entry), onConvert: onConvert)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 380, height: 480)
    }
}
```

- [ ] **Step 3: Wire PickerView into AppDelegate**

In `AppDelegate.swift`, add stored properties and replace the popover content. Add:

```swift
import SwiftUI
import ConveyCore
import ConveyKit
```

Add properties and a setup in `applicationDidFinishLaunching` (after the status item is created), replacing the placeholder `NSViewController()`:

```swift
    let history = HistoryStore()
    private let convey = Convey()

    private func makePickerController() -> NSViewController {
        let view = PickerView(
            history: history,
            targetsFor: { [convey] entry in convey.graph.validTargets(from: entry.sources) },
            onConvert: { [weak self] entry, target in self?.convert(entry, to: target) },
            onClear: { [weak self] in self?.history.clear() }
        )
        return NSHostingController(rootView: view)
    }

    private func convert(_ entry: ClipboardEntry, to target: Format) {
        guard let payload = entry.payload, let from = entry.sources.first else { return }
        Task { @MainActor in
            do {
                // Choose the richest source that can reach the target.
                let source = entry.sources.first(where: { convey.graph.path(from: $0, to: target) != nil }) ?? from
                let result = try await convey.convert(payload, from: source, to: target)
                PasteboardWriter().write(result, as: target, to: .general)
                popover.performClose(nil)
            } catch {
                NSSound.beep()
            }
        }
    }
```

Then set `popover.contentViewController = makePickerController()`.

Note: `entry.payload` returns the plain text/image bytes. When the chosen `source` is `.html` but the stored payload is plain text (HTML-only clipboards store the HTML string as `text`), the payload already holds the HTML string, so `convert(from: .html, ...)` receives the right bytes. Keep this behavior.

- [ ] **Step 4: Build + launch smoke test**

Run: `swift build`
Expected: builds clean.
Run the launch smoke test from Task 6 Step 4 again.
Expected: launches without crashing; clicking the icon shows the list (manual check).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyApp/PickerView.swift Sources/ConveyApp/EntryRowView.swift Sources/ConveyApp/AppDelegate.swift
git commit -m "feat(app): visual picker list with per-entry preview + convert options"
```

---

### Task 8: Image thumbnails + Mermaid/SVG previews

**Files:**
- Create: `Sources/ConveyApp/PreviewImageLoader.swift`
- Modify: `Sources/ConveyApp/EntryRowView.swift`

**Interfaces:**
- Produces: `@MainActor enum PreviewImageLoader { static func thumbnail(for entry: ClipboardEntry) -> NSImage?; static func rendered(for entry: ClipboardEntry, using convey: Convey) async -> NSImage? }` — image entries → `NSImage(data:)`; Mermaid entries → render to SVG via `convey.convert(.text(src), from: .mermaid, to: .png)` then `NSImage(data:)`.
- Consumes: AppKit, `ConveyCore` (`Convey`, `Format`), `ConveyKit`.

- [ ] **Step 1: Implement PreviewImageLoader**

`Sources/ConveyApp/PreviewImageLoader.swift`:

```swift
import AppKit
import ConveyCore
import ConveyKit

@MainActor
enum PreviewImageLoader {
    static func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let data = entry.imageData else { return nil }
        return NSImage(data: data)
    }

    static func rendered(for entry: ClipboardEntry, using convey: Convey) async -> NSImage? {
        guard entry.kind == .mermaid, let src = entry.text else { return nil }
        guard let result = try? await convey.convert(.text(src), from: .mermaid, to: .png),
              let data = result.bytes else { return nil }
        return NSImage(data: data)
    }
}
```

- [ ] **Step 2: Add an optional image to EntryRowView**

Modify `EntryRowView` to accept and display an optional `NSImage`:

```swift
    let thumbnail: NSImage?
    // ...in body, replace the text-or-"(image)" Text with:
    if let thumbnail {
        Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 120)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    } else {
        Text(entry.text.map { PreviewText.snippet($0) } ?? "(no preview)")
            .font(.system(.body, design: .rounded)).lineLimit(3)
    }
```

In `PickerView`, compute the sync thumbnail (`PreviewImageLoader.thumbnail(for:)`) per row and pass it. (Async Mermaid rendering can be added later via a small per-row `.task`; for this task, image thumbnails are the deliverable and Mermaid rows fall back to the text snippet if async rendering is not yet wired.)

- [ ] **Step 3: Build + launch smoke test**

Run: `swift build` then the launch smoke test.
Expected: builds clean; image entries show a thumbnail (manual check).

- [ ] **Step 4: Commit**

```bash
git add Sources/ConveyApp/PreviewImageLoader.swift Sources/ConveyApp/EntryRowView.swift Sources/ConveyApp/PickerView.swift
git commit -m "feat(app): image thumbnails (+ Mermaid render hook) in preview rows"
```

---

### Task 9: Global hotkey ⌥⌘V

**Files:**
- Create: `Sources/ConveyApp/HotKey.swift`
- Modify: `Sources/ConveyApp/AppDelegate.swift`

**Interfaces:**
- Produces: `final class HotKey { init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) }` wrapping Carbon `RegisterEventHotKey` + an event handler; deinit unregisters.
- Consumes: Carbon (`import Carbon.HIToolbox`), AppKit.

- [ ] **Step 1: Implement HotKey**

`Sources/ConveyApp/HotKey.swift`:

```swift
import Carbon.HIToolbox
import AppKit

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private static var counter: UInt32 = 0

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        HotKey.counter += 1
        let id = EventHotKeyID(signature: OSType(0x43_4E_56_59), id: HotKey.counter) // 'CNVY'

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().handler()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        guard status == noErr else { return nil }

        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
```

- [ ] **Step 2: Register ⌥⌘V in AppDelegate**

Add a stored `private var hotKey: HotKey?` and in `applicationDidFinishLaunching`:

```swift
        // ⌥⌘V — keyCode 9 is 'v'; modifiers optionKey | cmdKey.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(optionKey | cmdKey)) { [weak self] in
            self?.togglePopover()
        }
```
Add `import Carbon.HIToolbox` to `AppDelegate.swift`. Make `togglePopover` callable (it already exists; ensure it isn't `private` if referenced across the closure — keeping it `@objc private` is fine since the closure is inside the same class).

- [ ] **Step 3: Build + launch smoke test**

Run: `swift build` then the launch smoke test.
Expected: builds clean; while running, pressing ⌥⌘V toggles the popover (manual check — requires a foreground session).

- [ ] **Step 4: Commit**

```bash
git add Sources/ConveyApp/HotKey.swift Sources/ConveyApp/AppDelegate.swift
git commit -m "feat(app): global ⌥⌘V hotkey via Carbon RegisterEventHotKey"
```

---

### Task 10: Clipboard monitor timer + persistence wiring

**Files:**
- Modify: `Sources/ConveyApp/AppDelegate.swift`

**Interfaces:**
- Produces: a repeating timer polling `NSPasteboard.general.changeCount`; on change, builds an entry via `ClipboardMonitor.makeEntry(from:id:now:)` and adds it to `history`; loads persisted history on launch and saves on change + on quit.
- Consumes: `ConveyKit` (`ClipboardMonitor`, `HistoryStore`, `HistoryPersistence`), `ConveyCore` (`SystemPasteboard`).

- [ ] **Step 1: Wire monitoring + persistence**

In `AppDelegate.swift` add:

```swift
    private let monitor = ClipboardMonitor()
    private let persistence = HistoryPersistence(directory: HistoryPersistence.defaultDirectory)
    private var pollTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
```

In `applicationDidFinishLaunching` (before showing anything):

```swift
        history.replaceAll(persistence.load())
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
```

Add methods:

```swift
    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let entry = monitor.makeEntry(from: SystemPasteboard(pb), id: UUID(), now: Date()) else { return }
        history.add(entry)
        try? persistence.save(history.entries)
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? persistence.save(history.entries)
    }
```

Note: writing our own conversion result to the clipboard bumps `changeCount`; the next poll will re-capture it as a (deduped) entry — acceptable. Concealed/transient entries are filtered inside `makeEntry`.

- [ ] **Step 2: Build + launch smoke test**

Run: `swift build` then the launch smoke test.
Expected: builds clean; while running, copying text/images/HTML populates the list; entries persist across relaunch (manual check). Password-manager copies do NOT appear (manual check).

- [ ] **Step 3: Commit**

```bash
git add Sources/ConveyApp/AppDelegate.swift
git commit -m "feat(app): clipboard-change polling + history persistence wiring"
```

---

### Task 11: LICENSE, README, full verification, tag

**Files:**
- Create: `LICENSE`
- Modify: `README.md`

- [ ] **Step 1: Add an Apache-2.0 LICENSE**

Write the standard Apache License 2.0 text to `LICENSE` (copyright holder "Jacob Verhoeks"), matching the license used by the sibling Lucent project.

- [ ] **Step 2: Update README with the app section**

Add a section documenting the menu-bar app:

```markdown
## Menu-bar app (Plan 2)

Run: `swift run convey-app`

A menu-bar ⇄ icon opens a visual clipboard list. Each entry shows a type
badge, a preview (text snippet / image thumbnail / rendered diagram), and the
valid convert options for that entry — click one to rewrite the clipboard,
then ⌘V. Press ⌥⌘V to open the picker from anywhere. History persists across
launches; password-manager entries (concealed/transient) are never captured.
```

- [ ] **Step 3: Full verification**

Run: `swift test`
Expected: all `ConveyCoreTests` + `ConveyKitTests` pass, pristine.
Run: `swift build`
Expected: both `convey` and `convey-app` build clean.
Run the launch smoke test one final time.

- [ ] **Step 4: Commit and tag**

```bash
git add LICENSE README.md
git commit -m "docs: Apache-2.0 LICENSE + menu-bar app README; Plan 2 complete"
git tag plan2-app
```

---

## Self-Review

**Spec coverage (Plan 2):**
- Visual list of clipboard entries (current + history) — Task 7 ✓
- Per-entry preview: text snippet (Task 5/7), image thumbnail (Task 8), Mermaid/SVG render hook (Task 8) ✓
- Per-entry convert options from `validTargets` — Task 7 ✓
- Both triggers (menu-bar click + ⌥⌘V) sharing one picker — Tasks 6, 9 ✓
- History store: capped, deduped, persisted, clear — Tasks 3, 4, 7, 10 ✓
- Privacy: concealed/transient never captured/previewed/persisted — Tasks 1, 5, 10 ✓
- No Accessibility permission (Carbon hotkey; user presses ⌘V) — Task 9 ✓
- LICENSE for the now-public repo — Task 11 ✓

**Testability boundary (explicit):** `ConveyKit` logic is TDD'd (Concealment, ClipboardEntry, HistoryStore, HistoryPersistence, ClipboardMonitor, PreviewText). The `ConveyApp` shell (status item, popover, SwiftUI views, hotkey, timer) is verified by build + launch-without-crash; its interactive UI/hotkey/preview-rendering behavior requires manual verification in a foreground macOS session — called out per task.

**Placeholder scan:** none — every code step contains complete code.

**Type consistency:** `ClipboardEntry`(`sources`/`kind`/`text`/`imageData`/`payload`), `HistoryStore`(`entries`/`add`/`replaceAll`/`clear`), `ClipboardMonitor.makeEntry(from:id:now:)`, `Convey.graph`/`convert`, and `PasteboardWriter.write(_:as:to:)` are used identically across tasks.

**Known limitations (documented, not blockers):** async Mermaid row rendering is hooked but wired lazily (Task 8 note); polling interval 0.7s; convert picks the first source with a path to the target.
