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
