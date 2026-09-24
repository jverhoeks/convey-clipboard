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
        guard p.count >= 3, let k = UInt32(p[0]), let m = UInt32(p[1]) else { return nil }
        self.init(keyCode: k, modifiers: m, label: p.dropFirst(2).joined(separator: "|"))
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
                  label: s + (HotKeySpec.keyName(e.keyCode) ?? e.charactersIgnoringModifiers ?? "").uppercased())
    }

    /// Unshifted character for a key code ("1", not "!"). nil for non-printing keys.
    static func keyName(_ code: UInt16) -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0, len = 0, chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes {
            UCKeyTranslate($0.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), code,
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           UInt32(kUCKeyTranslateNoDeadKeysMask), &dead, chars.count, &len, &chars)
        }
        guard status == noErr, len > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: len)
        // F-keys/arrows translate to control or private-use scalars: no useful name.
        return name.unicodeScalars.contains { [.control, .privateUse].contains($0.properties.generalCategory) } ? nil : name
    }

    static func cmdShift(_ code: Int, _ ch: String) -> HotKeySpec {
        HotKeySpec(keyCode: UInt32(code), modifiers: UInt32(cmdKey | shiftKey), label: "⇧⌘" + ch)
    }
}

enum Prefs {
    /// Use the app's standard domain from the bundle. Recent macOS versions reject
    /// creating a suite whose name is the running app's own bundle identifier.
    /// The explicit suite keeps an unbundled developer executable on that domain too.
    static let store: UserDefaults = {
        let domain = "com.jverhoeks.convey"
        if Bundle.main.bundleIdentifier == domain { return .standard }
        return UserDefaults(suiteName: domain) ?? .standard
    }()

    static let defaults: [String: Any] = [
        "hotkey.picker": HotKeySpec(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey), label: "⌥⌘V").stored,
        "hotkey.screen": HotKeySpec.cmdShift(kVK_ANSI_0, "0").stored,
        "hotkey.area":   HotKeySpec.cmdShift(kVK_ANSI_1, "1").stored,
        "hotkey.window": HotKeySpec.cmdShift(kVK_ANSI_2, "2").stored,
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
    static func setStartsOnLogin(_ on: Bool) throws {
        if on {
            let plist: [String: Any] = ["Label": "convey-app", "RunAtLoad": true,
                                        "ProgramArguments": [Bundle.main.executablePath ?? CommandLine.arguments[0]]]
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL, options: .atomic)
        } else {
            // Removing the plist disables the next login without unloading/killing this running app.
            if startsOnLogin { try FileManager.default.removeItem(at: agentURL) }
        }
    }
}

struct HotKeyField: View {
    let title: String
    @AppStorage var stored: String
    @State private var monitor: Any?
    @AppStorage(Prefs.suspendedKey) private var suspended = false

    init(_ title: String, key: String) { self.title = title; _stored = AppStorage(wrappedValue: "", key) }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Button(monitor != nil ? "Press keys…" : (HotKeySpec(stored)?.label ?? "—")) { record() }
                    .frame(width: 140)
                    .disabled(suspended && monitor == nil)
                Button { stopRecording(); stored = "" } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stopRecording() }
    }

    private func stopRecording() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        Prefs.store.set(false, forKey: Prefs.suspendedKey)
    }

    private func record() {
        guard monitor == nil else { stopRecording(); return }
        // Suspend the global hotkeys, otherwise pressing a combo already bound to
        // another Convey action fires that action instead of reaching this monitor.
        Prefs.store.set(true, forKey: Prefs.suspendedKey)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let spec = HotKeySpec(event: e)
            // Esc cancels; a key with no modifier (or only ⇧) would hijack normal typing system-wide.
            if e.keyCode != UInt16(kVK_Escape), spec.modifiers & ~UInt32(shiftKey) != 0 { stored = spec.stored }
            stopRecording()
            return nil
        }
    }
}

struct PreferencesView: View {
    // Explicit suite: a modifier on `body` does not apply to this view's own property wrappers,
    // so these would otherwise follow the process domain (`convey-app` vs Convey.app).
    @AppStorage("screenshotPrefix", store: Prefs.store) var prefix = "Convey"
    @AppStorage("screenshotDirectory", store: Prefs.store) var directory = "~/Pictures/Convey"
    @AppStorage("screenshotCopy", store: Prefs.store) var copy = true
    @AppStorage("screenshotSave", store: Prefs.store) var save = true
    @State private var login = Prefs.startsOnLogin
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("System") {
                Toggle("Start Convey on login", isOn: $login)
                    .onChange(of: login) { enabled in
                        guard enabled != Prefs.startsOnLogin else { return }
                        do { try Prefs.setStartsOnLogin(enabled) }
                        catch { loginError = error.localizedDescription; login = Prefs.startsOnLogin }
                    }
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
        .frame(width: 440, height: 600)
        .alert("Could not update login setting", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
            Button("OK") { loginError = nil }
        } message: { Text(loginError ?? "") }
    }
}
