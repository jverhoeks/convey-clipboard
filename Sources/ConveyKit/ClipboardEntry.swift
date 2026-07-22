import Foundation
import ConveyCore

public struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let sources: [Format]
    public let kind: ClipboardKind
    public let text: String?
    public let imageData: Data?
    public let createdAt: Date

    public init(id: UUID, sources: [Format], kind: ClipboardKind, text: String?, imageData: Data?, createdAt: Date) {
        self.id = id
        self.sources = sources
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.createdAt = createdAt
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
