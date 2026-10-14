// Draws the README's two animations with the app's real renderers, composited onto a recreation of the
// design prototype's desktop. Run it through tools/make_demo_gif.sh.
//
//   demo-wake.gif   the screen lights up, then the bismillah is written out (BismillahView)
//   demo-dhikr.gif  the three dhikr open out of the notch, one after another (NotchPopupView)
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

_ = NSApplication.shared
let wakePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo-wake.gif"
let dhikrPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "demo-dhikr.gif"

// The prototype's desktop is 1440 x 900 (design space). Each GIF shows a crop of it at 800 x 500.
let designW: CGFloat = 1440, designH: CGFloat = 900
let outW = 800, outH = 500
let popupRect = CGRect(x: 460, y: designH - 360 - 180, width: 520, height: 180)     // the bismillah popup, y-up
let notchCenterX: CGFloat = 720
let notchGeometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: designW, height: designH), centerX: notchCenterX,
                                  width: 200, height: 32, topInset: 32, hasNotch: true)

/// A crop of the design space (y-down, like the prototype) and whether to draw a notch in the menu bar.
struct Scene {
    let crop: CGRect
    let notch: Bool
    var scale: CGFloat { CGFloat(outW) / crop.width }
    /// Maps design space (y-up) onto the output, `extra` times larger (for supersampling).
    func apply(to ctx: CGContext, extra: CGFloat = 1) {
        ctx.scaleBy(x: scale * extra, y: scale * extra)
        ctx.translateBy(x: -crop.minX, y: -(designH - crop.maxY))
    }
}
let wakeScene = Scene(crop: CGRect(x: 320, y: 190, width: 800, height: 500), notch: false)
let dhikrScene = Scene(crop: CGRect(x: 480, y: 0, width: 480, height: 300), notch: true)

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

// MARK: - the desktop (drawn at 2x then reduced, so small text stays smooth)

func desktop(_ scene: Scene) -> CGImage {
    let big = makeContext(outW * 2, outH * 2)
    scene.apply(to: big, extra: 2)

    big.setFillColor(color(0xc9d3ea)); big.fill(CGRect(x: 0, y: 0, width: designW, height: designH))
    big.setFillColor(color(0xefe3d6)); big.fillEllipse(in: CGRect(x: 1090 - 120, y: designH - 330 - 120, width: 240, height: 240))
    for (d, hex) in [("M0 560C180 505 360 490 540 530S880 610 1080 540S1330 480 1440 510V900H0Z", 0xaab9dd),
                     ("M0 650C230 590 430 610 650 660S1010 730 1230 650S1390 620 1440 635V900H0Z", 0x8598cc),
                     ("M0 765C260 705 520 725 770 775S1180 835 1440 745V900H0Z", 0x6174b6),
                     ("M0 845C300 805 620 835 900 855S1300 865 1440 825V900H0Z", 0x41529a)] as [(String, UInt32)] {
        big.addPath(svgPath(d)); big.setFillColor(color(hex)); big.fillPath()
    }

    // a plain app window under the notch, so the popup reads as floating over your work
    if scene.notch {
        func box(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: designH - top - h, width: w, height: h) }
        let frame = box(500, 128, 440, 420)
        big.saveGState()
        big.setShadow(offset: CGSize(width: 0, height: -10 * scene.scale * 2), blur: 24 * scene.scale * 2, color: color(0x000000, 0.2))
        big.addPath(CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil))
        big.setFillColor(color(0xfafafb)); big.fillPath()
        big.restoreGState()
        big.saveGState()
        big.addPath(CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil)); big.clip()
        big.setFillColor(color(0xececf1)); big.fill(box(500, 128, 440, 34))                    // title bar
        big.restoreGState()
        let buttons: [UInt32] = [0xff5f57, 0xfebc2e, 0x28c840]
        for (i, hex) in buttons.enumerated() {                                                  // window buttons
            big.setFillColor(color(hex)); big.fillEllipse(in: box(515 + CGFloat(i) * 20, 139, 12, 12))
        }
        big.setFillColor(color(0xcfd2dd)); big.addPath(CGPath(roundedRect: box(524, 188, 170, 12), cornerWidth: 6, cornerHeight: 6, transform: nil)); big.fillPath()
        let lines: [CGFloat] = [392, 350, 372, 210, 380, 300]
        for (i, w) in lines.enumerated() {                                                      // lines of text
            big.setFillColor(color(0xe1e3ea))
            big.addPath(CGPath(roundedRect: box(524, 218 + CGFloat(i) * 24, w, 9), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)); big.fillPath()
        }
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

    // the notch: black, flush with the top edge, as tall as the menu bar, rounded at the bottom like the real one
    if scene.notch {
        let w = notchGeometry.width, h = notchGeometry.height, r: CGFloat = 10
        let x0 = notchCenterX - w / 2, x1 = x0 + w, top = designH, bottom = designH - h
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: top)); p.addLine(to: CGPoint(x: x1, y: top)); p.addLine(to: CGPoint(x: x1, y: bottom + r))
        p.addArc(tangent1End: CGPoint(x: x1, y: bottom), tangent2End: CGPoint(x: x1 - r, y: bottom), radius: r)
        p.addLine(to: CGPoint(x: x0 + r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: x0, y: bottom), tangent2End: CGPoint(x: x0, y: bottom + r), radius: r)
        p.closeSubpath()
        big.addPath(p); big.setFillColor(color(0x000000)); big.fillPath()
    }

    // reduce to the GIF's size
    let small = makeContext(outW, outH)
    small.draw(big.makeImage()!, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    return small.makeImage()!
}

