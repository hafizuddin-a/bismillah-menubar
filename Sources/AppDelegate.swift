import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popup = PopupController()
    private let notchPopup = NotchPopupController()
    private let tasbih = TasbihCounter()
    private lazy var updater = Updater(isPopupShowing: { [weak self] in
        (self?.popup.isShowing ?? false) || (self?.notchPopup.isShowing ?? false)
    })
    private lazy var dhikr = DhikrScheduler(show: { [weak self] in self?.showDhikrIfPossible() ?? false })
    private var loginItem: NSMenuItem!
    private var allScreensItem: NSMenuItem!
    private var transliterationItem: NSMenuItem!
    private var skipShareItem: NSMenuItem!
    private var shortcutsItem: NSMenuItem!
    private var styleItems: [NSMenuItem] = []
    private var autoUpdateItem: NSMenuItem!
    private var dhikrCountItems: [NSMenuItem] = []
    private var dhikrNextItem: NSMenuItem!
    private var startHourParent: NSMenuItem!
    private var endHourParent: NSMenuItem!
    private var startHourItems: [NSMenuItem] = []
    private var endHourItems: [NSMenuItem] = []

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

        // Animation ▸ Writing / Fading
        let styleMenu = NSMenu()
        for (title, style) in [("Writing", BismillahView.Style.writing), ("Fading", .fading)] {
            let item = NSMenuItem(title: title, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            styleMenu.addItem(item)
            styleItems.append(item)
        }
        let styleParent = NSMenuItem(title: "Animation Mode", action: nil, keyEquivalent: "")
        styleParent.submenu = styleMenu
        menu.addItem(styleParent)
        transliterationItem = NSMenuItem(title: "Show Transliteration", action: #selector(toggleTransliteration), keyEquivalent: "")
        transliterationItem.target = self
        menu.addItem(transliterationItem)

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
        // the active hours: Starts at ▸ / Ends at ▸ (choices that would put the start after the end are greyed out)
        let startMenu = NSMenu(), endMenu = NSMenu()
        startMenu.autoenablesItems = false
        endMenu.autoenablesItems = false
        for hour in DhikrScheduler.startHourChoices {
            let item = NSMenuItem(title: Self.hourLabel(hour), action: #selector(chooseStartHour(_:)), keyEquivalent: "")
            item.target = self
            item.tag = hour
            startMenu.addItem(item)
            startHourItems.append(item)
        }
        for hour in DhikrScheduler.endHourChoices {
            let item = NSMenuItem(title: Self.hourLabel(hour), action: #selector(chooseEndHour(_:)), keyEquivalent: "")
            item.target = self
            item.tag = hour
            endMenu.addItem(item)
            endHourItems.append(item)
        }
        startHourParent = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        startHourParent.submenu = startMenu
        dhikrMenu.addItem(startHourParent)
        endHourParent = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        endHourParent.submenu = endMenu
        dhikrMenu.addItem(endHourParent)
        skipShareItem = NSMenuItem(title: "Skip While Screen Sharing", action: #selector(toggleSkipWhileSharing), keyEquivalent: "")
        skipShareItem.target = self
        dhikrMenu.addItem(skipShareItem)
        dhikrMenu.addItem(.separator())
        dhikrNextItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        dhikrNextItem.isEnabled = false
        dhikrMenu.addItem(dhikrNextItem)
        let showDhikr = NSMenuItem(title: "Show Now", action: #selector(showDhikrNow), keyEquivalent: "")
        showDhikr.target = self
        dhikrMenu.addItem(showDhikr)
        dhikrMenu.autoenablesItems = false
        dhikrMenu.delegate = self
        let dhikrParent = NSMenuItem(title: "Dhikr Reminders", action: nil, keyEquivalent: "")
        dhikrParent.submenu = dhikrMenu
        menu.addItem(dhikrParent)
        let counter = NSMenuItem(title: "Tasbih Counter", action: #selector(openTasbihCounter), keyEquivalent: "")
        counter.target = self
        menu.addItem(counter)

        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        allScreensItem = NSMenuItem(title: "Show on All Screens", action: #selector(toggleAllScreens), keyEquivalent: "")
        allScreensItem.target = self
        menu.addItem(allScreensItem)
        // Global Shortcuts ▸ Enabled / the two shortcuts (shown greyed, for reference)
        let shortcutsMenu = NSMenu()
        shortcutsMenu.autoenablesItems = false
        shortcutsItem = NSMenuItem(title: "Enabled", action: #selector(toggleGlobalShortcuts), keyEquivalent: "")
        shortcutsItem.target = self
        shortcutsMenu.addItem(shortcutsItem)
        shortcutsMenu.addItem(.separator())
        for (title, key) in [("Show Bismillah", "b"), ("Tasbih Counter", "t")] {
            let info = NSMenuItem(title: title, action: nil, keyEquivalent: key)
            info.keyEquivalentModifierMask = [.control, .option]
            info.isEnabled = false
            shortcutsMenu.addItem(info)
        }
        let shortcutsParent = NSMenuItem(title: "Global Shortcuts", action: nil, keyEquivalent: "")
        shortcutsParent.submenu = shortcutsMenu
        menu.addItem(shortcutsParent)
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
        let signature = NSMenuItem(title: "Sincerely, @madebyhafiz", action: #selector(openInstagram), keyEquivalent: "")
        signature.target = self
        signature.image = NSImage(systemSymbolName: "face.smiling.inverse", accessibilityDescription: nil)    // lines up with Quit's icon
        menu.addItem(signature)
        menu.delegate = self
        statusItem.menu = menu

        // After an automatic update the app reopens itself quietly; every other launch greets you.
        if !CommandLine.arguments.contains("--after-update") {
            popup.show(allScreens: showOnAllScreens, style: animationStyle, caption: showTransliteration)
        }
        updater.startAutomaticChecks()
        dhikr.start()
        tasbih.showsReading = showTransliteration
        tasbih.onChange = { [weak self] in self?.updateStatusTitle() }
        updateStatusTitle()
        applyGlobalShortcuts()

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
        popup.show(allScreens: showOnAllScreens, style: animationStyle, caption: showTransliteration)
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
        if skipDhikrWhileSharing && ScreenSharing.isActive() { return false }      // tries again in a couple of minutes
        notchPopup.show(allScreens: showOnAllScreens, showReading: showTransliteration)
        return true
    }

    @objc private func chooseDhikrCount(_ sender: NSMenuItem) { dhikr.perDay = sender.tag }
    @objc private func chooseStartHour(_ sender: NSMenuItem) { dhikr.startHour = sender.tag }
    @objc private func chooseEndHour(_ sender: NSMenuItem) { dhikr.endHour = sender.tag }

    /// "8:00 AM" or "08:00", following the Mac's own clock style. 24 is the end of the day.
    private static func hourLabel(_ hour: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .hour, value: hour % 24, to: calendar.startOfDay(for: Date())) ?? Date()
        let text = date.formatted(date: .omitted, time: .shortened)
        return hour == 24 ? "\(text) (end of day)" : text
    }

    @objc private func showDhikrNow() { notchPopup.show(allScreens: showOnAllScreens, showReading: showTransliteration) }

    // MARK: - menu actions

    @objc private func showBismillah() {
        lastGreeting = Date()
        popup.show(allScreens: showOnAllScreens, style: animationStyle, caption: showTransliteration)
    }

    /// Off by default: the bismillah appears on the screen you are using, the dhikr on the notched screen.
    private var showOnAllScreens: Bool {
        get { UserDefaults.standard.bool(forKey: "ShowOnAllScreens") }
        set { UserDefaults.standard.set(newValue, forKey: "ShowOnAllScreens") }
    }

    @objc private func toggleAllScreens() { showOnAllScreens.toggle() }

    /// How the bismillah appears: faded in and out (the default) or written out by the pen.
    private var animationStyle: BismillahView.Style {
        get { BismillahView.Style(rawValue: UserDefaults.standard.string(forKey: "AnimationStyle") ?? "") ?? .fading }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "AnimationStyle") }
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = BismillahView.Style(rawValue: raw) else { return }
        animationStyle = style
    }

    @objc private func openTasbihCounter() {
        tasbih.showsReading = showTransliteration
        tasbih.toggle(below: statusItem.button?.window?.frame)
    }

    /// The reading of each phrase in Latin letters, under the Arabic, for people still learning to read it. Off by default.
    private var showTransliteration: Bool {
        get { UserDefaults.standard.bool(forKey: "ShowTransliteration") }
        set { UserDefaults.standard.set(newValue, forKey: "ShowTransliteration") }
    }

    @objc private func toggleTransliteration() {
        showTransliteration.toggle()
        tasbih.showsReading = showTransliteration
    }

    /// On by default: a dhikr that comes due while the screen is being shared waits and tries again. Meetings are fine.
    private var skipDhikrWhileSharing: Bool {
        get { UserDefaults.standard.object(forKey: "SkipDhikrWhileSharing") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "SkipDhikrWhileSharing") }
    }

    @objc private func toggleSkipWhileSharing() { skipDhikrWhileSharing.toggle() }

    private func updateStatusTitle() {
        let count = tasbih.count
        statusItem?.button?.title = tasbih.showsCountInMenuBar && count > 0 ? "بسم الله  \(count)" : "بسم الله"
    }

    /// On by default: Control-Option-B shows the bismillah and Control-Option-T opens the counter, from any app.
    private var globalShortcutsOn: Bool {
        get { UserDefaults.standard.object(forKey: "GlobalShortcuts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "GlobalShortcuts") }
    }

    @objc private func toggleGlobalShortcuts() {
        globalShortcutsOn.toggle()
        applyGlobalShortcuts()
    }

    private func applyGlobalShortcuts() {
        guard globalShortcutsOn else { GlobalHotKeys.shared.unregister(); return }
        GlobalHotKeys.shared.register([
            .init(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey) { [weak self] in self?.showBismillah() },
            .init(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in self?.openTasbihCounter() },
        ])
    }

    // MARK: - bismillah:// links

    /// bismillah://show, bismillah://dhikr, bismillah://counter, bismillah://count (adds one to the counter)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "bismillah" {
            switch (url.host ?? url.path).lowercased() {
            case "show": showBismillah()
            case "dhikr": notchPopup.show(allScreens: showOnAllScreens, showReading: showTransliteration)
            case "counter": if !tasbih.isShowing { openTasbihCounter() }
            case "count": tasbih.increment()
            default: break
            }
        }
    }

    @objc private func toggleAutomaticUpdates() {
        updater.automaticEnabled.toggle()
        if updater.automaticEnabled { updater.checkIfDue() }
    }

    @objc private func checkForUpdates() { updater.checkManually() }

    @objc private func openInstagram() {
        if let url = URL(string: "https://www.instagram.com/madebyhafiz/") { NSWorkspace.shared.open(url) }
    }

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
        allScreensItem.state = showOnAllScreens ? .on : .off
        transliterationItem.state = showTransliteration ? .on : .off
        skipShareItem.state = skipDhikrWhileSharing ? .on : .off
        shortcutsItem.state = globalShortcutsOn ? .on : .off
        for item in styleItems { item.state = (item.representedObject as? String) == animationStyle.rawValue ? .on : .off }
        autoUpdateItem.state = updater.automaticEnabled ? .on : .off
        for item in dhikrCountItems { item.state = item.tag == dhikr.perDay ? .on : .off }
        startHourParent.title = "Starts at \(Self.hourLabel(dhikr.startHour))"
        endHourParent.title = "Ends at \(Self.hourLabel(dhikr.endHour))"
        for item in startHourItems {
            item.state = item.tag == dhikr.startHour ? .on : .off
            item.isEnabled = item.tag < dhikr.endHour
        }
        for item in endHourItems {
            item.state = item.tag == dhikr.endHour ? .on : .off
            item.isEnabled = item.tag > dhikr.startHour
        }
        if skipDhikrWhileSharing && ScreenSharing.isActive() {
            dhikrNextItem.title = "Paused while screen sharing"          // also a way to check the detection works for your setup
        } else if let next = dhikr.nextPopup {
            let time = next.formatted(date: .omitted, time: .shortened)
            dhikrNextItem.title = Calendar.current.isDateInToday(next) ? "Next: \(time)" : "Next: tomorrow, \(time)"
        } else {
            dhikrNextItem.title = "No reminders scheduled"
        }
    }
}
