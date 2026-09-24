import Foundation

/// Bundled local builds use their Info.plist version. Release CI stamps the tag
/// here so standalone CLI binaries also report the release version.
public let conveyVersion: String = {
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
        return version
    }
    // The CLI is a second executable within Contents/MacOS, not CFBundleExecutable.
    if let executable = Bundle.main.executableURL {
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        if contents.lastPathComponent == "Contents",
           let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let version = plist["CFBundleShortVersionString"] as? String { return version }
    }
    return "dev"
}()
