import XCTest
@testable import ConveyCore

final class VersionTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(conveyVersion.isEmpty)
    }
}
