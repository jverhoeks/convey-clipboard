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
