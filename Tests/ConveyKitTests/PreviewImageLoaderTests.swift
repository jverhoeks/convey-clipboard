import XCTest
import AppKit
import ConveyCore
@testable import ConveyKit

final class PreviewImageLoaderTests: XCTestCase {
    private func entry(kind: ClipboardKind, text: String?, image: Data?, sources: [Format], primary: Format) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: sources, kind: kind, primaryFormat: primary,
                       text: text, imageData: image, previewText: text, createdAt: Date(timeIntervalSince1970: 0))
    }

    @MainActor
    func testThumbnailForImageEntry() throws {
        // Build a tiny valid PNG via NSBitmapImageRep.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let e = entry(kind: .image, text: nil, image: png, sources: [.image], primary: .image)
        XCTAssertNotNil(PreviewImageLoader.thumbnail(for: e))
    }

    @MainActor
    func testThumbnailNilForNonImage() {
        let e = entry(kind: .plainText, text: "hi", image: nil, sources: [.plainText], primary: .plainText)
        XCTAssertNil(PreviewImageLoader.thumbnail(for: e))
    }

    @MainActor
    func testRenderedMermaidProducesImage() async throws {
        let src = "flowchart TD\n A[Start] --> B[End]"
        let e = entry(kind: .mermaid, text: src, image: nil, sources: [.plainText, .mermaid], primary: .mermaid)
        let image = await PreviewImageLoader.rendered(for: e, using: Convey())
        let unwrapped = try XCTUnwrap(image)          // real Mermaid->PNG via WebRuntime (needs GUI session)
        XCTAssertGreaterThan(unwrapped.size.width, 0)
    }
}
