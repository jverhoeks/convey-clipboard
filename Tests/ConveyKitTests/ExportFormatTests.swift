import XCTest
import ConveyCore
@testable import ConveyKit

final class ExportFormatTests: XCTestCase {
    func testBase64IsNotAFileType() {
        XCTAssertNil(ExportFormat.fileType(for: .base64DataURI))
    }

    func testImageResolvesToPNG() {
        let ef = ExportFormat.fileType(for: .image)
        XCTAssertEqual(ef?.format, .png)
        XCTAssertEqual(ef?.fileExtension, "png")
        XCTAssertEqual(ef?.isText, false)
    }

    func testHTMLFileType() {
        let ef = ExportFormat.fileType(for: .html)
        XCTAssertEqual(ef?.fileExtension, "html")
        XCTAssertEqual(ef?.isText, true)
    }

    func testHTMLOptions() {
        let opts = ExportFormat.options(nativeFormat: .html, reachable: [.markdown, .plainText])
        XCTAssertEqual(opts.map(\.label), ["HTML", "MD", "TXT"])
    }

    func testImageOptionsAreSinglePNG() {
        let opts = ExportFormat.options(nativeFormat: .image, reachable: [.base64DataURI])
        XCTAssertEqual(opts.map(\.format), [.png])
    }

    func testPlainTextOptions() {
        let opts = ExportFormat.options(nativeFormat: .plainText, reachable: [])
        XCTAssertEqual(opts.map(\.label), ["TXT"])
    }

    func testMermaidOptions() {
        let opts = ExportFormat.options(nativeFormat: .mermaid, reachable: [.svg, .png])
        XCTAssertEqual(opts.map(\.label), ["Mermaid", "SVG", "PNG"])
    }

    func testMarkdownOptionsDedupNativeFirst() {
        let opts = ExportFormat.options(nativeFormat: .markdown, reachable: [.html, .plainText])
        XCTAssertEqual(opts.map(\.label), ["MD", "HTML", "TXT"])
    }
}
