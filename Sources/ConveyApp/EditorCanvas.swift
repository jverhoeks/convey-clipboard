import AppKit
import SwiftUI

struct EditorCanvas: NSViewRepresentable {
    let image: CGImage
    let annotations: [ImageAnnotation]
    let tool: ImageAnnotation.Tool
    let color: AnnotationColor
    var filled = false
    var selectedID: UUID?
    var isEnabled = true
    var imageExcluding: (UUID) -> CGImage?
    var onSelect: (UUID?) -> Void
    var onChange: ([ImageAnnotation]) -> Void

    func makeNSView(context: Context) -> CanvasView { CanvasView() }
    func updateNSView(_ view: CanvasView, context: Context) {
        view.image = image
        view.annotations = annotations
        view.tool = tool
        view.color = color
        view.filled = filled
        view.isEnabled = isEnabled
        view.imageExcluding = imageExcluding
        view.onSelect = onSelect
        view.onChange = onChange
        if view.selectedID != selectedID { view.selectedID = selectedID }
        view.needsDisplay = true
    }

    final class CanvasView: NSView, NSTextFieldDelegate {
        var image: CGImage?
        var annotations: [ImageAnnotation] = []
        var tool: ImageAnnotation.Tool = .blur
        var color = AnnotationColor.red
        var filled = false
        var selectedID: UUID?
        var isEnabled = true
        var imageExcluding: ((UUID) -> CGImage?)?
        var onSelect: ((UUID?) -> Void)?
        var onChange: (([ImageAnnotation]) -> Void)?

        private enum Drag {
            case create(CGPoint, CGPoint)
            case move(UUID, CGRect, CGPoint)          // id, original view rect, grab offset
            case resize(UUID, ImageAnnotation.Handle, CGRect)
        }
        private var drag: Drag?
        private var editBackground: CGImage?
        private var live: ImageAnnotation?
        private var textField: NSTextField?
        private var textDraft: ImageAnnotation?
        private var suppressNextClick = false
        private var committingText = false

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private var imageRect: CGRect {
            guard let image else { return .zero }
            let available = bounds.insetBy(dx: 20, dy: 20)
            let scale = max(0, min(available.width / CGFloat(image.width), available.height / CGFloat(image.height)))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        }

        func deleteSelection() {
            guard textField == nil, let id = selectedID else { return }
            select(nil)
            onChange?(annotations.filter { $0.id != id })
        }

