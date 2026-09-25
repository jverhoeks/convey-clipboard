import XCTest
@testable import ConveyCore

final class CommandRouterTests: XCTestCase {
    func testParsesKnownEdge() {
        guard case let .convert(from, to) = parseCommand(["html2md"]) else {
            return XCTFail("expected convert")
        }
        XCTAssertEqual(from, .html)
        XCTAssertEqual(to, .markdown)
    }

    func testParsesList() {
        guard case .list = parseCommand(["list"]) else { return XCTFail("expected list") }
    }

    func testUnknownIsUsage() {
        guard case .usage = parseCommand(["frobnicate"]) else { return XCTFail("expected usage") }
    }

    func testParsesVersion() {
        guard case .version = parseCommand(["version"]) else { return XCTFail("expected version") }
        guard case .version = parseCommand(["--version"]) else { return XCTFail("expected version") }
        guard case .version = parseCommand(["-v"]) else { return XCTFail("expected version") }
        guard case .usage = parseCommand(["frobnicate"]) else { return XCTFail("expected usage") }
    }

    func testEmptyIsUsage() {
        guard case .usage = parseCommand([]) else { return XCTFail("expected usage") }
    }

    func testParsesRecAndPlay() {
        XCTAssertEqual(parseCommand(["rec"]), .rec(nil))
        XCTAssertEqual(parseCommand(["rec", "demo.cast"]), .rec("demo.cast"))
        XCTAssertEqual(parseCommand(["play", "demo.cast"]), .play("demo.cast"))
        XCTAssertEqual(parseCommand(["play"]), .usage)
    }

    func testControlVerbsAreForwarded() {
        XCTAssertEqual(parseCommand(["record", "window", "Terminal"]), .control(["record", "window", "Terminal"]))
        XCTAssertEqual(parseCommand(["windows"]), .control(["windows"]))
    }
}
