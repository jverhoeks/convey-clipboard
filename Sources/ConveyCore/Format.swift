public enum Format: String, CaseIterable, Sendable, Codable {
    case html
    case rtf
    case plainText
    case markdown
    case mermaid
    case image
    case png
    case svg
    case base64DataURI
}

public extension Format {
    var fileExtension: String {
        switch self {
        case .html: return "html"
        case .rtf: return "rtf"
        case .plainText, .base64DataURI: return "txt"
        case .markdown: return "md"
        case .mermaid: return "mmd"
        case .image, .png: return "png"
        case .svg: return "svg"
        }
    }
}
