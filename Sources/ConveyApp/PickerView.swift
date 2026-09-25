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
    let onEdit: (ClipboardEntry) -> Void
    let onRemove: (ClipboardEntry) -> Void
    let onClear: () -> Void
    let onPreferences: () -> Void
    let onCapture: (CaptureAction) -> Void
    let cache: PreviewCache

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Convey").font(.headline)
                Spacer()
                // Screenshot group, then the same three shapes in red for video recording.
                ForEach(CaptureAction.all) { action in
                    if action.id == 3 { Divider().frame(height: 14) }
                    Button { onCapture(action) } label: {
                        Image(systemName: action.symbol)
                            .foregroundStyle(action.record ? Color.red : Color.primary)
                            .frame(width: 22, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(action.help)
                    .accessibilityLabel(action.title)
                }
                Spacer()
                Button("Clear", action: onClear).buttonStyle(.borderless).font(.caption)
                Menu {
                    Button("Preferences…", action: onPreferences)
                    Divider()
                    Button("Quit Convey") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
                            onEdit: onEdit,
                            onRemove: onRemove,
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
