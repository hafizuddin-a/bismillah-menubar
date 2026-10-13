import AppKit

/// Borderless panel that can show up over full-screen apps without stealing focus.
private final class PopupPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }          // so Esc reaches us
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) }   // 53 = Esc
    }
}

/// The black rounded square. A click anywhere on it dismisses it.
private final class PopupContentView: NSView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 30
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.07).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the popup window: shows it centred on the screen, plays the animation, then fades it out.
final class PopupController {
    static let size = NSSize(width: 520, height: 180)
    private static let holdAfterWriting = 2.0
    private static let fade = 0.35

    private var panel: PopupPanel?
    private var bismillah: BismillahView?
    private var hideWork: DispatchWorkItem?

    /// True while the popup is on screen (including while it fades), so nothing restarts the app under it.
    var isShowing: Bool { panel?.isVisible ?? false }

    func show() {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel

        panel.setFrame(frameOnCurrentScreen(), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fade
            panel.animator().alphaValue = 1
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            bismillah?.showFinished()
        } else {
            bismillah?.play(after: Self.fade * 0.6)
        }

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + BismillahView.totalDuration + Self.holdAfterWriting, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fade
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            // A newer show() may have started during the fade; only hide if we are still faded out.
            if let panel, panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }

    // MARK: - building

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityLabel("Bismillah")
        panel.onDismiss = { [weak self] in self?.hide() }

        let content = PopupContentView(frame: NSRect(origin: .zero, size: Self.size))
        content.onClick = { [weak self] in self?.hide() }
        let view = BismillahView(frame: content.bounds)
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        panel.contentView = content
        bismillah = view
        return panel
    }

    private func frameOnCurrentScreen() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        return NSRect(x: f.midX - Self.size.width / 2, y: f.midY - Self.size.height / 2,
                      width: Self.size.width, height: Self.size.height)
    }
}
