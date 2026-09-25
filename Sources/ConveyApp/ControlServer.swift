import AppKit
import ScreenCaptureKit
import ConveyCore

/// What `convey windows|shot|record|stop|status` asks the running app to do.
/// Parsed here, not in the CLI, so the protocol is just the argument list.
enum ControlCommand: Equatable {
    enum Target: Equatable {
        case screen(Int)        // index into NSScreen.screens; 0 = the menu-bar display
        case window(String)     // window id, or app/title substring
        case area(CGRect)       // global points, origin top-left (like `screencapture -R`)
    }
    case windows(json: Bool, all: Bool)
    case shot(Target, output: String?)
    case record(Target, output: String?, duration: Double?)
    case stop, status

    static let usage = """
        convey windows [--json] [--all]                 list windows: id, app, title, x,y,w,h (--all: other Spaces too)
        convey shot   screen [N] | window <id|text> | area x,y,w,h  [-o file.png]
        convey record screen [N] | window <id|text> | area x,y,w,h  [-o file.mp4] [--duration secs]
        convey stop                                     stop recording, print the file
        convey status                                   idle, or the recording file and seconds elapsed
        """

    static func parse(_ args: [String]) throws -> ControlCommand {
        var rest = args.dropFirst()[...]
        var output: String?, duration: Double?, json = false, all = false
        var positional: [String] = []
        while let arg = rest.popFirst() {
            switch arg {
            case "-o", "--output": output = try value(&rest, for: arg)
            case "--duration":
                guard let d = Double(try value(&rest, for: arg)), d > 0 else { throw ControlError.usage("--duration needs seconds") }
                duration = d
            case "--json": json = true
            case "--all": all = true
            default: positional.append(arg)
            }
        }
        switch args.first {
        case "windows": return .windows(json: json, all: all)
        case "stop": return .stop
        case "status": return .status
        case "shot": return .shot(try target(positional), output: output)
        case "record": return .record(try target(positional), output: output, duration: duration)
        default: throw ControlError.usage("unknown command")
        }
    }

    private static func value(_ rest: inout ArraySlice<String>, for flag: String) throws -> String {
        guard let v = rest.popFirst() else { throw ControlError.usage("\(flag) needs a value") }
        return v
    }

    private static func target(_ p: [String]) throws -> Target {
        switch (p.first, p.count) {
        case ("screen", 1): return .screen(0)
        case ("screen", 2):
            guard let n = Int(p[1]), n >= 0 else { throw ControlError.usage("screen index must be 0, 1, …") }
            return .screen(n)
        case ("window", 2...): return .window(p.dropFirst().joined(separator: " "))
        case ("area", 2):
            let n = p[1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard n.count == 4, n[2] > 0, n[3] > 0 else { throw ControlError.usage("area is x,y,w,h in points") }
            return .area(CGRect(x: n[0], y: n[1], width: n[2], height: n[3]))
        default: throw ControlError.usage("target is screen [N], window <id|text>, or area x,y,w,h")
        }
    }
}

enum ControlError: LocalizedError {
    case usage(String), failed(String)
    var errorDescription: String? {
        switch self {
        case let .usage(m): return "\(m)\n\n\(ControlCommand.usage)"
        case let .failed(m): return m
        }
    }
}

/// Runs control commands inside the app, which holds the Screen Recording permission,
/// so agents and scripts don't need it themselves.
@MainActor
enum ControlRunner {
    static func run(_ args: [String]) async -> (ok: Bool, output: String) {
        do {
            guard Prefs.store.bool(forKey: "controlEnabled") else {
                throw ControlError.failed("Command-line control is off. Turn on Convey › Preferences › Allow command-line control.")
            }
            return (true, try await execute(ControlCommand.parse(args)))
        } catch { return (false, error.localizedDescription) }
    }

