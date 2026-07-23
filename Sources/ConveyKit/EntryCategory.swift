/// A coarse type bucket used by the picker's filter bar.
/// Every `ClipboardKind` maps to exactly one category.
public enum EntryCategory: String, CaseIterable, Sendable {
    case html, text, image

    public var label: String {
        switch self {
        case .html: return "HTML"
        case .text: return "Text"
        case .image: return "Image"
        }
    }

    /// Maps a `ClipboardKind` to its category. rtf/markdown/mermaid are Text.
    public static func of(_ kind: ClipboardKind) -> EntryCategory {
        switch kind {
        case .html: return .html
        case .image: return .image
        case .plainText, .rtf, .markdown, .mermaid: return .text
        }
    }

    /// Filters entries by selected categories. An empty selection returns all
    /// entries unchanged (empty = show all). Order is preserved.
    public static func filter(_ entries: [ClipboardEntry],
                              selected: Set<EntryCategory>) -> [ClipboardEntry] {
        guard !selected.isEmpty else { return entries }
        return entries.filter { selected.contains(of($0.kind)) }
    }
}
