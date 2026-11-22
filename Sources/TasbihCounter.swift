import AppKit
import QuartzCore

/// A small tally of "Subhanallahi wa bihamdihi" that drops down from the menu bar item like a menu (same material,
/// opening from its top-left corner) and stays until closed. Press Space to count, Esc to close; it remembers the
/// number between openings and between launches.
@MainActor
final class TasbihCounter {
    static let goal = 100
    private static let countKey = "TasbihCount"
    private static let phrase = "سُبْحَانَ ٱللَّهِ وَبِحَمْدِهِ"
    private static let size = NSSize(width: 272, height: 84)
    private static let cornerRadius: CGFloat = 12

    private var panel: CounterPanel?
    private let ringView = RingView(frame: NSRect(x: 0, y: 0, width: 58, height: 58))
    private let phraseLabel = TasbihCounter.label(phrase, font: NSFont(name: "GeezaPro", size: 22) ?? .systemFont(ofSize: 22))
    private let countLabel = TasbihCounter.label("0", font: .monospacedDigitSystemFont(ofSize: 17, weight: .semibold))
    private let spaceKey = KeyCapView(title: "Space")
    private let hintLabel = TasbihCounter.label("", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let hoverArea = ResetHoverArea()           // over the ring: hover shows a reset icon, click resets
    private let resetIcon = NSImageView()
    private var hovering = false
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    private(set) var count: Int {
        get { max(0, UserDefaults.standard.integer(forKey: Self.countKey)) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: Self.countKey) }
    }

    var isShowing: Bool { panel?.isVisible ?? false }

    /// Opens the counter under `anchor` (the menu bar item, in screen coordinates), its left edge lined up with the
    /// item's like a menu's, showing the saved number. Choosing it again closes it.
    func toggle(below anchor: NSRect?) {
        if isShowing && !closing { close(); return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        closing = false
        hovering = false
        refresh(animated: false)
        panel.setFrameOrigin(Self.origin(below: anchor))
        NSApp.activate()                             // so Space and Esc reach the popup
        panel.makeKeyAndOrderFront(nil)
        open(panel)
    }

    private var closing = false

    func close() {
        guard let panel, panel.isVisible, !closing else { return }
        closing = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, self.closing else { return }
                panel?.orderOut(nil)
                self.closing = false
            }
        })
    }

    /// Grows out of its top-left corner while fading in, the way a menu opens.
    private func open(_ panel: NSPanel) {
        panel.alphaValue = 1
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = panel.contentView?.layer else { return }
        let top = layer.bounds.maxY, scale = 0.9
        var grow = CATransform3DMakeTranslation(0, top, 0)
        grow = CATransform3DScale(grow, scale, scale, 1)
        grow = CATransform3DTranslate(grow, 0, -top, 0)
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = grow
        move.toValue = CATransform3DIdentity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = 0.14
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "open")
    }

    func increment() {
        count += 1
        refresh(animated: true)
        pulse(strongly: count == Self.goal)
    }

    func reset() {
        count = 0
        hovering = false
        refresh(animated: true)
    }

    // MARK: - building

    private static func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.isSelectable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    /// Hanging from the menu bar, left edge on the menu bar item's (as a menu does), kept inside the screen.
    private static func origin(below anchor: NSRect?) -> NSPoint {
        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let left = anchor?.minX ?? area.maxX - size.width - 8
        let x = min(max(left, area.minX + 4), area.maxX - size.width - 4)
        return NSPoint(x: x, y: area.maxY - size.height - 2)
    }

    private func makePanel() -> CounterPanel {
        let panel = CounterPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false                 // stays open until you close it
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("Tasbih Counter")
        panel.onSpace = { [weak self] in self?.increment() }
        panel.onEscape = { [weak self] in self?.close() }

        let content = NSView(frame: NSRect(origin: .zero, size: Self.size))
        content.translatesAutoresizingMaskIntoConstraints = false

        resetButton.target = self
        resetButton.action = #selector(resetPressed)
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.refusesFirstResponder = true         // so Space always counts, never presses a button
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .bold)
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.refusesFirstResponder = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        ringView.translatesAutoresizingMaskIntoConstraints = false
        phraseLabel.setAccessibilityLabel("Subhanallahi wa bihamdihi")
        phraseLabel.alignment = .left
        hintLabel.alignment = .left
        countLabel.maximumNumberOfLines = 1
        countLabel.lineBreakMode = .byClipping

        resetIcon.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        resetIcon.symbolConfiguration = .init(pointSize: 20, weight: .semibold)
        resetIcon.contentTintColor = .labelColor
        resetIcon.isHidden = true
        resetIcon.translatesAutoresizingMaskIntoConstraints = false
        hoverArea.translatesAutoresizingMaskIntoConstraints = false
        hoverArea.onHover = { [weak self] inside in self?.hovering = inside; self?.applyHover() }
        hoverArea.onClick = { [weak self] in self?.reset() }
        hoverArea.setAccessibilityLabel("Reset count to 0")

        for view in [ringView, countLabel, resetIcon, hoverArea, phraseLabel, spaceKey, hintLabel, resetButton, closeButton] { content.addSubview(view) }
        NSLayoutConstraint.activate([
            ringView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            ringView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ringView.widthAnchor.constraint(equalToConstant: 58),
            ringView.heightAnchor.constraint(equalToConstant: 58),
            countLabel.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),
            countLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 46),
            resetIcon.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
            resetIcon.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),
            hoverArea.leadingAnchor.constraint(equalTo: ringView.leadingAnchor),
            hoverArea.trailingAnchor.constraint(equalTo: ringView.trailingAnchor),
            hoverArea.topAnchor.constraint(equalTo: ringView.topAnchor),
            hoverArea.bottomAnchor.constraint(equalTo: ringView.bottomAnchor),
            phraseLabel.leadingAnchor.constraint(equalTo: ringView.trailingAnchor, constant: 14),
            phraseLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 15),
            spaceKey.leadingAnchor.constraint(equalTo: phraseLabel.leadingAnchor),
            spaceKey.centerYAnchor.constraint(equalTo: resetButton.centerYAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: spaceKey.trailingAnchor, constant: 5),
            hintLabel.centerYAnchor.constraint(equalTo: resetButton.centerYAnchor),
            resetButton.leadingAnchor.constraint(equalTo: hintLabel.trailingAnchor, constant: 8),
            resetButton.topAnchor.constraint(equalTo: phraseLabel.bottomAnchor, constant: 4),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 7),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        // glass on macOS 26 and later (what the menu next to it is drawn with), the menu material before that;
        // 12 pt is the corner radius of a real menu's window
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            panel.contentView = glass
        } else {
            let menuLook = NSVisualEffectView()
            menuLook.material = .menu
            menuLook.blendingMode = .behindWindow
            menuLook.state = .active
            menuLook.wantsLayer = true
            menuLook.layer?.cornerRadius = Self.cornerRadius
            menuLook.layer?.cornerCurve = .continuous
            menuLook.layer?.masksToBounds = true
            menuLook.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: menuLook.leadingAnchor), content.trailingAnchor.constraint(equalTo: menuLook.trailingAnchor),
                content.topAnchor.constraint(equalTo: menuLook.topAnchor), content.bottomAnchor.constraint(equalTo: menuLook.bottomAnchor),
            ])
            panel.contentView = menuLook
        }
        panel.setContentSize(Self.size)
        return panel
    }

    @objc private func resetPressed() { reset() }
    @objc private func closePressed() { close() }

    // MARK: - updating

    private func refresh(animated: Bool) {
        let n = count
        let done = n >= Self.goal
        countLabel.stringValue = "\(n)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: n < 1000 ? 17 : (n < 10000 ? 13 : 10), weight: .semibold)     // keeps big numbers inside the ring
        hintLabel.stringValue = done ? "to continue" : "to count · goal \(Self.goal)"
        resetButton.isHidden = !done
        hoverArea.isEnabled = n > 0
        applyHover()
        ringView.setProgress(CGFloat(min(n, Self.goal)) / CGFloat(Self.goal), complete: done,
                             animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel?.setAccessibilityValue("\(n)")
        hintLabel.setAccessibilityLabel("Press Space " + hintLabel.stringValue)
    }

    /// While the pointer is over the ring (and there is something to reset), the number gives way to a reset icon.
    private func applyHover() {
        let showReset = hovering && count > 0
        countLabel.isHidden = showReset
        resetIcon.isHidden = !showReset
    }

    /// A small bump of the number on every count, a bigger one on reaching the goal.
    private func pulse(strongly: Bool) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = countLabel.layer else { return }
        layer.removeAnimation(forKey: "pulse")
        let bump = CASpringAnimation(keyPath: "transform.scale")
        bump.fromValue = strongly ? 1.3 : 1.12
        bump.toValue = 1
        bump.damping = 12
        bump.initialVelocity = 0
        bump.duration = bump.settlingDuration
        layer.add(bump, forKey: "pulse")
    }
}

