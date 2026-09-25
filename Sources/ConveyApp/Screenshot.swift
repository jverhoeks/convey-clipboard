import AppKit
import ScreenCaptureKit
import ConveyCore

/// Greenshot-style capture: save PNG to a folder and/or put it on the clipboard.
/// Full screen, area, and window all capture through ScreenCaptureKit. `screencapture -l`
/// fails on current macOS ("could not create image from window"), so window mode picks
/// the window under the cursor itself.
enum Screenshot {
    enum Mode { case screen, window, area }

    /// Set by the app delegate: opens a capture in the annotation editor.
    @MainActor static var openInEditor: ((Data) -> Void)?

    @MainActor
    static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        requestPermission()
        return false
    }

    /// Preflight alone never adds Convey to System Settings › Screen Recording. A real
    /// ScreenCaptureKit query does: it registers the app and shows the system prompt.
    @MainActor
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
        Task { _ = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        let alert = NSAlert()
        alert.messageText = "Allow Convey to record the screen"
        alert.informativeText = "Turn on Convey in System Settings › Privacy & Security › Screen & System Audio Recording. macOS applies it after Convey restarts."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit & Reopen")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case .alertSecondButtonReturn:
            // Relaunch after we exit; the single-instance lock would refuse a copy started now.
            if Bundle.main.bundlePath.hasSuffix(".app") {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundlePath]
                try? p.run()
            }
            NSApp.terminate(nil)
        default: break
        }
    }

    @MainActor
    static func capture(_ mode: Mode) {
        let d = Prefs.store
        guard ["screenshotSave", "screenshotCopy", "screenshotEdit"].contains(where: d.bool(forKey:)) else { NSSound.beep(); return }
        guard ensurePermission() else { return }
        switch mode {
        case .screen:
            guard let s = screenUnderMouse else { NSSound.beep(); return }
            grab(s, rect: s.frame)
        case .area:
            AreaSelector.begin { screen, rect in
                // Give the window server a beat to remove the overlay before reading the framebuffer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { grab(screen, rect: rect) }
            }
        case .window:
            if #available(macOS 14, *) {
                Task { await WindowSelector.begin { window, scale in Task { await captureWindow(window, scale: scale) } } }
            } else {
                legacyWindowCapture()
            }
        }
    }

    @MainActor static var screenUnderMouse: NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// `rect` in global Cocoa coordinates (origin bottom-left); converted to the display's top-left point space.
    @MainActor
    private static func grab(_ screen: NSScreen, rect: NSRect) {
        Task { @MainActor in
            guard let png = await png(screen: screen, rect: rect) else { NSSound.beep(); return }
            deliver(png)
        }
    }

    /// PNG of `rect` (global Cocoa coordinates) on `screen`. No UI, no side effects.
    @MainActor
    static func png(screen: NSScreen, rect: NSRect) async -> Data? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        let local = SelectionGeometry.captureRect(rect, screenFrame: screen.frame, scale: screen.backingScaleFactor)
        let cg: CGImage?
        if #available(macOS 14, *) {
            cg = try? await sckImage(display: id, rect: local, scale: screen.backingScaleFactor)
        } else {
            // Crop the actual framebuffer using its pixel dimensions, including Retina/scaled displays.
            if let full = CGDisplayCreateImage(id) {
                let sx = CGFloat(full.width) / screen.frame.width
                let sy = CGFloat(full.height) / screen.frame.height
                cg = full.cropping(to: CGRect(x: local.minX * sx, y: local.minY * sy,
                                             width: local.width * sx, height: local.height * sy).integral)
            } else { cg = nil }
        }
        return cg.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    @available(macOS 14, *)
    private static func sckImage(display id: CGDirectDisplayID, rect: CGRect, scale: CGFloat) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = rect
        cfg.width = Int((rect.width * scale).rounded()); cfg.height = Int((rect.height * scale).rounded())
        cfg.captureResolution = .best
        cfg.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                                                          configuration: cfg)
    }

    @available(macOS 14, *)
    private static func captureWindow(_ window: SCWindow, scale: CGFloat) async {
        guard let png = try? await windowPNG(window, scale: scale) else { NSSound.beep(); return }
        await deliver(png)
    }

    @available(macOS 14, *)
    static func windowPNG(_ window: SCWindow, scale: CGFloat) async throws -> Data {
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int((window.frame.width * scale).rounded()))
        cfg.height = max(1, Int((window.frame.height * scale).rounded()))
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: cfg)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw EditorError.imageRendering }
        return png
    }

    /// Where a capture is saved: the screenshot folder, or a temp file when saving is off
    /// (recordings still need a file to put on the clipboard).
    @MainActor
    static func outputURL(extension ext: String) throws -> URL {
        let d = Prefs.store
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH_mm_ss"
        let prefix = (d.string(forKey: "screenshotPrefix") ?? "").replacingOccurrences(of: "/", with: "-")
        let dir = d.bool(forKey: "screenshotSave")
            ? URL(fileURLWithPath: ((d.string(forKey: "screenshotDirectory") ?? "~") as NSString).expandingTildeInPath)
            : FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = "\(prefix) \(fmt.string(from: Date()))".trimmingCharacters(in: .whitespaces)
        var url = dir.appendingPathComponent("\(base).\(ext)"), n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n).\(ext)"); n += 1
        }
        return url
    }

    @MainActor
    private static func deliver(_ data: Data) {
        let d = Prefs.store
        if d.bool(forKey: "screenshotSave") {
            do { try data.write(to: outputURL(extension: "png"), options: .atomic) }
            catch { alert("Could not save screenshot", error) }
        }
        if d.bool(forKey: "screenshotCopy") { PasteboardWriter().write(.bytes(data), as: .png, to: .general) }
        if d.bool(forKey: "screenshotEdit") { openInEditor?(data) }
    }

    @MainActor
    static func alert(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    /// macOS 13 has no SCScreenshotManager. Interactive `screencapture` is the fallback.
    private static func legacyWindowCapture() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("convey-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-t", "png", "-i", "-w", tmp.path]
        p.terminationHandler = { _ in
            guard let data = try? Data(contentsOf: tmp) else { return }
            try? FileManager.default.removeItem(at: tmp)
            Task { @MainActor in deliver(data) }
        }
        do { try p.run() } catch { NSSound.beep() }
    }
}

