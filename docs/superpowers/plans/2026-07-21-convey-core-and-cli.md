# Convey Core + CLI Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ConveyCore` (a headless Swift package that reads clipboard flavors, detects source format, and converts between formats via a composable graph) plus the `convey` CLI over it.

**Architecture:** A single Swift Package Manager package. `ConveyCore` is a library holding value types (`Format`, `Payload`), a `Converter` protocol, a BFS `ConversionGraph` that composes edges into paths, a testable `PasteboardReader`/`PasteboardWriter`, and a `WebRuntime` (a hidden `WKWebView` that hosts vendored `turndown`/`marked`/`mermaid` JS for the heavy edges). `convey` is a thin executable target that drives the core. Everything builds and tests from the terminal — no Xcode project.

**Tech Stack:** Swift 5.9+, Swift Package Manager, AppKit (`NSPasteboard`, `NSAttributedString`), WebKit (`WKWebView.callAsyncJavaScript`), XCTest. Vendored JS: turndown 7.2.0, marked 12.0.0, mermaid 10.9.0.

## Global Constraints

- Platform: macOS 13+ (`.macOS(.v13)` in Package.swift). `callAsyncJavaScript` needs macOS 11+; we target 13.
- No external Swift package dependencies. JS libraries are vendored (committed) under `Sources/ConveyCore/Resources/web/`, never fetched at runtime.
- `Format` enum raw values are the stable string identifiers used by the CLI and (later) the app: `html`, `rtf`, `plainText`, `markdown`, `mermaid`, `image`, `png`, `svg`, `base64DataURI`.
- Every code step below ends its task with a passing `swift test` (or `swift build` for the CLI/resource tasks) and a commit.
- TDD: write the failing test first for every unit that can be unit-tested. `WebRuntime`-backed edges use async integration tests.

---

### Task 1: Package scaffold + core value types

**Files:**
- Create: `Package.swift`
- Create: `Sources/ConveyCore/Format.swift`
- Create: `Sources/ConveyCore/Payload.swift`
- Create: `Sources/ConveyCore/Converter.swift`
- Test: `Tests/ConveyCoreTests/PayloadTests.swift`

**Interfaces:**
- Produces: `enum Format: String, CaseIterable, Sendable`; `enum Payload: Equatable, Sendable` with `.text(String)` / `.bytes(Data)` and computed `text: String?`, `bytes: Data?`; `protocol Converter: Sendable { var from: Format; var to: Format; func convert(_:) async throws -> Payload }`; `enum ConversionError: Error, Equatable`.

- [ ] **Step 1: Initialize the repo and package layout**

