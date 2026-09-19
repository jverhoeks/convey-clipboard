import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

struct EntryRowView: View {
    let entry: ClipboardEntry
    let targets: [Format]
    let saveFormats: [ExportFormat]
    let onConvert: (ClipboardEntry, Format) -> Void
    let onSave: (ClipboardEntry, Format) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let cache: PreviewCache

    @State private var image: NSImage?

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "HH:mm"; return df
    }()

    private var sourceCaption: String? {
        guard entry.sources.count > 1 else { return nil }
        return entry.sources.map { $0.rawValue.uppercased() }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.kind.badge).font(.headline)
                Spacer()
                Text(Self.timeFormatter.string(from: entry.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
                Button { onDelete(entry) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(RowActionButtonStyle(tint: .red))
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
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }

            if let sourceCaption {
                Text(sourceCaption)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if !targets.isEmpty {
                HStack {
                    ForEach(targets, id: \.self) { target in
                        Button("→ \(target.rawValue)") { onConvert(entry, target) }
                            .buttonStyle(RowActionButtonStyle())
                    }
                }
            }

            if !saveFormats.isEmpty {
                HStack {
                    ForEach(saveFormats, id: \.format) { fmt in
                        Button { onSave(entry, fmt.format) } label: {
                            Label(fmt.label, systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(RowActionButtonStyle())
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .task(id: entry.id) {
            image = await cache.image(for: entry)
        }
    }
}
