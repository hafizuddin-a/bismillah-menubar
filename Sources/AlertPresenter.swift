import AppKit

/// Shows an `NSAlert` without blocking the app.
///
/// `NSAlert.runModal()` takes over the main thread's run loop for as long as the alert is open, and while it is
/// open nothing scheduled on the main queue runs: no update check, no dhikr reminder. An alert nobody has
/// answered would quietly stop the app. This shows the very same alert as an ordinary window instead and hands
/// back the answer with `await`, so everything else carries on meanwhile.
@MainActor
enum AlertPresenter {
    /// Receives the button presses (an NSButton's target must be an object).
    private final class Responder: NSObject {
        var onPress: ((NSButton) -> Void)?
        @objc func pressed(_ sender: NSButton) { onPress?(sender) }
    }

    private static var open: [(alert: NSAlert, responder: Responder)] = []

    /// True while an alert shown through here is on screen.
    static var isShowing: Bool { !open.isEmpty }

    /// Shows `alert` and returns the button that was pressed (`.alertFirstButtonReturn` for the first button, and so
    /// on), the way `runModal()` would. Return presses the first button and Esc the last one, when there are two or more.
    static func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            alert.layout()
            let responder = Responder()
            responder.onPress = { [unowned alert] sender in
                guard let index = open.firstIndex(where: { $0.alert === alert }) else { return }     // already answered
                open.remove(at: index)
                alert.window.orderOut(nil)
                let pressed = alert.buttons.firstIndex(of: sender) ?? 0
                continuation.resume(returning: NSApplication.ModalResponse(
                    rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + pressed))
            }
            for button in alert.buttons {
                button.target = responder
                button.action = #selector(Responder.pressed(_:))
            }
            if alert.buttons.count > 1 { alert.buttons[alert.buttons.count - 1].keyEquivalent = "\u{1b}" }
            open.append((alert, responder))

            let window = alert.window
            window.level = .modalPanel
            window.hidesOnDeactivate = false                        // an accessory app has no Dock icon to find it again by
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Brings an alert that is already open back to the front, e.g. when its menu item is chosen a second time.
    static func bringToFront() {
        guard let window = open.last?.alert.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
