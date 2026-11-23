import AppKit
import QuartzCore

/// Draws the bismillah as if a pen were writing it.
///
/// Same trick as Apple's "hello": the *filled* glyph outline is only visible through a mask,
/// and the mask is a set of thick round-capped strokes that grow along each letter's centerline.
/// Every frame is rendered here with Core Graphics (mask = partially drawn pen strokes,
/// content = the glyph outline), then handed to the layer as an image.
final class BismillahView: NSView {
    /// Seconds between `play()` and the first pen stroke.
    static let leadIn = 0.15
    /// The whole outline fades in over the last strokes to hide any anti-aliasing seams.
    private static let fillStart = BismillahData.penEnd + 0.25
    private static let fillDuration = 0.45

    /// How much faster than the recorded pen timings the writing is played.
    static let speed = 1.25

    /// Total time from `play()` until the text is completely drawn.
    static var totalDuration: Double { leadIn + (fillStart + fillDuration) / speed }

    private struct Pen {
        let points: [CGPoint]          // in the glyph's 1000-wide design space
        let cumulative: [CGFloat]      // arc length at each point
        let width: CGFloat
        let start: Double
        let duration: Double
        var length: CGFloat { cumulative.last ?? 0 }
    }

    private let pens: [Pen] = BismillahData.strokes.map { s in
        var pts: [CGPoint] = []
        var i = 0
        while i + 1 < s.points.count {
            pts.append(CGPoint(x: s.points[i], y: s.points[i + 1]))
            i += 2
        }
        var cum: [CGFloat] = [0]
        for k in 1..<max(pts.count, 1) {
            cum.append(cum[k - 1] + hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y))
        }
        return Pen(points: pts, cumulative: cum, width: CGFloat(s.width), start: s.start, duration: s.duration)
    }

    /// How the bismillah appears: the pen writes it out, or the finished text fades in and out.
    enum Style: String {
        case writing, fading
    }
    /// The fading style fades in over `fadeInTime` and out over `fadeOutTime` (a little quicker, so it doesn't
    /// linger); the time between is a pause on the finished text.
    static let fadeInTime = 0.6
    static let fadeOutTime = 0.4

    /// The line under the text for people who can't read Arabic yet.
    static let captionText = "Bismillahir Rahmanir Rahim"
    private let caption = CATextLayer()
    var showsCaption = false {
        didSet {
            guard showsCaption != oldValue else { return }
            caption.isHidden = !showsCaption
            glyphPath = nil                    // the text sits a little higher to make room
            needsLayout = true
        }
    }

    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var fadeVisibleFor: Double?        // set while the fading style is playing
    private var glyphPath: CGPath?
    private var glyphScale: CGFloat = 1
    private var glyphOrigin: CGPoint = .zero      // bottom-left of the glyph box in view points

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.contentsGravity = .resize
        layerContentsRedrawPolicy = .never
        caption.string = Self.captionText
        caption.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        caption.fontSize = 13
        caption.foregroundColor = NSColor(white: 1, alpha: 0.66).cgColor
        caption.alignmentMode = .center
        caption.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        caption.isHidden = true
        layer?.addSublayer(caption)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { link?.invalidate() }

    // MARK: - playback

    /// Starts (or restarts) the animation. The fading style stays up for `visibleFor` seconds in all, fade-out included.
    func play(style: Style = .writing, after delay: Double = 0, visibleFor: Double = 0) {
        link?.invalidate()
        startTime = CACurrentMediaTime() + delay
        caption.removeAllAnimations()
        caption.opacity = 1
        if showsCaption && style == .writing {          // the reading arrives as the writing finishes
            let arrive = CABasicAnimation(keyPath: "opacity")
            arrive.fromValue = 0
            arrive.toValue = 1
            arrive.beginTime = CACurrentMediaTime() + delay + Self.totalDuration - 0.6
            arrive.duration = 0.5
            arrive.fillMode = .backwards
            caption.add(arrive, forKey: "arrive")
        }
        if style == .fading {
            fadeVisibleFor = visibleFor
            renderFrame(at: Self.totalDuration, finalOnly: true)
            setOpacity(0)
        } else {
            fadeVisibleFor = nil
            setOpacity(1)
            renderFrame(at: -1)
        }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Jumps to the finished state (also used for "reduce motion").
    func showFinished() {
        link?.invalidate()
        link = nil
        fadeVisibleFor = nil
        setOpacity(1)
        caption.removeAllAnimations()
        caption.opacity = 1
        renderFrame(at: Self.totalDuration, finalOnly: true)
    }

    private func setOpacity(_ value: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = value
        CATransaction.commit()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = CACurrentMediaTime() - startTime
        if let visibleFor = fadeVisibleFor {
            func smooth(_ u: Double) -> Double { let u = min(max(u, 0), 1); return u * u * (3 - 2 * u) }
            setOpacity(Float(min(smooth(t / Self.fadeInTime), smooth((visibleFor - t) / Self.fadeOutTime))))
            if t >= visibleFor {
                link.invalidate()
                self.link = nil
            }
            return
        }
        renderFrame(at: t)
        if t >= Self.totalDuration {
            link.invalidate()
            self.link = nil
        }
    }

    // MARK: - rendering

    private func layoutGlyph() {
        let w = BismillahData.width, h = BismillahData.height
        glyphScale = bounds.width * 0.88 / CGFloat(w)            // text spans ~88% of the popup
        let gw = CGFloat(w) * glyphScale, gh = CGFloat(h) * glyphScale
        glyphOrigin = CGPoint(x: (bounds.width - gw) / 2, y: (bounds.height - gh) / 2 + (showsCaption ? 10 : 0))
        // design space is y-down; CoreGraphics bitmap contexts are y-up
        let t = CGAffineTransform(a: glyphScale, b: 0, c: 0, d: -glyphScale,
                                  tx: glyphOrigin.x, ty: glyphOrigin.y + gh)
        glyphPath = SVGPath.parse(BismillahData.outline, transform: t)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: glyphOrigin.x + p.x * glyphScale,
                y: glyphOrigin.y + (CGFloat(BismillahData.height) - p.y) * glyphScale)
    }

    /// Renders the frame for time `t` (seconds since `play()`), shows it, and returns it.
    @discardableResult
    func renderFrame(at t: Double, finalOnly: Bool = false) -> CGImage? {
        if glyphPath == nil || bounds.width <= 0 { layoutGlyph() }
        guard let glyphPath, bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pw = Int(bounds.width * scale), ph = Int(bounds.height * scale)
        let local = (t - Self.leadIn) * Self.speed          // time in the recorded pen timings

        // 1. mask: alpha-only bitmap holding the pen strokes drawn so far
        guard let mask = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return nil }
        mask.scaleBy(x: scale, y: scale)
        mask.setStrokeColor(gray: 1, alpha: 1)
        mask.setFillColor(gray: 1, alpha: 1)
        mask.setLineCap(.round)
        mask.setLineJoin(.round)

        if finalOnly || local >= Self.fillStart + Self.fillDuration {
            mask.fill(CGRect(origin: .zero, size: bounds.size))
        } else if local > 0 {
            for pen in pens {
                let f = min(max((local - pen.start) / pen.duration, 0), 1)
                if f <= 0 || pen.points.isEmpty { continue }
                mask.setLineWidth(pen.width * glyphScale)
                strokePrefix(of: pen, fraction: CGFloat(f), in: mask)
            }
            let fillT = (local - Self.fillStart) / Self.fillDuration
            if fillT > 0 {
                let eased = 1 - pow(1 - min(fillT, 1), 2)
                mask.setFillColor(gray: 1, alpha: CGFloat(eased))
                mask.fill(CGRect(origin: .zero, size: bounds.size))
            }
        }

        // 2. content: the glyph outline, clipped by that mask
        guard let maskImage = mask.makeImage(),
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.clip(to: CGRect(x: 0, y: 0, width: pw, height: ph), mask: maskImage)
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addPath(glyphPath)
        ctx.fillPath()

        let image = ctx.makeImage()
        layer?.contentsScale = scale
        layer?.contents = image
        return image
    }

    /// Strokes the first `fraction` (by arc length) of the pen's polyline.
    private func strokePrefix(of pen: Pen, fraction: CGFloat, in ctx: CGContext) {
        let target = pen.length * fraction
        ctx.beginPath()
        let first = toView(pen.points[0])
        ctx.move(to: first)
        if pen.points.count == 1 || pen.length == 0 {
            ctx.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))     // a dot
        } else {
            for k in 1..<pen.points.count {
                if pen.cumulative[k] >= target {
                    let seg = pen.cumulative[k] - pen.cumulative[k - 1]
                    let u = seg > 0 ? (target - pen.cumulative[k - 1]) / seg : 0
                    let a = pen.points[k - 1], b = pen.points[k]
                    ctx.addLine(to: toView(CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)))
                    break
                }
                ctx.addLine(to: toView(pen.points[k]))
            }
        }
        ctx.strokePath()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caption.frame = CGRect(x: 0, y: 12, width: bounds.width, height: 20)
        CATransaction.commit()
        glyphPath = nil                                  // rebuilt for the new size on the next frame
        if link == nil { renderFrame(at: Self.totalDuration, finalOnly: true) }
    }
}
