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
    private static let width: CGFloat = 330
    private static let padding: CGFloat = 13
    private static var hadithURL: URL { URL(string: "https://sunnah.com/bukhari:6405")! }   // Sahih al-Bukhari 6405
    private static let cornerRadius: CGFloat = 12

    private var panel: CounterPanel?
    private let ringView = RingView(frame: NSRect(x: 0, y: 0, width: 58, height: 58))
    private let phraseLabel = TasbihCounter.label(phrase, font: NSFont(name: "GeezaPro", size: 22) ?? .systemFont(ofSize: 22))
    private let countLabel = TasbihCounter.label("0", font: .monospacedDigitSystemFont(ofSize: 17, weight: .semibold))
    private let readingLabel = TasbihCounter.label("Subhanallahi wa bihamdihi", font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    private let hadithButton = LinkButton(title: "Hadith", target: nil, action: nil)
    private let menuBarToggle = NSButton(checkboxWithTitle: "Show saved count in menu bar", target: nil, action: nil)
    private let contentStack = NSStackView()
    private let spaceKey = KeyCapView(title: "Space")
    private let hintLabel = TasbihCounter.label("", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
    private let hoverArea = ResetHoverArea()           // over the ring: hover shows a reset icon, click resets
    private let resetIcon = NSImageView()
    private var hovering = false
    private var hintText = ""
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    /// Everything counted since the last reset. Stored as one number, so counts saved by older versions carry over.
    private var total: Int {
        get { max(0, UserDefaults.standard.integer(forKey: Self.countKey)) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: Self.countKey) }
    }

    /// The number on the ring, 0 to `goal`. Counting on past the goal starts the next round (101 shows 1; exactly 100 shows 100).
    var count: Int { total == 0 ? 0 : (total - 1) % Self.goal + 1 }

    /// Rounds of `goal` finished so far.
    var rounds: Int { total / Self.goal }

    var isShowing: Bool { panel?.isVisible ?? false }

    /// Called whenever the number changes through counting or reset.
    var onChange: (() -> Void)?

    /// Whether the number is shown next to بسم الله in the menu bar. Off by default; set from the counter itself.
    var showsCountInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: "ShowCountInMenuBar") }
        set { UserDefaults.standard.set(newValue, forKey: "ShowCountInMenuBar") }
    }

    /// Whether the transliteration is shown under the Arabic. Takes effect at once if the counter is open.
    var showsReading = false {
        didSet {
            guard showsReading != oldValue else { return }
            applyReading()
        }
    }

    /// As tall as its rows need, whichever of them are showing.
    private var height: CGFloat {
        contentStack.layoutSubtreeIfNeeded()
        return max(ceil(contentStack.fittingSize.height) + 2 * Self.padding, 84)
    }

    private func applyReading() {
        readingLabel.isHidden = !showsReading
        guard let panel else { return }
        let f = panel.frame                              // grows downward, the top stays under the menu bar
        panel.setFrame(NSRect(x: f.minX, y: f.maxY - height, width: Self.width, height: height), display: true)
    }

    /// Opens the counter under `anchor` (the menu bar item, in screen coordinates), its left edge lined up with the
    /// item's like a menu's, showing the saved number. Choosing it again closes it.
    func toggle(below anchor: NSRect?) {
        if isShowing && !closing { close(); return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        closing = false
        hovering = false
        menuBarToggle.state = showsCountInMenuBar ? .on : .off
        refresh(animated: false)
        applyReading()
        panel.setFrameOrigin(Self.origin(below: anchor, height: height))
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
        total += 1
        refresh(animated: true)
        pulse(strongly: total % Self.goal == 0)
        onChange?()
    }

    /// Adds `n` at once (1 to 100), e.g. from a Shortcut.
    func add(_ n: Int) {
        let before = rounds
        total += min(max(n, 1), Self.goal)
        refresh(animated: true)
        pulse(strongly: rounds > before || total % Self.goal == 0)
        onChange?()
    }

    /// Clears the round on the ring: 15 of round 3 goes back to 0 of round 3, and rounds already finished stay.
    func reset() {
        total = total > 0 ? (total - 1) / Self.goal * Self.goal : 0
        hovering = false
        refresh(animated: true)
        onChange?()
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
    private static func origin(below anchor: NSRect?, height: CGFloat) -> NSPoint {
        // a menu bar item that is hidden or off screen has no usable position: fall back to the top right
        let anchorScreen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } }
        let area = (anchorScreen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let left = anchorScreen == nil ? area.maxX - width - 8 : anchor!.minX
        let x = min(max(left, area.minX + 4), area.maxX - width - 4)
        return NSPoint(x: x, y: area.maxY - height - 2)
    }

    private func makePanel() -> CounterPanel {
        let panel = CounterPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height),
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

        let content = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        content.translatesAutoresizingMaskIntoConstraints = false

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .bold)
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.refusesFirstResponder = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        hadithButton.target = self
        hadithButton.action = #selector(openHadith)
        hadithButton.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
        hadithButton.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        hadithButton.imagePosition = .imageLeading
        hadithButton.isBordered = false
        hadithButton.attributedTitle = NSAttributedString(string: "Hadith", attributes: [      // looks like a link
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue])
        hadithButton.contentTintColor = .linkColor
        hadithButton.toolTip = "The hadith about saying it 100 times (opens sunnah.com)"
        hadithButton.setAccessibilityLabel("Read the hadith about saying it 100 times")
        hadithButton.refusesFirstResponder = true
        menuBarToggle.target = self
        menuBarToggle.action = #selector(menuBarTogglePressed)
        menuBarToggle.controlSize = .mini
        menuBarToggle.font = .systemFont(ofSize: 10)
        menuBarToggle.refusesFirstResponder = true
        menuBarToggle.setAccessibilityLabel("Show the saved count next to بسم الله in the menu bar")
        ringView.translatesAutoresizingMaskIntoConstraints = false
        phraseLabel.setAccessibilityLabel("Subhanallahi wa bihamdihi")
        phraseLabel.alignment = .left
        readingLabel.alignment = .left
        readingLabel.isHidden = !showsReading
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
        hoverArea.setAccessibilityLabel("Clear this round (finished rounds stay)")
        hoverArea.toolTip = "Clears this round only"

        // the rows, top to bottom: the dhikr, its reading, "Space to count" (and Reset), then Hadith and the menu bar option
        let hintRow = NSStackView(views: [spaceKey, hintLabel])
        hintRow.orientation = .horizontal
        hintRow.spacing = 5
        hintRow.alignment = .centerY
        hintRow.heightAnchor.constraint(equalToConstant: 20).isActive = true        // the same height with or without Reset
        let linkRow = NSStackView(views: [hadithButton, menuBarToggle])
        linkRow.orientation = .horizontal
        linkRow.spacing = 12
        linkRow.alignment = .centerY
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        contentStack.detachesHiddenViews = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        for view in [phraseLabel, readingLabel, hintRow, linkRow] { contentStack.addArrangedSubview(view) }
        contentStack.setCustomSpacing(2, after: phraseLabel)
        contentStack.setCustomSpacing(7, after: hintRow)

        for view in [ringView, countLabel, resetIcon, hoverArea, contentStack, closeButton] { content.addSubview(view) }
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
            contentStack.leadingAnchor.constraint(equalTo: ringView.trailingAnchor, constant: 14),
            contentStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
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
        panel.setContentSize(NSSize(width: Self.width, height: height))
        return panel
    }

    @objc private func closePressed() { close() }
    @objc private func openHadith() { NSWorkspace.shared.open(Self.hadithURL) }
    @objc private func menuBarTogglePressed() {
        showsCountInMenuBar = menuBarToggle.state == .on
        onChange?()
    }

    // MARK: - updating

    private func refresh(animated: Bool) {
        let n = count
        let done = total > 0 && total % Self.goal == 0          // the ring is full right now
        countLabel.stringValue = "\(n)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: n < 1000 ? 17 : (n < 10000 ? 13 : 10), weight: .semibold)     // keeps big numbers inside the ring
        hintText = (done ? "to continue" : "to count · goal \(Self.goal)")
            + (rounds > 0 ? " · \(rounds) round\(rounds == 1 ? "" : "s")" : "")
        hintLabel.stringValue = hintText
        hoverArea.isEnabled = n > 0
        applyHover()
        ringView.setProgress(CGFloat(min(n, Self.goal)) / CGFloat(Self.goal), complete: done,
                             animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel?.setAccessibilityValue("\(n)")
        hintLabel.setAccessibilityLabel("Press Space " + hintLabel.stringValue)
    }

    /// While the pointer is over the ring (and there is something to reset), the number gives way to a reset icon.
    private func applyHover() {
        let showReset = hovering && total > 0
        countLabel.isHidden = showReset
        resetIcon.isHidden = !showReset
        hintLabel.stringValue = showReset ? "Clears this round only" : hintText     // instant, unlike a tooltip
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

/// A borderless button that shows the pointing hand, so it reads as a link.
private final class LinkButton: NSButton {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
