import XCTest
@testable import ConveyCore

final class AsciicastTests: XCTestCase {
    private func record(_ dir: Character, sec: UInt64, usec: UInt32, _ body: [UInt8]) -> [UInt8] {
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
        return le(UInt64(body.count)) + le(sec) + le(usec) + le(UInt32(dir.asciiValue!)) + body
    }

    func testConvertsOutputKeepsTimingAndJoinsSplitUTF8() throws {
        let euro = Array("€".utf8)  // 3 bytes, split across two chunks
        let data = Data(record("s", sec: 100, usec: 0, [])
            + record("i", sec: 100, usec: 100, Array("ls\r".utf8))
            + record("o", sec: 100, usec: 500_000, Array("\u{1b}[31mhi ".utf8) + euro.prefix(1))
            + record("o", sec: 101, usec: 250_000, Array(euro.dropFirst()) + Array("\r\n".utf8))
            + record("e", sec: 102, usec: 0, []))
        let lines = try Asciicast.fromScriptRecording(data, width: 80, height: 24).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], #"{"height":24,"timestamp":100,"version":2,"width":80}"#)
        XCTAssertEqual(lines[1], #"[0.500000,"o","\u001b[31mhi "]"#)
        XCTAssertEqual(lines[2], #"[1.250000,"o","€\r\n"]"#)
    }

    func testTruncatedThrows() {
        var bad = record("o", sec: 1, usec: 0, Array("hello".utf8))
        bad.removeLast(2)
        XCTAssertThrowsError(try Asciicast.fromScriptRecording(Data(bad), width: 80, height: 24))
    }
}
