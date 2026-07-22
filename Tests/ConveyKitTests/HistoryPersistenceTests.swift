import XCTest
import ConveyCore
@testable import ConveyKit

final class HistoryPersistenceTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("convey-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func entry(_ t: String) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), sources: [.plainText], kind: .plainText, primaryFormat: .plainText,
                       text: t, imageData: nil, previewText: t, createdAt: Date(timeIntervalSince1970: 0))
    }

    func testSaveThenLoadRoundTrips() throws {
        let p = HistoryPersistence(directory: tempDir())
        let saved = [entry("a"), entry("b")]
        try p.save(saved)
        XCTAssertEqual(p.load(), saved)
    }
    func testLoadMissingReturnsEmpty() {
        XCTAssertTrue(HistoryPersistence(directory: tempDir()).load().isEmpty)
    }
    func testLoadCorruptReturnsEmpty() throws {
        let dir = tempDir()
        let fileURL = dir.appendingPathComponent("history.json")
        try "not json{".data(using: .utf8)!.write(to: fileURL)
        XCTAssertTrue(HistoryPersistence(directory: dir).load().isEmpty)
    }
}
