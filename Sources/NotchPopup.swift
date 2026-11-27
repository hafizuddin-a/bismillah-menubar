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
    static let readingExtra: CGFloat = 10          // taller by this much when the transliteration is shown
    static let reminderHeight: CGFloat = 104       // the text area of the tasbih break reminder
    static let reminderTitle = "SubhanAllah, an hour has passed"
    static let reminderText = "Take a moment for tasbih."
    static let reminderTextTheHour = "Take a moment for tasbih, before The Hour."     // after several ignored ones

    /// A button that works on the first click although the popup never takes keyboard focus.
    private final class PillButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    }
    private var reminderViews: [NSView] = []

    /// Called by the reminder's Open Tasbih Counter button.
    var onOpenCounter: (() -> Void)?

    static func size(for geometry: NotchGeometry, showReading: Bool = false, reminder: Bool = false) -> NSSize {
        let area = reminder ? reminderHeight : textAreaHeight + (showReading ? readingExtra : 0)
        return NSSize(width: openWidth + 2 * margin, height: geometry.topInset + area + margin)
    }

    private let geometry: NotchGeometry
    private let shape = CAShapeLayer()
    private let label = CATextLayer()
    private let readingLabel = CATextLayer()
    private let textArea: CGFloat
    private var currentPath: CGPath?

    /// Called when the black shape is clicked.
    var onClick: (() -> Void)?

    init(geometry: NotchGeometry, phrase: Dhikr = NotchPopupView.phrases[0], showReading: Bool = false,
         reminder: Bool = false, theHour: Bool = false) {
        self.geometry = geometry
        textArea = reminder ? Self.reminderHeight : Self.textAreaHeight + (showReading ? Self.readingExtra : 0)
        super.init(frame: NSRect(origin: .zero, size: Self.size(for: geometry, showReading: showReading, reminder: reminder)))
        wantsLayer = true
        layer = CALayer()
        layerContentsRedrawPolicy = .never

        shape.fillColor = NSColor.black.cgColor
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowRadius = 14
        shape.shadowOffset = CGSize(width: 0, height: -6)
        shape.frame = bounds
        layer?.addSublayer(shape)
        if reminder {
            addReminder(text: theHour ? Self.reminderTextTheHour : Self.reminderText)
            apply(progress: 0)
            return
        }

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
        let areaBottom = bounds.height - geometry.topInset - textArea
        let readingSpace = showReading ? Self.readingExtra : 0
        label.frame = CGRect(x: (bounds.width - Self.openWidth) / 2,
                             y: areaBottom + readingSpace + (Self.textAreaHeight - textHeight) / 2 - 2,
                             width: Self.openWidth, height: textHeight)
        layer?.addSublayer(label)
        if showReading {
            readingLabel.string = phrase.reading
            readingLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            readingLabel.fontSize = 13
            readingLabel.foregroundColor = NSColor(white: 1, alpha: 0.66).cgColor
            readingLabel.alignmentMode = .center
            readingLabel.isWrapped = false
            readingLabel.contentsScale = label.contentsScale
            readingLabel.frame = CGRect(x: (bounds.width - Self.openWidth) / 2, y: areaBottom + readingSpace + 4, width: Self.openWidth, height: 18)
            layer?.addSublayer(readingLabel)
        }
        apply(progress: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func addReminder(text: String) {
        func line(_ text: String, size: CGFloat, weight: NSFont.Weight, white: CGFloat, y: CGFloat) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = NSColor(white: 1, alpha: white)
            field.alignment = .center
            field.frame = NSRect(x: (bounds.width - Self.openWidth) / 2, y: y, width: Self.openWidth, height: size + 6)
            return field
        }
        let bottom = bounds.height - geometry.topInset - textArea
        let button = PillButton(title: "", target: self, action: #selector(openCounterPressed))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.cgColor
        button.layer?.cornerRadius = 13
        button.attributedTitle = NSAttributedString(string: "Open Tasbih Counter", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.black])
        button.refusesFirstResponder = true
        button.frame = NSRect(x: (bounds.width - 160) / 2, y: bottom + 14, width: 160, height: 26)
        reminderViews = [line(Self.reminderTitle, size: 19, weight: .semibold, white: 1, y: bottom + 69),
                         line(text, size: 12, weight: .regular, white: 0.66, y: bottom + 49),
                         button]
        reminderViews.forEach(addSubview)
    }

    @objc private func openCounterPressed() { onOpenCounter?() }

    override var isFlipped: Bool { false }

    // Only the black shape takes clicks, so the transparent margin around it never gets in the way.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard currentPath?.contains(local) == true else { return nil }
        if let button = reminderViews.compactMap({ $0 as? NSButton }).first, button.alphaValue > 0.5,
           button.frame.contains(local) { return button }
        return self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    func apply(progress p: CGFloat) {
        let p = min(max(p, 0), 1)
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let openHeight = geometry.topInset + textArea
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
        readingLabel.opacity = label.opacity
        for view in reminderViews { view.alphaValue = CGFloat(label.opacity) }
        CATransaction.commit()
    }
}

