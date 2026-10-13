import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popup = PopupController()
    private let notchPopup = NotchPopupController()
    private lazy var updater = Updater(isPopupShowing: { [weak self] in
        (self?.popup.isShowing ?? false) || (self?.notchPopup.isShowing ?? false)
    })
    private lazy var dhikr = DhikrScheduler(show: { [weak self] in self?.showDhikrIfPossible() ?? false })
    private var loginItem: NSMenuItem!
    private var autoUpdateItem: NSMenuItem!
    private var dhikrCountItems: [NSMenuItem] = []
    private var dhikrNextItem: NSMenuItem!

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

        // Dhikr Reminders ▸ Off / 1 per day / 3 per day … / Next: … / Show Now
        let dhikrMenu = NSMenu()
        for count in DhikrScheduler.choices {
            let title = count == 0 ? "Off" : (count == 1 ? "1 per day" : "\(count) per day")
            let item = NSMenuItem(title: title, action: #selector(chooseDhikrCount(_:)), keyEquivalent: "")
            item.target = self
            item.tag = count
            dhikrMenu.addItem(item)
            dhikrCountItems.append(item)
        }
        dhikrMenu.addItem(.separator())
        dhikrNextItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        dhikrNextItem.isEnabled = false
        dhikrMenu.addItem(dhikrNextItem)
        let showDhikr = NSMenuItem(title: "Show Now", action: #selector(showDhikrNow), keyEquivalent: "")
        showDhikr.target = self
        dhikrMenu.addItem(showDhikr)
        dhikrMenu.delegate = self
        let dhikrParent = NSMenuItem(title: "Dhikr Reminders", action: nil, keyEquivalent: "")
        dhikrParent.submenu = dhikrMenu
        menu.addItem(dhikrParent)

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
        dhikr.start()

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
        dhikr.start()                                // the clock may have jumped while it slept
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

    // MARK: - dhikr

    /// Called by the scheduler. Returns false when it isn't a good moment, so the scheduler tries again soon.
    private func showDhikrIfPossible() -> Bool {
        if popup.isShowing || notchPopup.isShowing || Self.screenIsLocked || CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            return false
        }
        notchPopup.show()
        return true
    }

    @objc private func chooseDhikrCount(_ sender: NSMenuItem) { dhikr.perDay = sender.tag }

    @objc private func showDhikrNow() { notchPopup.show() }

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
        for item in dhikrCountItems { item.state = item.tag == dhikr.perDay ? .on : .off }
        if let next = dhikr.nextPopup {
            let time = next.formatted(date: .omitted, time: .shortened)
            dhikrNextItem.title = Calendar.current.isDateInToday(next) ? "Next: \(time)" : "Next: tomorrow, \(time)"
        } else {
            dhikrNextItem.title = "No reminders scheduled"
        }
    }
}
