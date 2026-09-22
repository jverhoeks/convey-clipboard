import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

struct PickerView: View {
    @ObservedObject var history: HistoryStore
    let targetsFor: (ClipboardEntry) -> [Format]
    let onConvert: (ClipboardEntry, Format) -> Void
    let onSave: (ClipboardEntry, Format) -> Void
    let onOpen: (ClipboardEntry) -> Void
    let onClear: () -> Void
    let onPreferences: () -> Void
    let cache: PreviewCache

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Convey").font(.headline)
                Spacer()
                Button("Clear", action: onClear).buttonStyle(.borderless).font(.caption)
                Button(action: onPreferences) { Image(systemName: "gearshape") }.buttonStyle(.borderless)
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
                            onConvert: onConvert,
                            onSave: onSave,
                            onOpen: onOpen,
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
