import AppKit
import ConveyCore
import ConveyKit

@MainActor
final class EditorDocument: ObservableObject {
    @Published var text: String
    @Published private(set) var annotations: [ImageAnnotation] = []
    @Published private(set) var renderedImage: CGImage?
    let sourceFormat: Format
    private let original: CGImage?
    private var undoStack: [[ImageAnnotation]] = []
    private var redoStack: [[ImageAnnotation]] = []
    private var exportedText = ""
    private var exportedAnnotations: [ImageAnnotation] = []

    /// Last undone snapshot, so existing checks can ask whether redo is available.
    var redoAnnotations: [ImageAnnotation] { redoStack.last ?? [] }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var isImage: Bool { original != nil }
    var isDirty: Bool { text != exportedText || annotations != exportedAnnotations }

    init(entry: ClipboardEntry) throws {
        if entry.primaryFormat == .image || entry.primaryFormat == .png {
            guard let data = entry.imageData, let bitmap = NSBitmapImageRep(data: data),
                  let image = bitmap.cgImage else { throw EditorError.missingContent }
            original = image
            renderedImage = image
            sourceFormat = .image
            text = ""
        } else if entry.primaryFormat == .rtf, let data = entry.imageData {
            text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                          documentAttributes: nil).string
            sourceFormat = .plainText
            original = nil
        } else if let content = entry.text {
            text = content
            sourceFormat = entry.primaryFormat
            original = nil
        } else { throw EditorError.missingContent }
        exportedText = text
    }

    func add(_ annotation: ImageAnnotation) throws { try replaceAnnotations(annotations + [annotation]) }

    func replaceAnnotations(_ marks: [ImageAnnotation]) throws {
        guard marks != annotations else { return }
        undoStack.append(annotations)
        redoStack = []
        try apply(marks)
    }

    func preview(excluding id: UUID) -> CGImage? {
        guard let original else { return nil }
        return try? ImageAnnotations.render(original, annotations: annotations.filter { $0.id != id })
    }

    func undoAnnotation() throws {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        try apply(previous)
    }

    func redoAnnotation() throws {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        try apply(next)
    }

    private func apply(_ marks: [ImageAnnotation]) throws {
        guard let original else { return }
        let image = try ImageAnnotations.render(original, annotations: marks)
        annotations = marks
        renderedImage = image
    }

    func payload() throws -> Payload {
        guard let image = renderedImage else { return .text(text) }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw EditorError.imageRendering }
        return .bytes(data)
    }

    func markExported(as format: Format) {
        // OCR/plain-text conversions do not preserve image annotations or rich source.
        guard format == sourceFormat else { return }
        exportedText = text
        exportedAnnotations = annotations
    }
}
