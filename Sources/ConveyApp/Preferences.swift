import AppKit
import SwiftUI
import Carbon.HIToolbox

/// One recordable global hotkey, persisted in UserDefaults as "keyCode|carbonModifiers|label".
/// Empty string = disabled.
struct HotKeySpec: Equatable {
    var keyCode: UInt32, modifiers: UInt32, label: String

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
    init?(_ stored: String) {
        let p = stored.split(separator: "|", omittingEmptySubsequences: false)
        guard p.count == 3, let k = UInt32(p[0]), let m = UInt32(p[1]) else { return nil }
        self.init(keyCode: k, modifiers: m, label: String(p[2]))
    }
    var stored: String { "\(keyCode)|\(modifiers)|\(label)" }

    init(event e: NSEvent) {
        var m: UInt32 = 0, s = ""
        let f = e.modifierFlags
        if f.contains(.control) { m |= UInt32(controlKey); s += "⌃" }
        if f.contains(.option)  { m |= UInt32(optionKey);  s += "⌥" }
        if f.contains(.shift)   { m |= UInt32(shiftKey);   s += "⇧" }
        if f.contains(.command) { m |= UInt32(cmdKey);     s += "⌘" }
        self.init(keyCode: UInt32(e.keyCode), modifiers: m,
                  label: s + (e.charactersIgnoringModifiers ?? "").uppercased())
    }

    static func ctrlShift(_ code: Int, _ ch: String) -> HotKeySpec {
        HotKeySpec(keyCode: UInt32(code), modifiers: UInt32(controlKey | shiftKey), label: "⌃⇧" + ch)
    }
}

enum Prefs {
    /// One explicit domain, so `make run` (bare binary) and Convey.app read the same settings.
    static let store = UserDefaults(suiteName: "com.jverhoeks.convey")!

    static let defaults: [String: Any] = [
        "hotkey.picker": HotKeySpec(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey), label: "⌥⌘V").stored,
        "hotkey.screen": HotKeySpec.ctrlShift(kVK_ANSI_0, "0").stored,
        "hotkey.area":   HotKeySpec.ctrlShift(kVK_ANSI_1, "1").stored,
        "hotkey.window": HotKeySpec.ctrlShift(kVK_ANSI_2, "2").stored,
        "screenshotPrefix": "Convey",
        "screenshotDirectory": "~/Pictures/Convey",
        "screenshotCopy": true,
        "screenshotSave": true,
    ]
    static let suspendedKey = "hotkeysSuspended"  // true only while a HotKeyField is recording
    static func hotKey(_ key: String) -> HotKeySpec? {
        HotKeySpec(store.string(forKey: key) ?? "")
    }

    // Start on login via a LaunchAgent: works for both `make run` (bare binary) and Convey.app.
    static let agentURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/convey-app.plist")
    static var startsOnLogin: Bool { FileManager.default.fileExists(atPath: agentURL.path) }
    static func setStartsOnLogin(_ on: Bool) {
        if on {
            let plist: [String: Any] = ["Label": "convey-app", "RunAtLoad": true,
                                        "ProgramArguments": [Bundle.main.executablePath ?? CommandLine.arguments[0]]]
            try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL)
        } else {
            _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"), arguments: ["unload", agentURL.path])
            try? FileManager.default.removeItem(at: agentURL)
        }
    }
}

struct HotKeyField: View {
    let title: String
    @AppStorage var stored: String
    @State private var monitor: Any?

    init(_ title: String, key: String) { self.title = title; _stored = AppStorage(wrappedValue: "", key) }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Button(monitor != nil ? "Press keys…" : (HotKeySpec(stored)?.label ?? "—")) { record() }
                    .frame(width: 140)
                Button { stored = "" } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
    }

    private func record() {
        // Suspend the global hotkeys, otherwise pressing a combo already bound to
        // another Convey action fires that action instead of reaching this monitor.
        Prefs.store.set(true, forKey: Prefs.suspendedKey)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let spec = HotKeySpec(event: e)
            // Esc cancels; a key with no modifier (or only ⇧) would hijack normal typing system-wide.
            if e.keyCode != UInt16(kVK_Escape), spec.modifiers & ~UInt32(shiftKey) != 0 { stored = spec.stored }
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
            Prefs.store.set(false, forKey: Prefs.suspendedKey)
            return nil
        }
    }
}

struct PreferencesView: View {
    @AppStorage("screenshotPrefix") var prefix = "Convey"
    @AppStorage("screenshotDirectory") var directory = "~/Pictures/Convey"
    @AppStorage("screenshotCopy") var copy = true
    @AppStorage("screenshotSave") var save = true
    @State private var login = Prefs.startsOnLogin

    var body: some View {
        Form {
            Section("System") {
                Toggle("Start Convey on login", isOn: $login)
                    .onChange(of: login) { Prefs.setStartsOnLogin($0) }
                TextField("Default filename prefix", text: $prefix)
                Button("Screen Recording permission…") {
                    if !CGRequestScreenCaptureAccess() {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
            }
            Section("Global Hotkeys") {
                HotKeyField("Clipboard picker", key: "hotkey.picker")
                HotKeyField("Area screenshot", key: "hotkey.area")
                HotKeyField("Window screenshot", key: "hotkey.window")
                HotKeyField("Fullscreen screenshot", key: "hotkey.screen")
            }
            Section("Screenshot Destinations") {
                Toggle("Always copy to clipboard", isOn: $copy)
                Toggle("Always save to folder", isOn: $save)
                TextField("Folder", text: $directory).disabled(!save)
            }
        }
        .formStyle(.grouped)
        .defaultAppStorage(Prefs.store)
        .frame(width: 440, height: 460)
    }
}
