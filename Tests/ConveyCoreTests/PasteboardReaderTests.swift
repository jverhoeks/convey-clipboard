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
