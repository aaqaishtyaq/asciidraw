import AppKit

// Point size of the Finder window content. Finder maps the picture 1:1.
let width = 640
let height = 380
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not allocate the disk image background.\n", stderr)
    exit(1)
}
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(srgbRed: 0.925, green: 0.937, blue: 0.953, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

let ink = NSColor(srgbRed: 0.55, green: 0.59, blue: 0.64, alpha: 1)
ink.setStroke()
ink.setFill()
let shaft = NSBezierPath()
shaft.lineWidth = 3
shaft.lineCapStyle = .butt
shaft.move(to: NSPoint(x: 286, y: 214))
shaft.line(to: NSPoint(x: 354, y: 214))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 346, y: 226))
head.line(to: NSPoint(x: 362, y: 214))
head.line(to: NSPoint(x: 346, y: 202))
head.close()
head.fill()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the disk image background.\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
