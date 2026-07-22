import Foundation
import ConveyCore

public struct ClipboardMonitor {
    private let reader: PasteboardReader

    public init(reader: PasteboardReader = PasteboardReader()) {
        self.reader = reader
    }

    public func makeEntry(from snapshot: PasteboardSnapshot, id: UUID, now: Date) -> ClipboardEntry? {
        if Concealment.isConcealedOrTransient(snapshot) { return nil }
        let sources = reader.sources(from: snapshot)
        guard !sources.isEmpty else { return nil }

        let kind = ClipboardKind(sources: sources)
        var text: String? = snapshot.string(forType: "public.utf8-plain-text")
        var imageData: Data?

        if text == nil, sources.contains(.image) {
            imageData = reader.payload(for: .image, from: snapshot)?.bytes
        }
        // HTML/RTF-only clipboards without plain text: capture the rich text so it stays reconvertible.
        if text == nil, imageData == nil {
            if let html = snapshot.string(forType: "public.html") { text = html }
        }
        guard text != nil || imageData != nil else { return nil }

        return ClipboardEntry(id: id, sources: sources, kind: kind, text: text, imageData: imageData, createdAt: now)
    }
}
