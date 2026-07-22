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
    private var hotKey: HotKey?
    private let monitor = ClipboardMonitor()
    private let persistence = HistoryPersistence(directory: HistoryPersistence.defaultDirectory)
    private var pollTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let saveQueue = DispatchQueue(label: "convey.history.save")

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // ⌥⌘V — keyCode 9 is 'v'; modifiers optionKey | cmdKey.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(optionKey | cmdKey)) { [weak self] in
            self?.togglePopover()
        }
    }

    private func makePickerController() -> NSViewController {
        let view = PickerView(
            history: history,
            targetsFor: { [convey] entry in convey.graph.validTargets(from: [entry.primaryFormat]) },
            onConvert: { [weak self] entry, target in self?.convert(entry, to: target) },
            onClear: { [weak self] in self?.history.clear() },
            renderMermaid: { [convey] entry in await PreviewImageLoader.rendered(for: entry, using: convey) }
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