/// Shows the dhikr: the shape grows out of the notch, holds, then folds back into it.
@MainActor
final class NotchPopupController {
    private nonisolated static let expand = 0.5, hold = 4.0, collapse = 0.4
    private nonisolated static let reminderHold = 15.0   // long enough to read and click
    private var holdTime = NotchPopupController.hold
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
    nonisolated static func progress(at t: Double, hold: Double = 4.0) -> CGFloat {
        if t < expand { return CGFloat(1 - pow(1 - t / expand, 3)) }
        if t < expand + hold { return 1 }
        let u = (t - expand - hold) / collapse
        return u >= 1 ? 0 : CGFloat(1 - u * u * u)
    }

    /// Shows one dhikr (the same on every screen): on the notched screen, or the screen the mouse is on, or on
    /// every screen when `allScreens` is true.
    func show(allScreens: Bool = false, showReading: Bool = false) {
        guard !isShowing else { return }
        let index = Self.nextPhrase(after: lastPhrase, count: NotchPopupView.phrases.count)
        lastPhrase = index
        let phrase = NotchPopupView.phrases[index]
        holdTime = Self.hold
        present(allScreens: allScreens, label: phrase.reading) { geometry in
            NotchPopupView(geometry: geometry, phrase: phrase, showReading: showReading)
        }
    }

    /// The tasbih break reminder, out of the notch like a dhikr but longer, with a button to open the counter.
    func showBreakReminder(allScreens: Bool = false, theHour: Bool = false, onOpenCounter: @escaping () -> Void) {
        guard !isShowing else { return }
        holdTime = Self.reminderHold
        present(allScreens: allScreens, label: NotchPopupView.reminderTitle) { [weak self] geometry in
            let view = NotchPopupView(geometry: geometry, reminder: true, theHour: theHour)
            view.onOpenCounter = {
                self?.dismiss()
                onOpenCounter()
            }
            return view
        }
    }

    private func present(allScreens: Bool, label: String, make: (NotchGeometry) -> NotchPopupView) {
        let geometries = allScreens && !NSScreen.screens.isEmpty ? NSScreen.screens.map(NotchGeometry.on) : [NotchGeometry.current()]

        windows = geometries.map { geometry in
            let view = make(geometry)
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
            panel.sharingType = .none                       // asks to be left out of screen shares and recordings
            panel.isReleasedWhenClosed = false              // clicks reach only the shape (see NotchPopupView.hitTest)
            panel.setAccessibilityLabel(label)
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
        let total = Self.expand + holdTime + Self.collapse
        if reduceMotion {
            if t > Self.expand + holdTime, windows.first?.panel.alphaValue == 1 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    for window in windows { window.panel.animator().alphaValue = 0 }
                }
            }
            if t > Self.expand + holdTime + 0.3 { finish() }
            return
        }
        lastProgress = Self.progress(at: t, hold: holdTime)
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
