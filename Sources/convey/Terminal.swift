import Foundation
import ConveyCore

/// `convey rec`: record a shell session as asciicast v2 (text + ANSI colors + timing, not pixels).
/// macOS's own `script -r` owns the pty, raw mode, and resizes; we only convert its log.
func recordTerminal(to path: String?) -> Int32 {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
        fputs("convey rec: needs an interactive terminal\n", stderr); return 1
    }
    let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd-HHmmss"
    let out = URL(fileURLWithPath: path ?? "convey-\(stamp.string(from: Date())).cast")
    let raw = FileManager.default.temporaryDirectory.appendingPathComponent("convey-rec-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: raw) }
    var size = winsize()
    _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
    let env = ProcessInfo.processInfo.environment
    let shell = env["SHELL"] ?? "/bin/zsh"

    // posix_spawn, not Process: Process starts the child in its own process group, so `script`
    // is a background job and stops (SIGTTOU) the moment it puts the terminal in raw mode.
    setenv("CONVEY_REC", "1", 1)  // lets a prompt show it's recording
    let argv = ["/usr/bin/script", "-q", "-r", raw.path, shell].map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    fputs("● Recording to \(out.path). Exit the shell (Ctrl-D) to stop.\n", stderr)
    var pid: pid_t = 0, status: Int32 = 0
    let spawned = posix_spawn(&pid, argv[0], nil, nil, argv, environ)
    guard spawned == 0 else { fputs("convey rec: \(String(cString: strerror(spawned)))\n", stderr); return 1 }
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}

    do {
        let cast = try Asciicast.fromScriptRecording(
            Data(contentsOf: raw), width: Int(size.ws_col == 0 ? 80 : size.ws_col),
            height: Int(size.ws_row == 0 ? 24 : size.ws_row),
            env: ["SHELL": shell, "TERM": env["TERM"] ?? "xterm-256color"])
        try cast.write(to: out, atomically: true, encoding: .utf8)
    } catch { fputs("convey rec: \(error)\n", stderr); return 1 }
    fputs("■ Saved \(out.path) — replay: convey play \(out.lastPathComponent)\n", stderr)
    return 0
}

/// `convey play`: replay an asciicast v2 file in this terminal. Pauses longer than 2 s are shortened.
func playCast(_ path: String) -> Int32 {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("convey play: cannot read \(path)\n", stderr); return 1
    }
    var last = 0.0
    for line in text.split(separator: "\n").dropFirst() {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [Any], event.count == 3,
              let t = (event[0] as? NSNumber)?.doubleValue, event[1] as? String == "o",
              let chunk = event[2] as? String else { continue }
        Thread.sleep(forTimeInterval: min(max(t - last, 0), 2))
        last = t
        FileHandle.standardOutput.write(Data(chunk.utf8))
    }
    return 0
}

/// `convey windows|shot|record|stop|status`: forwarded to the running Convey.app, which has the
/// Screen Recording permission (so the calling terminal or agent doesn't need it).
func control(_ args: [String]) -> Int32 {
    var args = args
    // The app has its own working directory; send absolute output paths.
    if let i = args.firstIndex(where: { $0 == "-o" || $0 == "--output" }), i + 1 < args.count {
        args[i + 1] = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath).standardizedFileURL.path
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    guard var addr = ControlSocket.address(ControlSocket.path), withUnsafePointer(to: &addr, {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }) == 0 else {
        fputs("convey: Convey.app is not running (open -a Convey)\n", stderr); return 1
    }
    guard let request = try? JSONSerialization.data(withJSONObject: args) else { return 1 }
    (request + Data("\n".utf8)).withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
    var reply = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 { break }
        reply.append(contentsOf: buffer[0..<n])
    }
    guard let answer = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
          let ok = answer["ok"] as? Bool, let output = answer["output"] as? String else {
        fputs("convey: no answer from Convey.app (is it up to date?)\n", stderr); return 1
    }
    if ok { print(output); return 0 }
    fputs("convey: \(output)\n", stderr)
    return 1
}
