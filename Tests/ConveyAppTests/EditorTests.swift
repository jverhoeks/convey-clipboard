import AppKit
import XCTest
import ConveyCore
import ConveyKit
@testable import ConveyApp

final class EditorTests: XCTestCase {
    private func testImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 80,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 20, y: 45, width: 10, height: 20))
        return try XCTUnwrap(context.makeImage())
    }

    private func color(_ image: CGImage, x: Int, y: Int) throws -> NSColor {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

    func testHighlightUsesTopLeftCoordinatesAndPreservesOtherPixels() throws {
        let original = try testImage()
        let result = try ImageAnnotations.render(original, annotations: [
            ImageAnnotation(tool: .highlight, rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        ])
        XCTAssertEqual(result.width, 100)
        XCTAssertEqual(result.height, 80)
        XCTAssertLessThan(try color(result, x: 5, y: 5).blueComponent, 0.8)
        XCTAssertEqual(try color(result, x: 5, y: 70).blueComponent, 1, accuracy: 0.01)
        XCTAssertEqual(try color(result, x: 90, y: 5).blueComponent, 1, accuracy: 0.01)
    }

    func testBlurChangesSelectedPixelsOnly() throws {
        let original = try testImage()
        let result = try ImageAnnotations.render(original, annotations: [
            ImageAnnotation(tool: .blur, rect: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4))
        ])
        XCTAssertGreaterThan(try color(result, x: 25, y: 25).redComponent,
                             try color(original, x: 25, y: 25).redComponent + 0.1)
        XCTAssertEqual(try color(result, x: 90, y: 70), try color(original, x: 90, y: 70))
    }

    @MainActor
    func testTextEditsPreserveFormatAndOriginalEntry() throws {
        for format in [Format.plainText, .markdown, .html] {
            let entry = ClipboardEntry(id: UUID(), sources: [format], kind: .plainText,
                primaryFormat: format, text: "original", imageData: nil, previewText: "original", createdAt: Date())
            let document = try EditorDocument(entry: entry)
            XCTAssertFalse(document.isDirty)
            document.text = "edited"
            XCTAssertTrue(document.isDirty)
            XCTAssertEqual(document.sourceFormat, format)
            XCTAssertEqual(try document.payload(), .text("edited"))
            XCTAssertEqual(entry.text, "original")
            document.markExported(as: format)
            XCTAssertFalse(document.isDirty)
        }
    }

    @MainActor
    func testEditorWindowsRenderTextAndImageContent() throws {
        _ = NSApplication.shared
        let imageData = try XCTUnwrap(NSBitmapImageRep(cgImage: testImage()).representation(using: .png, properties: [:]))
        for format in [Format.markdown, .image] {
            let entry = ClipboardEntry(id: UUID(), sources: [format], kind: format == .image ? .image : .markdown,
                primaryFormat: format, text: format == .image ? nil : "# Notes\n\nEdit this Markdown and save it.",
                imageData: format == .image ? imageData : nil, previewText: nil, createdAt: Date())
            let controller = try EditorWindowController(entry: entry, convey: Convey())
            let window = try XCTUnwrap(controller.window)
            defer { window.close() }
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(view.bounds.width, 850)
            XCTAssertGreaterThan(view.bounds.height, 400)
            if let directory = ProcessInfo.processInfo.environment["CONVEY_EDITOR_SNAPSHOT_DIR"] {
                window.appearance = NSAppearance(named: .aqua)
                window.orderFront(nil)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                    view.layer?.render(in: context.cgContext)
                }
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("convey-editor-\(format.rawValue).png"))
            }
        }
    }

    @MainActor
    func testCanvasMapsReverseDragToImageCoordinates() throws {
        _ = NSApplication.shared
        let canvas = EditorCanvas.CanvasView(frame: CGRect(x: 0, y: 0, width: 240, height: 200))
        let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        defer { window.close() }
        canvas.image = try testImage()
        canvas.tool = .highlight
        var marks: [ImageAnnotation] = []
        canvas.onChange = { marks = $0 }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 120, y: 100)))
        canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 40, y: 40)))
        let result = try XCTUnwrap(marks.last)
        XCTAssertEqual(result.tool, .highlight)
        XCTAssertEqual(result.rect.minX, 0.1, accuracy: 0.001)
        XCTAssertEqual(result.rect.minY, 0.125, accuracy: 0.001)
        XCTAssertEqual(result.rect.width, 0.4, accuracy: 0.001)
        XCTAssertEqual(result.rect.height, 0.375, accuracy: 0.001)
    }

    @MainActor
    func testImageUndoRedoAndFlattenedPNGExport() throws {
        let image = try testImage()
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let entry = ClipboardEntry(id: UUID(), sources: [.image], kind: .image,
            primaryFormat: .image, text: nil, imageData: data, previewText: nil, createdAt: Date())
        let document = try EditorDocument(entry: entry)
        let annotation = ImageAnnotation(tool: .highlight, rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        try document.add(annotation)
        XCTAssertTrue(document.isDirty)
        document.markExported(as: .plainText)
        XCTAssertTrue(document.isDirty, "OCR does not preserve image edits")
        let output = try XCTUnwrap(document.payload().bytes)
        XCTAssertNotEqual(output, data)
        let exported = try XCTUnwrap(NSBitmapImageRep(data: output))
        XCTAssertEqual(exported.pixelsWide, 100)
        XCTAssertEqual(exported.pixelsHigh, 80)
        try document.undoAnnotation()
        XCTAssertFalse(document.isDirty)
        XCTAssertTrue(document.annotations.isEmpty)
        try document.redoAnnotation()
        XCTAssertEqual(document.annotations, [annotation])
        XCTAssertEqual(try document.payload().bytes, output)
        try document.undoAnnotation()
        try document.add(ImageAnnotation(tool: .blur, rect: annotation.rect))
        XCTAssertTrue(document.redoAnnotations.isEmpty)
        XCTAssertEqual(entry.imageData, data)
    }

    func testSquareStrokesTheBorderAndKeepsTheCenter() throws {
        let original = try testImage()
        let result = try ImageAnnotations.render(original, annotations: [
            ImageAnnotation(tool: .rectangle, rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                            color: AnnotationColor(red: 1, green: 0, blue: 0))
        ])
        XCTAssertGreaterThan(try color(result, x: 50, y: 16).redComponent, 0.5)
        XCTAssertEqual(try color(result, x: 50, y: 40), try color(original, x: 50, y: 40))
        let filled = try ImageAnnotations.render(original, annotations: [
            ImageAnnotation(tool: .rectangle, rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
                            color: AnnotationColor(red: 1, green: 0, blue: 0), filled: true)
        ])
        XCTAssertGreaterThan(try color(filled, x: 50, y: 40).redComponent, 0.8)
        XCTAssertEqual(try color(filled, x: 5, y: 5), try color(original, x: 5, y: 5))
    }

    func testArrowAndTextLeaveAMark() throws {
        let original = try testImage()
        let arrow = try ImageAnnotations.render(original, annotations: [
            ImageAnnotation(tool: .arrow, rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                            color: AnnotationColor(red: 0, green: 0, blue: 1))
        ])
        var hit = false
        for x in 48...52 {
            for y in 38...42 where try color(arrow, x: x, y: y).blueComponent > 0.4 { hit = true }
        }
        XCTAssertTrue(hit)
        let text = try ImageAnnotations.render(original, annotations: [
            ImageAnnotation(tool: .text, rect: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.4),
                            color: .red, text: "Hi")
        ])
        var ink = false
        for x in stride(from: 8, to: 90, by: 2) {
            for y in stride(from: 6, to: 36, by: 2) {
                let sample = try color(text, x: x, y: y)
                if sample.redComponent > 0.4, sample.blueComponent < 0.7 { ink = true }
            }
        }
        XCTAssertTrue(ink)
    }

    func testResizeKeepsTheOppositeCorner() {
        let resized = AnnotationLayout.resizing(CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                                                handle: .bottomRight, to: CGPoint(x: 0.8, y: 0.9))
        XCTAssertEqual(resized.minX, 0.2, accuracy: 0.001)
        XCTAssertEqual(resized.minY, 0.2, accuracy: 0.001)
        XCTAssertEqual(resized.maxX, 0.8, accuracy: 0.001)
        XCTAssertEqual(resized.maxY, 0.9, accuracy: 0.001)
    }

    func testSelectedHandleWinsOverTheShapeBehindIt() {
        let mark = ImageAnnotation(tool: .rectangle, rect: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        let image = CGRect(x: 0, y: 0, width: 100, height: 100)
        let corner = AnnotationLayout.hit(CGPoint(x: 20, y: 20), annotations: [mark], imageRect: image, selected: mark.id)
        XCTAssertEqual(corner?.id, mark.id)
        XCTAssertEqual(corner?.handle, .topLeft)
        let body = AnnotationLayout.hit(CGPoint(x: 40, y: 40), annotations: [mark], imageRect: image, selected: nil)
        XCTAssertEqual(body?.id, mark.id)
        XCTAssertNil(body?.handle)
    }

    @MainActor
    func testMovingAShapeCanBeUndone() throws {
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: testImage()).representation(using: .png, properties: [:]))
        let entry = ClipboardEntry(id: UUID(), sources: [.image], kind: .image, primaryFormat: .image,
            text: nil, imageData: data, previewText: nil, createdAt: Date())
        let document = try EditorDocument(entry: entry)
        var shape = ImageAnnotation(tool: .ellipse, rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        try document.add(shape)
        shape.rect = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        try document.replaceAnnotations([shape])
        try document.undoAnnotation()
        XCTAssertEqual(try XCTUnwrap(document.annotations.first).rect.minX, 0.1, accuracy: 0.001)
        try document.redoAnnotation()
        XCTAssertEqual(try XCTUnwrap(document.annotations.first).rect.minX, 0.5, accuracy: 0.001)
    }
}
