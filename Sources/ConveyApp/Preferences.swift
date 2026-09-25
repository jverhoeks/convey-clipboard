import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

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
    static func cmdShiftOption(_ code: Int, _ ch: String) -> HotKeySpec {
        HotKeySpec(keyCode: UInt32(code), modifiers: UInt32(cmdKey | shiftKey | optionKey), label: "⌥⇧⌘" + ch)
    }
}

enum Prefs {
    /// Use the app's standard domain from the bundle. Recent macOS versions reject
    /// creating a suite whose name is the running app's own bundle identifier.
    /// The explicit suite keeps an unbundled developer executable on that domain too.
    static let store: UserDefaults = {
        let domain = "org.verhoeks.convey"
        // One-time carry-over of hotkeys/settings from the pre-rename bundle id.
        if UserDefaults.standard.persistentDomain(forName: domain) == nil,
           let old = UserDefaults.standard.persistentDomain(forName: "com.jverhoeks.convey") {
            UserDefaults.standard.setPersistentDomain(old, forName: domain)
        }
        if Bundle.main.bundleIdentifier == domain { return .standard }
        return UserDefaults(suiteName: domain) ?? .standard
    }()

    static let defaults: [String: Any] = [
        "hotkey.picker": HotKeySpec(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey), label: "⌥⌘V").stored,
        "hotkey.screen": HotKeySpec.cmdShift(kVK_ANSI_0, "0").stored,
        "hotkey.area":   HotKeySpec.cmdShift(kVK_ANSI_1, "1").stored,
        "hotkey.window": HotKeySpec.cmdShift(kVK_ANSI_2, "2").stored,
        "hotkey.recordScreen": HotKeySpec.cmdShiftOption(kVK_ANSI_0, "0").stored,
        "hotkey.recordArea":   HotKeySpec.cmdShiftOption(kVK_ANSI_1, "1").stored,
        "hotkey.recordWindow": HotKeySpec.cmdShiftOption(kVK_ANSI_2, "2").stored,
        "screenshotPrefix": "Convey",
        "screenshotDirectory": "~/Pictures/Convey",
        "screenshotCopy": true,
        "screenshotSave": true,
        "screenshotEdit": false,
        "controlEnabled": false,
    ]
    static let suspendedKey = "hotkeysSuspended"  // true only while a HotKeyField is recording
    static func hotKey(_ key: String) -> HotKeySpec? {
        HotKeySpec(store.string(forKey: key) ?? "")
    }

    // Start on login as a proper Login Item (listed as "Convey", follows the app if moved).
    // Needs the Convey.app bundle; the bare debug binary gets an error alert.
    static var startsOnLogin: Bool { SMAppService.mainApp.status == .enabled }
    static func setStartsOnLogin(_ on: Bool) throws {
        // Drop the LaunchAgent older builds wrote, so login doesn't start two copies.
        try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/convey-app.plist"))
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
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
    @AppStorage("screenshotEdit", store: Prefs.store) var edit = false
    @AppStorage("controlEnabled", store: Prefs.store) var control = false
    @State private var login = Prefs.startsOnLogin
    @State private var loginError: String?
    @State private var permitted = CGPreflightScreenCaptureAccess()

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
                Toggle("Allow command-line control", isOn: $control)
                    .help("Lets `convey shot/record/windows` (scripts, AI agents) capture through Convey's Screen Recording permission. Only your own user account can connect.")
                LabeledContent("Screen Recording") {
                    if permitted { Text("Allowed").foregroundStyle(.secondary) }
                    else { Button("Allow…") { Screenshot.requestPermission() } }
                }
            }
            Section("Global Hotkeys") {
                HotKeyField("Clipboard picker", key: "hotkey.picker")
                HotKeyField("Area screenshot", key: "hotkey.area")
                HotKeyField("Window screenshot", key: "hotkey.window")
                HotKeyField("Fullscreen screenshot", key: "hotkey.screen")
                HotKeyField("Record area", key: "hotkey.recordArea")
                HotKeyField("Record window", key: "hotkey.recordWindow")
                HotKeyField("Record screen", key: "hotkey.recordScreen")
            }
            Section("Capture Destinations") {
                Toggle("Always copy to clipboard", isOn: $copy)
                Toggle("Always save to folder", isOn: $save)
                Toggle("Open screenshots in the editor", isOn: $edit)
                TextField("Folder", text: $directory).disabled(!save)
            }
        }
        .formStyle(.grouped)
        .defaultAppStorage(Prefs.store)
        .frame(width: 440, height: 720)
        .alert("Could not update login setting", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
            Button("OK") { loginError = nil }
        } message: { Text(loginError ?? "") }
    }
}
