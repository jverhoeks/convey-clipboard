import XCTest
@testable import ConveyCore

final class MermaidConverterTests: XCTestCase {
    let source = "flowchart TD\n A[Start] --> B[End]"

    @MainActor
    func testMermaidToSvg() async throws {
        let runtime = WebRuntime()
        let result = try await MermaidToSVGConverter(runtime: runtime).convert(.text(source))
        let svg = try XCTUnwrap(result.text)
        XCTAssertTrue(svg.contains("<svg"))
    }

    @MainActor
    func testMermaidToPng() async throws {
        let runtime = WebRuntime()
        let result = try await MermaidToPNGConverter(runtime: runtime).convert(.text(source))
        let data = try XCTUnwrap(result.bytes)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
