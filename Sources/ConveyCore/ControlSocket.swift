import Foundation

/// Where the running Convey.app listens for `convey windows|shot|record|stop|status`.
/// Protocol: one connection per command; the client sends a JSON array of arguments plus "\n",
/// the app answers `{"ok": Bool, "output": String}` plus "\n" and closes.
public enum ControlSocket {
    public static var path: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Convey/control.sock").path
    }

    public static let verbs: Set<String> = ["windows", "shot", "record", "stop", "status"]

    /// Fills a `sockaddr_un` for `path`; nil when the path doesn't fit (104 bytes on macOS).
    public static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }
}
