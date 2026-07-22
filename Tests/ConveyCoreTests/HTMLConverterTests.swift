import XCTest
@testable import ConveyCore

final class HTMLConverterTests: XCTestCase {
    private func fixture() throws -> String {
        let url = Bundle.module.url(forResource: "confluence", withExtension: "html", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @MainActor
    func testHtmlToMarkdown() async throws {
        let runtime = WebRuntime()
        let result = try await HTMLToMarkdownConverter(runtime: runtime).convert(.text(fixture()))
        let md = try XCTUnwrap(result.text)
        XCTAssertTrue(md.contains("# Title"))
        XCTAssertTrue(md.contains("**bold**"))
        XCTAssertTrue(md.contains("[link](https://x.test)"))
        // turndown 7.2.0 with default bulletListMarker ("*") emits "*   one" (three spaces);
        // brief anticipated a possible "-   one"/"- one" form, but bridge.js does not set
        // bulletListMarker, so the library default ("*") is what's actually produced.
        XCTAssertTrue(md.contains("*   one") || md.contains("- one") || md.contains("-   one"))
    }

    @MainActor
    func testHtmlToPlainText() async throws {
        let runtime = WebRuntime()
        let result = try await HTMLToPlainTextConverter(runtime: runtime).convert(.text(fixture()))
        let text = try XCTUnwrap(result.text)
        XCTAssertTrue(text.contains("Title"))
        XCTAssertFalse(text.contains("<strong>"))
        // Block elements (h1/p/li) must be layout-separated, not mashed together:
        // a detached div's innerText would collapse to textContent with no breaks.
        XCTAssertTrue(text.contains("\n"))
        XCTAssertFalse(text.contains("Titleone"))
        XCTAssertTrue(text.contains("one"))
        XCTAssertTrue(text.contains("two"))
    }
}