        override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            let shown = editBackground ?? image
            if let shown {
                NSImage(cgImage: shown, size: NSSize(width: shown.width, height: shown.height))
                    .draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if let live { draw(live, in: AnnotationLayout.viewRect(live.rect, imageRect: imageRect)) }
            if let selectedID, drag == nil, textField == nil,
               let mark = annotations.first(where: { $0.id == selectedID }) {
                drawHandles(around: AnnotationLayout.viewRect(mark.rect, imageRect: imageRect))
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled, textField == nil else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard imageRect.insetBy(dx: -8, dy: -8).contains(point) else { return }
            window?.makeFirstResponder(self)
            if event.clickCount == 2, let hit = AnnotationLayout.hit(point, annotations: annotations, imageRect: imageRect, selected: selectedID),
               annotations.first(where: { $0.id == hit.id })?.tool == .text {
                suppressNextClick = true
                beginTextEdit(annotations.first { $0.id == hit.id }!)
                return
            }
            if let hit = AnnotationLayout.hit(point, annotations: annotations, imageRect: imageRect, selected: selectedID),
               let mark = annotations.first(where: { $0.id == hit.id }) {
                select(hit.id)
                editBackground = imageExcluding?(hit.id) ?? image
                let frame = AnnotationLayout.viewRect(mark.rect, imageRect: imageRect)
                if let handle = hit.handle {
                    drag = .resize(hit.id, handle, frame)
                } else {
                    drag = .move(hit.id, frame, CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
                }
                live = mark
                needsDisplay = true
                return
            }
            guard imageRect.contains(point) else { return }
            select(nil)
            if tool == .text {
                let box = textBox(at: point)
                var draft = ImageAnnotation(tool: .text, rect: AnnotationLayout.normalizedRect(box, imageRect: imageRect),
                                            color: color, text: "", filled: filled)
                draft.rect = AnnotationLayout.normalizedRect(box, imageRect: imageRect)
                beginTextEdit(draft)
                return
            }
            drag = .create(point, point)
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            let point = SelectionGeometry.clamp(convert(event.locationInWindow, from: nil), to: imageRect)
            switch drag {
            case let .create(start, _):
                let square = event.modifierFlags.contains(.shift) && (tool == .rectangle || tool == .ellipse)
                let view = square ? squared(from: start, to: point) : SelectionGeometry.rectangle(from: start, to: point)
                let norm = AnnotationLayout.normalizedRect(view, imageRect: imageRect)
                live = ImageAnnotation(tool: tool, rect: norm, color: color, filled: filled,
                                       arrowFromMaxX: start.x > point.x, arrowFromMaxY: start.y > point.y)
                drag = .create(start, point)
            case let .move(id, origin, grab):
                guard var mark = annotations.first(where: { $0.id == id }) else { return }
                var moved = origin
                moved.origin = CGPoint(x: point.x - grab.x, y: point.y - grab.y)
                mark.rect = AnnotationLayout.normalizedRect(moved, imageRect: imageRect)
                live = mark
            case let .resize(id, handle, _):
                guard var mark = annotations.first(where: { $0.id == id }) else { return }
                let normPoint = AnnotationLayout.normalizedRect(CGRect(origin: point, size: .zero), imageRect: imageRect).origin
                if mark.tool == .arrow {
                    let frame = AnnotationLayout.viewRect(mark.rect, imageRect: imageRect)
                    var (tail, head) = AnnotationLayout.arrowEnds(in: frame, fromMaxX: mark.arrowFromMaxX,
                                                                  fromMaxY: mark.arrowFromMaxY, yDown: true)
                    if Self.handleIsHead(handle, fromMaxX: mark.arrowFromMaxX, fromMaxY: mark.arrowFromMaxY) {
                        head = point
                    } else { tail = point }
                    mark.arrowFromMaxX = tail.x > head.x
                    mark.arrowFromMaxY = tail.y > head.y
                    mark.rect = AnnotationLayout.normalizedRect(SelectionGeometry.rectangle(from: tail, to: head), imageRect: imageRect)
                } else {
                    mark.rect = AnnotationLayout.resizing(mark.rect, handle: handle, to: normPoint)
                }
                live = mark
            case nil:
                return
            }
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            if suppressNextClick { suppressNextClick = false; drag = nil; return }
            guard let drag else { return }
            mouseDragged(with: event)
            let finished = live
            self.drag = nil
            live = nil
            editBackground = nil
            needsDisplay = true
            guard let finished else { return }
            let drawn = finished.tool == .arrow
                ? max(finished.rect.width, finished.rect.height) > 0.01
                : finished.rect.width > 0.005 && finished.rect.height > 0.005
            guard drawn else { return }
            var marks = annotations
            if case .create = drag {
                marks.append(finished)
                select(finished.id)
            } else if let index = marks.firstIndex(where: { $0.id == finished.id }) {
                marks[index] = finished
            }
            onChange?(marks)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                drag = nil; live = nil; editBackground = nil; needsDisplay = true
            } else if textField == nil, event.keyCode == 51 || event.keyCode == 117 {
                deleteSelection()
            } else {
                super.keyDown(with: event)
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) { commitText() }

        private func select(_ id: UUID?) {
            guard selectedID != id else { return }
            selectedID = id
            onSelect?(id)
        }

        private func textBox(at point: CGPoint) -> CGRect {
            let size = CGSize(width: min(imageRect.width * 0.36, 220), height: min(imageRect.height * 0.1, 36))
            var box = CGRect(x: point.x, y: point.y - size.height / 2, width: size.width, height: size.height)
            if box.maxX > imageRect.maxX { box.origin.x = imageRect.maxX - box.width }
            if box.maxY > imageRect.maxY { box.origin.y = imageRect.maxY - box.height }
            if box.minX < imageRect.minX { box.origin.x = imageRect.minX }
            if box.minY < imageRect.minY { box.origin.y = imageRect.minY }
            return box
        }

        private func squared(from start: CGPoint, to end: CGPoint) -> CGRect {
            let side = max(abs(end.x - start.x), abs(end.y - start.y))
            return CGRect(x: end.x < start.x ? start.x - side : start.x,
                          y: end.y < start.y ? start.y - side : start.y,
                          width: side, height: side)
        }

        private func beginTextEdit(_ mark: ImageAnnotation) {
            select(mark.id)
            textDraft = mark
            let field = NSTextField(frame: AnnotationLayout.viewRect(mark.rect, imageRect: imageRect))
            field.stringValue = mark.text
            field.isBezeled = false
            field.isBordered = false
            field.drawsBackground = true
            field.backgroundColor = mark.filled ? mark.color.nsColor : NSColor.black.withAlphaComponent(0.55)
            field.textColor = mark.filled ? mark.color.contrastingNSColor : mark.color.nsColor
            field.font = .systemFont(ofSize: max(13, field.frame.height * 0.55), weight: .semibold)
            field.focusRingType = .none
            field.delegate = self
            field.target = self
            field.action = #selector(commitText)
            addSubview(field)
            textField = field
            window?.makeFirstResponder(field)
        }

        private static func handleIsHead(_ handle: ImageAnnotation.Handle, fromMaxX: Bool, fromMaxY: Bool) -> Bool {
            switch handle {
            case .bottomRight: return !fromMaxX && !fromMaxY
            case .bottomLeft: return fromMaxX && !fromMaxY
            case .topRight: return !fromMaxX && fromMaxY
            case .topLeft: return fromMaxX && fromMaxY
            }
        }

        @objc private func commitText() {
            guard !committingText, let field = textField, let draft = textDraft else { return }
            committingText = true
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.removeFromSuperview()
            textField = nil
            textDraft = nil
            committingText = false
            var marks = annotations.filter { $0.id != draft.id }
            if !value.isEmpty {
                var saved = draft
                saved.text = value
                saved.color = draft.color
                marks.append(saved)
                select(saved.id)
            } else if selectedID == draft.id {
                select(nil)
            }
            onChange?(marks)
            needsDisplay = true
        }

        private func draw(_ mark: ImageAnnotation, in rect: CGRect) {
            let color = mark.color.nsColor
            let width = AnnotationLayout.lineWidth(for: imageRect.width)
            switch mark.tool {
            case .blur:
                color.withAlphaComponent(0.18).setFill(); rect.fill()
                color.setStroke()
                let outline = NSBezierPath(rect: rect)
                outline.lineWidth = width
                outline.stroke()
            case .highlight:
                color.withAlphaComponent(0.35).setFill(); rect.fill()
            case .rectangle:
                if mark.filled { color.setFill(); rect.fill() }
                color.setStroke()
                let path = NSBezierPath(rect: rect.insetBy(dx: width / 2, dy: width / 2))
                path.lineWidth = width; path.stroke()
            case .ellipse:
                if mark.filled { color.setFill(); NSBezierPath(ovalIn: rect).fill() }
                color.setStroke()
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: width / 2, dy: width / 2))
                path.lineWidth = width; path.stroke()
            case .arrow:
                let (tail, head) = AnnotationLayout.arrowEnds(in: rect, fromMaxX: mark.arrowFromMaxX,
                                                              fromMaxY: mark.arrowFromMaxY, yDown: true)
                strokeArrow(from: tail, to: head, width: width, color: color)
            case .text:
                if mark.filled { color.setFill(); rect.fill() }
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
                let ink = mark.filled ? mark.color.contrastingNSColor : color
                (mark.text as NSString).draw(in: rect.insetBy(dx: 4, dy: 2), withAttributes: [
                    .font: NSFont.systemFont(ofSize: max(12, rect.height * 0.62), weight: .semibold),
                    .foregroundColor: ink, .paragraphStyle: style,
                ])
            }
        }

