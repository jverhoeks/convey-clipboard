import XCTest
import ConveyCore
@testable import ConveyKit

final class ClipboardEntryTests: XCTestCase {
    private func entry(text: String?, image: Data? = nil, sources: [Format],
                        primaryFormat: Format? = nil, previewText: String? = nil) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: sources, kind: ClipboardKind(sources: sources),
                       primaryFormat: primaryFormat ?? sources.first ?? .plainText,
                       text: text, imageData: image, previewText: previewText ?? text,
                       createdAt: Date(timeIntervalSince1970: 0))
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

    func testDecodesOldFormatMissingNewFields() throws {
        // Pre-fix history.json entries had no `primaryFormat`/`previewText` keys.
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "sources": ["html"],
            "kind": "html",
            "text": "<b>hi</b>",
            "imageData": null,
            "createdAt": 0
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.sources, [.html])
        XCTAssertEqual(decoded.primaryFormat, .html) // defaults to first source
        XCTAssertEqual(decoded.previewText, "<b>hi</b>") // defaults to text
    }

    func testDecodesOldFormatWithNoSourcesDefaultsPlainText() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "sources": [],
            "kind": "plainText",
            "text": null,
            "imageData": null,
            "createdAt": 0
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: data)
        XCTAssertEqual(decoded.primaryFormat, .plainText)
        XCTAssertNil(decoded.previewText)
    }
}
