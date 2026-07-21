import XCTest
@testable import ConveyCore

final class PayloadTests: XCTestCase {
    func testTextAccessor() {
        XCTAssertEqual(Payload.text("hi").text, "hi")
        XCTAssertNil(Payload.text("hi").bytes)
    }

    func testBytesAccessor() {
        let data = Data([1, 2, 3])
        XCTAssertEqual(Payload.bytes(data).bytes, data)
        XCTAssertNil(Payload.bytes(data).text)
    }

    func testFormatRawValuesAreStable() {
        XCTAssertEqual(Format.plainText.rawValue, "plainText")
        XCTAssertEqual(Format.base64DataURI.rawValue, "base64DataURI")
    }
}