        private func strokeArrow(from tail: CGPoint, to head: CGPoint, width: CGFloat, color: NSColor) {
            let dx = head.x - tail.x, dy = head.y - tail.y
            let len = hypot(dx, dy)
            guard len > 1 else { return }
            let ux = dx / len, uy = dy / len
            let headLen = min(len * 0.45, max(12, width * 4))
            let base = CGPoint(x: head.x - ux * headLen, y: head.y - uy * headLen)
            color.setStroke(); color.setFill()
            let line = NSBezierPath()
            line.move(to: tail); line.line(to: base)
            line.lineWidth = width; line.lineCapStyle = .round; line.stroke()
            let headPath = NSBezierPath()
            headPath.move(to: head)
            headPath.line(to: CGPoint(x: base.x + (-uy) * headLen * 0.45, y: base.y + ux * headLen * 0.45))
            headPath.line(to: CGPoint(x: base.x - (-uy) * headLen * 0.45, y: base.y - ux * headLen * 0.45))
            headPath.close(); headPath.fill()
        }

        private func drawHandles(around rect: CGRect) {
            NSColor.white.setFill()
            NSColor.black.withAlphaComponent(0.8).setStroke()
            for point in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                          CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
                let handle = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                NSBezierPath(rect: handle).fill()
                NSBezierPath(rect: handle).stroke()
            }
        }
    }
}

/// Plain source editing with native selection, keyboard shortcuts and undo.
struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.string = text
        view.delegate = context.coordinator
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = isEditable
        if view.string != text { view.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextEditor
        init(_ parent: SourceTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}
