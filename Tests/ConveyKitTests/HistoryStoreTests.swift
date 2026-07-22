import XCTest
import ConveyCore
@testable import ConveyKit

@MainActor
final class HistoryStoreTests: XCTestCase {
    private func entry(_ text: String) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: [.plainText], kind: .plainText,
                       text: text, imageData: nil, createdAt: Date(timeIntervalSince1970: 0))
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

    func testCrossTypeEntriesAreNotDuplicates() {
        let s = HistoryStore()
        let textEntry = entry("a")
        let imageEntry = ClipboardEntry(id: UUID(), sources: [.image], kind: .image,
                                         text: nil, imageData: Data([1, 2]), createdAt: Date(timeIntervalSince1970: 0))
        s.add(textEntry)
        s.add(imageEntry)
        XCTAssertEqual(s.entries.count, 2)
    }
}
