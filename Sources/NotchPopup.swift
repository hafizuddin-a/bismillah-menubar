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

    static func current() -> NotchGeometry {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            let left = screen.auxiliaryTopLeftArea ?? .zero
            let right = screen.auxiliaryTopRightArea ?? .zero
            let gap = screen.frame.width - left.width - right.width
            let width = gap > 60 ? gap : 200
            let centerX = left.width > 0 ? screen.frame.minX + left.width + width / 2 : screen.frame.midX
            let inset = screen.safeAreaInsets.top
            return NotchGeometry(screenFrame: screen.frame, centerX: centerX, width: width, height: inset,
                                 topInset: inset, hasNotch: true)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screenFrame: screen.frame, centerX: screen.frame.midX, width: 120, height: 4,
                             topInset: menuBar, hasNotch: false)
    }
}

/// The black shape that opens out of the notch and holds the dhikr. `apply(progress:)` draws any moment of
/// the animation, 0 = notch-sized, 1 = fully open, so the whole thing can also be rendered offscreen.
final class NotchPopupView: NSView {
    static let text = "سُبْحَانَ ٱللَّهِ وَبِحَمْدِهِ"
    static let openWidth: CGFloat = 370
    static let textAreaHeight: CGFloat = 70
    static let margin: CGFloat = 40                // room around the shape for its shadow

    static func size(for geometry: NotchGeometry) -> NSSize {
        NSSize(width: openWidth + 2 * margin, height: geometry.topInset + textAreaHeight + margin)
    }

    private let geometry: NotchGeometry
    private let shape = CAShapeLayer()
    private let label = CATextLayer()

    init(geometry: NotchGeometry) {
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

        let font = NSFont(name: "GeezaPro", size: 30) ?? NSFont.systemFont(ofSize: 30)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributed = NSAttributedString(string: Self.text, attributes: [
            .font: font, .foregroundColor: NSColor.white, .paragraphStyle: style])
        label.string = attributed
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

    private var panel: NSPanel?
    private var view: NotchPopupView?
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var reduceMotion = false

    var isShowing: Bool { panel?.isVisible ?? false }

    /// 0 = closed, 1 = open, `t` seconds into the animation.
    nonisolated static func progress(at t: Double) -> CGFloat {
        if t < expand { return CGFloat(1 - pow(1 - t / expand, 3)) }
        if t < expand + hold { return 1 }
        let u = (t - expand - hold) / collapse
        return u >= 1 ? 0 : CGFloat(1 - u * u * u)
    }

    func show() {
        guard !isShowing else { return }
        let geometry = NotchGeometry.current()
        let view = NotchPopupView(geometry: geometry)
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
        panel.ignoresMouseEvents = true                 // never gets in the way of the menu bar
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityLabel("Subhanallahi wa bihamdihi")
        self.panel = panel
        self.view = view

        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        startTime = CACurrentMediaTime()
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
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = CACurrentMediaTime() - startTime
        let total = Self.expand + Self.hold + Self.collapse
        if reduceMotion {
            if t > Self.expand + Self.hold, let panel, panel.alphaValue == 1 {
                NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 0 }
            }
            if t > Self.expand + Self.hold + 0.3 { finish() }
            return
        }
        view?.apply(progress: Self.progress(at: t))
        if t >= total { finish() }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
    }
}
