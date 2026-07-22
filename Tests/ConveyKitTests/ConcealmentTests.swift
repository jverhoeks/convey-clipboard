import XCTest
import ConveyCore
@testable import ConveyKit

private struct FakeSnapshot: PasteboardSnapshot {
    var availableTypes: [String]
    func data(forType type: String) -> Data? { nil }
    func string(forType type: String) -> String? { nil }
}

final class ConcealmentTests: XCTestCase {
    func testDetectsConcealed() {
        let s = FakeSnapshot(availableTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        XCTAssertTrue(Concealment.isConcealedOrTransient(s))
    }
    func testDetectsTransient() {
        let s = FakeSnapshot(availableTypes: ["org.nspasteboard.TransientType"])
        XCTAssertTrue(Concealment.isConcealedOrTransient(s))
    }
    func testOrdinaryIsNotConcealed() {
        let s = FakeSnapshot(availableTypes: ["public.html", "public.utf8-plain-text"])
        XCTAssertFalse(Concealment.isConcealedOrTransient(s))
    }
}
