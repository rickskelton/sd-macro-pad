// Draws the app icon and writes Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // Body: the standard macOS icon tile, 824 pt inside a 1024 pt canvas.
    let body = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 186 * s, yRadius: 186 * s)
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
                        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1)])!.draw(in: body, angle: -90)

    // Six keys, each lit from below in its own colour.
    let colours: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow, .systemPink, .systemTeal]
    let key: CGFloat = 150, gap: CGFloat = 28, left: CGFloat = 178, top: CGFloat = 690
    for row in 0..<2 {
        for column in 0..<3 {
            let x = left + CGFloat(column) * (key + gap), y = top - CGFloat(row) * (key + gap) - key
            let colour = colours[row * 3 + column]
            let glow = NSShadow()
            glow.shadowColor = colour.withAlphaComponent(0.9)
            glow.shadowBlurRadius = 34 * s
            NSGraphicsContext.saveGraphicsState()
            glow.set()
            colour.setFill()
            NSBezierPath(roundedRect: rect(x + 8, y + 2, key - 16, key - 10), xRadius: 30 * s, yRadius: 30 * s).fill()
            NSGraphicsContext.restoreGraphicsState()
            let cap = NSBezierPath(roundedRect: rect(x, y + 14, key, key - 14), xRadius: 30 * s, yRadius: 30 * s)
            NSGradient(colors: [NSColor(calibratedWhite: 0.36, alpha: 1), NSColor(calibratedWhite: 0.20, alpha: 1)])!.draw(in: cap, angle: -90)
        }
    }

    // The dial.
    let dial = NSBezierPath(ovalIn: rect(706, 437, 150, 150))
    NSGradient(colors: [NSColor(calibratedWhite: 0.62, alpha: 1), NSColor(calibratedWhite: 0.30, alpha: 1)])!.draw(in: dial, angle: -90)
    NSColor(calibratedWhite: 0.12, alpha: 1).setStroke()
    dial.lineWidth = 8 * s
    dial.stroke()
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 781 * s, y: 512 * s))
    mark.line(to: NSPoint(x: 781 * s, y: 569 * s))
    mark.lineWidth = 12 * s
    mark.lineCapStyle = .round
    NSColor.white.setStroke()
    mark.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
