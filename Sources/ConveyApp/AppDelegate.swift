import AppKit
import SwiftUI
import Carbon.HIToolbox
import ConveyCore
import ConveyKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    let history = HistoryStore()
    private let convey = Convey()
    private lazy var previewCache = PreviewCache(convey: convey)
    private var hotKeys: [HotKey] = []
    private let monitor = ClipboardMonitor()
    private let persistence = HistoryPersistence(directory: HistoryPersistence.defaultDirectory)
    private var pollTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let saveQueue = DispatchQueue(label: "convey.history.save")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.store.register(defaults: Prefs.defaults)
        installEditingMenu()
        history.replaceAll(persistence.load())
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, so it's safe to hop to the MainActor
            // synchronously here to call the MainActor-isolated pollClipboard().
            MainActor.assumeIsolated {
                self?.pollClipboard()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = StatusIcon.idle
            button.imagePosition = .imageLeading
            button.toolTip = "Convey Clipboard"
            button.setAccessibilityLabel("Convey Clipboard")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])  // right-click: Preferences / Quit menu
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = makePickerController()

        Screenshot.openInEditor = { [weak self] png in self?.editCapture(png) }
        Recorder.onChange = { [weak self] started in self?.showRecording(since: started) }

        ControlServer.start()
        Prefs.store.removeObject(forKey: Prefs.suspendedKey)  // stale if we died mid-recording
        registerHotKeys()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: Prefs.store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKeys() }
        }
    }

    private func registerHotKeys() {
        let bindings: [(String, () -> Void)] = [
            ("hotkey.picker", { [weak self] in self?.togglePopover() }),
            ("hotkey.screen", { Screenshot.capture(.screen) }),
            ("hotkey.area",   { Screenshot.capture(.area) }),
            ("hotkey.window", { Screenshot.capture(.window) }),
            ("hotkey.recordScreen", { Recorder.toggle(.screen) }),
            ("hotkey.recordArea",   { Recorder.toggle(.area) }),
            ("hotkey.recordWindow", { Recorder.toggle(.window) }),
        ]
        hotKeys = []  // unregister old ones first
        guard !Prefs.store.bool(forKey: Prefs.suspendedKey) else { return }
        hotKeys = bindings.compactMap { key, action in
            Prefs.hotKey(key).flatMap { HotKey(keyCode: $0.keyCode, modifiers: $0.modifiers, handler: action) }
        }
    }

    // Re-opening Convey.app (Finder/Spotlight) shows Preferences: the only entry point when
    // macOS hides the menu-bar icon (System Settings › Menu Bar, or a crowded notch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return false
    }

    private func installEditingMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Convey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
                                    ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                    ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private var prefsWindow: NSWindow?
    private var editors: [UUID: EditorWindowController] = [:]

    private func edit(_ entry: ClipboardEntry) {
        do {
            let controller: EditorWindowController
            if let existing = editors[entry.id] {
                controller = existing
            } else {
                controller = try EditorWindowController(entry: entry, convey: convey)
                controller.onClose = { [weak self] in self?.editors.removeValue(forKey: entry.id) }
                editors[entry.id] = controller
            }
            popover.performClose(nil)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch { showConversionError(error) }
    }
    /// A fresh capture straight into the annotation editor (Greenshot's "open in editor" destination).
    private func editCapture(_ png: Data) {
        edit(ClipboardEntry(id: UUID(), sources: [.image], kind: .image, primaryFormat: .image,
                            text: nil, imageData: png, previewText: nil, createdAt: Date()))
    }

    private var recordingTimer: Timer?
    private func showRecording(since start: Date?) {
        recordingTimer?.invalidate(); recordingTimer = nil
        guard let button = statusItem.button else { return }
        guard let start else {
            button.image = StatusIcon.idle; button.title = ""; button.toolTip = "Convey Clipboard"
            return
        }
        button.image = StatusIcon.recording
        button.toolTip = "Recording — click to stop"
        let tick = { [weak button] in
            let s = Int(Date().timeIntervalSince(start))
            button?.attributedTitle = NSAttributedString(string: String(format: " %d:%02d", s / 60, s % 60),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
        }
        tick()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
    }

    @objc private func openPreferences() { showPreferences() }
    @objc private func menuCapture(_ item: NSMenuItem) { CaptureAction.all[item.tag].perform() }
    private func showPreferences() {
        popover.performClose(nil)
        if prefsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            w.title = "Convey Preferences"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
            prefsWindow = w
        }
        prefsWindow?.center(); prefsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePickerController() -> NSViewController {
        let view = PickerView(
            history: history,
            targetsFor: { [convey] entry in convey.graph.validTargets(from: [entry.primaryFormat]) },
            onConvert: { [weak self] entry, target in self?.convert(entry, to: target) },
            onSave: { [weak self] entry, target in self?.save(entry, as: target) },
            onOpen: { [weak self] entry in self?.open(entry) },
            onEdit: { [weak self] entry in self?.edit(entry) },
            onRemove: { [weak self] entry in
                self?.history.remove(id: entry.id)
                self?.persistHistory()
            },
            onClear: { [weak self] in
                self?.history.clear()
                self?.persistHistory()
            },
            onPreferences: { [weak self] in self?.showPreferences() },
            onCapture: { [weak self] action in
                self?.popover.performClose(nil)
                action.perform()
            },
            cache: previewCache
        )
        return NSHostingController(rootView: view)
    }

    private func convert(_ entry: ClipboardEntry, to target: Format) {
        guard let payload = entry.payload else { return }
        Task { @MainActor in
            do {
                let result = try await convey.convert(payload, from: entry.primaryFormat, to: target)
                PasteboardWriter().write(result, as: target, to: .general)
                popover.performClose(nil)
            } catch {
                showConversionError(error)
            }
        }
    }

    /// Payload of `entry` in `target` (converting if needed), written to `url` for Save/Open.
    private func export(_ entry: ClipboardEntry, as target: Format, to url: URL) async throws {
        guard let payload = entry.payload else { return }
        let out = target == entry.primaryFormat ? payload
                : try await convey.convert(payload, from: entry.primaryFormat, to: target)
        switch out {
        case let .text(t): try t.write(to: url, atomically: true, encoding: .utf8)
        case let .bytes(d): try d.write(to: url, options: .atomic)
        }
    }

    private func save(_ entry: ClipboardEntry, as target: Format) {
        popover.performClose(nil)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clipboard.\(target.fileExtension)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do { try await export(entry, as: target, to: url) } catch { showConversionError(error) }
        }
    }

    private func open(_ entry: ClipboardEntry) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("convey-\(entry.id.uuidString.prefix(8)).\(entry.primaryFormat.fileExtension)")
        Task { @MainActor in
            do { try await export(entry, as: entry.primaryFormat, to: url); NSWorkspace.shared.open(url) }
            catch { NSSound.beep() }
        }
    }

    private func showConversionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not convert clipboard entry"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        let rightClick = NSApp.currentEvent?.type == .rightMouseUp
        if Recorder.isRecording, !rightClick { Recorder.stop(); return }
        if rightClick {
            let menu = NSMenu()
            if Recorder.isRecording {
                menu.addItem(withTitle: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "").target = self
            } else {
                for action in CaptureAction.all {
                    if action.id == 3 { menu.addItem(.separator()) }
                    let item = menu.addItem(withTitle: action.help, action: #selector(menuCapture(_:)), keyEquivalent: "")
                    item.target = self; item.tag = action.id
                }
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Convey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func stopRecording() { Recorder.stop() }

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let entry = monitor.makeEntry(from: SystemPasteboard(pb), id: UUID(), now: Date()) else { return }
        history.add(entry)
        persistHistory()
    }

    private func persistHistory() {
        let snapshot = history.entries
        let persistence = self.persistence
        saveQueue.async { try? persistence.save(snapshot) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard editors.values.contains(where: { $0.editorDocument.isDirty }) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit and discard unsaved edits?"
        alert.informativeText = "Copy or save your editor changes before quitting to keep them."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        Recorder.stop()
        saveQueue.sync { try? self.persistence.save(self.history.entries) }
    }
}

/// Menu-bar artwork: the app icon's clipboard with ⇄, drawn as a full-height template image
/// (a text glyph rendered tiny, and SF Symbol lookup can fail and leave an invisible item).
enum StatusIcon {
    static let idle: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let board = NSBezierPath(roundedRect: NSRect(x: 2.75, y: 0.75, width: 12.5, height: 14.5), xRadius: 2.5, yRadius: 2.5)
            board.lineWidth = 1.5
            board.stroke()
            NSBezierPath(roundedRect: NSRect(x: 5.5, y: 13.5, width: 7, height: 4), xRadius: 1.5, yRadius: 1.5).fill()
            let arrows = NSBezierPath()
            arrows.move(to: NSPoint(x: 5.5, y: 9.5)); arrows.line(to: NSPoint(x: 12.5, y: 9.5))    // →
            arrows.move(to: NSPoint(x: 10.3, y: 11.7)); arrows.line(to: NSPoint(x: 12.5, y: 9.5)); arrows.line(to: NSPoint(x: 10.3, y: 7.3))
            arrows.move(to: NSPoint(x: 12.5, y: 5)); arrows.line(to: NSPoint(x: 5.5, y: 5))        // ←
            arrows.move(to: NSPoint(x: 7.7, y: 7.2)); arrows.line(to: NSPoint(x: 5.5, y: 5)); arrows.line(to: NSPoint(x: 7.7, y: 2.8))
            arrows.lineWidth = 1.5
            arrows.lineCapStyle = .round
            arrows.lineJoinStyle = .round
            arrows.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Convey Clipboard"
        return image
    }()

    static let recording: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 1, yRadius: 1).fill()  // stop square
            return true
        }
        image.accessibilityDescription = "Stop recording"
        return image
    }()
}
