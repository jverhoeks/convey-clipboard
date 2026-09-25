import XCTest
@testable import ConveyApp

final class ControlCommandTests: XCTestCase {
    func testParsesTargetsAndFlags() throws {
        XCTAssertEqual(try ControlCommand.parse(["windows", "--json"]), .windows(json: true, all: false))
        XCTAssertEqual(try ControlCommand.parse(["windows", "--all"]), .windows(json: false, all: true))
        XCTAssertEqual(try ControlCommand.parse(["shot", "screen"]), .shot(.screen(0), output: nil))
        XCTAssertEqual(try ControlCommand.parse(["shot", "screen", "1", "-o", "/tmp/a.png"]), .shot(.screen(1), output: "/tmp/a.png"))
        XCTAssertEqual(try ControlCommand.parse(["record", "window", "Google", "Chrome", "--duration", "5"]),
                       .record(.window("Google Chrome"), output: nil, duration: 5))
        XCTAssertEqual(try ControlCommand.parse(["record", "area", "10,20,300,200", "-o", "/tmp/v.mp4"]),
                       .record(.area(CGRect(x: 10, y: 20, width: 300, height: 200)), output: "/tmp/v.mp4", duration: nil))
        XCTAssertEqual(try ControlCommand.parse(["stop"]), .stop)
    }

    func testRejectsBadInput() {
        for bad in [["shot"], ["shot", "area", "1,2,3"], ["record", "screen", "--duration", "0"],
                    ["shot", "window"], ["shot", "screen", "-o"], ["frobnicate"]] {
            XCTAssertThrowsError(try ControlCommand.parse(bad), "\(bad)")
        }
    }
}
