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
    /// Snapped to whole pixels at `scale`: mouse positions are fractional, and a fractional source
    /// rect makes ScreenCaptureKit resample, which blurs 1 px lines and text. `even` trims to even
    /// pixel sizes for video encoders, so the stream doesn't rescale either.
    static func captureRect(_ rect: CGRect, screenFrame: CGRect, scale: CGFloat = 1, even: Bool = false) -> CGRect {
        var x = ((rect.minX - screenFrame.minX) * scale).rounded()
        var y = ((screenFrame.maxY - rect.maxY) * scale).rounded()
        var w = (rect.width * scale).rounded(), h = (rect.height * scale).rounded()
        if even { w -= w.truncatingRemainder(dividingBy: 2); h -= h.truncatingRemainder(dividingBy: 2) }
        x = max(0, x); y = max(0, y)
        return CGRect(x: x / scale, y: y / scale, width: max(w, even ? 2 : 1) / scale, height: max(h, even ? 2 : 1) / scale)
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
