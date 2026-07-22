public enum CLICommand: Equatable {
    case list
    case convert(from: Format, to: Format)
    case usage
}

public let edgeTable: [String: (Format, Format)] = [
    "html2md": (.html, .markdown),
    "html2txt": (.html, .plainText),
    "md2html": (.markdown, .html),
    "rtf2md": (.rtf, .markdown),
    "img2b64": (.image, .base64DataURI),
    "mmd2svg": (.mermaid, .svg),
    "mmd2png": (.mermaid, .png),
]

public func parseCommand(_ args: [String]) -> CLICommand {
    guard let first = args.first else { return .usage }
    if first == "list" { return .list }
    if let edge = edgeTable[first] { return .convert(from: edge.0, to: edge.1) }
    return .usage
}
