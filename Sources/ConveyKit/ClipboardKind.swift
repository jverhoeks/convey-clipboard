import ConveyCore

public enum ClipboardKind: String, Codable, Sendable {
    case html, rtf, markdown, plainText, mermaid, image

    public var badge: String {
        switch self {
        case .html: return "HTML"
        case .rtf: return "RTF"
        case .markdown: return "Markdown"
        case .plainText: return "Text"
        case .mermaid: return "Mermaid"
        case .image: return "Image"
        }
    }

    // Pick the most specific/richest kind from detected sources.
    public init(sources: [Format]) {
        if sources.contains(.html) { self = .html }
        else if sources.contains(.rtf) { self = .rtf }
        else if sources.contains(.image) { self = .image }
        else if sources.contains(.mermaid) { self = .mermaid }
        else if sources.contains(.markdown) { self = .markdown }
        else { self = .plainText }
    }
}
