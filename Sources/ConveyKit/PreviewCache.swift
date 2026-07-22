import AppKit
import ConveyCore

/// Memoizes the row preview image (thumbnail or rendered Mermaid diagram) for each
/// clipboard entry, keyed by entry id, so it survives SwiftUI `LazyVStack` row
/// recycling instead of being recomputed every time a row scrolls back on screen.
@MainActor
public final class PreviewCache {
    private var images: [UUID: NSImage] = [:]
    private var order: [UUID] = []           // insertion order for eviction
    private let convey: Convey
    private let capacity: Int

    public init(convey: Convey, capacity: Int = 100) {
        self.convey = convey
        self.capacity = capacity
    }

    /// Already-computed image for this id, if any (sync, for immediate display).
    public func cached(_ id: UUID) -> NSImage? { images[id] }

    /// Returns the row image for an entry, computing+caching it once.
    /// Image entries -> thumbnail; mermaid entries -> rendered diagram; others -> nil.
    public func image(for entry: ClipboardEntry) async -> NSImage? {
        if let existing = images[entry.id] { return existing }

        var result: NSImage? = PreviewImageLoader.thumbnail(for: entry)
        if result == nil, entry.kind == .mermaid {
            result = await PreviewImageLoader.rendered(for: entry, using: convey)
        }
        // A concurrent call may have populated it while we awaited; prefer the stored one.
        if let raced = images[entry.id] { return raced }
        if let result { store(entry.id, result) }
        return result
    }

    private func store(_ id: UUID, _ image: NSImage) {
        images[id] = image
        order.append(id)
        while order.count > capacity {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
    }
}
