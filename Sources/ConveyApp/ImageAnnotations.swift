import AppKit
import CoreImage

struct AnnotationColor: Equatable {
    var red, green, blue: Double

    static let red = AnnotationColor(red: 0.90, green: 0.23, blue: 0.20)
    var nsColor: NSColor { NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1) }
    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: 1) }
    /// Ink that stays readable when this color is used as a solid background.
    var contrastingNSColor: NSColor {
        (0.299 * red + 0.587 * green + 0.114 * blue) > 0.62 ? .black : .white
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.deviceRGB) ?? .systemRed
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
    }
}

struct ImageAnnotation: Equatable, Identifiable {
    enum Tool: String, CaseIterable {
        case blur = "Blur"
        case highlight = "Highlight"
        case rectangle = "Square"
        case ellipse = "Circle"
        case arrow = "Arrow"
        case text = "Text"

        var symbol: String {
            switch self {
            case .blur: return "drop.halffull"
            case .highlight: return "highlighter"
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .arrow: return "arrow.up.right"
            case .text: return "textformat"
            }
        }
        var drawsVector: Bool { self != .blur }
        var canFill: Bool { self == .rectangle || self == .ellipse || self == .text }
    }

    enum Handle: Equatable { case topLeft, topRight, bottomLeft, bottomRight }

    var id: UUID
    var tool: Tool
    /// Normalized coordinates measured from the image's top-left corner. Stored standardized.
    var rect: CGRect
    var color: AnnotationColor
    var text: String
    /// Square, circle, and text only. Text uses `color` as the background and contrasting ink.
    var filled: Bool
    /// Arrow tail sits on the max-X / max-Y corner when set. Ignored for other tools.
    var arrowFromMaxX: Bool
    var arrowFromMaxY: Bool

    init(tool: Tool, rect: CGRect, color: AnnotationColor = .red, text: String = "", filled: Bool = false,
         arrowFromMaxX: Bool = false, arrowFromMaxY: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.tool = tool
        self.rect = rect.standardized
        self.color = color
        self.text = text
        self.filled = filled
        self.arrowFromMaxX = arrowFromMaxX
        self.arrowFromMaxY = arrowFromMaxY
    }
}

enum AnnotationLayout {
    static func lineWidth(for span: CGFloat) -> CGFloat { max(2, span * 0.004) }

    static func viewRect(_ normalized: CGRect, imageRect: CGRect) -> CGRect {
        let r = normalized.standardized
        return CGRect(x: imageRect.minX + r.minX * imageRect.width,
                      y: imageRect.minY + r.minY * imageRect.height,
                      width: r.width * imageRect.width, height: r.height * imageRect.height)
    }

    static func normalizedRect(_ view: CGRect, imageRect: CGRect) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        return CGRect(x: (view.minX - imageRect.minX) / imageRect.width,
                      y: (view.minY - imageRect.minY) / imageRect.height,
                      width: view.width / imageRect.width, height: view.height / imageRect.height).standardized
    }

    /// `yDown` matches the canvas (flipped). Core Graphics image space is y-up, so pass false there.
    static func arrowEnds(in rect: CGRect, fromMaxX: Bool, fromMaxY: Bool, yDown: Bool) -> (CGPoint, CGPoint) {
        let tail = CGPoint(x: fromMaxX ? rect.maxX : rect.minX,
                           y: (fromMaxY == yDown) ? rect.maxY : rect.minY)
        let head = CGPoint(x: fromMaxX ? rect.minX : rect.maxX,
                           y: (fromMaxY == yDown) ? rect.minY : rect.maxY)
        return (tail, head)
    }

    static func resizing(_ rect: CGRect, handle: ImageAnnotation.Handle, to point: CGPoint) -> CGRect {
        let r = rect.standardized
        let resized: CGRect
        switch handle {
        case .bottomRight: resized = CGRect(x: r.minX, y: r.minY, width: point.x - r.minX, height: point.y - r.minY)
        case .bottomLeft: resized = CGRect(x: point.x, y: r.minY, width: r.maxX - point.x, height: point.y - r.minY)
        case .topRight: resized = CGRect(x: r.minX, y: point.y, width: point.x - r.minX, height: r.maxY - point.y)
        case .topLeft: resized = CGRect(x: point.x, y: point.y, width: r.maxX - point.x, height: r.maxY - point.y)
        }
        return resized.standardized
    }

    static func hit(_ point: CGPoint, annotations: [ImageAnnotation], imageRect: CGRect,
                    selected: UUID?, handleSize: CGFloat = 8) -> (id: UUID, handle: ImageAnnotation.Handle?)? {
        if let selected, let mark = annotations.first(where: { $0.id == selected }) {
            let frame = viewRect(mark.rect, imageRect: imageRect)
            let handles: [(ImageAnnotation.Handle, CGPoint)] = [
                (.topLeft, CGPoint(x: frame.minX, y: frame.minY)),
                (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
                (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)),
                (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY)),
            ]
            if let handle = handles.first(where: { hypot($0.1.x - point.x, $0.1.y - point.y) <= handleSize + 2 })?.0 {
                return (selected, handle)
            }
        }
        for mark in annotations.reversed() {
            if mark.tool == .arrow {
                let frame = viewRect(mark.rect, imageRect: imageRect)
                let (tail, head) = arrowEnds(in: frame, fromMaxX: mark.arrowFromMaxX, fromMaxY: mark.arrowFromMaxY, yDown: true)
                if distance(point, toSegmentFrom: tail, to: head) <= handleSize { return (mark.id, nil) }
            } else if viewRect(mark.rect, imageRect: imageRect).insetBy(dx: -4, dy: -4).contains(point) {
                return (mark.id, nil)
            }
        }
        return nil
    }

    private static func distance(_ point: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / len2))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

