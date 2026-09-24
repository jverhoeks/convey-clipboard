import XCTest
import ConveyCore
@testable import ConveyKit

@MainActor
final class HistoryStoreTests: XCTestCase {
    private func entry(_ text: String) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: [.plainText], kind: .plainText, primaryFormat: .plainText,
                       text: text, imageData: nil, previewText: text, createdAt: Date(timeIntervalSince1970: 0))
    }

    func testAddNewestFirst() {
        let s = HistoryStore()
        s.add(entry("a")); s.add(entry("b"))
        XCTAssertEqual(s.entries.map(\.text), ["b", "a"])
    }
    func testDuplicateContentMovesToFront() {
        let s = HistoryStore()
        s.add(entry("a")); s.add(entry("b")); s.add(entry("a"))
        XCTAssertEqual(s.entries.map(\.text), ["a", "b"])
    }
    func testCapacityDropsOldest() {
        let s = HistoryStore(capacity: 2)
        s.add(entry("a")); s.add(entry("b")); s.add(entry("c"))
        XCTAssertEqual(s.entries.map(\.text), ["c", "b"])
    }
    func testClear() {
        let s = HistoryStore(); s.add(entry("a")); s.clear()
        XCTAssertTrue(s.entries.isEmpty)
    }

    func testRemovePersistsOnlyRemainingEntries() throws {
        let first = entry("first"), second = entry("second")
        let store = HistoryStore()
        store.add(first)
        store.add(second)
        store.remove(id: first.id)
        store.remove(id: UUID())
        XCTAssertEqual(store.entries, [second])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = HistoryPersistence(directory: directory)
        try persistence.save(store.entries)
        XCTAssertEqual(persistence.load(), [second])
    }

    func testNonpositiveCapacityKeepsHistoryEmpty() {
        for capacity in [0, -1] {
            let store = HistoryStore(capacity: capacity)
            store.add(entry("a"))
            XCTAssertTrue(store.entries.isEmpty)
            store.replaceAll([entry("b")])
            XCTAssertTrue(store.entries.isEmpty)
        }
    }

    func testCrossTypeEntriesAreNotDuplicates() {
        let s = HistoryStore()
        let textEntry = entry("a")
        let imageEntry = ClipboardEntry(id: UUID(), sources: [.image], kind: .image, primaryFormat: .image,
                                         text: nil, imageData: Data([1, 2]), previewText: nil, createdAt: Date(timeIntervalSince1970: 0))
        s.add(textEntry)
        s.add(imageEntry)
        XCTAssertEqual(s.entries.count, 2)
    }
}
