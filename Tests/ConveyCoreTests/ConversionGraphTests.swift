import XCTest
@testable import ConveyCore

private struct StubConverter: Converter {
    let from: Format
    let to: Format
    let transform: @Sendable (String) -> String
    func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(value) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        return .text(transform(value))
    }
}

final class ConversionGraphTests: XCTestCase {
    private func graph() -> ConversionGraph {
        ConversionGraph([
            StubConverter(from: .rtf, to: .html) { "<h>\($0)</h>" },
            StubConverter(from: .html, to: .markdown) { $0.replacingOccurrences(of: "<h>", with: "# ").replacingOccurrences(of: "</h>", with: "") },
        ])
    }

    func testValidTargetsReachableFromSource() {
        let targets = graph().validTargets(from: [.rtf])
        XCTAssertEqual(Set(targets), Set([.html, .markdown]))
    }

    func testValidTargetsExcludesSource() {
        XCTAssertFalse(graph().validTargets(from: [.rtf]).contains(.rtf))
    }

    func testPathIsMultiHop() {
        let path = graph().path(from: .rtf, to: .markdown)
        XCTAssertEqual(path?.count, 2)
    }

    func testConvertComposesEdges() async throws {
        let result = try await graph().convert(.text("hello"), from: .rtf, to: .markdown)
        XCTAssertEqual(result, .text("# hello"))
    }

    func testConvertThrowsWhenNoPath() async {
        do {
            _ = try await graph().convert(.text("x"), from: .markdown, to: .rtf)
            XCTFail("expected throw")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .noPath(from: .markdown, to: .rtf))
        } catch {
            XCTFail("wrong error type")
        }
    }
}
