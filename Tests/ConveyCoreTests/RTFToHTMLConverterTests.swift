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