enum ImageAnnotations {
    static func render(_ original: CGImage, annotations: [ImageAnnotation]) throws -> CGImage {
        guard !annotations.isEmpty else { return original }
        let bounds = CGRect(x: 0, y: 0, width: original.width, height: original.height)
        guard let context = CGContext(data: nil, width: original.width, height: original.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EditorError.imageRendering }
        context.draw(original, in: bounds)
        let ciContext = CIContext()
        for annotation in annotations {
            let r = annotation.rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            if annotation.tool == .arrow, r.width > 0.004 || r.height > 0.004 {
                let box = CGRect(x: r.minX * bounds.width, y: r.minY * bounds.height,
                                 width: max(r.width, 0.001) * bounds.width, height: max(r.height, 0.001) * bounds.height)
                let (tailDown, headDown) = AnnotationLayout.arrowEnds(in: box, fromMaxX: annotation.arrowFromMaxX,
                                                                      fromMaxY: annotation.arrowFromMaxY, yDown: true)
                let tail = CGPoint(x: tailDown.x, y: bounds.height - tailDown.y)
                let head = CGPoint(x: headDown.x, y: bounds.height - headDown.y)
                context.saveGState()
                context.setStrokeColor(annotation.color.cgColor)
                context.setFillColor(annotation.color.cgColor)
                strokeArrow(from: tail, to: head, width: AnnotationLayout.lineWidth(for: bounds.width), context: context)
                context.restoreGState()
                continue
            }
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            let area = CGRect(x: r.minX * bounds.width, y: (1 - r.maxY) * bounds.height,
                              width: r.width * bounds.width, height: r.height * bounds.height).integral.intersection(bounds)
            guard area.width > 0, area.height > 0 else { continue }
            switch annotation.tool {
            case .highlight:
                context.setFillColor(annotation.color.cgColor.copy(alpha: 0.35) ?? annotation.color.cgColor)
                context.fill(area)
            case .blur:
                guard let current = context.makeImage() else { throw EditorError.imageRendering }
                let blurred = CIImage(cgImage: current).clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14])
                guard let patch = ciContext.createCGImage(blurred, from: area) else { throw EditorError.imageRendering }
                context.saveGState()
                context.clip(to: area)
                context.setBlendMode(.copy)
                context.draw(patch, in: area)
                context.restoreGState()
            case .rectangle, .ellipse, .arrow, .text:
                drawVector(annotation, in: area, pixelWidth: bounds.width, context: context)
            }
        }
        guard let result = context.makeImage() else { throw EditorError.imageRendering }
        return result
    }

    private static func drawVector(_ annotation: ImageAnnotation, in area: CGRect, pixelWidth: CGFloat, context: CGContext) {
        let width = AnnotationLayout.lineWidth(for: pixelWidth)
        context.saveGState()
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.tool {
        case .rectangle:
            if annotation.filled { context.fill(area) }
            context.stroke(area.insetBy(dx: width / 2, dy: width / 2))
        case .ellipse:
            if annotation.filled { context.fillEllipse(in: area) }
            context.strokeEllipse(in: area.insetBy(dx: width / 2, dy: width / 2))
        case .arrow:
            break
        case .text:
            drawText(annotation, in: area, context: context)
        case .blur, .highlight:
            break
        }
        context.restoreGState()
    }

    private static func strokeArrow(from tail: CGPoint, to head: CGPoint, width: CGFloat, context: CGContext) {
        let dx = head.x - tail.x, dy = head.y - tail.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len, uy = dy / len
        let headLen = min(len * 0.45, max(12, width * 4))
        let base = CGPoint(x: head.x - ux * headLen, y: head.y - uy * headLen)
        context.move(to: tail)
        context.addLine(to: base)
        context.strokePath()
        let px = -uy, py = ux
        context.move(to: head)
        context.addLine(to: CGPoint(x: base.x + px * headLen * 0.45, y: base.y + py * headLen * 0.45))
        context.addLine(to: CGPoint(x: base.x - px * headLen * 0.45, y: base.y - py * headLen * 0.45))
        context.closePath()
        context.fillPath()
    }

    private static func drawText(_ annotation: ImageAnnotation, in area: CGRect, context: CGContext) {
        let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if annotation.filled {
            context.setFillColor(annotation.color.cgColor)
            context.fill(area)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let font = NSFont.systemFont(ofSize: max(12, area.height * 0.62), weight: .semibold)
        let ink = annotation.filled ? annotation.color.contrastingNSColor : annotation.color.nsColor
        (trimmed as NSString).draw(in: area.insetBy(dx: 4, dy: 2), withAttributes: [
            .font: font, .foregroundColor: ink, .paragraphStyle: style,
        ])
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum EditorError: LocalizedError {
    case imageRendering, missingContent
    var errorDescription: String? {
        switch self {
        case .imageRendering: return "The image could not be rendered."
        case .missingContent: return "This entry has no editable content."
        }
    }
}
