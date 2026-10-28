import AppKit

let size = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
let sheet = canvas.insetBy(dx: 168, dy: 188)

let image = NSImage(size: canvas.size)
image.lockFocus()

NSGradient(colors: [
    NSColor(srgbRed: 0.17, green: 0.21, blue: 0.25, alpha: 1),
    NSColor(srgbRed: 0.08, green: 0.10, blue: 0.12, alpha: 1),
])!.draw(in: canvas, angle: -90)

NSColor.black.withAlphaComponent(0.30).setFill()
NSBezierPath(roundedRect: sheet.offsetBy(dx: 0, dy: -16), xRadius: 40, yRadius: 40).fill()

let paper = NSColor(srgbRed: 0.97, green: 0.955, blue: 0.925, alpha: 1)
let ink = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
paper.setFill()
let sheetPath = NSBezierPath(roundedRect: sheet, xRadius: 40, yRadius: 40)
sheetPath.fill()

NSGraphicsContext.current?.saveGraphicsState()
sheetPath.addClip()

NSColor(srgbRed: 0.90, green: 0.88, blue: 0.84, alpha: 1).setFill()
NSRect(x: sheet.minX, y: sheet.maxY - 86, width: sheet.width, height: 86).fill()

let ticks = NSBezierPath()
ticks.lineWidth = 4
var tickX = sheet.minX + 34
while tickX < sheet.maxX - 16 {
    let major = abs(tickX - (sheet.minX + 34)).truncatingRemainder(dividingBy: 108) < 8
    let length: CGFloat = major ? 48 : 26
    ticks.move(to: NSPoint(x: tickX, y: sheet.maxY - 16))
    ticks.line(to: NSPoint(x: tickX, y: sheet.maxY - 16 - length))
    tickX += 36
}
NSColor(srgbRed: 0.45, green: 0.44, blue: 0.41, alpha: 1).setStroke()
ticks.stroke()

let dot = NSColor(srgbRed: 0.55, green: 0.56, blue: 0.58, alpha: 0.45)
var dotY = sheet.minY + 40
while dotY < sheet.maxY - 110 {
    var dotX = sheet.minX + 42
    while dotX < sheet.maxX - 30 {
        dot.setFill()
        NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: 8, height: 8)).fill()
        dotX += 40
    }
    dotY += 40
}

let frame = NSRect(x: sheet.minX + 72, y: sheet.minY + 72, width: sheet.width - 144, height: sheet.height - 210)
ink.setStroke()
let box = NSBezierPath(rect: frame)
box.lineWidth = 30
box.lineJoinStyle = .miter
box.stroke()

let split = NSBezierPath()
split.move(to: NSPoint(x: frame.minX, y: frame.midY))
split.line(to: NSPoint(x: frame.maxX, y: frame.midY))
split.lineWidth = 24
split.stroke()

ink.setFill()
let gem = NSBezierPath()
let gemCenter = NSPoint(x: frame.minX + 124, y: frame.minY + frame.height * 0.75)
let gemRadius: CGFloat = 54
gem.move(to: NSPoint(x: gemCenter.x, y: gemCenter.y + gemRadius))
gem.line(to: NSPoint(x: gemCenter.x + gemRadius, y: gemCenter.y))
gem.line(to: NSPoint(x: gemCenter.x, y: gemCenter.y - gemRadius))
gem.line(to: NSPoint(x: gemCenter.x - gemRadius, y: gemCenter.y))
gem.close()
gem.fill()

let arrowY = frame.minY + frame.height * 0.25
let shaft = NSBezierPath()
shaft.lineWidth = 28
shaft.lineCapStyle = .butt
shaft.move(to: NSPoint(x: frame.minX + 86, y: arrowY))
shaft.line(to: NSPoint(x: frame.maxX - 110, y: arrowY))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: frame.maxX - 168, y: arrowY + 50))
head.line(to: NSPoint(x: frame.maxX - 64, y: arrowY))
head.line(to: NSPoint(x: frame.maxX - 168, y: arrowY - 50))
head.close()
head.fill()

NSGraphicsContext.current?.restoreGraphicsState()
image.unlockFocus()

let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
