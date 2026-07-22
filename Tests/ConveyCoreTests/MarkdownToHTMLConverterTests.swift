import XCTest
@testable import ConveyCore

final class MarkdownToHTMLConverterTests: XCTestCase {
    @MainActor
    func testMarkdownToHtml() async throws {
        let runtime = WebRuntime()
        let result = try await MarkdownToHTMLConverter(runtime: runtime).convert(.text("# Hi\n\n**bold**"))
        let html = try XCTUnwrap(result.text)
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
    }
}
