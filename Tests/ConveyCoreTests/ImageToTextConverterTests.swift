import AppKit
import XCTest
@testable import ConveyCore

final class ImageToTextConverterTests: XCTestCase {
    @MainActor
    private func image(text: String) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 1000, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 300).fill()
        (text as NSString).draw(at: NSPoint(x: 40, y: 120), withAttributes: [
            .font: NSFont.systemFont(ofSize: 52), .foregroundColor: NSColor.black,
        ])
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor
    func testImageTextIsDiscoverableAndRecognizedThroughFacade() async throws {
        let convey = Convey()
        XCTAssertTrue(convey.graph.validTargets(from: [.image]).contains(.plainText))
        let result = try await convey.convert(.bytes(image(text: "Hello Convey 123")),
                                               from: .image, to: .plainText)
        XCTAssertEqual(result.text, "Hello Convey 123")
        XCTAssertEqual(Format.plainText.fileExtension, "txt")
    }

    @MainActor
    func testBlankImageReportsNoText() async throws {
        let data = try image(text: "")
        do {
            _ = try await ImageToTextConverter().convert(.bytes(data))
            XCTFail("Expected a no-text error instead of empty output")
        } catch ImageTextError.noText {
            // The caller must not overwrite the clipboard or export an empty file.
        }
    }

    func testRejectsInvalidImageData() async {
        do {
            _ = try await ImageToTextConverter().convert(.bytes(Data("not an image".utf8)))
            XCTFail("Expected invalid image data to fail")
        } catch { }
    }

    func testRejectsTextPayload() async {
        do {
            _ = try await ImageToTextConverter().convert(.text("hello"))
            XCTFail("Expected bytes-only converter to fail")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .wrongPayload(expected: "bytes"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
