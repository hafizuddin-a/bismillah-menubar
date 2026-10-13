// Draws assets/demo.gif for the README: the app's real popup renderer (BismillahView) composited onto a
// recreation of the design prototype's desktop. Run it through tools/make_demo_gif.sh.
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

_ = NSApplication.shared
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo.gif"

// The prototype's desktop is 1440 x 900; the GIF is drawn at two thirds of that.
let designW: CGFloat = 1440, designH: CGFloat = 900
let outW = 960, outH = 600
let k = CGFloat(outW) / designW
let popupRect = CGRect(x: 460, y: designH - 360 - 180, width: 520, height: 180)   // y-up design space

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

/// Absolute SVG path data (M L C S V H Z) in the prototype's y-down space, returned y-up.
func svgPath(_ d: String) -> CGPath {
    var tokens: [String] = []
    var current = ""
    for ch in d {
        if ch.isLetter { if !current.isEmpty { tokens.append(current); current = "" }; tokens.append(String(ch)) }
        else if ch == " " || ch == "," { if !current.isEmpty { tokens.append(current); current = "" } }
        else { current.append(ch) }
    }
    if !current.isEmpty { tokens.append(current) }
    let path = CGMutablePath()
    var i = 0, cmd = "M"
    var cur = CGPoint.zero, lastC2 = CGPoint.zero
    func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: designH - p.y) }
    while i < tokens.count {
        if tokens[i].first!.isLetter { cmd = tokens[i]; i += 1; if cmd == "Z" { path.closeSubpath() }; continue }
        switch cmd {
        case "M": cur = CGPoint(x: num(), y: num()); path.move(to: flip(cur)); cmd = "L"
        case "L": cur = CGPoint(x: num(), y: num()); path.addLine(to: flip(cur))
        case "V": cur = CGPoint(x: cur.x, y: num()); path.addLine(to: flip(cur))
        case "H": cur = CGPoint(x: num(), y: cur.y); path.addLine(to: flip(cur))
        case "C":
            let c1 = CGPoint(x: num(), y: num()), c2 = CGPoint(x: num(), y: num()), p = CGPoint(x: num(), y: num())
            path.addCurve(to: flip(p), control1: flip(c1), control2: flip(c2)); lastC2 = c2; cur = p
        case "S":
            let c1 = CGPoint(x: 2 * cur.x - lastC2.x, y: 2 * cur.y - lastC2.y)
            let c2 = CGPoint(x: num(), y: num()), p = CGPoint(x: num(), y: num())
            path.addCurve(to: flip(p), control1: flip(c1), control2: flip(c2)); lastC2 = c2; cur = p
        default: i += 1
        }
    }
    return path
}

func textLine(_ s: String, _ font: NSFont, _ ink: NSColor) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink]))
}
func width(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }
func draw(_ line: CTLine, x: CGFloat, baselineFromTop: CGFloat, in ctx: CGContext) {
    ctx.textPosition = CGPoint(x: x, y: designH - baselineFromTop)
    CTLineDraw(line, ctx)
}

// MARK: - the desktop (drawn once, at 2x then reduced, so small text stays smooth)

func desktop() -> CGImage {
    let s: CGFloat = 2
    let big = makeContext(outW * 2, outH * 2)
    big.scaleBy(x: k * s, y: k * s)

    big.setFillColor(color(0xc9d3ea)); big.fill(CGRect(x: 0, y: 0, width: designW, height: designH))
    big.setFillColor(color(0xefe3d6)); big.fillEllipse(in: CGRect(x: 1090 - 120, y: designH - 330 - 120, width: 240, height: 240))
    for (d, hex) in [("M0 560C180 505 360 490 540 530S880 610 1080 540S1330 480 1440 510V900H0Z", 0xaab9dd),
                     ("M0 650C230 590 430 610 650 660S1010 730 1230 650S1390 620 1440 635V900H0Z", 0x8598cc),
                     ("M0 765C260 705 520 725 770 775S1180 835 1440 745V900H0Z", 0x6174b6),
                     ("M0 845C300 805 620 835 900 855S1300 865 1440 825V900H0Z", 0x41529a)] as [(String, UInt32)] {
        big.addPath(svgPath(d)); big.setFillColor(color(hex)); big.fillPath()
    }

    // menu bar
    big.setFillColor(color(0xffffff, 0.62)); big.fill(CGRect(x: 0, y: designH - 32, width: designW, height: 32))
    let ink = NSColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x1a / 255, alpha: 1)
    let ui = NSFont.systemFont(ofSize: 13), uiBold = NSFont.systemFont(ofSize: 13, weight: .semibold)
    var x: CGFloat = 14
    for (i, name) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
        let line = textLine(name, i == 0 ? uiBold : ui, ink)
        draw(line, x: x, baselineFromTop: 20.5, in: big)
        x += width(line) + 20
    }
    // right side, laid out from the right edge like the prototype's flex row
    let clock = textLine("Tue 13 Oct  9:41 AM", NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), ink)
    let clockX = designW - 14 - width(clock)
    draw(clock, x: clockX, baselineFromTop: 20.5, in: big)
    let batteryX = clockX - 18 - 27
    let wifiX = batteryX - 14 - 18
    let item = textLine("بسم الله", NSFont(name: "GeezaPro", size: 15) ?? ui, ink)

    // icons are drawn in their own y-down 14 px box, centred in the bar
    func addIcon(_ path: CGPath, at x: CGFloat) {
        var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: designH - 9)
        big.addPath(path.copy(using: &t)!)
    }
    big.setStrokeColor(ink.cgColor); big.setLineCap(.round)
    big.setLineWidth(1.7)
    for d in ["M1.5 5.2C5.6 1.3 12.4 1.3 16.5 5.2", "M4.2 8.2C7 5.8 11 5.8 13.8 8.2", "M6.9 11.2C8.2 10 9.8 10 11.1 11.2"] {
        let p = CGMutablePath()
        // these local paths are y-down already, so build them without the desktop's flip
        let nums = d.replacingOccurrences(of: "M", with: "").replacingOccurrences(of: "C", with: " ").split(separator: " ").map { CGFloat(Double($0)!) }
        p.move(to: CGPoint(x: nums[0], y: nums[1]))
        p.addCurve(to: CGPoint(x: nums[6], y: nums[7]), control1: CGPoint(x: nums[2], y: nums[3]), control2: CGPoint(x: nums[4], y: nums[5]))
        addIcon(p, at: wifiX); big.strokePath()
    }
    big.setStrokeColor(ink.withAlphaComponent(0.45).cgColor); big.setLineWidth(1.2)
    addIcon(CGPath(roundedRect: CGRect(x: 1, y: 2, width: 21, height: 10), cornerWidth: 3, cornerHeight: 3, transform: nil), at: batteryX)
    big.strokePath()
    big.setFillColor(ink.cgColor)
    addIcon(CGPath(roundedRect: CGRect(x: 3, y: 4, width: 14, height: 6), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil), at: batteryX)
    big.fillPath()
    big.setStrokeColor(ink.withAlphaComponent(0.45).cgColor); big.setLineWidth(1.6)
    let cap = CGMutablePath(); cap.move(to: CGPoint(x: 24, y: 5.5)); cap.addLine(to: CGPoint(x: 24, y: 8.5))
    addIcon(cap, at: batteryX); big.strokePath()

    // the Bismillah menu bar item
    let itemRight = wifiX - 16
    let itemX = itemRight - (width(item) + 18)
    draw(item, x: itemX + 9, baselineFromTop: 21, in: big)

    // reduce to the GIF's size
    let small = makeContext(outW, outH)
    small.draw(big.makeImage()!, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    return small.makeImage()!
}