```bash
cd /Users/jjverhoeks/src/tries/2026-07-21-convey
git init
mkdir -p Sources/ConveyCore/Converters Sources/ConveyCore/Resources/web Sources/convey Tests/ConveyCoreTests/Fixtures
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Convey",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ConveyCore", targets: ["ConveyCore"]),
        .executable(name: "convey", targets: ["convey"]),
    ],
    targets: [
        .target(
            name: "ConveyCore",
            resources: [.copy("Resources/web")]
        ),
        .executableTarget(
            name: "convey",
            dependencies: ["ConveyCore"]
        ),
        .testTarget(
            name: "ConveyCoreTests",
            dependencies: ["ConveyCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 3: Write the failing test for `Payload`**

`Tests/ConveyCoreTests/PayloadTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class PayloadTests: XCTestCase {
    func testTextAccessor() {
        XCTAssertEqual(Payload.text("hi").text, "hi")
        XCTAssertNil(Payload.text("hi").bytes)
    }

    func testBytesAccessor() {
        let data = Data([1, 2, 3])
        XCTAssertEqual(Payload.bytes(data).bytes, data)
        XCTAssertNil(Payload.bytes(data).text)
    }

    func testFormatRawValuesAreStable() {
        XCTAssertEqual(Format.plainText.rawValue, "plainText")
        XCTAssertEqual(Format.base64DataURI.rawValue, "base64DataURI")
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `swift test`
Expected: FAIL to build — `Format`/`Payload` undefined.

- [ ] **Step 5: Implement the value types**

`Sources/ConveyCore/Format.swift`:

```swift
public enum Format: String, CaseIterable, Sendable {
    case html
    case rtf
    case plainText
    case markdown
    case mermaid
    case image
    case png
    case svg
    case base64DataURI
}
```

`Sources/ConveyCore/Payload.swift`:

```swift
import Foundation

public enum Payload: Equatable, Sendable {
    case text(String)
    case bytes(Data)

    public var text: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    public var bytes: Data? {
        if case let .bytes(value) = self { return value }
        return nil
    }
}
```

`Sources/ConveyCore/Converter.swift`:

```swift
public protocol Converter: Sendable {
    var from: Format { get }
    var to: Format { get }
    func convert(_ input: Payload) async throws -> Payload
}

public enum ConversionError: Error, Equatable {
    case wrongPayload(expected: String)
    case noPath(from: Format, to: Format)
    case engineFailed(String)
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ConveyCore Tests/ConveyCoreTests/PayloadTests.swift .gitignore 2>/dev/null; \
printf '.build/\n*.xcodeproj\n.DS_Store\n' > .gitignore; git add .gitignore
git commit -m "feat: package scaffold + Format/Payload/Converter value types"
```

---

### Task 2: ConversionGraph (edge registry + path composition)

**Files:**
- Create: `Sources/ConveyCore/ConversionGraph.swift`
- Test: `Tests/ConveyCoreTests/ConversionGraphTests.swift`

**Interfaces:**
- Consumes: `Converter`, `Format`, `Payload`, `ConversionError`.
- Produces: `final class ConversionGraph` with `init(_ converters: [Converter] = [])`, `func register(_:)`, `func validTargets(from sources: [Format]) -> [Format]`, `func path(from: Format, to: Format) -> [Converter]?`, `func convert(_ payload: Payload, from: Format, to: Format) async throws -> Payload`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyCoreTests/ConversionGraphTests.swift`:

```swift
import XCTest
@testable import ConveyCore

private struct StubConverter: Converter {
    let from: Format
    let to: Format
    let transform: @Sendable (String) -> String
    func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(value) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        return .text(transform(value))
    }
}

final class ConversionGraphTests: XCTestCase {
    private func graph() -> ConversionGraph {
        ConversionGraph([
            StubConverter(from: .rtf, to: .html) { "<h>\($0)</h>" },
            StubConverter(from: .html, to: .markdown) { $0.replacingOccurrences(of: "<h>", with: "# ").replacingOccurrences(of: "</h>", with: "") },
        ])
    }

    func testValidTargetsReachableFromSource() {
        let targets = graph().validTargets(from: [.rtf])
        XCTAssertEqual(Set(targets), Set([.html, .markdown]))
    }

    func testValidTargetsExcludesSource() {
        XCTAssertFalse(graph().validTargets(from: [.rtf]).contains(.rtf))
    }

    func testPathIsMultiHop() {
        let path = graph().path(from: .rtf, to: .markdown)
        XCTAssertEqual(path?.count, 2)
    }

    func testConvertComposesEdges() async throws {
        let result = try await graph().convert(.text("hello"), from: .rtf, to: .markdown)
        XCTAssertEqual(result, .text("# hello"))
    }

    func testConvertThrowsWhenNoPath() async {
        do {
            _ = try await graph().convert(.text("x"), from: .markdown, to: .rtf)
            XCTFail("expected throw")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .noPath(from: .markdown, to: .rtf))
        } catch {
            XCTFail("wrong error type")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConversionGraphTests`
Expected: FAIL — `ConversionGraph` undefined.

- [ ] **Step 3: Implement `ConversionGraph`**

`Sources/ConveyCore/ConversionGraph.swift`:

```swift
public final class ConversionGraph: @unchecked Sendable {
    private var edges: [Format: [Converter]] = [:]

    public init(_ converters: [Converter] = []) {
        converters.forEach(register)
    }

    public func register(_ converter: Converter) {
        edges[converter.from, default: []].append(converter)
    }

    public func validTargets(from sources: [Format]) -> [Format] {
        var visited = Set(sources)
        var queue = sources
        var result: [Format] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            for edge in edges[node] ?? [] where !visited.contains(edge.to) {
                visited.insert(edge.to)
                result.append(edge.to)
                queue.append(edge.to)
            }
        }
        return result
    }

    public func path(from: Format, to: Format) -> [Converter]? {
        if from == to { return [] }
        var visited: Set<Format> = [from]
        var queue: [(Format, [Converter])] = [(from, [])]
        while !queue.isEmpty {
            let (node, acc) = queue.removeFirst()
            for edge in edges[node] ?? [] where !visited.contains(edge.to) {
                let next = acc + [edge]
                if edge.to == to { return next }
                visited.insert(edge.to)
                queue.append((edge.to, next))
            }
        }
        return nil
    }

    public func convert(_ payload: Payload, from: Format, to: Format) async throws -> Payload {
        guard let path = path(from: from, to: to) else {
            throw ConversionError.noPath(from: from, to: to)
        }
        var current = payload
        for converter in path {
            current = try await converter.convert(current)
        }
        return current
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConversionGraphTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyCore/ConversionGraph.swift Tests/ConveyCoreTests/ConversionGraphTests.swift
git commit -m "feat: ConversionGraph with BFS multi-hop path composition"
```

---

### Task 3: PasteboardReader + snapshot abstraction

**Files:**
- Create: `Sources/ConveyCore/PasteboardSnapshot.swift`
- Create: `Sources/ConveyCore/PasteboardReader.swift`
- Test: `Tests/ConveyCoreTests/PasteboardReaderTests.swift`

**Interfaces:**
- Produces: `protocol PasteboardSnapshot { var availableTypes: [String] { get }; func data(forType:) -> Data?; func string(forType:) -> String? }`; `struct SystemPasteboard: PasteboardSnapshot` (wraps `NSPasteboard`); `struct PasteboardReader { func sources(from:) -> [Format]; func payload(for:from:) -> Payload?; static func looksLikeMermaid(_:) -> Bool }`.
- Consumes: `Format`, `Payload`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyCoreTests/PasteboardReaderTests.swift`:

```swift
import XCTest
@testable import ConveyCore

private struct FakeSnapshot: PasteboardSnapshot {
    var availableTypes: [String]
    var strings: [String: String] = [:]
    var datas: [String: Data] = [:]
    func data(forType type: String) -> Data? { datas[type] }
    func string(forType type: String) -> String? { strings[type] }
}

final class PasteboardReaderTests: XCTestCase {
    let reader = PasteboardReader()

    func testDetectsHtmlAndPlainText() {
        let snap = FakeSnapshot(
            availableTypes: ["public.html", "public.utf8-plain-text"],
            strings: ["public.utf8-plain-text": "hello"]
        )
        XCTAssertEqual(Set(reader.sources(from: snap)), Set([.html, .plainText]))
    }

    func testAddsMermaidWhenTextLooksLikeMermaid() {
        let snap = FakeSnapshot(
            availableTypes: ["public.utf8-plain-text"],
            strings: ["public.utf8-plain-text": "flowchart TD\n A-->B"]
        )
        XCTAssertTrue(reader.sources(from: snap).contains(.mermaid))
    }

    func testNoMermaidForOrdinaryText() {
        let snap = FakeSnapshot(
            availableTypes: ["public.utf8-plain-text"],
            strings: ["public.utf8-plain-text": "just a sentence"]
        )
        XCTAssertFalse(reader.sources(from: snap).contains(.mermaid))
    }

    func testPayloadForHtml() {
        let snap = FakeSnapshot(availableTypes: ["public.html"], strings: ["public.html": "<b>x</b>"])
        XCTAssertEqual(reader.payload(for: .html, from: snap), .text("<b>x</b>"))
    }

    func testPayloadForImagePrefersPng() {
        let png = Data([0x89, 0x50])
        let snap = FakeSnapshot(availableTypes: ["public.png"], datas: ["public.png": png])
        XCTAssertEqual(reader.payload(for: .image, from: snap), .bytes(png))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PasteboardReaderTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Implement the snapshot protocol + system adapter**

`Sources/ConveyCore/PasteboardSnapshot.swift`:

```swift
import Foundation
import AppKit

public protocol PasteboardSnapshot {
    var availableTypes: [String] { get }
    func data(forType type: String) -> Data?
    func string(forType type: String) -> String?
}

public struct SystemPasteboard: PasteboardSnapshot {
    private let pasteboard: NSPasteboard

    public init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var availableTypes: [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    public func data(forType type: String) -> Data? {
        pasteboard.data(forType: NSPasteboard.PasteboardType(type))
    }

    public func string(forType type: String) -> String? {
        pasteboard.string(forType: NSPasteboard.PasteboardType(type))
    }
}
```

- [ ] **Step 4: Implement `PasteboardReader`**

`Sources/ConveyCore/PasteboardReader.swift`:

```swift
import Foundation

public struct PasteboardReader {
    public init() {}

    static let flavorMap: [String: Format] = [
        "public.html": .html,
        "public.rtf": .rtf,
        "public.utf8-plain-text": .plainText,
        "public.png": .image,
        "public.tiff": .image,
    ]

    static let mermaidPrefixes = [
        "graph ", "graph\n", "flowchart", "sequenceDiagram", "classDiagram",
        "stateDiagram", "erDiagram", "gantt", "pie", "journey", "gitGraph",
        "mindmap", "timeline",
    ]

    public static func looksLikeMermaid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return mermaidPrefixes.contains { trimmed.hasPrefix($0) }
    }

    public func sources(from snapshot: PasteboardSnapshot) -> [Format] {
        var result: [Format] = []
        for type in snapshot.availableTypes {
            if let format = Self.flavorMap[type], !result.contains(format) {
                result.append(format)
            }
        }
        if result.contains(.plainText),
           let text = snapshot.string(forType: "public.utf8-plain-text"),
           Self.looksLikeMermaid(text) {
            result.append(.mermaid)
        }
        return result
    }

    public func payload(for format: Format, from snapshot: PasteboardSnapshot) -> Payload? {
        switch format {
        case .html:
            return snapshot.string(forType: "public.html").map(Payload.text)
        case .rtf:
            return snapshot.data(forType: "public.rtf").map(Payload.bytes)
        case .plainText, .mermaid, .markdown:
            return snapshot.string(forType: "public.utf8-plain-text").map(Payload.text)
        case .image:
            if let png = snapshot.data(forType: "public.png") { return .bytes(png) }
            return snapshot.data(forType: "public.tiff").map(Payload.bytes)
        case .png, .svg, .base64DataURI:
            return nil
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PasteboardReaderTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ConveyCore/PasteboardSnapshot.swift Sources/ConveyCore/PasteboardReader.swift Tests/ConveyCoreTests/PasteboardReaderTests.swift
git commit -m "feat: PasteboardReader with flavor detection + mermaid heuristic"
```

---

### Task 4: Image → base64 data-URI converter (pure Swift)

**Files:**
- Create: `Sources/ConveyCore/Converters/ImageToBase64Converter.swift`
- Test: `Tests/ConveyCoreTests/ImageToBase64ConverterTests.swift`

**Interfaces:**
- Produces: `struct ImageToBase64Converter: Converter` (`from: .image`, `to: .base64DataURI`); `static func mime(for: Data) -> String`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyCoreTests/ImageToBase64ConverterTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class ImageToBase64ConverterTests: XCTestCase {
    let converter = ImageToBase64Converter()

    func testEncodesPngWithCorrectMime() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let result = try await converter.convert(.bytes(png))
        XCTAssertEqual(result, .text("data:image/png;base64," + png.base64EncodedString()))
    }

    func testDetectsJpeg() {
        XCTAssertEqual(ImageToBase64Converter.mime(for: Data([0xFF, 0xD8, 0xFF])), "image/jpeg")
    }

    func testRejectsTextPayload() async {
        do {
            _ = try await converter.convert(.text("x"))
            XCTFail("expected throw")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .wrongPayload(expected: "bytes"))
        } catch { XCTFail("wrong error") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImageToBase64ConverterTests`
Expected: FAIL — converter undefined.

- [ ] **Step 3: Implement the converter**

`Sources/ConveyCore/Converters/ImageToBase64Converter.swift`:

```swift
import Foundation

public struct ImageToBase64Converter: Converter {
    public let from: Format = .image
    public let to: Format = .base64DataURI

    public init() {}

    public static func mime(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        return "application/octet-stream"
    }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .bytes(data) = input else {
            throw ConversionError.wrongPayload(expected: "bytes")
        }
        return .text("data:\(Self.mime(for: data));base64,\(data.base64EncodedString())")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ImageToBase64ConverterTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyCore/Converters/ImageToBase64Converter.swift Tests/ConveyCoreTests/ImageToBase64ConverterTests.swift
git commit -m "feat: image -> base64 data-URI converter"
```

---

### Task 5: RTF → HTML converter (AppKit, main actor)

**Files:**
- Create: `Sources/ConveyCore/Converters/RTFToHTMLConverter.swift`
- Create: `Tests/ConveyCoreTests/Fixtures/sample.rtf`
- Test: `Tests/ConveyCoreTests/RTFToHTMLConverterTests.swift`

**Interfaces:**
- Produces: `struct RTFToHTMLConverter: Converter` (`from: .rtf`, `to: .html`). Runs its AppKit work inside `MainActor.run`.

- [ ] **Step 1: Create the RTF fixture**

```bash
printf '{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 Hello \\b bold\\b0 world.}' \
  > /Users/jjverhoeks/src/tries/2026-07-21-convey/Tests/ConveyCoreTests/Fixtures/sample.rtf
```

- [ ] **Step 2: Write the failing test**

`Tests/ConveyCoreTests/RTFToHTMLConverterTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class RTFToHTMLConverterTests: XCTestCase {
    func testConvertsRtfToHtmlContainingText() async throws {
        let url = Bundle.module.url(forResource: "sample", withExtension: "rtf", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let result = try await RTFToHTMLConverter().convert(.bytes(data))
        let html = try XCTUnwrap(result.text)
        XCTAssertTrue(html.contains("Hello"))
        XCTAssertTrue(html.lowercased().contains("bold"))
        XCTAssertTrue(html.lowercased().contains("<html") || html.lowercased().contains("<p"))
    }

    func testRejectsTextPayload() async {
        do {
            _ = try await RTFToHTMLConverter().convert(.text("x"))
            XCTFail("expected throw")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .wrongPayload(expected: "bytes"))
        } catch { XCTFail("wrong error") }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter RTFToHTMLConverterTests`
Expected: FAIL — converter undefined.

- [ ] **Step 4: Implement the converter**

`Sources/ConveyCore/Converters/RTFToHTMLConverter.swift`:

```swift
import Foundation
import AppKit

public struct RTFToHTMLConverter: Converter {
    public let from: Format = .rtf
    public let to: Format = .html

    public init() {}

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .bytes(data) = input else {
            throw ConversionError.wrongPayload(expected: "bytes")
        }
        return try await MainActor.run {
            guard let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) else {
                throw ConversionError.engineFailed("rtf parse")
            }
            let htmlData = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            )
            guard let html = String(data: htmlData, encoding: .utf8) else {
                throw ConversionError.engineFailed("html encode")
            }
            return Payload.text(html)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter RTFToHTMLConverterTests`
Expected: PASS (2 tests).
(If the HTML-writer assertion is flaky in a headless CI, keep the `Hello`/`bold` assertions — they are the load-bearing ones.)

- [ ] **Step 6: Commit**

```bash
git add Sources/ConveyCore/Converters/RTFToHTMLConverter.swift Tests/ConveyCoreTests/RTFToHTMLConverterTests.swift Tests/ConveyCoreTests/Fixtures/sample.rtf
git commit -m "feat: RTF -> HTML converter via NSAttributedString"
```

---

### Task 6: WebRuntime + vendored JS

**Files:**
- Create: `Sources/ConveyCore/Resources/web/runtime.html`
- Create: `Sources/ConveyCore/Resources/web/bridge.js`
- Vendor: `Sources/ConveyCore/Resources/web/turndown.js`, `marked.min.js`, `mermaid.min.js`
- Create: `Sources/ConveyCore/WebRuntime.swift`
- Test: `Tests/ConveyCoreTests/WebRuntimeTests.swift`

**Interfaces:**
- Produces: `@MainActor final class WebRuntime` with `init()`, `func whenReady() async throws`, `func call(_ body: String, arguments: [String: Any]) async throws -> Any?`.

- [ ] **Step 1: Vendor the JS libraries (pinned versions)**

```bash
cd /Users/jjverhoeks/src/tries/2026-07-21-convey/Sources/ConveyCore/Resources/web
curl -fsSL https://unpkg.com/turndown@7.2.0/dist/turndown.js -o turndown.js
curl -fsSL https://unpkg.com/marked@12.0.0/marked.min.js -o marked.min.js
curl -fsSL https://unpkg.com/mermaid@10.9.0/dist/mermaid.min.js -o mermaid.min.js
ls -la
```
Expected: three non-empty `.js` files. Verify each defines a browser global (`TurndownService`, `marked`, `mermaid`); if the mermaid UMD build does not attach `window.mermaid`, switch the vendored file to `https://unpkg.com/mermaid@10.9.0/dist/mermaid.js` and re-check.

- [ ] **Step 2: Write `runtime.html`**

`Sources/ConveyCore/Resources/web/runtime.html`:

```html
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <script src="turndown.js"></script>
    <script src="marked.min.js"></script>
    <script src="mermaid.min.js"></script>
    <script src="bridge.js"></script>
  </head>
  <body></body>
</html>
```

- [ ] **Step 3: Write `bridge.js`**

`Sources/ConveyCore/Resources/web/bridge.js`:

```js
const _turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });

window.htmlToMarkdown = (html) => _turndown.turndown(html);

window.markdownToHtml = (md) => marked.parse(md);

window.htmlToPlainText = (html) => {
  const el = document.createElement("div");
  el.innerHTML = html;
  return el.innerText || el.textContent || "";
};

if (window.mermaid) {
  mermaid.initialize({ startOnLoad: false });
}

window.mermaidToSvg = async (src) => {
  const id = "conv" + (window._n = (window._n || 0) + 1);
  const { svg } = await mermaid.render(id, src);
  return svg;
};

window.mermaidToPngDataUrl = async (src, scale) => {
  const id = "conv" + (window._n = (window._n || 0) + 1);
  const { svg } = await mermaid.render(id, src);
  const url = "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svg)));
  const img = new Image();
  await new Promise((resolve, reject) => {
    img.onload = resolve;
    img.onerror = reject;
    img.src = url;
  });
  const s = scale || 2;
  const w = img.width || 800;
  const h = img.height || 600;
  const canvas = document.createElement("canvas");
  canvas.width = w * s;
  canvas.height = h * s;
  const ctx = canvas.getContext("2d");
  ctx.scale(s, s);
  ctx.drawImage(img, 0, 0);
  return canvas.toDataURL("image/png");
};
```

- [ ] **Step 4: Write the failing integration test**

`Tests/ConveyCoreTests/WebRuntimeTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class WebRuntimeTests: XCTestCase {
    @MainActor
    func testEvaluatesJavaScript() async throws {
        let runtime = WebRuntime()
        let result = try await runtime.call("return 1 + 1;", arguments: [:])
        XCTAssertEqual((result as? NSNumber)?.intValue, 2)
    }

    @MainActor
    func testBridgeFunctionsLoaded() async throws {
        let runtime = WebRuntime()
        let result = try await runtime.call("return typeof window.htmlToMarkdown;", arguments: [:])
        XCTAssertEqual(result as? String, "function")
    }
}
```

- [ ] **Step 5: Run test to verify it fails**

Run: `swift test --filter WebRuntimeTests`
Expected: FAIL — `WebRuntime` undefined.

- [ ] **Step 6: Implement `WebRuntime`**

`Sources/ConveyCore/WebRuntime.swift`:

```swift
import Foundation
import WebKit

@MainActor
public final class WebRuntime: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isReady = false

    public override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        guard let url = Bundle.module.url(
            forResource: "runtime",
            withExtension: "html",
            subdirectory: "web"
        ) else {
            fatalError("runtime.html missing from ConveyCore bundle")
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    public func whenReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { continuation in
            self.readyContinuation = continuation
        }
    }

    public func call(_ body: String, arguments: [String: Any]) async throws -> Any? {
        try await whenReady()
        return try await webView.callAsyncJavaScript(
            body,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        readyContinuation?.resume()
        readyContinuation = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter WebRuntimeTests`
Expected: PASS (2 tests). If it hangs, WKWebView needs the main run loop — confirm the tests are `@MainActor` (they are) and that `swift test` is run on a machine with a window server (local macOS, not a headless SSH session without one).

- [ ] **Step 8: Commit**

```bash
git add Sources/ConveyCore/Resources/web Sources/ConveyCore/WebRuntime.swift Tests/ConveyCoreTests/WebRuntimeTests.swift
git commit -m "feat: WebRuntime (hidden WKWebView) + vendored turndown/marked/mermaid"
```

---

### Task 7: HTML → Markdown and HTML → Plain-text converters

**Files:**
- Create: `Sources/ConveyCore/Converters/HTMLToMarkdownConverter.swift`
- Create: `Sources/ConveyCore/Converters/HTMLToPlainTextConverter.swift`
- Create: `Tests/ConveyCoreTests/Fixtures/confluence.html`
- Test: `Tests/ConveyCoreTests/HTMLConverterTests.swift`

**Interfaces:**
- Consumes: `WebRuntime`.
- Produces: `struct HTMLToMarkdownConverter: Converter` (`.html` → `.markdown`, `init(runtime:)`); `struct HTMLToPlainTextConverter: Converter` (`.html` → `.plainText`, `init(runtime:)`).

- [ ] **Step 1: Create the HTML fixture**

`Tests/ConveyCoreTests/Fixtures/confluence.html`:

```html
<h1>Title</h1><p>Some <strong>bold</strong> text and a <a href="https://x.test">link</a>.</p><ul><li>one</li><li>two</li></ul>
```

- [ ] **Step 2: Write the failing tests**

`Tests/ConveyCoreTests/HTMLConverterTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class HTMLConverterTests: XCTestCase {
    private func fixture() throws -> String {
        let url = Bundle.module.url(forResource: "confluence", withExtension: "html", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @MainActor
    func testHtmlToMarkdown() async throws {
        let runtime = WebRuntime()
        let result = try await HTMLToMarkdownConverter(runtime: runtime).convert(.text(fixture()))
        let md = try XCTUnwrap(result.text)
        XCTAssertTrue(md.contains("# Title"))
        XCTAssertTrue(md.contains("**bold**"))
        XCTAssertTrue(md.contains("[link](https://x.test)"))
        XCTAssertTrue(md.contains("-   one") || md.contains("- one"))
    }

    @MainActor
    func testHtmlToPlainText() async throws {
        let runtime = WebRuntime()
        let result = try await HTMLToPlainTextConverter(runtime: runtime).convert(.text(fixture()))
        let text = try XCTUnwrap(result.text)
        XCTAssertTrue(text.contains("Title"))
        XCTAssertFalse(text.contains("<strong>"))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter HTMLConverterTests`
Expected: FAIL — converters undefined.

- [ ] **Step 4: Implement both converters**

`Sources/ConveyCore/Converters/HTMLToMarkdownConverter.swift`:

```swift
public struct HTMLToMarkdownConverter: Converter {
    public let from: Format = .html
    public let to: Format = .markdown
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(html) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return window.htmlToMarkdown(html);", arguments: ["html": html])
        guard let markdown = result as? String else {
            throw ConversionError.engineFailed("turndown")
        }
        return .text(markdown)
    }
}
```

`Sources/ConveyCore/Converters/HTMLToPlainTextConverter.swift`:

```swift
public struct HTMLToPlainTextConverter: Converter {
    public let from: Format = .html
    public let to: Format = .plainText
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(html) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return window.htmlToPlainText(html);", arguments: ["html": html])
        guard let text = result as? String else {
            throw ConversionError.engineFailed("htmlToPlainText")
        }
        return .text(text)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter HTMLConverterTests`
Expected: PASS (2 tests). (If the bullet assertion fails, inspect turndown's actual list output and align the assertion — turndown 7.2.0 uses `-   item`.)

- [ ] **Step 6: Commit**

```bash
git add Sources/ConveyCore/Converters/HTMLToMarkdownConverter.swift Sources/ConveyCore/Converters/HTMLToPlainTextConverter.swift Tests/ConveyCoreTests/Fixtures/confluence.html Tests/ConveyCoreTests/HTMLConverterTests.swift
git commit -m "feat: HTML -> Markdown and HTML -> plain-text converters"
```

---

### Task 8: Markdown → HTML converter

**Files:**
- Create: `Sources/ConveyCore/Converters/MarkdownToHTMLConverter.swift`
- Test: `Tests/ConveyCoreTests/MarkdownToHTMLConverterTests.swift`

**Interfaces:**
- Consumes: `WebRuntime`.
- Produces: `struct MarkdownToHTMLConverter: Converter` (`.markdown` → `.html`, `init(runtime:)`).

- [ ] **Step 1: Write the failing test**

`Tests/ConveyCoreTests/MarkdownToHTMLConverterTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class MarkdownToHTMLConverterTests: XCTestCase {
    @MainActor
    func testMarkdownToHtml() async throws {
        let runtime = WebRuntime()
        let result = try await MarkdownToHTMLConverter(runtime: runtime).convert(.text("# Hi\n\n**bold**"))
        let html = try XCTUnwrap(result.text)
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownToHTMLConverterTests`
Expected: FAIL — converter undefined.

- [ ] **Step 3: Implement the converter**

`Sources/ConveyCore/Converters/MarkdownToHTMLConverter.swift`:

```swift
public struct MarkdownToHTMLConverter: Converter {
    public let from: Format = .markdown
    public let to: Format = .html
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(markdown) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return window.markdownToHtml(md);", arguments: ["md": markdown])
        guard let html = result as? String else {
            throw ConversionError.engineFailed("marked")
        }
        return .text(html)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownToHTMLConverterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyCore/Converters/MarkdownToHTMLConverter.swift Tests/ConveyCoreTests/MarkdownToHTMLConverterTests.swift
git commit -m "feat: Markdown -> HTML converter via marked"
```

---

### Task 9: Mermaid → SVG and Mermaid → PNG converters

**Files:**
- Create: `Sources/ConveyCore/Converters/MermaidConverters.swift`
- Test: `Tests/ConveyCoreTests/MermaidConverterTests.swift`

**Interfaces:**
- Consumes: `WebRuntime`.
- Produces: `struct MermaidToSVGConverter: Converter` (`.mermaid` → `.svg`, `init(runtime:)`, output `.text(svg)`); `struct MermaidToPNGConverter: Converter` (`.mermaid` → `.png`, `init(runtime:)`, output `.bytes(pngData)`).

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyCoreTests/MermaidConverterTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class MermaidConverterTests: XCTestCase {
    let source = "flowchart TD\n A[Start] --> B[End]"

    @MainActor
    func testMermaidToSvg() async throws {
        let runtime = WebRuntime()
        let result = try await MermaidToSVGConverter(runtime: runtime).convert(.text(source))
        let svg = try XCTUnwrap(result.text)
        XCTAssertTrue(svg.contains("<svg"))
    }

    @MainActor
    func testMermaidToPng() async throws {
        let runtime = WebRuntime()
        let result = try await MermaidToPNGConverter(runtime: runtime).convert(.text(source))
        let data = try XCTUnwrap(result.bytes)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MermaidConverterTests`
Expected: FAIL — converters undefined.

- [ ] **Step 3: Implement both converters**

`Sources/ConveyCore/Converters/MermaidConverters.swift`:

```swift
import Foundation

public struct MermaidToSVGConverter: Converter {
    public let from: Format = .mermaid
    public let to: Format = .svg
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(src) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return await window.mermaidToSvg(src);", arguments: ["src": src])
        guard let svg = result as? String else {
            throw ConversionError.engineFailed("mermaid svg")
        }
        return .text(svg)
    }
}

public struct MermaidToPNGConverter: Converter {
    public let from: Format = .mermaid
    public let to: Format = .png
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(src) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return await window.mermaidToPngDataUrl(src, 2);", arguments: ["src": src])
        guard let dataURL = result as? String,
              let comma = dataURL.range(of: ","),
              let data = Data(base64Encoded: String(dataURL[comma.upperBound...])) else {
            throw ConversionError.engineFailed("mermaid png")
        }
        return .bytes(data)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MermaidConverterTests`
Expected: PASS (2 tests). (If PNG width comes back 0 and rendering is blank, the SVG lacked intrinsic size; note it and fall back to reading `viewBox` in `bridge.js` — tracked as a known-quality item, not a blocker for SVG output.)

- [ ] **Step 5: Commit**

```bash
git add Sources/ConveyCore/Converters/MermaidConverters.swift Tests/ConveyCoreTests/MermaidConverterTests.swift
git commit -m "feat: Mermaid -> SVG and Mermaid -> PNG converters"
```

---

### Task 10: PasteboardWriter + Convey facade

**Files:**
- Create: `Sources/ConveyCore/PasteboardWriter.swift`
- Create: `Sources/ConveyCore/Convey.swift`
- Test: `Tests/ConveyCoreTests/PasteboardWriterTests.swift`
- Test: `Tests/ConveyCoreTests/ConveyFacadeTests.swift`

**Interfaces:**
- Produces: `struct PasteboardWriter { static func uti(for: Format) -> String; @MainActor func write(_:as:to:) }`; `@MainActor final class Convey { let graph: ConversionGraph; init(); func convert(_:from:to:) async throws -> Payload }`. The facade registers all converters (pure + WebRuntime-backed) so `graph.validTargets`/`convert` work over the full v1 catalog.
- Consumes: every converter from Tasks 4–9, `ConversionGraph`, `WebRuntime`.

- [ ] **Step 1: Write the failing tests**

`Tests/ConveyCoreTests/PasteboardWriterTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class PasteboardWriterTests: XCTestCase {
    func testUtiMapping() {
        XCTAssertEqual(PasteboardWriter.uti(for: .markdown), "public.utf8-plain-text")
        XCTAssertEqual(PasteboardWriter.uti(for: .html), "public.html")
        XCTAssertEqual(PasteboardWriter.uti(for: .png), "public.png")
        XCTAssertEqual(PasteboardWriter.uti(for: .base64DataURI), "public.utf8-plain-text")
    }
}
```

`Tests/ConveyCoreTests/ConveyFacadeTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class ConveyFacadeTests: XCTestCase {
    @MainActor
    func testFacadeExposesHtmlToMarkdownTarget() {
        let convey = Convey()
        XCTAssertTrue(convey.graph.validTargets(from: [.html]).contains(.markdown))
    }

    @MainActor
    func testFacadeComposesRtfToMarkdown() {
        let convey = Convey()
        // RTF -> HTML (AppKit) -> Markdown (turndown) must be a discoverable path.
        XCTAssertNotNil(convey.graph.path(from: .rtf, to: .markdown))
    }

    @MainActor
    func testFacadeConvertsHtmlToMarkdown() async throws {
        let convey = Convey()
        let result = try await convey.convert(.text("<h1>Hi</h1>"), from: .html, to: .markdown)
        XCTAssertEqual(result.text?.trimmingCharacters(in: .whitespacesAndNewlines), "# Hi")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PasteboardWriterTests`
Expected: FAIL — `PasteboardWriter`/`Convey` undefined.

- [ ] **Step 3: Implement `PasteboardWriter`**

`Sources/ConveyCore/PasteboardWriter.swift`:

```swift
import Foundation
import AppKit

public struct PasteboardWriter {
    public init() {}

    public static func uti(for format: Format) -> String {
        switch format {
        case .markdown, .plainText, .mermaid, .base64DataURI:
            return "public.utf8-plain-text"
        case .html:
            return "public.html"
        case .svg:
            return "public.svg-image"
        case .png, .image:
            return "public.png"
        case .rtf:
            return "public.rtf"
        }
    }

    @MainActor
    public func write(_ payload: Payload, as format: Format, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let type = NSPasteboard.PasteboardType(Self.uti(for: format))
        switch payload {
        case let .text(string):
            pasteboard.setString(string, forType: type)
        case let .bytes(data):
            pasteboard.setData(data, forType: type)
        }
    }
}
```

- [ ] **Step 4: Implement the `Convey` facade**

`Sources/ConveyCore/Convey.swift`:

```swift
@MainActor
public final class Convey {
    public let graph: ConversionGraph
    private let runtime: WebRuntime

    public init() {
        let runtime = WebRuntime()
        self.runtime = runtime
        graph = ConversionGraph([
            ImageToBase64Converter(),
            RTFToHTMLConverter(),
            HTMLToMarkdownConverter(runtime: runtime),
            HTMLToPlainTextConverter(runtime: runtime),
            MarkdownToHTMLConverter(runtime: runtime),
            MermaidToSVGConverter(runtime: runtime),
            MermaidToPNGConverter(runtime: runtime),
        ])
    }

    public func convert(_ payload: Payload, from: Format, to: Format) async throws -> Payload {
        try await graph.convert(payload, from: from, to: to)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PasteboardWriterTests && swift test --filter ConveyFacadeTests`
Expected: PASS (1 + 3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ConveyCore/PasteboardWriter.swift Sources/ConveyCore/Convey.swift Tests/ConveyCoreTests/PasteboardWriterTests.swift Tests/ConveyCoreTests/ConveyFacadeTests.swift
git commit -m "feat: PasteboardWriter + Convey facade registering the v1 catalog"
```

---

### Task 11: `convey` CLI

**Files:**
- Create: `Sources/convey/main.swift`
- Create: `Sources/convey/CommandRouter.swift`
- Test: `Tests/ConveyCoreTests/CommandRouterTests.swift`

**Interfaces:**
- Consumes: `Convey`, `PasteboardReader`, `PasteboardWriter`, `SystemPasteboard`, `Format`, `Payload`.
- Produces (in `CommandRouter.swift`, so it can be unit-tested without a run loop): `enum CLICommand { case list; case convert(from: Format, to: Format); case usage }`; `func parseCommand(_ args: [String]) -> CLICommand`; `let edgeTable: [String: (Format, Format)]`.

- [ ] **Step 1: Write the failing test for command parsing**

`Tests/ConveyCoreTests/CommandRouterTests.swift`:

```swift
import XCTest
@testable import ConveyCore

final class CommandRouterTests: XCTestCase {
    func testParsesKnownEdge() {
        guard case let .convert(from, to) = parseCommand(["html2md"]) else {
            return XCTFail("expected convert")
        }
        XCTAssertEqual(from, .html)
        XCTAssertEqual(to, .markdown)
    }

    func testParsesList() {
        guard case .list = parseCommand(["list"]) else { return XCTFail("expected list") }
    }

    func testUnknownIsUsage() {
        guard case .usage = parseCommand(["frobnicate"]) else { return XCTFail("expected usage") }
    }

    func testEmptyIsUsage() {
        guard case .usage = parseCommand([]) else { return XCTFail("expected usage") }
    }
}
```

Note: `parseCommand`, `CLICommand`, and `edgeTable` live in `ConveyCore` (a new file `Sources/ConveyCore/CommandRouter.swift`) so the test target can import them. The `convey` target's `main.swift` only does I/O and the run loop.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CommandRouterTests`
Expected: FAIL — `parseCommand` undefined.

- [ ] **Step 3: Implement the router in ConveyCore**

`Sources/ConveyCore/CommandRouter.swift`:

```swift
public enum CLICommand: Equatable {
    case list
    case convert(from: Format, to: Format)
    case usage
}

public let edgeTable: [String: (Format, Format)] = [
    "html2md": (.html, .markdown),
    "html2txt": (.html, .plainText),
    "md2html": (.markdown, .html),
    "rtf2md": (.rtf, .markdown),
    "img2b64": (.image, .base64DataURI),
    "mmd2svg": (.mermaid, .svg),
    "mmd2png": (.mermaid, .png),
]

public func parseCommand(_ args: [String]) -> CLICommand {
    guard let first = args.first else { return .usage }
    if first == "list" { return .list }
    if let edge = edgeTable[first] { return .convert(from: edge.0, to: edge.1) }
    return .usage
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CommandRouterTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Write the CLI entry point**

`Sources/convey/main.swift` (top-level executable; uses `NSApplication.run()` to drive the main run loop that `WKWebView` needs — this is the reliable pattern for WebKit inside a CLI):

```swift
import AppKit
import ConveyCore

let usage = """
convey <command>

  list                        show detected clipboard flavors + valid targets
  html2md | html2txt          convert clipboard HTML
  md2html                     convert clipboard Markdown to HTML
  rtf2md                      convert clipboard RTF to Markdown
  img2b64                     convert clipboard image to a base64 data-URI
  mmd2svg | mmd2png           render clipboard Mermaid text

Reads the clipboard, converts, writes the result back to the clipboard.
For text edges, piped stdin is used as input and stdout receives the result.
"""

@MainActor
func run() async -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    let command = parseCommand(args)

    switch command {
    case .usage:
        print(usage)
        return 2

    case .list:
        let sources = PasteboardReader().sources(from: SystemPasteboard())
        let targets = Convey().graph.validTargets(from: sources)
        print("sources: " + sources.map(\.rawValue).joined(separator: ", "))
        print("targets: " + targets.map(\.rawValue).joined(separator: ", "))
        return 0

    case let .convert(from, to):
        let reader = PasteboardReader()
        let snapshot = SystemPasteboard()

        // Text edges accept piped stdin; otherwise read from the clipboard.
        let stdinText = readPipedStdin()
        let input: Payload?
        if let stdinText, from != .image {
            input = .text(stdinText)
        } else {
            input = reader.payload(for: from, from: snapshot)
        }
        guard let input else {
            FileHandle.standardError.write(Data("convey: no \(from.rawValue) content on clipboard\n".utf8))
            return 1
        }

        do {
            let result = try await Convey().convert(input, from: from, to: to)
            if stdinText != nil, case let .text(out) = result {
                print(out)
            } else {
                PasteboardWriter().write(result, as: to, to: .general)
                FileHandle.standardError.write(Data("convey: wrote \(to.rawValue) to clipboard\n".utf8))
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("convey: \(error)\n".utf8))
            return 1
        }
    }
}

func readPipedStdin() -> String? {
    guard isatty(fileno(stdin)) == 0 else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { return nil }
    return String(data: data, encoding: .utf8)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

Task { @MainActor in
    let code = await run()
    exit(code)
}

app.run()
```

- [ ] **Step 6: Build and smoke-test the CLI**

```bash
cd /Users/jjverhoeks/src/tries/2026-07-21-convey
swift build
echo '<h1>Hi</h1><p><b>bold</b></p>' | .build/debug/convey html2md
```
Expected stdout:
```
# Hi

**bold**
```

- [ ] **Step 7: Commit**

```bash
git add Sources/ConveyCore/CommandRouter.swift Sources/convey/main.swift Tests/ConveyCoreTests/CommandRouterTests.swift
git commit -m "feat: convey CLI (list + convert edges, clipboard + stdin/stdout)"
```

---

### Task 12: README + full-suite green + tag

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

`README.md`:

```markdown
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

## Build & test

    swift build
    swift test

Requires macOS 13+ and a window server session (WebKit-backed conversions).
```

- [ ] **Step 2: Run the full test suite**

Run: `swift test`
Expected: PASS — all suites (Payload, ConversionGraph, PasteboardReader, ImageToBase64, RTFToHTML, WebRuntime, HTMLConverter, MarkdownToHTML, MermaidConverter, PasteboardWriter, ConveyFacade, CommandRouter).

- [ ] **Step 3: Commit and tag**

```bash
git add README.md docs
git commit -m "docs: README + Plan 1 complete"
git tag plan1-core-cli
```

---

## Self-Review

**Spec coverage (Plan 1 scope):**
- HTML→Markdown — Task 7 ✓
- Any→Plain text — Task 7 (HTML→plainText) + composed RTF→plainText via graph ✓
- RTF→Markdown — composed RTF→HTML (Task 5) → HTML→Markdown (Task 7), verified in Task 10 ✓
- Markdown→HTML — Task 8 ✓
- Image→base64 — Task 4 ✓
- Mermaid→SVG/PNG — Task 9 ✓
- Flavor detection table + Mermaid heuristic — Task 3 ✓
- Shared headless core consumed by a thin CLI — Tasks 1–11 ✓
- CLI WebRuntime run-loop concern — addressed via `NSApplication.run()`; documented fallback if unavailable.
- **Deferred to a follow-up (documented non-goal here):** Mermaid → Excalidraw/whiteboard/Atlassian JSON targets (require porting Lucent's converter) and clipboard *history* (Plan 2, part of the app UI).

**Placeholder scan:** none — every code step contains complete code.

**Type consistency:** `Format` raw values, `Payload` cases, `Converter.convert` signature, `WebRuntime.call(_:arguments:)`, and `Convey.graph` are used identically across tasks.

**Known-quality items (flagged inline, not blockers):** Mermaid PNG sizing when SVG lacks intrinsic dimensions (Task 9); turndown list-marker exact text (Task 7); RTF HTML-writer assertion robustness (Task 5).
