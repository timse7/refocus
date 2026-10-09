// Renders the Refocus app icon: a sharp front window, background windows
// dissolving into sparkles. Usage: swift make-icon.swift <out.png> [size]
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon_1024.png"
let S = CGFloat(args.count > 2 ? Double(args[2])! : 1024)
let k = S / 1024 // design is on a 1024 grid

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext
cg.scaleBy(x: k, y: k)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// Body: 824x824 squircle centred on the 1024 canvas (Apple's macOS icon grid).
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = .black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
rgb(40, 30, 90).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [rgb(124, 77, 255), rgb(64, 40, 170), rgb(28, 22, 82)],
           atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -60)
// soft glow behind the front window
NSGradient(colors: [rgb(205, 185, 255, 0.40), rgb(205, 185, 255, 0)], atLocations: [0, 1],
           colorSpace: .sRGB)!
    .draw(fromCenter: NSPoint(x: 540, y: 420), radius: 0, toCenter: NSPoint(x: 540, y: 420), radius: 400, options: [])
NSGraphicsContext.restoreGraphicsState()

func window(_ r: NSRect, alpha: CGFloat, detail: Bool) {
    let path = NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34)
    NSGraphicsContext.saveGraphicsState()
    if detail {
        let s = NSShadow()
        s.shadowColor = .black.withAlphaComponent(0.4)
        s.shadowBlurRadius = 30
        s.shadowOffset = NSSize(width: 0, height: -14)
        s.set()
    }
    rgb(255, 255, 255, alpha).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    guard detail else { return }
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    // title bar
    rgb(235, 232, 245).setFill()
    NSRect(x: r.minX, y: r.maxY - 70, width: r.width, height: 70).fill()
    for (i, c) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 34 + CGFloat(i) * 42, y: r.maxY - 49, width: 26, height: 26)).fill()
    }
    // content lines
    rgb(150, 135, 210).setFill()
    for (i, w) in [0.72, 0.55, 0.64].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: r.minX + 40, y: r.maxY - 135 - CGFloat(i) * 52,
                                         width: (r.width - 80) * w, height: 22), xRadius: 11, yRadius: 11).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func sparkle(_ c: NSPoint, _ size: CGFloat, alpha: CGFloat) {
    let p = NSBezierPath()
    let w = size * 0.22
    p.move(to: NSPoint(x: c.x, y: c.y + size))
    p.curve(to: NSPoint(x: c.x + size, y: c.y), controlPoint1: NSPoint(x: c.x + w, y: c.y + w), controlPoint2: NSPoint(x: c.x + w, y: c.y + w))
    p.curve(to: NSPoint(x: c.x, y: c.y - size), controlPoint1: NSPoint(x: c.x + w, y: c.y - w), controlPoint2: NSPoint(x: c.x + w, y: c.y - w))
    p.curve(to: NSPoint(x: c.x - size, y: c.y), controlPoint1: NSPoint(x: c.x - w, y: c.y - w), controlPoint2: NSPoint(x: c.x - w, y: c.y - w))
    p.curve(to: NSPoint(x: c.x, y: c.y + size), controlPoint1: NSPoint(x: c.x - w, y: c.y + w), controlPoint2: NSPoint(x: c.x - w, y: c.y + w))
    p.close()
    rgb(255, 236, 170, alpha).setFill()
    p.fill()
}

// Background windows, fading out towards the top-left.
window(NSRect(x: 196, y: 556, width: 340, height: 240), alpha: 0.16, detail: false)
window(NSRect(x: 250, y: 464, width: 400, height: 280), alpha: 0.30, detail: false)
// The window in focus.
window(NSRect(x: 314, y: 214, width: 500, height: 370), alpha: 1, detail: true)

sparkle(NSPoint(x: 268, y: 800), 62, alpha: 0.95)
sparkle(NSPoint(x: 186, y: 690), 30, alpha: 0.8)
sparkle(NSPoint(x: 350, y: 860), 24, alpha: 0.7)
sparkle(NSPoint(x: 200, y: 470), 20, alpha: 0.55)

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
