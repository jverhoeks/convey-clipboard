import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let editorDocument: EditorDocument
    var onClose: (() -> Void)?

    init(entry: ClipboardEntry, convey: Convey) throws {
        editorDocument = try EditorDocument(entry: entry)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Convey — \(editorDocument.isImage ? "Image" : editorDocument.sourceFormat.editorLabel)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 850, height: 420)
        window.contentView = NSHostingView(rootView: EditorView(document: editorDocument, convey: convey))
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editorDocument.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard your edits?"
        alert.informativeText = "Copy to Clipboard or Save As to keep your changes. The original history entry is unchanged."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

private extension Format {
    var editorLabel: String {
        switch self {
        case .plainText: return "Text"
        case .image, .png: return "PNG"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        default: return rawValue
        }
    }
}

private struct EditorView: View {
    @ObservedObject var document: EditorDocument
    let convey: Convey
    @State private var tool: ImageAnnotation.Tool = .blur
    @State private var color = Color(red: 0.90, green: 0.23, blue: 0.20)
    @State private var filled = false
    @State private var selectedID: UUID?
    @State private var target: Format
    @State private var busy = false
    @State private var status = ""
    @State private var errorMessage: String?

    init(document: EditorDocument, convey: Convey) {
        self.document = document
        self.convey = convey
        _target = State(initialValue: document.sourceFormat)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if document.isImage {
                    Picker("Tool", selection: $tool) {
                        ForEach(ImageAnnotation.Tool.allCases, id: \.self) { tool in
                            Image(systemName: tool.symbol).accessibilityLabel(tool.rawValue).tag(tool)
                        }
                    }.pickerStyle(.segmented).frame(width: 250).help(tool.rawValue)
                    ColorPicker("Color", selection: $color, supportsOpacity: false).labelsHidden().frame(width: 28)
                    Toggle("Fill", isOn: $filled).toggleStyle(.checkbox).disabled(!fillApplies)
                        .help("Fill a square or circle, or put a background behind text")
                    Button { deleteSelection() } label: { Image(systemName: "trash") }
                        .disabled(selectedID == nil).help("Delete selected shape")
                    Button { perform { try document.undoAnnotation() } } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!document.canUndo).help("Undo annotation")
                        .keyboardShortcut("z", modifiers: .command)
                    Button { perform { try document.redoAnnotation() } } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!document.canRedo).help("Redo annotation")
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                } else {
                    Text("\(document.sourceFormat.editorLabel) source").font(.headline)
                }
                Spacer()
                Picker("Export", selection: $target) {
                    ForEach([document.sourceFormat] + convey.graph.validTargets(from: [document.sourceFormat]), id: \.self) {
                        Text($0.editorLabel).tag($0)
                    }
                }.frame(width: 175)
                Button("Copy to Clipboard") { export(save: false) }
                Button("Save As…") { export(save: true) }.keyboardShortcut("s", modifiers: .command)
            }.padding(12)
            Divider()
            if let image = document.renderedImage {
                EditorCanvas(image: image, annotations: document.annotations, tool: tool,
                             color: AnnotationColor(nsColor: NSColor(color)), filled: filled, selectedID: selectedID,
                             isEnabled: !busy,
                             imageExcluding: { document.preview(excluding: $0) },
                             onSelect: { id in
                                 selectedID = id
                                 if let id, let mark = document.annotations.first(where: { $0.id == id }), mark.tool.canFill {
                                     filled = mark.filled
                                 }
                             },
                             onChange: { marks in perform { try document.replaceAnnotations(marks) } })
                    .onChange(of: filled) { value in
                        guard let id = selectedID,
                              var mark = document.annotations.first(where: { $0.id == id }),
                              mark.tool.canFill, mark.filled != value else { return }
                        mark.filled = value
                        perform { try document.replaceAnnotations(document.annotations.map { $0.id == id ? mark : $0 }) }
                    }
            } else {
                SourceTextEditor(text: $document.text, isEditable: !busy)
            }
            Divider()
            HStack {
                Text(document.isImage ? imageHint : "Edit the source, then copy or save in the selected format.")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Text(status)
            }.font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .disabled(busy)
        .alert("Could not complete action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onChange(of: document.text) { _ in status = "" }
    }

    private var fillApplies: Bool {
        if let id = selectedID, let mark = document.annotations.first(where: { $0.id == id }) {
            return mark.tool.canFill
        }
        return tool.canFill
    }

    private var imageHint: String {
        switch tool {
        case .text: return "Click to add text. Turn on Fill for a background behind it. Delete removes the selection."
        case .arrow: return "Drag in the direction of the arrow. Click a shape to move or resize it."
        case .rectangle, .ellipse: return "Drag to draw. Hold Shift for a perfect \(tool == .rectangle ? "square" : "circle"). Fill uses the chosen color as the background."
        case .blur, .highlight: return "Drag a rectangle to \(tool.rawValue.lowercased()). Click a shape to resize it, or press Delete."
        }
    }

    private func deleteSelection() {
        guard let id = selectedID else { return }
        perform { try document.replaceAnnotations(document.annotations.filter { $0.id != id }) }
        selectedID = nil
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); status = "" } catch { errorMessage = error.localizedDescription }
    }

    private func export(save: Bool) {
        let url: URL?
        if save {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "clipboard.\(target.fileExtension)"
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            url = destination
        } else { url = nil }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let input = try document.payload()
                let output = try await convey.convert(input, from: document.sourceFormat, to: target)
                if let url {
                    switch output {
                    case let .text(text): try text.write(to: url, atomically: true, encoding: .utf8)
                    case let .bytes(data): try data.write(to: url, options: .atomic)
                    }
                } else { PasteboardWriter().write(output, as: target, to: .general) }
                // Native controls may still receive a queued edit during an async conversion.
                if try document.payload() == input { document.markExported(as: target) }
                status = save ? "Saved" : "Copied to clipboard"
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
