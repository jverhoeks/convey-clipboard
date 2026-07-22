import XCTest
import ConveyCore
@testable import ConveyKit

private struct FakeSnapshot: PasteboardSnapshot {
    var availableTypes: [String]
    var strings: [String: String] = [:]
    var datas: [String: Data] = [:]
    func data(forType type: String) -> Data? { datas[type] }
    func string(forType type: String) -> String? { strings[type] }
}

final class ClipboardMonitorTests: XCTestCase {
    let monitor = ClipboardMonitor()
    let id = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func testBuildsTextEntry() {
        let s = FakeSnapshot(availableTypes: ["public.html", "public.utf8-plain-text"],
                             strings: ["public.html": "<b>x</b>", "public.utf8-plain-text": "x"])
        let e = monitor.makeEntry(from: s, id: id, now: now)
        XCTAssertEqual(e?.kind, .html)
        XCTAssertEqual(e?.text, "x")   // prefers plain text for the stored/reconvertible payload
    }
    func testSkipsConcealed() {
        let s = FakeSnapshot(availableTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                             strings: ["public.utf8-plain-text": "secret"])
        XCTAssertNil(monitor.makeEntry(from: s, id: id, now: now))
    }
    func testSkipsEmpty() {
        XCTAssertNil(monitor.makeEntry(from: FakeSnapshot(availableTypes: []), id: id, now: now))
    }
    func testBuildsImageEntry() {
        let png = Data([0x89, 0x50])
        let s = FakeSnapshot(availableTypes: ["public.png"], datas: ["public.png": png])
        let e = monitor.makeEntry(from: s, id: id, now: now)
        XCTAssertEqual(e?.kind, .image)
        XCTAssertEqual(e?.imageData, png)
    }
}
