import Foundation
import AppKit

public struct PasteboardWriter {
    public init() {}

    public static func uti(for format: Format) -> String {
        switch format {
        case .markdown, .plainText, .mermaid, .base64DataURI:
            return "public.utf8-plain-text"
        case .html:
            return "public.html"
        case .svg:
            return "public.svg-image"
        case .png, .image:
            return "public.png"
        case .rtf:
            return "public.rtf"
        }
    }

    @MainActor
    public func write(_ payload: Payload, as format: Format, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let type = NSPasteboard.PasteboardType(Self.uti(for: format))
        switch payload {
        case let .text(string):
            pasteboard.setString(string, forType: type)
        case let .bytes(data):
            pasteboard.setData(data, forType: type)
        }
    }
}
