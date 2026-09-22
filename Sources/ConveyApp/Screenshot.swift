import AppKit
import ConveyCore

/// Greenshot-style capture: save PNG to a folder and/or put it on the clipboard.
/// Uses the system `screencapture` tool, so no Screen Recording plumbing of our own.
enum Screenshot {
    enum Mode: String { case screen = "", window = "-w", area = "-s" }

    @MainActor
    static func capture(_ mode: Mode) {
        let d = Prefs.store
        let save = d.bool(forKey: "screenshotSave"), copy = d.bool(forKey: "screenshotCopy")
        guard save || copy else { NSSound.beep(); return }

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH_mm_ss"
        let name = "\(d.string(forKey: "screenshotPrefix") ?? "") \(fmt.string(from: Date())).png"
        let dir = save ? URL(fileURLWithPath: ((d.string(forKey: "screenshotDirectory") ?? "~") as NSString).expandingTildeInPath)
                       : FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name.trimmingCharacters(in: .whitespaces))

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // ponytail: -m = main display only; without it screencapture writes one file per display
        // and only the first would reach the clipboard. Add display picking if that matters.
        p.arguments = ["-x", "-t", "png"] + (mode == .screen ? ["-m"] : ["-i", mode.rawValue]) + [file.path]
        p.terminationHandler = { _ in
            // User may have pressed Esc: no file, nothing to copy.
            guard copy, let data = try? Data(contentsOf: file) else { return }
            Task { @MainActor in PasteboardWriter().write(.bytes(data), as: .png, to: .general) }
            if !save { try? FileManager.default.removeItem(at: file) }
        }
        do { try p.run() } catch { NSSound.beep() }
    }
}
