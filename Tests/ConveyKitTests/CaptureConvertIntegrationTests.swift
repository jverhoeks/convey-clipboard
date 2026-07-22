import XCTest
import ConveyCore
@testable import ConveyKit

final class CaptureConvertIntegrationTests: XCTestCase {
    @MainActor
    func testHtmlEntryConvertsToRealMarkdown() async throws {
        // Simulate a Confluence copy: HTML flavor + plain-text fallback.
        struct Snap: PasteboardSnapshot {
            var availableTypes = ["public.html", "public.utf8-plain-text"]
            func data(forType t: String) -> Data? { nil }
            func string(forType t: String) -> String? {
                t == "public.html" ? "<h1>Title</h1><p><strong>bold</strong></p>" :
                t == "public.utf8-plain-text" ? "Title bold" : nil
            }
        }
        let entry = try XCTUnwrap(ClipboardMonitor().makeEntry(from: Snap(), id: UUID(), now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(entry.primaryFormat, .html)
        let convey = Convey()
        let result = try await convey.convert(try XCTUnwrap(entry.payload), from: entry.primaryFormat, to: .markdown)
        let md = try XCTUnwrap(result.text)
        XCTAssertTrue(md.contains("# Title"))     // real turndown output, not the flattened "Title bold"
        XCTAssertTrue(md.contains("**bold**"))
    }
}
