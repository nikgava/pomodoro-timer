import AppKit
import Foundation

// Regenerate the custom checked-in icon using only the macOS drawing APIs:
// swift scripts/make-icon.swift /tmp/Pomodoro.iconset
// iconutil -c icns /tmp/Pomodoro.iconset -o Resources/AppIcon.icns
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/Pomodoro.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let files = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

for (size, filename) in files {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    background.fill()
    NSColor(calibratedWhite: 0.84, alpha: 1).setStroke()
    background.lineWidth = 2
    background.stroke()
    NSColor(calibratedWhite: 0.22, alpha: 1).setStroke()
    let dial = NSBezierPath(ovalIn: NSRect(x: 270, y: 235, width: 484, height: 484))
    dial.lineWidth = 44
    dial.stroke()
    let crown = NSBezierPath()
    crown.lineWidth = 44
    crown.lineCapStyle = .round
    crown.move(to: NSPoint(x: 512, y: 721))
    crown.line(to: NSPoint(x: 512, y: 789))
    crown.move(to: NSPoint(x: 459, y: 789))
    crown.line(to: NSPoint(x: 565, y: 789))
    crown.stroke()
    let hands = NSBezierPath()
    hands.lineWidth = 39
    hands.lineCapStyle = .round
    hands.lineJoinStyle = .round
    hands.move(to: NSPoint(x: 409, y: 575))
    hands.line(to: NSPoint(x: 512, y: 477))
    hands.line(to: NSPoint(x: 512, y: 637))
    hands.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent(filename))
}
