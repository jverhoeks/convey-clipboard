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