// MARK: - frames

let background = desktop()
let view = BismillahView(frame: NSRect(x: 0, y: 0, width: popupRect.width, height: popupRect.height))

func easeOut(_ u: Double) -> Double { 1 - pow(1 - min(max(u, 0), 1), 2) }

/// tp = seconds since the popup appeared; nil = empty desktop.
func frame(at tp: Double?) -> CGImage {
    let ctx = makeContext(outW, outH)
    ctx.draw(background, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    guard let tp, let writing = view.renderFrame(at: max(tp, 0) + BismillahView.leadIn) else { return ctx.makeImage()! }

    // same envelope as the prototype's 8.2 s cycle: quick pop in, hold, then fade out
    let popIn = 0.164, fadeStart = 7.462, fadeEnd = 7.872
    var opacity = 1.0, scale = 1.0
    if tp < popIn { let e = easeOut(tp / popIn); opacity = e; scale = 0.94 + 0.06 * e }
    else if tp > fadeStart { let e = easeOut((tp - fadeStart) / (fadeEnd - fadeStart)); opacity = 1 - e; scale = 1 - 0.015 * e }
    if opacity <= 0 { return ctx.makeImage()! }

    ctx.saveGState()
    ctx.scaleBy(x: k, y: k)
    let cx = popupRect.midX, cy = popupRect.midY
    ctx.translateBy(x: cx, y: cy); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -cx, y: -cy)
    ctx.setAlpha(opacity)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let shape = CGPath(roundedRect: popupRect, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.setFillColor(color(0x000000))
    // two soft shadows like the prototype's (offsets are in device pixels, so scale them by hand)
    ctx.setShadow(offset: CGSize(width: 0, height: -40 * k), blur: 60 * k, color: color(0x000000, 0.45))
    ctx.addPath(shape); ctx.fillPath()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 16 * k, color: color(0x000000, 0.3))
    ctx.addPath(shape); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0)
    ctx.addPath(CGPath(roundedRect: popupRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 29.5, cornerHeight: 29.5, transform: nil))
    ctx.setStrokeColor(color(0xffffff, 0.07)); ctx.setLineWidth(1); ctx.strokePath()
    ctx.draw(writing, in: popupRect)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    return ctx.makeImage()!
}

// (time since the popup appeared, how long the frame stays on screen)
var schedule: [(Double?, Double)] = [(nil, 0.6), (0.06, 0.06), (0.12, 0.06)]
var t = 0.16
while t < 5.45 { schedule.append((t, 0.08)); t += 0.08 }
schedule.append((5.6, 1.85))                            // finished text, held
schedule += [(7.5, 0.1), (7.62, 0.1), (7.74, 0.1)]      // fade out

guard let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.gif.identifier as CFString, schedule.count, nil)
else { fatalError("can't create \(outPath)") }
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
for (tp, delay) in schedule {
    CGImageDestinationAddImage(gif, frame(at: tp), [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay]] as CFDictionary)
}
guard CGImageDestinationFinalize(gif) else { fatalError("couldn't write \(outPath)") }
print("wrote \(outPath): \(schedule.count) frames, \(String(format: "%.1f", schedule.reduce(0) { $0 + $1.1 })) s loop")
