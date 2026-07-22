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
