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
