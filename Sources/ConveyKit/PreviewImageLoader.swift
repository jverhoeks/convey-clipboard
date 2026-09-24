import AppKit
import ConveyCore
import ImageIO

@MainActor
public enum PreviewImageLoader {
    public static func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let data = entry.imageData else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }

    public static func rendered(for entry: ClipboardEntry, using convey: Convey) async -> NSImage? {
        guard entry.kind == .mermaid, let src = entry.text else { return nil }
        guard let result = try? await convey.convert(.text(src), from: .mermaid, to: .png),
              let data = result.bytes else { return nil }
        return NSImage(data: data)
    }
}
