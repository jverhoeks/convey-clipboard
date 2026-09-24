import AppKit
import SwiftUI
import ConveyCore
import ConveyKit

/// Renders the README images from the live AppKit UI.
///
/// `convey-app --screenshots <directory>` only. Uses in-memory sample entries and never
/// reads or writes clipboard history. The picker's documented default hotkey is applied
/// for the preferences shot, then the previous value is restored.
@MainActor
enum ScreenshotGallery {
    static func run(directory: URL) async -> Int32 {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSApp.activate(ignoringOtherApps: true)
            let convey = Convey()
            let cache = PreviewCache(convey: convey)
            let markdown = sampleMarkdown
            let entries = try sampleEntries(markdown: markdown)
            if let mermaid = entries.first(where: { $0.kind == .mermaid }) {
                fputs("rendering mermaid preview…\n", stderr)
                if await cache.image(for: mermaid) == nil {
                    fputs("mermaid preview unavailable; the row will show source text\n", stderr)
                }
            }
            let history = HistoryStore()
            history.replaceAll(entries)
            try await writeHistory(history, cache: cache, convey: convey, to: directory)
            try await writePreferences(to: directory)
            try await writeTextEditor(markdown, convey: convey, to: directory)
            try await writeImageEditor(convey: convey, to: directory)
            try await writeAreaCapture(to: directory)
            fputs("wrote screenshots to \(directory.path)\n", stderr)
            return 0
        } catch {
            fputs("screenshots: \(error)\n", stderr)
            return 1
        }
    }

    // MARK: - Windows

    private static func writeHistory(_ history: HistoryStore, cache: PreviewCache, convey: Convey, to directory: URL) async throws {
        let anchor = anchorWindow()
        defer { anchor.orderOut(nil) }
        let picker = PickerView(
            history: history,
            targetsFor: { convey.graph.validTargets(from: [$0.primaryFormat]) },
            onConvert: { _, _ in }, onSave: { _, _ in }, onOpen: { _ in }, onEdit: { _ in },
            onRemove: { _ in }, onClear: {}, onPreferences: {}, cache: cache)
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = NSHostingController(rootView: picker)
        guard let anchorView = anchor.contentView else { throw GalleryError.noWindow("history") }
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        var shown = popover.isShown
        if !shown {
            try await Task.sleep(nanoseconds: 100_000_000)
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
            shown = popover.isShown
        }
        guard shown, let window = popover.contentViewController?.view.window else { throw GalleryError.noWindow("history") }
        try await Task.sleep(nanoseconds: 800_000_000)
        try await write(window, named: "history.png", to: directory)
        popover.performClose(nil)
    }

    private static func writePreferences(to directory: URL) async throws {
        let saved = Prefs.defaults.keys.map { ($0, Prefs.store.object(forKey: $0)) }
        Prefs.store.register(defaults: Prefs.defaults)
        for (key, value) in Prefs.defaults { Prefs.store.set(value, forKey: key) }
        defer {
            for (key, value) in saved {
                if let value { Prefs.store.set(value, forKey: key) }
                else { Prefs.store.removeObject(forKey: key) }
            }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
        window.title = "Convey Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        placeOnSharpestScreen(window)
        try await Task.sleep(nanoseconds: 600_000_000)
        try await write(window, named: "preferences.png", to: directory)
        window.orderOut(nil)
    }

    private static func writeTextEditor(_ markdown: String, convey: Convey, to directory: URL) async throws {
        let entry = ClipboardEntry(
            id: UUID(), sources: [.markdown], kind: .markdown, primaryFormat: .markdown,
            text: markdown, imageData: nil, previewText: markdown, createdAt: Date())
        let controller = try EditorWindowController(entry: entry, convey: convey)
        controller.showWindow(nil)
        guard let window = controller.window else { throw GalleryError.noWindow("text editor") }
        window.setContentSize(NSSize(width: 860, height: 460))
        window.makeKeyAndOrderFront(nil)
        placeOnSharpestScreen(window)
        try await Task.sleep(nanoseconds: 500_000_000)
        try await write(window, named: "editor-text.png", to: directory)
        window.orderOut(nil)
    }

    private static func writeImageEditor(convey: Convey, to directory: URL) async throws {
        let entry = ClipboardEntry(
            id: UUID(), sources: [.image], kind: .image, primaryFormat: .image,
            text: nil, imageData: try SampleCard.png(), previewText: nil, createdAt: Date())
        let controller = try EditorWindowController(entry: entry, convey: convey)
        try controller.editorDocument.add(.init(tool: .blur, rect: SampleCard.tokenRect))
        try controller.editorDocument.add(.init(tool: .highlight, rect: SampleCard.dateRect))
        controller.showWindow(nil)
        guard let window = controller.window else { throw GalleryError.noWindow("image editor") }
        window.makeKeyAndOrderFront(nil)
        placeOnSharpestScreen(window)
        try await Task.sleep(nanoseconds: 500_000_000)
        try await write(window, named: "editor-image.png", to: directory)
        window.orderOut(nil)
    }

    private static func writeAreaCapture(to directory: URL) async throws {
        let view = AreaCaptureDemo(frame: NSRect(x: 0, y: 0, width: 720, height: 450))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.contentView = view
        window.level = .floating
        placeOnSharpestScreen(window)
        view.prepare()
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        try await write(window, named: "area-capture.png", to: directory)
        window.orderOut(nil)
    }

    /// Prefer the Retina display so window captures stay sharp. `center()` follows the mouse,
    /// which may be on a 1x external monitor.
    private static func placeOnSharpestScreen(_ window: NSWindow) {
        guard let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) else {
            window.center()
            return
        }
        let vis = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: vis.midX - size.width / 2, y: vis.midY - size.height / 2))
    }

    /// Invisible anchor at the top of the sharpest screen, so the picker popover is captured there.
    private static func anchorWindow() -> NSWindow {
        let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let rect = NSRect(x: vis.midX - 8, y: vis.maxY - 2, width: 16, height: 2)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
        return window
    }

    // MARK: - Capture

    private static func write(_ window: NSWindow, named name: String, to directory: URL) async throws {
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        guard window.windowNumber > 0 else { throw GalleryError.noWindow(name) }
        let cg: CGImage
        let own = captureOwnWindow(window)
        let drawn = (window.contentView?.superview ?? window.contentView).flatMap(renderView)
        // Grouped forms are vibrant; a window-list capture can flatten them to gray.
        if let own, usable(own), chroma(own) > 8 {
            cg = own
        } else if let drawn, usable(drawn), chroma(drawn) > 8 {
            cg = drawn
        } else if let own, usable(own) {
            cg = own
        } else if let drawn, usable(drawn) {
            cg = drawn
        } else {
            cg = try await screencapture(window)
        }
        guard let data = NSBitmapImageRep(cgImage: trim(cg)).representation(using: .png, properties: [:]) else {
            throw GalleryError.unrepresentable
        }
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        let scale = window.screen?.backingScaleFactor ?? 0
        fputs("  \(name) \(cg.width)x\(cg.height) @\(scale)x chroma \(chroma(cg))\n", stderr)
    }

    private static func captureOwnWindow(_ window: NSWindow) -> CGImage? {
        let id = CGWindowID(window.windowNumber)
        // boundsIgnoreFraming drops the shadow but, on some displays, also the accent color.
        let framed = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.bestResolution])
        let content = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])
        return [framed, content].compactMap { $0 }.max { chroma($0) < chroma($1) }
    }

    /// Off-screen draw of the view. Used when a window-list capture drops vibrancy color.
    private static func renderView(_ view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private static func screencapture(_ window: NSWindow) async throws -> CGImage {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("convey-shot-\(UUID().uuidString).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proc.terminationHandler = { process in
                if process.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: GalleryError.captureFailed("screencapture exit \(process.terminationStatus)")) }
            }
            do { try proc.run() } catch {
                continuation.resume(throwing: error)
            }
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), usable(cg) else {
            throw GalleryError.captureFailed(url.lastPathComponent)
        }
        return cg
    }

    private static func chroma(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let bpp = max(image.bitsPerPixel / 8, 1)
        guard bpp >= 3 else { return 0 }
        var best = 0
        for y in stride(from: 0, to: image.height, by: 12) {
            let row = bytes + y * image.bytesPerRow
            for x in stride(from: 0, to: image.width, by: 12) {
                let p = row + x * bpp
                let r = Int(p[0]), g = Int(p[1]), b = Int(p[2])
                best = max(best, max(r, g, b) - min(r, g, b))
                if best > 24 { return best }
            }
        }
        return best
    }

    private static func usable(_ image: CGImage) -> Bool {
        guard image.width > 20, image.height > 20,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
        let bpp = max(image.bitsPerPixel / 8, 1)
        let alphaLast = image.alphaInfo == .premultipliedLast || image.alphaInfo == .last || image.alphaInfo == .noneSkipLast
        let alphaOffset = alphaLast ? bpp - 1 : 0
        var opaque = 0, minV = 255, maxV = 0
        let n = 48
        for i in 0..<n {
            let x = (image.width - 1) * i / max(n - 1, 1)
            let y = (image.height - 1) * ((i * 5) % n) / max(n - 1, 1)
            let p = bytes + y * image.bytesPerRow + x * bpp
            if bpp >= 4, p[alphaOffset] > 16 { opaque += 1 }
            let v = Int(p[min(bpp - 1, 1)])
            minV = min(minV, v)
            maxV = max(maxV, v)
        }
        return opaque > n / 4 && maxV - minV > 6
    }

    /// Drop the transparent margin window shadows leave around a capture.
    private static func trim(_ image: CGImage) -> CGImage {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return image }
        let bpp = max(image.bitsPerPixel / 8, 1)
        guard bpp >= 4 else { return image }
        let alphaLast = image.alphaInfo == .premultipliedLast || image.alphaInfo == .last || image.alphaInfo == .noneSkipLast
        let alphaOffset = alphaLast ? bpp - 1 : 0
        var minX = image.width, minY = image.height, maxX = 0, maxY = 0
        for y in stride(from: 0, to: image.height, by: 2) {
            let row = bytes + y * image.bytesPerRow
            for x in stride(from: 0, to: image.width, by: 2) {
                guard row[x * bpp + alphaOffset] > 40 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return image }
        let rect = CGRect(x: max(0, minX - 2), y: max(0, minY - 2),
                          width: min(image.width, maxX + 3) - max(0, minX - 2),
                          height: min(image.height, maxY + 3) - max(0, minY - 2))
        return image.cropping(to: rect) ?? image
    }

    // MARK: - Sample clipboard

    private static let sampleMarkdown = """
        # Launch checklist

        - Convert HTML to Markdown
        - OCR a screenshot on device
        - Blur a token before you share it

        Ship date: Monday.
        """

    private static func sampleEntries(markdown: String) throws -> [ClipboardEntry] {
        let now = Date()
        let mermaid = """
        flowchart LR
          Copy --> Detect
          Detect --> Markdown
          Detect --> PNG
        """
        let html = "<h1>Meeting notes</h1><p>Convert this <strong>HTML</strong> before pasting it into the doc.</p>"
        return [
            ClipboardEntry(id: UUID(), sources: [.mermaid], kind: .mermaid, primaryFormat: .mermaid,
                           text: mermaid, imageData: nil, previewText: mermaid, createdAt: now),
            ClipboardEntry(id: UUID(), sources: [.markdown], kind: .markdown, primaryFormat: .markdown,
                           text: markdown, imageData: nil, previewText: markdown, createdAt: now.addingTimeInterval(-60)),
            ClipboardEntry(id: UUID(), sources: [.html], kind: .html, primaryFormat: .html,
                           text: html, imageData: nil,
                           previewText: "Meeting notes — convert this HTML before pasting it into the doc.",
                           createdAt: now.addingTimeInterval(-120)),
            ClipboardEntry(id: UUID(), sources: [.plainText], kind: .plainText, primaryFormat: .plainText,
                           text: "TOKEN=demo-token-not-real", imageData: nil,
                           previewText: "TOKEN=demo-token-not-real",
                           createdAt: now.addingTimeInterval(-180), isSecret: true),
        ]
    }
}

