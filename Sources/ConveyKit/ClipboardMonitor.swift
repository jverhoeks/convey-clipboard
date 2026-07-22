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
        let plain = snapshot.string(forType: "public.utf8-plain-text")

        let primaryFormat: Format
        var text: String? = nil
        var imageData: Data? = nil

        if let html = snapshot.string(forType: "public.html") {
            primaryFormat = .html; text = html
        } else if let rtf = snapshot.data(forType: "public.rtf") {
            primaryFormat = .rtf; imageData = rtf
        } else if sources.contains(.image), let img = reader.payload(for: .image, from: snapshot)?.bytes {
            primaryFormat = .image; imageData = img
        } else if let plain {
            primaryFormat = sources.contains(.mermaid) ? .mermaid
                          : sources.contains(.markdown) ? .markdown
                          : .plainText
            text = plain
        } else {
            return nil
        }

        // Readable preview: prefer the plain-text fallback; else the text payload; else nil (image → thumbnail).
        let previewText = plain ?? text

        return ClipboardEntry(id: id, sources: sources, kind: kind, primaryFormat: primaryFormat,
                              text: text, imageData: imageData, previewText: previewText, createdAt: now)
    }
}
