import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popup = PopupController()
    private lazy var updater = Updater(isPopupShowing: { [weak self] in self?.popup.isShowing ?? false })
    private var loginItem: NSMenuItem!
    private var autoUpdateItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "بسم الله"                    // plain text, no harakat; the system tints it
            button.font = NSFont(name: "GeezaPro", size: 15) ?? .menuBarFont(ofSize: 0)
            button.setAccessibilityLabel("Bismillah")
        }

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Bismillah", action: #selector(showBismillah), keyEquivalent: "b")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        autoUpdateItem = NSMenuItem(title: "Update Automatically", action: #selector(toggleAutomaticUpdates), keyEquivalent: "")
        autoUpdateItem.target = self
        menu.addItem(autoUpdateItem)
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let versionItem = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Bismillah", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        // After an automatic update the app reopens itself quietly; every other launch greets you.
        if !CommandLine.arguments.contains("--after-update") {
            popup.show()
        }
        updater.startAutomaticChecks()

        // Greet again whenever the Mac wakes (lid opened, or the display woke up).
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(macDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(macDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        // If the lid opens onto the lock screen, wait for the unlock: a popup can't appear above it.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenWasUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: - wake / unlock

    private var greetOnceUnlocked = false
    private var lastGreeting = Date.distantPast

    @objc func macDidWake() {
        greetOnceUnlocked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.greetIfPossible() }
        // the Mac may have slept past an update check
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.updater.checkIfDue() }
    }

    @objc private func screenWasUnlocked() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.greetIfPossible() }
    }

    private func greetIfPossible() {
        guard greetOnceUnlocked, !Self.screenIsLocked else { return }
        greetOnceUnlocked = false
        // wake and screensDidWake usually both fire; don't greet twice
        guard Date().timeIntervalSince(lastGreeting) > 5 else { return }
        lastGreeting = Date()
        popup.show()
    }

    private static var screenIsLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    // MARK: - menu actions

    @objc private func showBismillah() {
        lastGreeting = Date()
        popup.show()
    }

    @objc private func toggleAutomaticUpdates() {
        updater.automaticEnabled.toggle()
        if updater.automaticEnabled { updater.checkIfDue() }
    }

    @objc private func checkForUpdates() { updater.checkManually() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nTry moving Bismillah.app to /Applications first."
            alert.runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        autoUpdateItem.state = updater.automaticEnabled ? .on : .off
    }
}
