import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

struct EntryRowView: View {
    let entry: ClipboardEntry
    let targets: [Format]
    let onConvert: (ClipboardEntry, Format) -> Void
    let cache: PreviewCache

    // Backed by `PreviewCache`, which persists across row recycling in the
    // enclosing `LazyVStack` — scrolling a row off/on screen no longer
    // re-decodes the thumbnail or re-renders the Mermaid diagram.
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.kind.badge)
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(entry.previewText.map { PreviewText.snippet($0) } ?? "(no preview)")
                    .font(.system(.body, design: .rounded))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }
            if !targets.isEmpty {
                HStack {
                    ForEach(targets, id: \.self) { target in
                        Button("→ \(target.rawValue)") { onConvert(entry, target) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: entry.id) {
            image = await cache.image(for: entry)
        }
    }
}