private enum GalleryError: CustomStringConvertible, Error {
    case noWindow(String), captureFailed(String), unrepresentable
    var description: String {
        switch self {
        case let .noWindow(name): return "\(name) did not appear"
        case let .captureFailed(name): return "could not capture \(name)"
        case .unrepresentable: return "could not encode a screenshot"
        }
    }
}

/// Picture used by the image-editor screenshot. Normalized rects match `ImageAnnotation` (top-left origin).
private enum SampleCard {
    static let size = CGSize(width: 960, height: 540)
    static let tokenRect = CGRect(x: 72.0 / 960, y: 228.0 / 540, width: 520.0 / 960, height: 48.0 / 540)
    static let dateRect = CGRect(x: 248.0 / 960, y: 300.0 / 540, width: 230.0 / 960, height: 46.0 / 540)

    static func png() throws -> Data {
        let view = SampleCardView(frame: NSRect(origin: .zero, size: size))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw GalleryError.unrepresentable }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw GalleryError.unrepresentable }
        return data
    }
}

private final class SampleCardView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard NSGraphicsContext.current?.cgContext != nil else { return }
        let bounds = CGRect(origin: .zero, size: SampleCard.size)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.93, alpha: 1),
            NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.97, alpha: 1),
        ])?.draw(in: bounds, angle: -90)

        let card = bounds.insetBy(dx: 54, dy: 46)
        NSColor.black.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: card.offsetBy(dx: 0, dy: 8), xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).addClip()
        NSColor.white.setFill()
        card.fill()
        NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.60, alpha: 1).setFill()
        NSRect(x: card.minX, y: card.minY, width: card.width, height: 10).fill()
        NSGraphicsContext.restoreGraphicsState()

        let title: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
        ]
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1),
        ]
        let tokenAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
        ]
        ("Sprint review" as NSString).draw(at: NSPoint(x: 88, y: 86), withAttributes: title)
        ("Ship the picker, then annotate the screenshot." as NSString).draw(at: NSPoint(x: 88, y: 148), withAttributes: body)
        ("Owner: Ada Lovelace" as NSString).draw(at: NSPoint(x: 88, y: 188), withAttributes: body)

        let token = CGRect(x: 72, y: 228, width: 520, height: 48)
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: token, xRadius: 8, yRadius: 8).fill()
        ("API token: demo-token-0000" as NSString).draw(at: NSPoint(x: 88, y: 242), withAttributes: tokenAttrs)

        ("Ship date:" as NSString).draw(at: NSPoint(x: 88, y: 312), withAttributes: body)
        ("12 October" as NSString).draw(at: NSPoint(x: 260, y: 312), withAttributes: title.merging([
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        ]) { _, new in new })
    }
}

