import Foundation

@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var entries: [ClipboardEntry] = []
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    public func add(_ entry: ClipboardEntry) {
        entries.removeAll { $0.sameContent(as: entry) }
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    public func replaceAll(_ newEntries: [ClipboardEntry]) {
        entries = Array(newEntries.prefix(capacity))
    }

    public func clear() {
        entries.removeAll()
    }
}
