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

/// Owns the popup windows: shows the popup centred on one screen (or on every screen), plays the animation, then
/// fades it out.
final class PopupController {
    static let size = NSSize(width: 520, height: 180)
    private static let holdAfterWriting = 2.0
    private static let fade = 0.35

    /// One window per screen it has been shown on; they are reused between showings.
    private var windows: [(panel: PopupPanel, view: BismillahView)] = []
    private var hideWork: DispatchWorkItem?

    /// True while the popup is on screen (including while it fades), so nothing restarts the app under it.
    var isShowing: Bool { windows.contains { $0.panel.isVisible } }

    /// Shows the popup on the screen the mouse is on, or on every screen when `allScreens` is true.
    func show(allScreens: Bool = false) {
        hideWork?.cancel()
        let screens = Self.targetScreens(allScreens: allScreens)
        while windows.count < screens.count { windows.append(makeWindow()) }
        for window in windows[screens.count...] { window.panel.orderOut(nil) }

        for (index, screen) in screens.enumerated() {
            let (panel, view) = windows[index]
            panel.setFrame(Self.frame(centeredOn: screen), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            if index == 0 { panel.makeKey() }            // so Esc reaches us
            panel.invalidateShadow()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fade
                panel.animator().alphaValue = 1
            }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                view.showFinished()
            } else {
                view.play(after: Self.fade * 0.6)
            }
        }

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + BismillahView.totalDuration + Self.holdAfterWriting, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        let visible = windows.map(\.panel).filter(\.isVisible)
        guard !visible.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fade
            for panel in visible { panel.animator().alphaValue = 0 }
        }, completionHandler: {
            // A newer show() may have started during the fade; only hide the windows that are still faded out.
            for panel in visible where panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }

    // MARK: - building

    private func makeWindow() -> (panel: PopupPanel, view: BismillahView) {
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
        return (panel, view)
    }

    private static func targetScreens(allScreens: Bool) -> [NSScreen] {
        if allScreens && !NSScreen.screens.isEmpty { return NSScreen.screens }
        let mouse = NSEvent.mouseLocation
        return [NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]]
    }

    private static func frame(centeredOn screen: NSScreen) -> NSRect {
        let f = screen.frame
        return NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height)
    }
}
