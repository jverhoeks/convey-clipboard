import XCTest
import AppKit
@testable import ConveyCore

final class PasteboardWriterTests: XCTestCase {
    func testUtiMapping() {
        XCTAssertEqual(PasteboardWriter.uti(for: .markdown), "public.utf8-plain-text")
        XCTAssertEqual(PasteboardWriter.uti(for: .html), "public.html")
        XCTAssertEqual(PasteboardWriter.uti(for: .png), "public.png")
        XCTAssertEqual(PasteboardWriter.uti(for: .base64DataURI), "public.utf8-plain-text")
    }

    @MainActor
    func testWriteTextThenReadBack() {
        let pb = NSPasteboard(name: NSPasteboard.Name("convey.test.write"))
        PasteboardWriter().write(.text("hello"), as: .markdown, to: pb)
        XCTAssertEqual(pb.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")), "hello")
    }

    @MainActor
    func testWriteBytesThenReadBack() {
        let pb = NSPasteboard(name: NSPasteboard.Name("convey.test.write.bytes"))
        let data = Data([0x89, 0x50])
        PasteboardWriter().write(.bytes(data), as: .png, to: pb)
        XCTAssertEqual(pb.data(forType: NSPasteboard.PasteboardType("public.png")), data)
    }
}
