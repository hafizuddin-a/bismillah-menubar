import AppKit

/// The small popup under the menu bar item that asks whether to turn the tasbih break reminder on.
@MainActor
final class BreakReminderPrompt: NSObject {
    private final class Panel: NSPanel {
        var onEscape: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { onEscape?() }
    }

    private static let width: CGFloat = 280
    private var panel: Panel?
    private var answer: ((Bool) -> Void)?

    var isShowing: Bool { panel?.isVisible ?? false }

    /// Opens under `anchor` (the menu bar item). `answer` gets true for "Yes, Remind Me" and false for "No";
    /// Esc closes it and changes nothing.
    func show(below anchor: NSRect?, answer: @escaping (Bool) -> Void) {
        close()
        self.answer = answer

        let title = NSTextField(labelWithString: "Tasbih break reminder")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: "Would you like to be reminded to do tasbih after 1 hour of activity?")
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        text.preferredMaxLayoutWidth = Self.width - 28
        let yes = NSButton(title: "Yes, Remind Me", target: self, action: #selector(yesPressed))
        yes.keyEquivalent = "\r"
        let no = NSButton(title: "No", target: self, action: #selector(noPressed))
        let buttons = NSStackView(views: [no, yes])
        buttons.spacing = 8

        let stack = NSStackView(views: [title, text, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: text)
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        stack.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: ceil(stack.fittingSize.height))

        let panel = Panel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("Tasbih break reminder")
        panel.onEscape = { [weak self] in self?.close() }

        // the same background as the tasbih counter: glass on macOS 26 and later, the menu material before that
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
        ])
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = 12
            glass.contentView = content
            panel.contentView = glass
        } else {
            let menuLook = NSVisualEffectView(frame: content.frame)
            menuLook.material = .menu
            menuLook.blendingMode = .behindWindow
            menuLook.state = .active
            menuLook.wantsLayer = true
            menuLook.layer?.cornerRadius = 12
            menuLook.layer?.cornerCurve = .continuous
            menuLook.layer?.masksToBounds = true
            menuLook.addSubview(content)
            panel.contentView = menuLook
        }
        panel.setContentSize(size)

        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } }
        let area = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let left = screen == nil ? area.maxX - Self.width - 8 : anchor!.minX
        panel.setFrameOrigin(NSPoint(x: min(max(left, area.minX + 4), area.maxX - Self.width - 4),
                                     y: area.maxY - size.height - 2))
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        answer = nil
    }

    private func finish(_ yes: Bool) {
        let answer = self.answer
        close()
        answer?(yes)
    }

    @objc private func yesPressed() { finish(true) }
    @objc private func noPressed() { finish(false) }
}
