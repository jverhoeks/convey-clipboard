import ConveyCore

/// Describes a file type a clipboard entry can be exported/saved as.
/// Pure value type — all file-type knowledge lives here so it is testable
/// without any UI or save panel.
public struct ExportFormat: Equatable, Sendable {
    public let format: Format          // conversion target the save flow should produce
    public let label: String           // short UI label, e.g. "PNG"
    public let fileExtension: String   // e.g. "png"
    public let utTypeIdentifier: String
    public let isText: Bool            // text payload vs. raw bytes

    public init(format: Format, label: String, fileExtension: String,
                utTypeIdentifier: String, isText: Bool) {
        self.format = format; self.label = label; self.fileExtension = fileExtension
        self.utTypeIdentifier = utTypeIdentifier; self.isText = isText
    }

    /// Maps a `Format` to its file type, or `nil` if it is not savable as a file.
    /// `.image` and `.png` both resolve to PNG; `.base64DataURI` is not a file.
    public static func fileType(for format: Format) -> ExportFormat? {
        switch format {
        case .html:
            return ExportFormat(format: .html, label: "HTML", fileExtension: "html",
                                utTypeIdentifier: "public.html", isText: true)
        case .markdown:
            return ExportFormat(format: .markdown, label: "MD", fileExtension: "md",
                                utTypeIdentifier: "net.daringfireball.markdown", isText: true)
        case .plainText:
            return ExportFormat(format: .plainText, label: "TXT", fileExtension: "txt",
                                utTypeIdentifier: "public.plain-text", isText: true)
        case .mermaid:
            return ExportFormat(format: .mermaid, label: "Mermaid", fileExtension: "mmd",
                                utTypeIdentifier: "public.plain-text", isText: true)
        case .svg:
            return ExportFormat(format: .svg, label: "SVG", fileExtension: "svg",
                                utTypeIdentifier: "public.svg-image", isText: true)
        case .rtf:
            return ExportFormat(format: .rtf, label: "RTF", fileExtension: "rtf",
                                utTypeIdentifier: "public.rtf", isText: false)
        case .png, .image:
            return ExportFormat(format: .png, label: "PNG", fileExtension: "png",
                                utTypeIdentifier: "public.png", isText: false)
        case .base64DataURI:
            return nil
        }
    }

    /// The ordered, de-duplicated list of savable formats for an entry:
    /// native format first, then graph-reachable formats, filtered to file types.
    public static func options(nativeFormat: Format, reachable: [Format]) -> [ExportFormat] {
        var orderedFormats: [Format] = []
        for f in [nativeFormat] + reachable where !orderedFormats.contains(f) {
            orderedFormats.append(f)
        }
        var result: [ExportFormat] = []
        var seen: Set<Format> = []
        for f in orderedFormats {
            guard let ef = fileType(for: f), !seen.contains(ef.format) else { continue }
            seen.insert(ef.format)
            result.append(ef)
        }
        return result
    }
}
