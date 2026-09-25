import XCTest
@testable import ConveyApp

final class SelectionGeometryTests: XCTestCase {
    func testDragInEveryDirection() {
        let a = CGPoint(x: 10, y: 20), b = CGPoint(x: 100, y: 80)
        let expected = CGRect(x: 10, y: 20, width: 90, height: 60)
        XCTAssertEqual(SelectionGeometry.rectangle(from: a, to: b), expected)
        XCTAssertEqual(SelectionGeometry.rectangle(from: b, to: a), expected)
        XCTAssertEqual(SelectionGeometry.rectangle(from: CGPoint(x: 10, y: 80),
                                                   to: CGPoint(x: 100, y: 20)), expected)
        XCTAssertEqual(SelectionGeometry.rectangle(from: CGPoint(x: 100, y: 20),
                                                   to: CGPoint(x: 10, y: 80)), expected)
    }

    func testDragOutsideDisplayIsClamped() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(SelectionGeometry.clamp(CGPoint(x: -100, y: 1200), to: bounds),
                       CGPoint(x: 0, y: 1080))
        XCTAssertEqual(SelectionGeometry.clamp(CGPoint(x: 2000, y: -20), to: bounds),
                       CGPoint(x: 1920, y: 0))
    }

    func testCaptureCoordinatesForOffsetDisplays() {
        for origin in [CGPoint.zero, CGPoint(x: -1920, y: 200), CGPoint(x: 400, y: -1080)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
            let selection = CGRect(x: origin.x + 100, y: origin.y + 200, width: 300, height: 400)
            XCTAssertEqual(SelectionGeometry.captureRect(selection, screenFrame: screen),
                           CGRect(x: 100, y: 480, width: 300, height: 400))
        }
    }

    func testScreenCaptureKitFramesUseATopLeftPrimaryOrigin() {
        // Top-left of a 1080-point primary display.
        XCTAssertEqual(SelectionGeometry.cocoaRect(fromTopLeft: CGRect(x: 0, y: 0, width: 100, height: 80),
                                                   primaryHeight: 1080),
                       CGRect(x: 0, y: 1000, width: 100, height: 80))
        // A display arranged below the primary starts at y=1080 in that space.
        XCTAssertEqual(SelectionGeometry.cocoaRect(fromTopLeft: CGRect(x: 0, y: 1080, width: 100, height: 80),
                                                   primaryHeight: 1080),
                       CGRect(x: 0, y: -80, width: 100, height: 80))
    }

    func testFrontmostWindowWinsTheHitTest() {
        let frames = [CGRect(x: 0, y: 0, width: 50, height: 50), CGRect(x: 0, y: 0, width: 200, height: 200)]
        XCTAssertEqual(SelectionGeometry.frontmost(containing: CGPoint(x: 10, y: 10), frames: frames), 0)
        XCTAssertEqual(SelectionGeometry.frontmost(containing: CGPoint(x: 100, y: 100), frames: frames), 1)
        XCTAssertNil(SelectionGeometry.frontmost(containing: CGPoint(x: -1, y: 10), frames: frames))
    }

    func testCaptureRectSnapsFractionalMouseRectToWholePixels() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let drag = CGRect(x: 100.37, y: 200.2, width: 300.49, height: 99.6)
        let r = SelectionGeometry.captureRect(drag, screenFrame: screen, scale: 2)
        for v in [r.minX, r.minY, r.width, r.height] { XCTAssertEqual((v * 2).rounded(), v * 2) }
        XCTAssertEqual(r.width, 300.5)
        let video = SelectionGeometry.captureRect(drag, screenFrame: screen, scale: 1, even: true)
        XCTAssertEqual(video.width, 300); XCTAssertEqual(video.height, 100)
    }
}
