import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

struct PickerView: View {
    @ObservedObject var history: HistoryStore
    let targetsFor: (ClipboardEntry) -> [Format]
    let saveFormatsFor: (ClipboardEntry) -> [ExportFormat]
    let onConvert: (ClipboardEntry, Format) -> Void
    let onSave: (ClipboardEntry, Format) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let onClear: () -> Void
    let cache: PreviewCache

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Convey").font(.headline)
                Spacer()
                Button("Clear All", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if history.entries.isEmpty {
                        Text("Clipboard history is empty.\nCopy something to get started.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.top, 40)
                    }
                    ForEach(history.entries) { entry in
                        EntryRowView(
                            entry: entry,
                            targets: targetsFor(entry),
                            saveFormats: saveFormatsFor(entry),
                            onConvert: onConvert,
                            onSave: onSave,
                            onDelete: onDelete,
                            cache: cache
                        )
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 380, height: 480)
    }
}
