public enum CLICommand: Equatable {
    case list
    case convert(from: Format, to: Format)
    case version
    case usage
    /// Record the terminal to an asciicast file (nil = timestamped name in the current directory).
    case rec(String?)
    case play(String)
    /// Forwarded to the running Convey.app over `ControlSocket`.
    case control([String])
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
    if first == "version" || first == "--version" || first == "-v" { return .version }
    if first == "list" { return .list }
    if ControlSocket.verbs.contains(first) { return .control(args) }
    if first == "rec" { return args.count <= 2 ? .rec(args.dropFirst().first) : .usage }
    if first == "play" { return args.count == 2 ? .play(args[1]) : .usage }
    if let edge = edgeTable[first] { return .convert(from: edge.0, to: edge.1) }
    return .usage
}
