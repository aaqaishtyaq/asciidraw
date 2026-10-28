import AppKit

// The icon is this picture, set in Menlo. A capital A, centered.
let lines = [
    "   #   ",
    "  # #  ",
    " #   # ",
    "#######",
    "#     #",
    "#     #",
]

let size = CGFloat(Int(CommandLine.arguments.dropFirst().first ?? "1024") ?? 1024)
let pixels = Int(size)
let columns = CGFloat(lines.map(\.count).max() ?? 1)
let rows = CGFloat(lines.count)
let fontSize = size * 0.96 / max(columns * 0.60, rows)
let font = NSFont(name: "Menlo-Bold", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(srgbRed: 0.945, green: 0.955, blue: 0.965, alpha: 1),
]
let sample = ("M" as NSString).size(withAttributes: attributes)
let lineHeight = sample.height * 0.78
let gridW = sample.width * columns
let gridH = lineHeight * rows
let originX = (size - gridW) / 2
let originY = (size - gridH) / 2

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not allocate the icon.\n", stderr)
    exit(1)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(srgbRed: 0.067, green: 0.071, blue: 0.086, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
for (row, line) in lines.enumerated() {
    let point = NSPoint(
        x: originX,
        y: originY + (rows - 1 - CGFloat(row)) * lineHeight
    )
    (line as NSString).draw(at: point, withAttributes: attributes)
}
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the icon.\n", stderr)
    exit(1)
}
let output = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/asciidraw-icon.png"
try png.write(to: URL(fileURLWithPath: output))
