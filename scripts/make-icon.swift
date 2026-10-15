// Draws Lumina's app icon (the menu bar's rays symbol on a gradient squircle)
// and writes Resources/AppIcon.icns, plus docs/icon.png for the README.
// Usage: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
// macOS icon grid: the shape is 824pt inside a 1024pt canvas.
let shapeRect = NSRect(x: 100, y: 100, width: 824, height: 824)

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let shape = NSBezierPath(roundedRect: shapeRect, xRadius: 185, yRadius: 185)

    // Drop shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Background gradient
    NSGradient(colors: [
        NSColor(red: 0.36, green: 0.42, blue: 1.00, alpha: 1),
        NSColor(red: 0.20, green: 0.16, blue: 0.62, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    // Symbol
    let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "rays", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolRect = NSRect(
        x: (canvas - symbol.size.width) / 2,
        y: (canvas - symbol.size.height) / 2,
        width: symbol.size.width,
        height: symbol.size.height
    )
    symbol.draw(in: symbolRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    try renderIcon(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try renderIcon(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(output.path)")

let readmeIcon = root.appendingPathComponent("docs/icon.png")
try FileManager.default.createDirectory(at: readmeIcon.deletingLastPathComponent(), withIntermediateDirectories: true)
try renderIcon(pixels: 256).write(to: readmeIcon)
print("Wrote \(readmeIcon.path)")
