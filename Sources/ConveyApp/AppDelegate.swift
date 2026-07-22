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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            targetsFor: { [convey] entry in convey.graph.validTargets(from: entry.sources) },
            onConvert: { [weak self] entry, target in self?.convert(entry, to: target) },
            onClear: { [weak self] in self?.history.clear() }
        )
        return NSHostingController(rootView: view)
    }

    private func convert(_ entry: ClipboardEntry, to target: Format) {
        guard let payload = entry.payload, let from = entry.sources.first else { return }
        Task { @MainActor in
            do {
                // Choose the richest source that can reach the target.
                let source = entry.sources.first(where: { convey.graph.path(from: $0, to: target) != nil }) ?? from
                let result = try await convey.convert(payload, from: source, to: target)
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
}
