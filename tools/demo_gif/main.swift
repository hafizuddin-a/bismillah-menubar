// Draws the README's animations with the app's real renderers, composited onto a recreation of the
// design prototype's desktop. Run it through tools/make_demo_gif.sh.
//
//   demo-wake.gif    the screen lights up, then the bismillah is written out (BismillahView, writing mode)
//   demo-dhikr.gif   the three dhikr open out of the notch, one after another (NotchPopupView)
//   demo-fade.gif    the same wake, with the bismillah fading in and out (BismillahView, fading mode)
//   demo-tasbih.gif  the tasbih counter dropping from the menu bar and counting to 100 (drawn here, to match
//                    TasbihCounter.swift, because its menu material can't be rendered offscreen)
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

_ = NSApplication.shared
let wakePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo-wake.gif"
let dhikrPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "demo-dhikr.gif"
let fadePath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "demo-fade.gif"
let tasbihPath = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "demo-tasbih.gif"

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
let tasbihScene = Scene(crop: CGRect(x: 960, y: 0, width: 480, height: 300), notch: false)

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

    /// `textAlpha` set means the fading style: the finished text, at that opacity (`fadeAt` is where the panel fades out).
    func bismillahPopup(_ ctx: CGContext, tp: Double, textAlpha: CGFloat? = nil, fadeAt: Double? = nil) {
        guard let image = writing.renderFrame(at: textAlpha == nil ? max(tp, 0) + BismillahView.leadIn : BismillahView.totalDuration) else { return }
        // the same envelope as the prototype: quick pop in, hold, fade out
        let popIn = 0.164, fadeStart = fadeAt ?? BismillahView.totalDuration + 1.862, fadeEnd = fadeStart + (fadeAt == nil ? 0.41 : 0.35)
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
        if let textAlpha { ctx.setAlpha(textAlpha) }
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

    // MARK: - GIF 3: the same wake, in fading mode

    /// The text's opacity `tp` seconds after the popup appears: the same envelope as BismillahView's fading style.
    func fadeAlpha(_ tp: Double) -> CGFloat {
        let delay = 0.21                                              // PopupController starts the text a moment after the panel
        let local = tp - delay, visibleFor = BismillahView.totalDuration + 2.0 - delay
        func smooth(_ u: Double) -> Double { let u = min(max(u, 0), 1); return u * u * (3 - 2 * u) }
        return CGFloat(min(smooth(local / BismillahView.fadeTime), smooth((visibleFor - local) / BismillahView.fadeTime)))
    }
    let hideAt = BismillahView.totalDuration + 2.0                    // when the panel itself starts to fade
    func fadeWake(_ tp: Double?, black: CGFloat = 0, _ delay: Double) -> Frame {
        ({ compose(wakeBackground, wakeScene, blackout: black) { ctx in
            if let tp { bismillahPopup(ctx, tp: tp, textAlpha: fadeAlpha(tp), fadeAt: hideAt) }
        } }, delay)
    }
    var fadeFrames: [Frame] = [fadeWake(nil, black: 1, 0.8)]
    for veil in [0.75, 0.5, 0.3, 0.12] { fadeFrames.append(fadeWake(nil, black: CGFloat(veil), 0.1)) }
    fadeFrames += [fadeWake(nil, 0.5), fadeWake(0.06, 0.06), fadeWake(0.12, 0.06)]
    var ft = 0.18
    while ft < 0.9 { fadeFrames.append(fadeWake(ft, 0.06)); ft += 0.06 }                        // fades in
    fadeFrames.append(fadeWake(3.0, 1.9))                                                     // the pause (shorter than the real one)
    ft = hideAt - 0.6
    while ft < hideAt + 0.02 { fadeFrames.append(fadeWake(ft, 0.06)); ft += 0.06 }              // fades out
    fadeFrames += [fadeWake(hideAt + 0.1, 0.08), fadeWake(hideAt + 0.2, 0.08), fadeWake(hideAt + 0.3, 0.3)]   // then the popup itself
    write(fadeFrames, to: fadePath)

    // MARK: - GIF 4: the tasbih counter

    // the Bismillah menu bar item sits where desktop() puts it; the counter hangs from its left edge
    let barInk = NSColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x1a / 255, alpha: 1)
    let clockWidth = width(textLine("Tue 13 Oct  9:41 AM", NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), barInk))
    let wifiLeft = designW - 14 - clockWidth - 18 - 27 - 14 - 18
    let itemWidth = width(textLine("بسم الله", NSFont(name: "GeezaPro", size: 15) ?? .systemFont(ofSize: 13), barInk))
    let counterLeft = wifiLeft - 16 - (itemWidth + 18)
    let counterTop = designH - 32 - 2
    let tasbihBackground = desktop(tasbihScene)
    let green = color(0x30d158)

    /// The counter at `count`, `open` of the way through its opening (0...1), the number scaled by `bump`.
    func counter(_ ctx: CGContext, count: Int, open: Double = 1, bump: CGFloat = 1, resetHot: Bool = false) {
        let e = easeOut(open)
        if e <= 0 { return }
        let w: CGFloat = 272, h: CGFloat = 84
        let done = count >= 100
        ctx.saveGState()
        ctx.translateBy(x: counterLeft, y: counterTop)           // top-left corner, y up
        ctx.scaleBy(x: 0.9 + 0.1 * e, y: 0.9 + 0.1 * e)             // grows out of that corner while fading in
        ctx.setAlpha(e)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let rect = CGRect(x: 0, y: -h, width: w, height: h)
        let shape = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * tasbihScene.scale), blur: 22 * tasbihScene.scale, color: color(0x000000, 0.28))
        ctx.addPath(shape); ctx.setFillColor(color(0xf6f6f8, 0.72)); ctx.fillPath()          // glass: the wallpaper shows through
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), cornerWidth: 11.75, cornerHeight: 11.75, transform: nil))
        ctx.setStrokeColor(color(0x000000, 0.14)); ctx.setLineWidth(0.5); ctx.strokePath()
        ctx.translateBy(x: 0, y: -h)                                // now bottom-left, y up, like the app's layout

        // the ring
        let centre = CGPoint(x: 43, y: 42), radius: CGFloat = 25
        ctx.setLineWidth(5); ctx.setLineCap(.round)
        ctx.setStrokeColor(color(0x000000, 0.14)); ctx.addArc(center: centre, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false); ctx.strokePath()
        if count > 0 {
            ctx.setStrokeColor(done ? green : color(0x14141a, 0.9))
            let fraction = CGFloat(min(count, 100)) / 100
            ctx.addArc(center: centre, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * fraction, clockwise: true); ctx.strokePath()
        }
        // the number
        let digits = textLine("\(count)", NSFont.monospacedDigitSystemFont(ofSize: count < 1000 ? 17 : 13, weight: .semibold), barInk)
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y); ctx.scaleBy(x: bump, y: bump)
        ctx.textPosition = CGPoint(x: -width(digits) / 2, y: -6); CTLineDraw(digits, ctx)
        ctx.restoreGState()
        // the dhikr
        ctx.textPosition = CGPoint(x: 84, y: 48)
        CTLineDraw(textLine("سُبْحَانَ ٱللَّهِ وَبِحَمْدِهِ", NSFont(name: "GeezaPro", size: 22) ?? .systemFont(ofSize: 22), barInk), ctx)
        // "Space" as a key, then what it does
        let key = CGRect(x: 84, y: 20, width: 43, height: 16)
        ctx.addPath(CGPath(roundedRect: key, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.setFillColor(color(0x14141a, 0.07)); ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: key.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
        ctx.setStrokeColor(color(0x14141a, 0.28)); ctx.setLineWidth(1); ctx.strokePath()
        let space = textLine("Space", NSFont.systemFont(ofSize: 10, weight: .medium), barInk.withAlphaComponent(0.6))
        ctx.textPosition = CGPoint(x: key.midX - width(space) / 2, y: key.minY + 4.5); CTLineDraw(space, ctx)
        let hintText = textLine(done ? "to continue" : "to count · goal 100", NSFont.systemFont(ofSize: 11), barInk.withAlphaComponent(0.6))
        ctx.textPosition = CGPoint(x: 132, y: 24); CTLineDraw(hintText, ctx)
        if done {                                                                        // Reset appears at 100
            let button = CGRect(x: 201, y: 18, width: 51, height: 20)
            ctx.addPath(CGPath(roundedRect: button, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.setFillColor(resetHot ? color(0x14141a, 0.2) : color(0xffffff, 0.95)); ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: button.insetBy(dx: 0.25, dy: 0.25), cornerWidth: 9.75, cornerHeight: 9.75, transform: nil))
            ctx.setStrokeColor(color(0x000000, 0.18)); ctx.setLineWidth(0.5); ctx.strokePath()
            let reset = textLine("Reset", NSFont.systemFont(ofSize: 11), barInk)
            ctx.textPosition = CGPoint(x: button.midX - width(reset) / 2, y: button.minY + 6); CTLineDraw(reset, ctx)
        }
        // the close mark
        ctx.setStrokeColor(color(0x14141a, 0.3)); ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: 252.5, y: 65.5)); ctx.addLine(to: CGPoint(x: 259.5, y: 72.5))
        ctx.move(to: CGPoint(x: 259.5, y: 65.5)); ctx.addLine(to: CGPoint(x: 252.5, y: 72.5)); ctx.strokePath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    func tasbih(_ count: Int, open: Double = 1, bump: CGFloat = 1, resetHot: Bool = false, _ delay: Double) -> Frame {
        ({ compose(tasbihBackground, tasbihScene) { ctx in counter(ctx, count: count, open: open, bump: bump, resetHot: resetHot) } }, delay)
    }

    var tasbihFrames: [Frame] = [tasbih(0, open: 0, 0.8)]                                         // just the menu bar
    for step in 1...5 { tasbihFrames.append(tasbih(0, open: Double(step) / 5, 0.04)) }             // drops down
    tasbihFrames.append(tasbih(0, 0.7))
    for n in 1...8 { tasbihFrames += [tasbih(n, bump: 1.12, 0.05), tasbih(n, 0.1)] }                 // Space, Space, Space...
    for n in [14, 22, 35, 50, 68, 85] { tasbihFrames.append(tasbih(n, 0.2)) }                       // and on (skipping ahead)
    for n in 96...99 { tasbihFrames.append(tasbih(n, 0.22)) }
    tasbihFrames += [tasbih(100, bump: 1.3, 0.07), tasbih(100, bump: 1.1, 0.07), tasbih(100, 1.1)]       // 100: green, Reset appears
    tasbihFrames += [tasbih(101, bump: 1.12, 0.05), tasbih(101, 0.7)]                              // it keeps going
    tasbihFrames += [tasbih(101, resetHot: true, 0.25), tasbih(0, 0.8)]                              // Reset
    for step in (0..<4).reversed() { tasbihFrames.append(tasbih(0, open: Double(step) / 4, 0.05)) }   // closes
    tasbihFrames.append(tasbih(0, open: 0, 0.5))
    write(tasbihFrames, to: tasbihPath)
}
