import XCTest
import AppKit
import ConveyCore
@testable import ConveyKit

final class PreviewCacheTests: XCTestCase {
    private func imageEntry(_ id: UUID, png: Data) -> ClipboardEntry {
        ClipboardEntry(id: id, sources: [.image], kind: .image, primaryFormat: .image,
                       text: nil, imageData: png, previewText: nil, createdAt: Date(timeIntervalSince1970: 0))
    }
    private func png() throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    @MainActor
    func testMemoizesSameInstance() async throws {
        let cache = PreviewCache(convey: Convey())
        let e = imageEntry(UUID(), png: try png())
        let firstResult = await cache.image(for: e)
        let secondResult = await cache.image(for: e)
        let first = try XCTUnwrap(firstResult)
        let second = try XCTUnwrap(secondResult)
        XCTAssertTrue(first === second)          // same NSImage instance -> no recompute
        XCTAssertTrue(cache.cached(e.id) === first)
    }

    @MainActor
    func testEvictsOldestBeyondCapacity() async throws {
        let cache = PreviewCache(convey: Convey(), capacity: 2)
        let data = try png()
        let a = imageEntry(UUID(), png: data), b = imageEntry(UUID(), png: data), c = imageEntry(UUID(), png: data)
        _ = await cache.image(for: a); _ = await cache.image(for: b); _ = await cache.image(for: c)
        XCTAssertNil(cache.cached(a.id))         // oldest evicted
        XCTAssertNotNil(cache.cached(b.id))
        XCTAssertNotNil(cache.cached(c.id))
    }
}
