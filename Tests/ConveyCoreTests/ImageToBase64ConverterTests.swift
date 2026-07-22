import XCTest
import AppKit
@testable import ConveyCore

final class ImageToBase64ConverterTests: XCTestCase {
    let converter = ImageToBase64Converter()

    func testEncodesPngWithCorrectMime() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let result = try await converter.convert(.bytes(png))
        XCTAssertEqual(result, .text("data:image/png;base64," + png.base64EncodedString()))
    }

    func testDetectsJpeg() {
        XCTAssertEqual(ImageToBase64Converter.mime(for: Data([0xFF, 0xD8, 0xFF])), "image/jpeg")
    }

    @MainActor
    func testTranscodesTiffToPng() async throws {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation else {
            return XCTFail("could not build a TIFF fixture")
        }
        XCTAssertTrue(ImageToBase64Converter.isTIFF(tiff))

        let result = try await converter.convert(.bytes(tiff))
        let text = try XCTUnwrap(result.text)
        XCTAssertTrue(text.hasPrefix("data:image/png;base64,"))
    }

    func testRejectsTextPayload() async {
        do {
            _ = try await converter.convert(.text("x"))
            XCTFail("expected throw")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .wrongPayload(expected: "bytes"))
        } catch { XCTFail("wrong error") }
    }
}
