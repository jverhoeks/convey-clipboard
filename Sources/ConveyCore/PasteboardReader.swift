import Foundation

public struct PasteboardReader {
    public init() {}

    static let flavorMap: [String: Format] = [
        "public.html": .html,
        "public.rtf": .rtf,
        "public.utf8-plain-text": .plainText,
        "public.png": .image,
        "public.tiff": .image,
    ]

    static let mermaidPrefixes = [
        "graph ", "graph\n", "flowchart", "sequenceDiagram", "classDiagram",
        "stateDiagram", "erDiagram", "gantt", "pie", "journey", "gitGraph",
        "mindmap", "timeline",
    ]

    public static func looksLikeMermaid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return mermaidPrefixes.contains { trimmed.hasPrefix($0) }
    }

    static let markdownLinePatterns = [
        "^#{1,6}\\s",              // heading
        "^\\s*```",                // fenced code block
        "^\\s*([-*+]|\\d+\\.)\\s", // bullet or numbered list
    ]

    public static func looksLikeMarkdown(_ text: String) -> Bool {
        if text.range(of: "\\*\\*[^*]+\\*\\*", options: .regularExpression) != nil {
            return true
        }
        if text.range(of: "\\[[^\\]]+\\]\\([^)]+\\)", options: .regularExpression) != nil {
            return true
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            for pattern in markdownLinePatterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            }
        }
        return false
    }

    public func sources(from snapshot: PasteboardSnapshot) -> [Format] {
        var result: [Format] = []
        for type in snapshot.availableTypes {
            if let format = Self.flavorMap[type], !result.contains(format) {
                result.append(format)
            }
        }
        if result.contains(.plainText),
           let text = snapshot.string(forType: "public.utf8-plain-text") {
            if Self.looksLikeMermaid(text) {
                result.append(.mermaid)
            } else if Self.looksLikeMarkdown(text) {
                result.append(.markdown)
            }
        }
        return result
    }

    public func payload(for format: Format, from snapshot: PasteboardSnapshot) -> Payload? {
        switch format {
        case .html:
            return snapshot.string(forType: "public.html").map(Payload.text)
        case .rtf:
            return snapshot.data(forType: "public.rtf").map(Payload.bytes)
        case .plainText, .mermaid, .markdown:
            return snapshot.string(forType: "public.utf8-plain-text").map(Payload.text)
        case .image:
            if let png = snapshot.data(forType: "public.png") { return .bytes(png) }
            return snapshot.data(forType: "public.tiff").map(Payload.bytes)
        case .png, .svg, .base64DataURI:
            return nil
        }
    }
}
