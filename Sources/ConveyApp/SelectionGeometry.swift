import Foundation

enum SelectionGeometry {
    static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y))
    }

    /// Cocoa global coordinates use a bottom-left origin; capture uses display-local top-left.
    static func captureRect(_ rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    /// ScreenCaptureKit window frames are points, origin at the top-left of the primary display.
    static func cocoaRect(fromTopLeft rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// `frames` is front to back. Nil when the point misses every window.
    static func frontmost(containing point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }
}
