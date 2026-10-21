// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func drawIcon(in context: CGContext) {
    let size = canvas
    // macOS icon grid: an 824pt rounded square centered on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Soft drop shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    context.addPath(tilePath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Graphite background with a subtle top light.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(white: 0.2, alpha: 1).cgColor, NSColor(white: 0.04, alpha: 1).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // The island: a black pill hanging from the top edge, with a tiny live activity in it.
    let island = CGRect(x: size / 2 - 150, y: tile.maxY - 118, width: 300, height: 74)
    context.addPath(CGPath(roundedRect: island, cornerWidth: 37, cornerHeight: 37, transform: nil))
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    let orange = NSColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1)
    context.setFillColor(orange.cgColor)
    context.fillEllipse(in: CGRect(x: island.minX + 26, y: island.midY - 15, width: 30, height: 30))
    context.setFillColor(NSColor(white: 1, alpha: 0.9).cgColor)
    context.addPath(CGPath(roundedRect: CGRect(x: island.maxX - 110, y: island.midY - 9, width: 84, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil))
    context.fillPath()
    context.restoreGState()

    // The ring: a track and most of a lap filled in orange.
    let center = CGPoint(x: size / 2, y: size / 2 - 40)
    let radius: CGFloat = 250
    context.setLineCap(.round)
    context.setLineWidth(62)
    context.setStrokeColor(NSColor(white: 1, alpha: 0.1).cgColor)
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    context.setStrokeColor(orange.cgColor)
    context.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 1.5, clockwise: true)
    context.strokePath()

    // Clock hands meeting at an orange hub.
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(34)
    context.move(to: center)
    context.addLine(to: CGPoint(x: center.x, y: center.y + 160))
    context.strokePath()
    context.setLineWidth(34)
    context.move(to: center)
    context.addLine(to: CGPoint(x: center.x + 110, y: center.y - 64))
    context.strokePath()
    context.setFillColor(orange.cgColor)
    context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cLockIn-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(pixels: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
