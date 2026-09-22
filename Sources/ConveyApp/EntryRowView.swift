import AppKit
import SwiftUI
import LocalAuthentication
import ConveyCore
import ConveyKit

struct EntryRowView: View {
    let entry: ClipboardEntry
    let targets: [Format]
    let onConvert: (ClipboardEntry, Format) -> Void
    let onSave: (ClipboardEntry, Format) -> Void
    let onOpen: (ClipboardEntry) -> Void
    let cache: PreviewCache

    // Backed by `PreviewCache`, which persists across row recycling in the
    // enclosing `LazyVStack` — scrolling a row off/on screen no longer
    // re-decodes the thumbnail or re-renders the Mermaid diagram.
    @State private var image: NSImage?
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.kind.badge)
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
                if entry.isSecret { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange) }
                Spacer()
                actionsMenu
            }
            if entry.isSecret && !revealed {
                Button { reveal() } label: {
                    Label("Looks like a secret — click to reveal", systemImage: "eye.slash")
                }.buttonStyle(.borderless).font(.callout)
            } else if let image {
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: entry.id) {
            image = await cache.image(for: entry)
        }
    }

    private var actionsMenu: some View {
        Menu {
            if !targets.isEmpty {
                Section("Convert clipboard to") {
                    ForEach(targets, id: \.self) { t in Button(t.rawValue) { onConvert(entry, t) } }
                }
            }
            Section("Save as…") {
                ForEach([entry.primaryFormat] + targets, id: \.self) { t in Button(t.rawValue) { onSave(entry, t) } }
            }
            Button("Open in default app") { onOpen(entry) }
        } label: { Image(systemName: "ellipsis.circle") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func reveal() {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { revealed = true; return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "reveal a clipboard entry that looks like a secret") { ok, _ in
            Task { @MainActor in revealed = ok }
        }
    }
}
