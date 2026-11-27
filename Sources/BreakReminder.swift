import AppKit

/// Notices an unbroken hour at the Mac, so the app can suggest a short tasbih break. Off by default.
///
/// "Unbroken" means keyboard or mouse input with no pause of `breakLength` (5 minutes) or more; locking the screen
/// or sleeping also counts as a break. Only how long ago the last input was is read, never what it was, so no
/// permission is needed. A reminder that can't appear right now waits; nothing is ever queued up.
@MainActor
final class BreakReminder {
    private static let enabledKey = "TasbihBreakReminder"
    private static let ignoredKey = "TasbihBreakIgnored"
    /// After this many reminders in a row without the counter being opened, the next one mentions The Hour.
    static let ignoredBeforeTheHour = 5

    /// How long you have to be at it. `-BreakAfterSeconds 60` on the command line shortens it for testing.
    let after: TimeInterval
    /// This long without input counts as having taken a break.
    private let breakLength: TimeInterval
    private let tickEvery: TimeInterval
    /// The least time between this reminder and a dhikr popup.
    var gap: TimeInterval { min(10 * 60, after / 4) }

    private let defaults: UserDefaults
    private let idleSeconds: () -> TimeInterval
    private let away: () -> Bool                       // locked, or the display is off
    private let show: () -> Bool                       // false = not a good moment, try again shortly

    private var timer: Timer?
    private var activeSince: Date?
    private var lastTick = Date()
    private(set) var lastShown = Date.distantPast

    init(defaults: UserDefaults = .standard, after: TimeInterval? = nil, breakLength: TimeInterval = 5 * 60,
         tickEvery: TimeInterval? = nil, idleSeconds: @escaping () -> TimeInterval = BreakReminder.systemIdleSeconds,
         away: @escaping () -> Bool, show: @escaping () -> Bool) {
        let test = defaults.double(forKey: "BreakAfterSeconds")
        let length = after ?? (test > 0 ? test : 60 * 60)
        self.after = length
        self.breakLength = breakLength
        self.tickEvery = tickEvery ?? min(30, max(1, length / 20))
        self.defaults = defaults
        self.idleSeconds = idleSeconds
        self.away = away
        self.show = show
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey); start() }
    }

    /// The hour is up and the reminder is waiting for a good moment; dhikr popups hold back so it can have one.
    var isDue: Bool {
        guard isEnabled, let since = activeSince else { return false }
        return Date().timeIntervalSince(since) >= after
    }

    /// Call as a reminder appears: whether this one should mention The Hour. It counts as ignored until the counter
    /// is opened.
    func nextMentionsTheHour() -> Bool {
        let ignored = defaults.integer(forKey: Self.ignoredKey)
        let mentions = ignored >= Self.ignoredBeforeTheHour
        defaults.set(mentions ? 0 : ignored + 1, forKey: Self.ignoredKey)
        return mentions
    }

    /// The counter was opened, from the reminder or any other way: nothing has been ignored.
    func counterOpened() { defaults.set(0, forKey: Self.ignoredKey) }

    /// Starts (or stops) watching, with a fresh hour.
    func start() {
        timer?.invalidate()
        timer = nil
        activeSince = nil
        lastTick = Date()
        guard isEnabled else { return }
        let timer = Timer(timeInterval: tickEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        let now = Date()
        let slept = now.timeIntervalSince(lastTick) >= breakLength
        lastTick = now
        let idle = idleSeconds()
        if slept || away() || idle >= breakLength {
            activeSince = nil
            return
        }
        let since = activeSince ?? now
        activeSince = since
        // only while you are actually there to see it
        guard now.timeIntervalSince(since) >= after, idle < 60, show() else { return }
        lastShown = now
        activeSince = now                              // the next one is a full hour from here
    }

    nonisolated static func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)    // any input
    }
}
