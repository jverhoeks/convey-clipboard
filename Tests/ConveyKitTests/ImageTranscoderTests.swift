import XCTest
import AppKit
@testable import ConveyKit

final class ImageTranscoderTests: XCTestCase {
    private func sampleTIFF() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.tiffRepresentation!
    }

    func testTIFFConvertsToPNG() {
        let png = ImageTranscoder.pngData(from: sampleTIFF())
        XCTAssertNotNil(png)
        // PNG magic number: 0x89 'P' 'N' 'G'
        XCTAssertEqual(Array(png!.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ImageTranscoder.pngData(from: Data([0x00, 0x01, 0x02])))
    }
}
