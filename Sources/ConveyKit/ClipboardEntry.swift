import Foundation
import ConveyCore

public struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let sources: [Format]
    public let kind: ClipboardKind
    public let primaryFormat: Format   // the format the stored payload actually is
    public let text: String?           // payload when text-based (html/markdown/mermaid/plainText)
    public let imageData: Data?        // payload when bytes (image OR rtf)
    public let previewText: String?    // human-readable snippet for the row (may differ from `text`)
    public let createdAt: Date

    public init(id: UUID, sources: [Format], kind: ClipboardKind, primaryFormat: Format,
                text: String?, imageData: Data?, previewText: String?, createdAt: Date) {
        self.id = id; self.sources = sources; self.kind = kind; self.primaryFormat = primaryFormat
        self.text = text; self.imageData = imageData; self.previewText = previewText; self.createdAt = createdAt
    }

    public var payload: Payload? {
        if let text { return .text(text) }
        if let imageData { return .bytes(imageData) }
        return nil
    }

    public func sameContent(as other: ClipboardEntry) -> Bool {
        if let a = text, let b = other.text { return a == b }
        if let a = imageData, let b = other.imageData { return a == b }
        return false
    }
}
