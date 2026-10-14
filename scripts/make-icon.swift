// Renders the GridSnap app icon to a 1024×1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Standard macOS icon body: 824pt square with ~185pt corners, centred on the canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.3))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x2B5BEA))
ctx.fillPath()
ctx.restoreGState()

// Background gradient
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x4F8BFF), color(0x2B4FD8), color(0x3A2FB8)] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

// Soft top sheen
let sheen = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
ctx.restoreGState()

// 3 × 2 grid of tiles; the left 2 × 2 block is the "snapped" window.
let columns = 3, rows = 2
let gridRect = body.insetBy(dx: 150, dy: 205)
let gap: CGFloat = 26
let tileW = (gridRect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
let tileH = (gridRect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

func tileRect(col: Int, row: Int, colSpan: Int = 1, rowSpan: Int = 1) -> CGRect {
    // row 0 is the top row
    let x = gridRect.minX + CGFloat(col) * (tileW + gap)
    let w = tileW * CGFloat(colSpan) + gap * CGFloat(colSpan - 1)
    let h = tileH * CGFloat(rowSpan) + gap * CGFloat(rowSpan - 1)
    let top = gridRect.maxY - CGFloat(row) * (tileH + gap)
    return CGRect(x: x, y: top - h, width: w, height: h)
}

// Empty tiles
for row in 0..<rows {
    let rect = tileRect(col: 2, row: row)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil))
    ctx.setFillColor(color(0xFFFFFF, 0.2))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 32, cornerHeight: 32, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.35))
    ctx.setLineWidth(4)
    ctx.strokePath()
}

// Snapped window
let window = tileRect(col: 0, row: 0, colSpan: 2, rowSpan: 2)
let windowPath = CGPath(roundedRect: window, cornerWidth: 40, cornerHeight: 40, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x10124A, 0.35))
ctx.addPath(windowPath)
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Window title bar with traffic lights
ctx.saveGState()
ctx.addPath(windowPath)
ctx.clip()
let titleBar = CGRect(x: window.minX, y: window.maxY - 64, width: window.width, height: 64)
ctx.setFillColor(color(0xE6ECFA))
ctx.fill(titleBar)
ctx.restoreGState()
for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    let d: CGFloat = 22
    ctx.setFillColor(color(UInt32(hex)))
    ctx.fillEllipse(in: CGRect(x: window.minX + 32 + CGFloat(i) * 36, y: titleBar.midY - d / 2, width: d, height: d))
}

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
