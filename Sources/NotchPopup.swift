import AppKit
import QuartzCore

/// Where the notch is. A Mac without one gets a small stand-in tab at the top centre of the screen.
struct NotchGeometry {
    let screenFrame: NSRect
    let centerX: CGFloat           // screen coordinates
    let width: CGFloat             // the closed shape: the notch itself, or the stand-in tab
    let height: CGFloat
    let topInset: CGFloat          // how far down the open shape's text area starts: notch or menu bar height
    let hasNotch: Bool

    /// The screen with a notch if there is one, otherwise the screen the mouse is on.
    static func current() -> NotchGeometry {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return on(screen) }
        let mouse = NSEvent.mouseLocation
        return on(NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0])
    }

    /// The notch of this screen, or the stand-in tab if it has none.
    static func on(_ screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea ?? .zero
            let right = screen.auxiliaryTopRightArea ?? .zero
            let gap = screen.frame.width - left.width - right.width
            let width = gap > 60 ? gap : 200
            let centerX = left.width > 0 ? screen.frame.minX + left.width + width / 2 : screen.frame.midX
            let inset = screen.safeAreaInsets.top
            return NotchGeometry(screenFrame: screen.frame, centerX: centerX, width: width, height: inset,
                                 topInset: inset, hasNotch: true)
        }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screenFrame: screen.frame, centerX: screen.frame.midX, width: 120, height: 4,
                             topInset: menuBar, hasNotch: false)
    }
}

/// The black shape that opens out of the notch and holds the dhikr. `apply(progress:)` draws any moment of
/// the animation, 0 = notch-sized, 1 = fully open, so the whole thing can also be rendered offscreen.
final class NotchPopupView: NSView {
    /// A dhikr to show, and how it is read aloud (for VoiceOver).
    struct Dhikr {
        let arabic: String
        let reading: String
    }
    static let phrases = [
        Dhikr(arabic: "سُبْحَانَ ٱللَّهِ وَبِحَمْدِهِ", reading: "Subhanallahi wa bihamdihi"),
        Dhikr(arabic: "أَسْتَغْفِرُ ٱللَّهَ ٱلْعَظِيمَ", reading: "Astaghfirullah al-Azim"),
        Dhikr(arabic: "ٱللَّهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ", reading: "Allahumma salli ala Muhammad"),
    ]
    static let openWidth: CGFloat = 370
    static let textAreaHeight: CGFloat = 70
    static let margin: CGFloat = 40                // room around the shape for its shadow

    static func size(for geometry: NotchGeometry) -> NSSize {
        NSSize(width: openWidth + 2 * margin, height: geometry.topInset + textAreaHeight + margin)
    }

    private let geometry: NotchGeometry
    private let shape = CAShapeLayer()
    private let label = CATextLayer()
    private var currentPath: CGPath?

    /// Called when the black shape is clicked.
    var onClick: (() -> Void)?

    init(geometry: NotchGeometry, phrase: Dhikr = NotchPopupView.phrases[0]) {
        self.geometry = geometry
        super.init(frame: NSRect(origin: .zero, size: Self.size(for: geometry)))
        wantsLayer = true
        layer = CALayer()
        layerContentsRedrawPolicy = .never

        shape.fillColor = NSColor.black.cgColor
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowRadius = 14
        shape.shadowOffset = CGSize(width: 0, height: -6)
        shape.frame = bounds
        layer?.addSublayer(shape)

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        func attributed(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: phrase.arabic, attributes: [
                .font: NSFont(name: "GeezaPro", size: size) ?? NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.white, .paragraphStyle: style])
        }
        // 30 pt, or smaller if a longer phrase wouldn't fit the open shape with some air around it
        let fit = Self.openWidth - 56
        let natural = attributed(30).size().width
        label.string = attributed(natural > fit ? (30 * fit / natural).rounded(.down) : 30)
        label.alignmentMode = .center
        label.isWrapped = false
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        let textHeight: CGFloat = 52
        let areaBottom = bounds.height - geometry.topInset - Self.textAreaHeight
        label.frame = CGRect(x: (bounds.width - Self.openWidth) / 2, y: areaBottom + (Self.textAreaHeight - textHeight) / 2 - 2,
                             width: Self.openWidth, height: textHeight)
        layer?.addSublayer(label)
        apply(progress: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { false }

    // Only the black shape takes clicks, so the transparent margin around it never gets in the way.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return currentPath?.contains(local) == true ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    func apply(progress p: CGFloat) {
        let p = min(max(p, 0), 1)
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let openHeight = geometry.topInset + Self.textAreaHeight
        let width = lerp(geometry.width, Self.openWidth)
        let height = lerp(geometry.height, openHeight)
        let radius = min(lerp(geometry.hasNotch ? 10 : 6, 30), height / 2, width / 2)

        // flush with the top edge of the window (= the top edge of the screen); only the bottom corners are round
        let x0 = (bounds.width - width) / 2, x1 = x0 + width
        let top = bounds.height, bottom = top - height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0, y: top))
        path.addLine(to: CGPoint(x: x1, y: top))
        path.addLine(to: CGPoint(x: x1, y: bottom + radius))
        path.addArc(tangent1End: CGPoint(x: x1, y: bottom), tangent2End: CGPoint(x: x1 - radius, y: bottom), radius: radius)
        path.addLine(to: CGPoint(x: x0 + radius, y: bottom))
        path.addArc(tangent1End: CGPoint(x: x0, y: bottom), tangent2End: CGPoint(x: x0, y: bottom + radius), radius: radius)
        path.closeSubpath()

        currentPath = path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        shape.shadowPath = path
        shape.shadowOpacity = Float(0.5 * p)
        label.opacity = Float(min(max((p - 0.55) / 0.35, 0), 1))        // the text arrives once the shape is mostly open
        CATransaction.commit()
    }
}

