#!/usr/bin/env swift
import AppKit
import Foundation

// Original vector drawing, rasterized at each macOS app icon size.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
func icon(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 205, yRadius: 205)
    let colors = [NSColor(red: 0.05, green: 0.16, blue: 0.21, alpha: 1), NSColor(red: 0.10, green: 0.28, blue: 0.32, alpha: 1)]
    NSGradient(colors: colors)!.draw(in: tile, angle: 45)
    let base = NSColor(red: 0.78, green: 0.92, blue: 0.93, alpha: 0.14)
    let fills = [NSColor(red: 0.33, green: 0.84, blue: 0.73, alpha: 1),
                 NSColor(red: 0.52, green: 0.69, blue: 1.0, alpha: 1),
                 NSColor(red: 1, green: 0.73, blue: 0.47, alpha: 1)]
    for (index, height) in [330.0, 500.0, 410.0].enumerated() {
        let x = 242.0 + Double(index) * 190
        base.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 244, width: 142, height: 536), xRadius: 48, yRadius: 48).fill()
        fills[index].setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 244, width: 142, height: height), xRadius: 48, yRadius: 48).fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 12, y: 484, width: 166, height: 16), xRadius: 8, yRadius: 8).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try icon(size * scale).write(to: catalog.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: catalog.appendingPathComponent("Contents.json"))
try icon(512).write(to: root.appendingPathComponent("docs/icon.png"))
print("Generated CLIProxyBar icons.")