    private static func execute(_ command: ControlCommand) async throws -> String {
        switch command {
        case let .windows(json, all):
            let list = try await windows(onScreenOnly: !all)
            if json {
                let rows: [[String: Any]] = list.map {
                    ["id": Int($0.windowID), "app": $0.owningApplication?.applicationName ?? "", "title": $0.title ?? "",
                     "x": Int($0.frame.minX), "y": Int($0.frame.minY), "w": Int($0.frame.width), "h": Int($0.frame.height)]
                }
                return String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
            }
            return list.map {
                "\($0.windowID)\t\($0.owningApplication?.applicationName ?? "")\t\($0.title ?? "")\t"
                    + "\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width)),\(Int($0.frame.height))"
            }.joined(separator: "\n")

        case let .shot(target, output):
            try requirePermission()
            let url = try output.map { URL(fileURLWithPath: $0) } ?? Screenshot.outputURL(extension: "png")
            let png: Data?
            switch target {
            case let .window(query):
                guard #available(macOS 14, *) else { throw ControlError.failed("Window screenshots need macOS 14.") }
                let (window, scale) = try await find(query)
                png = try await Screenshot.windowPNG(window, scale: scale)
            default:
                let (screen, rect) = try region(target)
                png = await Screenshot.png(screen: screen, rect: rect)
            }
            guard let png else { throw ControlError.failed("Capture failed.") }
            try png.write(to: url, options: .atomic)
            return url.path

        case let .record(target, output, duration):
            try requirePermission()
            let url = output.map { URL(fileURLWithPath: $0) }
            if case let .window(query) = target {
                let (window, scale) = try await find(query)
                try await Recorder.start(window: window, scale: scale, output: url)
            } else {
                let (screen, rect) = try region(target)
                try await Recorder.start(screen: screen, rect: rect, output: url)
            }
            guard let duration else { return "recording \(Recorder.file?.path ?? "")" }
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let done = try await Recorder.finish() else { throw ControlError.failed("Recording was stopped early.") }
            return done.path

        case .stop:
            guard let done = try await Recorder.finish() else { throw ControlError.failed("Not recording.") }
            return done.path

        case .status:
            guard let file = Recorder.file, let since = Recorder.startedAt else { return "idle" }
            return "recording \(file.path) \(Int(Date().timeIntervalSince(since)))s"
        }
    }

    private static func requirePermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw ControlError.failed("Convey has no Screen Recording permission. Open Convey › Preferences › Screen Recording › Allow…")
        }
    }

    /// Normal app windows, front to back, without Convey's own. Off-screen = other Spaces or hidden.
    private static func windows(onScreenOnly: Bool = true) async throws -> [SCWindow] {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenOnly).windows.filter {
            $0.windowLayer == 0 && $0.frame.width > 8 && $0.frame.height > 8
                && $0.owningApplication?.processID != getpid()
                // Off-screen lists are mostly untitled helper windows nobody wants to capture.
                && ($0.isOnScreen || !($0.title ?? "").isEmpty)
        }
    }

    /// A window id, else the frontmost window whose app name or title contains `query`.
    private static func find(_ query: String) async throws -> (SCWindow, CGFloat) {
        let list = try await windows()
        let q = query.lowercased()
        guard let window = list.first(where: { UInt32(query) == $0.windowID })
                ?? list.first(where: { ($0.owningApplication?.applicationName ?? "").lowercased().contains(q)
                                       || ($0.title ?? "").lowercased().contains(q) })
        else { throw ControlError.failed("No window matches \"\(query)\". See `convey windows`.") }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let frame = SelectionGeometry.cocoaRect(fromTopLeft: window.frame, primaryHeight: primary)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main
        return (window, screen?.backingScaleFactor ?? 2)
    }

    /// Screen and Cocoa-global rect for a screen or area target.
    private static func region(_ target: ControlCommand.Target) throws -> (NSScreen, NSRect) {
        switch target {
        case let .screen(i):
            guard NSScreen.screens.indices.contains(i) else {
                throw ControlError.failed("No screen \(i); there are \(NSScreen.screens.count).")
            }
            return (NSScreen.screens[i], NSScreen.screens[i].frame)
        case let .area(topLeft):
            let rect = SelectionGeometry.cocoaRect(fromTopLeft: topLeft, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
            else { throw ControlError.failed("That area is not on any screen.") }
            return (screen, rect.intersection(screen.frame))
        case .window: fatalError("windows are resolved by find(_:)")
        }
    }
}

/// Unix-socket listener for the CLI. Only this user's processes can connect: the socket is
/// 0600 inside ~/Library, and the peer's uid is checked.
enum ControlServer {
    static func start() {
        let path = ControlSocket.path
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        unlink(path)
        guard var addr = ControlSocket.address(path) else { return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard fd >= 0, bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            fputs("convey-app: control socket unavailable: \(String(cString: strerror(errno)))\n", stderr)
            return
        }
        Thread.detachNewThread {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { continue }
                handle(client)
            }
        }
    }

    private static func handle(_ client: Int32) {
        var uid: uid_t = 0, gid: gid_t = 0
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid(), let line = readLine(client),
              let args = try? JSONSerialization.jsonObject(with: line) as? [String] else { close(client); return }
        Task { @MainActor in
            let (ok, output) = await ControlRunner.run(args)
            let reply = (try? JSONSerialization.data(withJSONObject: ["ok": ok, "output": output])) ?? Data()
            (reply + Data("\n".utf8)).withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
            close(client)
        }
    }

    private static func readLine(_ fd: Int32) -> Data? {
        var data = Data(), byte: UInt8 = 0
        while data.count < 65_536, read(fd, &byte, 1) == 1 {
            if byte == UInt8(ascii: "\n") { return data }
            data.append(byte)
        }
        return data.isEmpty ? nil : data
    }
}