/// The window itself: takes Space (count) and Esc (close), ignoring the repeats of a held key.
private final class CounterPanel: NSPanel {
    var onSpace: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: if !event.isARepeat { onSpace?() }        // Space
        case 53: onEscape?()                               // Esc
        default: super.keyDown(with: event)
        }
    }
}

/// A ring that fills as the count goes up.
private final class RingView: NSView {
    private let track = CAShapeLayer()
    private let bar = CAShapeLayer()
    private var complete = false
    private var progress: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        for shape in [track, bar] {
            shape.fillColor = nil
            shape.lineWidth = 5
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        bar.strokeEnd = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 4, dy: 4)
        let path = CGMutablePath()
        // from the top, clockwise
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, bar] { shape.frame = bounds; shape.path = path }
        CATransaction.commit()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.strokeColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
            bar.strokeColor = (complete ? NSColor.systemGreen : NSColor.labelColor.withAlphaComponent(0.9)).cgColor
        }
    }

    func setProgress(_ value: CGFloat, complete: Bool, animated: Bool) {
        self.complete = complete
        let previous = progress
        progress = value
        updateColors()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.strokeEnd = value
        CATransaction.commit()
        if animated && value != previous {
            let grow = CABasicAnimation(keyPath: "strokeEnd")
            grow.fromValue = value == 0 ? previous : (bar.presentation()?.strokeEnd ?? previous)
            grow.toValue = value
            grow.duration = value == 0 ? 0.5 : 0.18
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.add(grow, forKey: "grow")
        }
    }
}

/// "Space" drawn as a small key, so it reads as the key to press.
private final class KeyCapView: NSView {
    private let label: NSTextField

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)                 // the hint's own label already says "Press Space"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.28).cgColor
        }
    }
}

/// An invisible patch over the ring: reports the pointer entering and leaving, and clicks, while it is enabled.
final class ResetHoverArea: NSView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { onHover?(false) }
            window?.invalidateCursorRects(for: self)
            setAccessibilityElement(isEnabled)
        }
    }
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.button)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { onHover?(true) } }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { if isEnabled { onClick?() } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func accessibilityPerformPress() -> Bool { guard isEnabled else { return false }; onClick?(); return true }
}
