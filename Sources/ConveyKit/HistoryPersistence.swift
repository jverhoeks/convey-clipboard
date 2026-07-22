import Foundation

public struct HistoryPersistence {
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("history.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Convey", isDirectory: true)
    }

    public func save(_ entries: [ClipboardEntry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
