import AppKit
import ConveyCore

@MainActor
public enum PreviewImageLoader {
    public static func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let data = entry.imageData else { return nil }
        return NSImage(data: data)
    }

    public static func rendered(for entry: ClipboardEntry, using convey: Convey) async -> NSImage? {
        guard entry.kind == .mermaid, let src = entry.text else { return nil }
        guard let result = try? await convey.convert(.text(src), from: .mermaid, to: .png),
              let data = result.bytes else { return nil }
        return NSImage(data: data)
    }
}
