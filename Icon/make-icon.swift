import AppKit

// Draws the Life Desk icon: open book with a check mark on a warm dark squircle, coral accent.
func render(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let u = s / 1024
    let inset = 100 * u
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = CGPath(roundedRect: rect, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)
    ctx.saveGState(); ctx.addPath(bg); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [NSColor(red: 0.20, green: 0.17, blue: 0.14, alpha: 1).cgColor,
                                                    NSColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: s - inset), end: CGPoint(x: s / 2, y: inset), options: [])
    ctx.restoreGState()

    let coral = NSColor(red: 0.851, green: 0.471, blue: 0.353, alpha: 1)
    let cream = NSColor(red: 0.93, green: 0.90, blue: 0.85, alpha: 1)
    // Open book: two pages meeting at the spine.
    func page(_ left: Bool) {
        let p = NSBezierPath()
        let cx = s / 2, top = 590 * u, bot = 300 * u, w = 280 * u, dip = 60 * u
        let sx: CGFloat = left ? -1 : 1
        p.move(to: CGPoint(x: cx, y: bot))
        p.curve(to: CGPoint(x: cx + sx * w, y: bot + 40 * u), controlPoint1: CGPoint(x: cx + sx * 90 * u, y: bot - dip), controlPoint2: CGPoint(x: cx + sx * 200 * u, y: bot - dip + 10 * u))
        p.line(to: CGPoint(x: cx + sx * w, y: top))
        p.curve(to: CGPoint(x: cx, y: top - 30 * u), controlPoint1: CGPoint(x: cx + sx * 200 * u, y: top + 40 * u), controlPoint2: CGPoint(x: cx + sx * 90 * u, y: top + 30 * u))
        p.close()
        (left ? cream.withAlphaComponent(0.92) : cream).setFill()
        p.fill()
    }
    page(true); page(false)
    // spine
    coral.setStroke()
    let spine = NSBezierPath(); spine.lineWidth = 14 * u; spine.lineCapStyle = .round
    spine.move(to: CGPoint(x: s / 2, y: 300 * u)); spine.line(to: CGPoint(x: s / 2, y: 565 * u)); spine.stroke()
    // check mark above the book
    let ck = NSBezierPath(); ck.lineWidth = 56 * u; ck.lineCapStyle = .round; ck.lineJoinStyle = .round
    ck.move(to: CGPoint(x: 405 * u, y: 715 * u)); ck.line(to: CGPoint(x: 475 * u, y: 645 * u)); ck.line(to: CGPoint(x: 625 * u, y: 800 * u))
    ck.stroke()
    img.unlockFocus()
    return img
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64), ("128", 128), ("128@2x", 256),
                   ("256", 256), ("256@2x", 512), ("512", 512), ("512@2x", 1024)] as [(String, Int)] {
    let img = render(CGFloat(px))
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name.replacingOccurrences(of: "@2x", with: "x2")).png"))
}
