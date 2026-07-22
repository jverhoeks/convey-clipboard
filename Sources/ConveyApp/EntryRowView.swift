import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

struct EntryRowView: View {
    let entry: ClipboardEntry
    let targets: [Format]
    let onConvert: (ClipboardEntry, Format) -> Void

    // Decoded once per entry (keyed by `.task(id:)`) rather than re-decoded on every body re-render.
    @State private var thumbnail: NSImage?

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
            if let thumbnail {
                Image(nsImage: thumbnail)
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
            thumbnail = PreviewImageLoader.thumbnail(for: entry)
        }
    }
}
