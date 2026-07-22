import XCTest
@testable import ConveyCore

final class WebRuntimeTests: XCTestCase {
    @MainActor
    func testEvaluatesJavaScript() async throws {
        let runtime = WebRuntime()
        let result = try await runtime.call("return 1 + 1;", arguments: [:])
        XCTAssertEqual((result as? NSNumber)?.intValue, 2)
    }

    @MainActor
    func testBridgeFunctionsLoaded() async throws {
        let runtime = WebRuntime()
        let result = try await runtime.call("return typeof window.htmlToMarkdown;", arguments: [:])
        XCTAssertEqual(result as? String, "function")
    }
}