/// Shows the dhikr: the shape grows out of the notch, holds, then folds back into it.
@MainActor
final class NotchPopupController {
    private nonisolated static let expand = 0.5, hold = 4.0, collapse = 0.4
    private static let dismissTime = 0.3               // folding away after a click

    private var windows: [(panel: NSPanel, view: NotchPopupView)] = []
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var reduceMotion = false
    private var lastPhrase: Int?
    private var lastProgress: CGFloat = 0
    private var closing: (start: CFTimeInterval, from: CGFloat)?       // set once the popup has been clicked

    var isShowing: Bool { windows.contains { $0.panel.isVisible } }

    /// A random phrase number out of `count`, never the same as `last`, so you never see one twice in a row.
    nonisolated static func nextPhrase(after last: Int?, count: Int) -> Int {
        (0..<count).filter { $0 != last }.randomElement() ?? 0
    }

    /// 0 = closed, 1 = open, `t` seconds into the animation.
    nonisolated static func progress(at t: Double) -> CGFloat {
        if t < expand { return CGFloat(1 - pow(1 - t / expand, 3)) }
        if t < expand + hold { return 1 }
        let u = (t - expand - hold) / collapse
        return u >= 1 ? 0 : CGFloat(1 - u * u * u)
    }

    /// Shows one dhikr (the same on every screen): on the notched screen, or the screen the mouse is on, or on
    /// every screen when `allScreens` is true.
    func show(allScreens: Bool = false) {
        guard !isShowing else { return }
        let index = Self.nextPhrase(after: lastPhrase, count: NotchPopupView.phrases.count)
        lastPhrase = index
        let phrase = NotchPopupView.phrases[index]
        let geometries = allScreens && !NSScreen.screens.isEmpty ? NSScreen.screens.map(NotchGeometry.on) : [NotchGeometry.current()]

        windows = geometries.map { geometry in
            let view = NotchPopupView(geometry: geometry, phrase: phrase)
            let size = view.frame.size
            let panel = NSPanel(contentRect: NSRect(x: geometry.centerX - size.width / 2,
                                                    y: geometry.screenFrame.maxY - size.height,
                                                    width: size.width, height: size.height),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = view
            panel.level = .popUpMenu                        // above the menu bar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false                         // the shape draws its own
            panel.isReleasedWhenClosed = false              // clicks reach only the shape (see NotchPopupView.hitTest)
            panel.setAccessibilityLabel(phrase.reading)
            view.onClick = { [weak self] in self?.dismiss() }
            return (panel, view)
        }
        closing = nil
        lastProgress = 0

        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        startTime = CACurrentMediaTime()
        for (panel, view) in windows {
            if reduceMotion {
                view.apply(progress: 1)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
            } else {
                view.apply(progress: 0)
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
        }
        // one display link drives every screen's shape, so they open and close together
        let link = windows[0].view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// A click on the popup: fold it away now instead of waiting out the hold.
    func dismiss() {
        guard isShowing, closing == nil else { return }
        if reduceMotion {
            closing = (CACurrentMediaTime(), 1)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                for window in windows { window.panel.animator().alphaValue = 0 }
            }, completionHandler: { [weak self] in Task { @MainActor in self?.finish() } })
        } else {
            closing = (CACurrentMediaTime(), lastProgress)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if let closing {
            if reduceMotion { return }                  // the fade-out in dismiss() finishes it
            let u = (now - closing.start) / Self.dismissTime
            if u >= 1 { finish(); return }
            lastProgress = closing.from * CGFloat(1 - u * u * u)
            apply(lastProgress)
            return
        }
        let t = now - startTime
        let total = Self.expand + Self.hold + Self.collapse
        if reduceMotion {
            if t > Self.expand + Self.hold, windows.first?.panel.alphaValue == 1 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    for window in windows { window.panel.animator().alphaValue = 0 }
                }
            }
            if t > Self.expand + Self.hold + 0.3 { finish() }
            return
        }
        lastProgress = Self.progress(at: t)
        apply(lastProgress)
        if t >= total { finish() }
    }

    private func apply(_ progress: CGFloat) {
        for window in windows { window.view.apply(progress: progress) }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        for window in windows { window.panel.orderOut(nil) }
        windows = []
        closing = nil
    }
}