/// One dimmed, click-through-proof overlay per screen; drag to pick a rectangle, Esc to cancel.
@MainActor
final class AreaSelector: NSWindow {
    private static var active: [AreaSelector] = []
    private static var done: ((NSScreen, NSRect) -> Void)?
    private var start: NSPoint?
    private let view = SelectionView()

    static func begin(_ done: @escaping (NSScreen, NSRect) -> Void) {
        guard active.isEmpty else { return }
        self.done = done
        active = NSScreen.screens.map(AreaSelector.init)
        NSApp.activate(ignoringOtherApps: true)
        active.forEach { $0.makeKeyAndOrderFront(nil) }
        active.first { $0.frame.contains(NSEvent.mouseLocation) }?.makeKey()
        NSCursor.crosshair.set()
    }

    private static func finish(_ result: (NSScreen, NSRect)? = nil) {
        guard !active.isEmpty else { return }
        let completion = done
        done = nil
        active.forEach { $0.orderOut(nil) }
        active = []
        NSCursor.arrow.set()
        if let (s, r) = result, r.width > 2, r.height > 2 { completion?(s, r) }
    }

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
        view.pointer = convertPoint(fromScreen: NSEvent.mouseLocation)
    }

    override var canBecomeKey: Bool { true }
    private func point(for e: NSEvent) -> NSPoint {
        let p = view.convert(e.locationInWindow, from: nil)
        return SelectionGeometry.clamp(p, to: view.bounds)
    }
    override func mouseMoved(with e: NSEvent) {
        view.pointer = point(for: e)
        NSCursor.crosshair.set()
    }
    override func mouseDown(with e: NSEvent) {
        start = point(for: e)
        view.rect = .zero
        mouseMoved(with: e)
    }
    override func mouseDragged(with e: NSEvent) {
        guard let a = start else { return }
        let b = point(for: e)
        view.pointer = b
        NSCursor.crosshair.set()
        view.rect = SelectionGeometry.rectangle(from: a, to: b)
    }
    override func mouseUp(with e: NSEvent) {
        guard let screen, start != nil else { return }
        mouseDragged(with: e)
        AreaSelector.finish((screen, convertToScreen(view.convert(view.rect, to: nil))))
    }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { AreaSelector.finish() }  // Esc
    }

    private final class SelectionView: NSView {
        var rect = NSRect.zero { didSet { needsDisplay = true } }
        var pointer: NSPoint? { didSet { needsDisplay = true } }
        private var tracking: NSTrackingArea?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero,
                options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }
        override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
        override func mouseEntered(with event: NSEvent) { window?.mouseMoved(with: event) }
        override func mouseExited(with event: NSEvent) { pointer = nil }
        override func mouseMoved(with event: NSEvent) { window?.mouseMoved(with: event) }
        override func mouseDown(with event: NSEvent) { window?.mouseDown(with: event) }
        override func mouseDragged(with event: NSEvent) { window?.mouseDragged(with: event) }
        override func mouseUp(with event: NSEvent) { window?.mouseUp(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func draw(_ dirty: NSRect) {
            NSColor.black.withAlphaComponent(0.25).setFill(); bounds.fill()
            NSColor.clear.setFill(); rect.fill(using: .copy)
            if let pointer, bounds.contains(pointer) {
                let axes = NSBezierPath()
                axes.move(to: NSPoint(x: bounds.minX, y: pointer.y))
                axes.line(to: NSPoint(x: bounds.maxX, y: pointer.y))
                axes.move(to: NSPoint(x: pointer.x, y: bounds.minY))
                axes.line(to: NSPoint(x: pointer.x, y: bounds.maxY))
                NSColor.white.withAlphaComponent(0.6).setStroke()
                axes.lineWidth = 0.5
                axes.stroke()
            }
            NSColor.white.setStroke(); NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            guard rect.width >= 1, rect.height >= 1 else { return }
            // Size in pixels, as the saved PNG will be, just below the selection.
            let scale = window?.backingScaleFactor ?? 1
            let label = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attrs)
            var pill = NSRect(x: rect.minX, y: rect.minY - size.height - 10, width: size.width + 12, height: size.height + 4)
            if pill.minY < bounds.minY { pill.origin.y = rect.minY + 4 }
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
            label.draw(at: NSPoint(x: pill.minX + 6, y: pill.minY + 2), withAttributes: attrs)
        }
    }
}

