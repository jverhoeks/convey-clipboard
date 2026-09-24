import AppKit

if let flag = CommandLine.arguments.firstIndex(of: "--screenshots") {
    let next = CommandLine.arguments.index(after: flag)
    guard next < CommandLine.arguments.endIndex else {
        fputs("usage: convey-app --screenshots <directory>\n", stderr)
        exit(2)
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[next], isDirectory: true)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    Task { @MainActor in
        let code = await ScreenshotGallery.run(directory: directory)
        exit(code)
    }
    app.run()
}

// Single instance: hold an exclusive lock for the process lifetime. Works for both the bare
// debug binary and Convey.app, unlike a bundle-identifier check.
let lockFD = open(NSTemporaryDirectory() + "convey-app.lock", O_CREAT | O_RDWR, 0o600)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    fputs("convey-app is already running\n", stderr)
    exit(1)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar only, no dock icon
app.run()
