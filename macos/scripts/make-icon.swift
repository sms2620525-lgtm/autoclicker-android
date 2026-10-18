import AppKit
import Foundation
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.03, y: p * 0.03, width: p * 0.94, height: p * 0.94), xRadius: p * 0.21, yRadius: p * 0.21).fill()
        NSColor(calibratedRed: 0.50, green: 0.96, blue: 0.76, alpha: 1).setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: p * 0.25, y: p * 0.25, width: p * 0.50, height: p * 0.50))
        circle.lineWidth = p * 0.055
        circle.stroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: p * 0.5, y: p * 0.13)); cross.line(to: NSPoint(x: p * 0.5, y: p * 0.36))
        cross.move(to: NSPoint(x: p * 0.5, y: p * 0.64)); cross.line(to: NSPoint(x: p * 0.5, y: p * 0.87))
        cross.move(to: NSPoint(x: p * 0.13, y: p * 0.5)); cross.line(to: NSPoint(x: p * 0.36, y: p * 0.5))
        cross.move(to: NSPoint(x: p * 0.64, y: p * 0.5)); cross.line(to: NSPoint(x: p * 0.87, y: p * 0.5))
        cross.lineWidth = p * 0.04
        cross.stroke()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
