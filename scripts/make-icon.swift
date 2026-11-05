// Draws the Macnell app icon at 1024×1024.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// MARK: Background: legal-pad squircle (macOS icon grid: 824pt shape inside 1024 canvas)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
tileShadow.shadowBlurRadius = 24
tileShadow.shadowOffset = NSSize(width: 0, height: -10)
tileShadow.set()
color(0xFBF3C2).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
NSGradient(starting: color(0xFDF8D6), ending: color(0xF1E3A0))!.draw(in: tile, angle: -90)
// Ruled lines and the red margin
color(0x3D6FA8, 0.20).setFill()
var y = tile.minY + 58
while y < tile.maxY {
    NSRect(x: tile.minX, y: y, width: tile.width, height: 4).fill()
    y += 62
}
color(0xD9534F, 0.55).setFill()
NSRect(x: tile.minX + 120, y: tile.minY, width: 5, height: tile.height).fill()
NSGraphicsContext.restoreGraphicsState()

// MARK: Notebook
let book = NSRect(x: 292, y: 178, width: 452, height: 640)
let bookPath = NSBezierPath(roundedRect: book, xRadius: 30, yRadius: 30)
let leather = color(0x3F6B53)

NSGraphicsContext.saveGraphicsState()
let bookShadow = NSShadow()
bookShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
bookShadow.shadowBlurRadius = 30
bookShadow.shadowOffset = NSSize(width: 6, height: -16)
bookShadow.set()
leather.setFill()
bookPath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
bookPath.addClip()
NSGradient(starting: color(0x4C7D62), ending: color(0x335A45))!.draw(in: book, angle: -70)
// Spine
NSColor.black.withAlphaComponent(0.18).setFill()
NSRect(x: book.minX, y: book.minY, width: 34, height: book.height).fill()
NSColor.white.withAlphaComponent(0.08).setFill()
NSRect(x: book.minX + 34, y: book.minY, width: 3, height: book.height).fill()

// Paper label band
let band = NSRect(x: book.minX, y: book.minY + 150, width: book.width, height: 170)
color(0xF4F3EE).setFill()
band.fill()
NSColor.black.withAlphaComponent(0.07).setFill()
NSRect(x: band.minX, y: band.minY, width: band.width, height: 3).fill()

// Elastic band
let elasticX = book.maxX - 74
color(0x22392C).setFill()
NSRect(x: elasticX, y: book.minY, width: 24, height: book.height).fill()
NSColor.white.withAlphaComponent(0.12).setFill()
NSRect(x: elasticX + 5, y: book.minY, width: 3, height: book.height).fill()
NSGraphicsContext.restoreGraphicsState()

// Checkbox + lines on the label
let box = NSRect(x: book.minX + 72, y: band.midY - 34, width: 68, height: 68)
let boxPath = NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16)
color(0x3D6FA8).setFill()
boxPath.fill()
let check = NSBezierPath()
check.move(to: NSPoint(x: box.minX + 16, y: box.midY + 1))
check.line(to: NSPoint(x: box.minX + 29, y: box.minY + 18))
check.line(to: NSPoint(x: box.maxX - 15, y: box.maxY - 17))
check.lineWidth = 10
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor.white.setStroke()
check.stroke()

color(0x2B2924, 0.75).setFill()
NSBezierPath(roundedRect: NSRect(x: box.maxX + 30, y: band.midY + 8, width: 170, height: 16), xRadius: 8, yRadius: 8).fill()
color(0x2B2924, 0.30).setFill()
NSBezierPath(roundedRect: NSRect(x: box.maxX + 30, y: band.midY - 26, width: 120, height: 14), xRadius: 7, yRadius: 7).fill()

// Embossed wordmark
let p = NSMutableParagraphStyle()
p.alignment = .center
let content = NSRect(x: book.minX + 34, y: 0, width: elasticX - book.minX - 34, height: 0)
("macnell" as NSString).draw(with: NSRect(x: content.minX, y: book.maxY - 196, width: content.width, height: 70),
                             options: .usesLineFragmentOrigin,
                             attributes: [.font: NSFont.systemFont(ofSize: 50, weight: .semibold),
                                          .kern: 7, .foregroundColor: NSColor.white.withAlphaComponent(0.42),
                                          .paragraphStyle: p])
NSColor.white.withAlphaComponent(0.28).setFill()
NSRect(x: content.midX - 46, y: book.maxY - 212, width: 92, height: 4).fill()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("✓ \(out)")
