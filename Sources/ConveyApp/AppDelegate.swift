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
        history.replaceAll(persistence.load())
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, so it's safe to hop to the MainActor
            // synchronously here to call the MainActor-isolated pollClipboard().
            MainActor.assumeIsolated {
                self?.pollClipboard()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Convey")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = makePickerController()

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
        ]
        hotKeys = []  // unregister old ones first
        guard !Prefs.store.bool(forKey: Prefs.suspendedKey) else { return }
        hotKeys = bindings.compactMap { key, action in
            Prefs.hotKey(key).flatMap { HotKey(keyCode: $0.keyCode, modifiers: $0.modifiers, handler: action) }
        }
    }

    private var prefsWindow: NSWindow?
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
            onClear: { [weak self] in self?.history.clear() },
            onPreferences: { [weak self] in self?.showPreferences() },
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
                NSSound.beep()
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
            do { try await export(entry, as: target, to: url) } catch { NSSound.beep() }
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

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let entry = monitor.makeEntry(from: SystemPasteboard(pb), id: UUID(), now: Date()) else { return }
        history.add(entry)
        let snapshot = history.entries
        let persistence = self.persistence
        saveQueue.async { try? persistence.save(snapshot) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveQueue.sync { try? self.persistence.save(self.history.entries) }
    }
}