/// The desktop, then `overlay` drawn in design space, then a black veil (`blackout` 0...1) for the screen waking.
func compose(_ background: CGImage, _ scene: Scene, blackout: CGFloat = 0, overlay: (CGContext) -> Void) -> CGImage {
    let ctx = makeContext(outW, outH)
    let whole = CGRect(x: 0, y: 0, width: outW, height: outH)
    ctx.draw(background, in: whole)
    ctx.saveGState()
    scene.apply(to: ctx)
    overlay(ctx)
    ctx.restoreGState()
    if blackout > 0 { ctx.setFillColor(CGColor(gray: 0, alpha: blackout)); ctx.fill(whole) }
    return ctx.makeImage()!
}

func easeOut(_ u: Double) -> Double { 1 - pow(1 - min(max(u, 0), 1), 2) }
typealias Frame = (render: () -> CGImage, delay: Double)

func write(_ frames: [Frame], to path: String) {
    guard let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
    else { fatalError("can't create \(path)") }
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
    for frame in frames {
        CGImageDestinationAddImage(gif, frame.render(), [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: frame.delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(gif) else { fatalError("couldn't write \(path)") }
    print("wrote \(path): \(frames.count) frames, \(String(format: "%.1f", frames.reduce(0) { $0 + $1.delay })) s loop")
}

MainActor.assumeIsolated {
    // MARK: - GIF 1: the screen wakes, the bismillah is written out

    let wakeBackground = desktop(wakeScene)
    let writing = BismillahView(frame: NSRect(origin: .zero, size: popupRect.size))

    func bismillahPopup(_ ctx: CGContext, tp: Double) {
        guard let image = writing.renderFrame(at: max(tp, 0) + BismillahView.leadIn) else { return }
        // the same envelope as the prototype: quick pop in, hold, fade out
        let popIn = 0.164, fadeStart = BismillahView.totalDuration + 1.862, fadeEnd = fadeStart + 0.41
        var opacity = 1.0, scale = 1.0
        if tp < popIn { let e = easeOut(tp / popIn); opacity = e; scale = 0.94 + 0.06 * e }
        else if tp > fadeStart { let e = easeOut((tp - fadeStart) / (fadeEnd - fadeStart)); opacity = 1 - e; scale = 1 - 0.015 * e }
        if opacity <= 0 { return }
        let unit = wakeScene.scale                          // shadow offsets are in device pixels, so scale them by hand
        ctx.translateBy(x: popupRect.midX, y: popupRect.midY); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -popupRect.midX, y: -popupRect.midY)
        ctx.setAlpha(opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let shape = CGPath(roundedRect: popupRect, cornerWidth: 30, cornerHeight: 30, transform: nil)
        ctx.setFillColor(color(0x000000))
        ctx.setShadow(offset: CGSize(width: 0, height: -40 * unit), blur: 60 * unit, color: color(0x000000, 0.45))
        ctx.addPath(shape); ctx.fillPath()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * unit), blur: 16 * unit, color: color(0x000000, 0.3))
        ctx.addPath(shape); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.addPath(CGPath(roundedRect: popupRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 29.5, cornerHeight: 29.5, transform: nil))
        ctx.setStrokeColor(color(0xffffff, 0.07)); ctx.setLineWidth(1); ctx.strokePath()
        ctx.draw(image, in: popupRect)
        ctx.endTransparencyLayer()
    }
    func wake(_ tp: Double?, black: CGFloat = 0, _ delay: Double) -> Frame {
        ({ compose(wakeBackground, wakeScene, blackout: black) { ctx in if let tp { bismillahPopup(ctx, tp: tp) } } }, delay)
    }

    var wakeFrames: [Frame] = [wake(nil, black: 1, 0.8)]                          // the screen is off
    for veil in [0.75, 0.5, 0.3, 0.12] { wakeFrames.append(wake(nil, black: CGFloat(veil), 0.1)) }      // it lights up
    wakeFrames += [wake(nil, 0.5), wake(0.06, 0.06), wake(0.12, 0.06)]
    var t = 0.16
    let written = BismillahView.totalDuration
    while t < written - 0.15 { wakeFrames.append(wake(t, 0.07)); t += 0.07 }      // the bismillah is written out
    wakeFrames.append(wake(written, 1.4))                                         // held
    wakeFrames += [wake(written + 1.9, 0.1), wake(written + 2.02, 0.1), wake(written + 2.14, 0.1)]     // fades away
    write(wakeFrames, to: wakePath)

    // MARK: - GIF 2: the dhikr open out of the notch, one after another

    let dhikrBackground = desktop(dhikrScene)
    let views = NotchPopupView.phrases.map { NotchPopupView(geometry: notchGeometry, phrase: $0) }

    func dhikr(_ phrase: Int, _ progress: CGFloat, _ delay: Double) -> Frame {
        ({
            compose(dhikrBackground, dhikrScene) { ctx in
                let view = views[phrase]
                view.apply(progress: progress)
                ctx.translateBy(x: notchCenterX - view.frame.width / 2, y: designH - view.frame.height)       // flush with the top edge
                view.layer?.render(in: ctx)
            }
        }, delay)
    }

    var dhikrFrames: [Frame] = [dhikr(0, 0, 0.9)]                                 // just the notch
    for phrase in views.indices {
        for step in 1...10 { dhikrFrames.append(dhikr(phrase, CGFloat(1 - pow(1 - Double(step) / 10, 3)), 0.05)) }     // opens
        dhikrFrames.append(dhikr(phrase, 1, 1.7))                                  // held (shorter than the real 4 s)
        for step in 1...8 { dhikrFrames.append(dhikr(phrase, CGFloat(1 - pow(Double(step) / 8, 3)), 0.05)) }          // folds back
        dhikrFrames.append(dhikr(phrase, 0, 0.6))
    }
    write(dhikrFrames, to: dhikrPath)
}
