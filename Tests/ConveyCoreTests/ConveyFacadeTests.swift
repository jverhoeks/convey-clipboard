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
}
