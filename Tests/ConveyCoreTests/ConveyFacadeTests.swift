import XCTest
@testable import ConveyCore

final class ConveyFacadeTests: XCTestCase {
    @MainActor
    func testFacadeExposesHtmlToMarkdownTarget() {
        let convey = Convey()
        XCTAssertTrue(convey.graph.validTargets(from: [.html]).contains(.markdown))
    }

    @MainActor
    func testFacadeComposesRtfToMarkdown() {
        let convey = Convey()
        // RTF -> HTML (AppKit) -> Markdown (turndown) must be a discoverable path.
        XCTAssertNotNil(convey.graph.path(from: .rtf, to: .markdown))
    }

    @MainActor
    func testFacadeConvertsHtmlToMarkdown() async throws {
        let convey = Convey()
        let result = try await convey.convert(.text("<h1>Hi</h1>"), from: .html, to: .markdown)
        XCTAssertEqual(result.text?.trimmingCharacters(in: .whitespacesAndNewlines), "# Hi")
    }

    @MainActor
    func testFacadeConvertsRtfToMarkdownEndToEnd() async throws {
        let url = Bundle.module.url(forResource: "sample", withExtension: "rtf", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let result = try await Convey().convert(.bytes(data), from: .rtf, to: .markdown)
        let md = try XCTUnwrap(result.text)
        XCTAssertTrue(md.contains("Hello"))
        XCTAssertTrue(md.contains("bold"))
    }
}