/// The area-capture overlay, drawn with the same fills and strokes as `AreaSelector`, over a stand-in desktop.
/// The real overlay covers the user's screen; this does not.
private final class AreaCaptureDemo: NSView {
    override var isFlipped: Bool { true }
    private var scene: NSImage?

    func prepare() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let canvas = FlippedScene(frame: bounds)
        canvas.dark = dark
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        canvas.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        scene = image
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let scene else { return }
        scene.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        let selection = NSRect(x: 120, y: 150, width: 360, height: 190)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        scene.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        let pointer = NSPoint(x: selection.maxX, y: selection.maxY)
        let axes = NSBezierPath()
        axes.move(to: NSPoint(x: bounds.minX, y: pointer.y))
        axes.line(to: NSPoint(x: bounds.maxX, y: pointer.y))
        axes.move(to: NSPoint(x: pointer.x, y: bounds.minY))
        axes.line(to: NSPoint(x: pointer.x, y: bounds.maxY))
        NSColor.white.withAlphaComponent(0.6).setStroke()
        axes.lineWidth = 0.5
        axes.stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5)).stroke()

        let cursor = NSCursor.crosshair.image
        cursor.draw(in: NSRect(x: pointer.x - cursor.size.width / 2, y: pointer.y - cursor.size.height / 2,
                                width: cursor.size.width, height: cursor.size.height))
    }
}