/// Click the window under the cursor. Escape cancels. Hands back the ScreenCaptureKit window
/// and its display scale; the overlay is never part of the capture, which targets that window alone.
@MainActor
final class WindowSelector: NSWindow {
    private struct Candidate {
        let window: SCWindow
        let frame: CGRect // Cocoa global
        let title: String?
    }

    private static var active: [WindowSelector] = []
    private static var candidates: [Candidate] = []
    private static var highlight: Candidate?
    private static var pick: ((SCWindow, CGFloat) -> Void)?
    private let view = HighlightView()

    static func begin(_ pick: @escaping (SCWindow, CGFloat) -> Void) async {
        guard active.isEmpty else { return }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        catch { NSSound.beep(); return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // Front to back, so the first frame containing the pointer is the one the user sees.
        candidates = content.windows.compactMap { window in
            guard window.isOnScreen, window.frame.width > 8, window.frame.height > 8 else { return nil }
            return Candidate(window: window,
                             frame: SelectionGeometry.cocoaRect(fromTopLeft: window.frame, primaryHeight: primaryHeight),
                             title: window.title)
        }
        guard !candidates.isEmpty else { NSSound.beep(); return }
        self.pick = pick
        active = NSScreen.screens.map(WindowSelector.init)
        NSApp.activate(ignoringOtherApps: true)
        active.forEach { $0.makeKeyAndOrderFront(nil) }
        active.first { $0.frame.contains(NSEvent.mouseLocation) }?.makeKey()
        NSCursor.arrow.set()
        updateHighlight(at: NSEvent.mouseLocation)
    }

    private static func updateHighlight(at global: CGPoint) {
        let index = SelectionGeometry.frontmost(containing: global, frames: candidates.map(\.frame))
        highlight = index.map { candidates[$0] }
        for selector in active {
            selector.view.highlight = selector.localHighlight
            selector.view.needsDisplay = true
        }
    }

    private static func finish() {
        guard !active.isEmpty else { return }
        let windows = active
        active = []
        highlight = nil
        candidates = []
        pick = nil
        windows.forEach { $0.orderOut(nil) }
        NSCursor.arrow.set()
    }

    private static func choose(_ candidate: Candidate) {
        let pick = pick
        finish()
        let center = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main
        pick?(candidate.window, screen?.backingScaleFactor ?? 2)
    }

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    private var localHighlight: (rect: CGRect, title: String?)? {
        guard let highlight = WindowSelector.highlight, let screen else { return nil }
        let local = highlight.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let visible = local.intersection(CGRect(origin: .zero, size: screen.frame.size))
        guard !visible.isNull, visible.width > 1, visible.height > 1 else { return nil }
        return (visible, highlight.title)
    }

    private func globalPoint(for e: NSEvent) -> CGPoint {
        let local = view.convert(e.locationInWindow, from: nil)
        return convertToScreen(NSRect(origin: local, size: .zero)).origin
    }
    override func mouseMoved(with e: NSEvent) { WindowSelector.updateHighlight(at: globalPoint(for: e)) }
    override func mouseDown(with e: NSEvent) { mouseMoved(with: e) }
    override func mouseUp(with e: NSEvent) {
        // Close on mouse-up. Tearing the overlay down inside mouseDown drops the event.
        let point = globalPoint(for: e)
        guard let index = SelectionGeometry.frontmost(containing: point, frames: WindowSelector.candidates.map(\.frame))
        else { return }
        WindowSelector.choose(WindowSelector.candidates[index])
    }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { WindowSelector.finish() }
    }

    private final class HighlightView: NSView {
        var highlight: (rect: CGRect, title: String?)?
        private var tracking: NSTrackingArea?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }
        override func mouseEntered(with event: NSEvent) { window?.mouseMoved(with: event) }
        override func mouseExited(with event: NSEvent) { WindowSelector.updateHighlight(at: NSEvent.mouseLocation) }
        override func mouseMoved(with event: NSEvent) { window?.mouseMoved(with: event) }
        override func mouseDown(with event: NSEvent) { window?.mouseDown(with: event) }
        override func mouseUp(with event: NSEvent) { window?.mouseUp(with: event) }
        override func draw(_ dirty: NSRect) {
            NSColor.black.withAlphaComponent(0.35).setFill()
            bounds.fill()
            guard let highlight else { return }
            NSColor.clear.setFill()
            highlight.rect.fill(using: .copy)
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: highlight.rect.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()
            guard let title = highlight.title, !title.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            (title as NSString).draw(at: NSPoint(x: highlight.rect.minX + 8, y: highlight.rect.maxY + 6),
                                     withAttributes: attrs)
        }
    }
}
