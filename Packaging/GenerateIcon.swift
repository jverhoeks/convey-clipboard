import AppKit

// Reproducible vector artwork, rasterized separately at each macOS icon size.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 58, y: 58, width: 908, height: 908), xRadius: 205, yRadius: 205)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0.05, 0.14, 0.24).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.04, 0.12, 0.22), ending: color(0.10, 0.34, 0.45))!.draw(in: tile, angle: 70)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    let sheet = NSBezierPath(roundedRect: NSRect(x: 270, y: 204, width: 484, height: 600), xRadius: 65, yRadius: 65)
    NSGraphicsContext.saveGraphicsState()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.set()
    NSColor.white.setFill()
    sheet.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.84, 0.94, 0.97), ending: .white)!.draw(in: sheet, angle: 90)

    let clip = NSBezierPath(roundedRect: NSRect(x: 404, y: 752, width: 216, height: 90), xRadius: 30, yRadius: 30)
    NSGradient(starting: color(0.13, 0.70, 0.70), ending: color(0.42, 0.93, 0.81))!.draw(in: clip, angle: 90)
    color(0.07, 0.29, 0.37).setFill()
    NSBezierPath(roundedRect: NSRect(x: 469, y: 786, width: 86, height: 17), xRadius: 8, yRadius: 8).fill()

    func arrow(y: CGFloat, right: Bool, ink: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = 46
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: right ? 386 : 638, y: y))
        path.line(to: NSPoint(x: right ? 638 : 386, y: y))
        path.move(to: NSPoint(x: right ? 570 : 454, y: y + 68))
        path.line(to: NSPoint(x: right ? 638 : 386, y: y))
        path.line(to: NSPoint(x: right ? 570 : 454, y: y - 68))
        ink.setStroke()
        path.stroke()
    }
    arrow(y: 584, right: true, ink: color(0.05, 0.57, 0.59))
    arrow(y: 394, right: false, ink: color(0.13, 0.34, 0.57))
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        try render(size: points * scale).write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