private final class FlippedScene: NSView {
    var dark = true
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let top = dark
            ? NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 1)
            : NSColor(calibratedRed: 0.55, green: 0.70, blue: 0.82, alpha: 1)
        let bottom = dark
            ? NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.34, alpha: 1)
            : NSColor(calibratedRed: 0.82, green: 0.89, blue: 0.93, alpha: 1)
        NSGradient(colors: [top, bottom])?.draw(in: bounds, angle: -90)

        panel(NSRect(x: 36, y: 40, width: 280, height: 250), title: "Notes", lines: [
            "Q3 launch",
            "• Clipboard history",
            "• Image editor",
            "• On-device OCR",
        ])
        panel(NSRect(x: 360, y: 86, width: 320, height: 220), title: "Mail", lines: [
            "To: ada@example.com",
            "Subject: Screenshots",
            "",
            "The picker is ready for review.",
        ])
    }

    private func panel(_ rect: NSRect, title: String, lines: [String]) {
        let fill = dark ? NSColor(calibratedWhite: 0.15, alpha: 1) : NSColor.white
        let bar = dark ? NSColor(calibratedWhite: 0.20, alpha: 1) : NSColor(calibratedWhite: 0.95, alpha: 1)
        let primary = dark ? NSColor.white : NSColor(calibratedWhite: 0.12, alpha: 1)
        let secondary = dark ? NSColor(calibratedWhite: 0.72, alpha: 1) : NSColor(calibratedWhite: 0.32, alpha: 1)
        NSColor.black.withAlphaComponent(dark ? 0.35 : 0.18).setFill()
        NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: 5), xRadius: 12, yRadius: 12).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).addClip()
        fill.setFill()
        rect.fill()
        bar.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 36).fill()

        let lights: [NSColor] = [
            NSColor(calibratedRed: 1, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 1, green: 0.74, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.25, alpha: 1),
        ]
        for (index, color) in lights.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 14 + CGFloat(index) * 16, y: rect.minY + 13, width: 10, height: 10)).fill()
        }
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: secondary,
        ]
        (title as NSString).draw(at: NSPoint(x: rect.minX + 70, y: rect.minY + 10), withAttributes: titleAttrs)
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: primary,
        ]
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: rect.minX + 18, y: rect.minY + 52 + CGFloat(index) * 26), withAttributes: lineAttrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
