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

    @State private var selected: Set<EntryCategory> = []

    private var visibleEntries: [ClipboardEntry] {
        EntryCategory.filter(history.entries, selected: selected)
    }

    private func chip(_ category: EntryCategory) -> some View {
        let isOn = selected.contains(category)
        return Button {
            if isOn { selected.remove(category) } else { selected.insert(category) }
        } label: {
            Text(category.label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
    }

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
            .padding(.horizontal, 10)
            .padding(.top, 10)

            HStack(spacing: 6) {
                ForEach(EntryCategory.allCases, id: \.self) { category in
                    chip(category)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if history.entries.isEmpty {
                        Text("Clipboard history is empty.\nCopy something to get started.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.top, 40)
                    } else if visibleEntries.isEmpty {
                        Text("No items match the filter.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.top, 40)
                    }
                    ForEach(visibleEntries) { entry in
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
