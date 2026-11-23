import Foundation

/// Decides when the dhikr popup appears: N random times a day, within the active hours (08:00 to 22:00 by default).
///
/// The day's plan is saved, so quitting and reopening the app doesn't reshuffle it or repeat popups. A popup is
/// never shown late and never queued: if one comes due while you are away (Mac asleep, app closed, screen locked
/// or off, sharing your screen), it is dropped, and once you are back the popups still owed for the day (your
/// number minus what was shown) are planned afresh over the rest of the active hours, starting a few minutes
/// after you return. Late in the day they are packed a little closer, never under `squeezeGap` apart, so the
/// day's total still adds up when it can. Changing the number mid-day, or the hours, re-plans the same way.
@MainActor
final class DhikrScheduler {
    static let perDayKey = "DhikrPerDay"
    static let choices = [0, 1, 3, 5, 10, 15, 20, 30]           // 0 = off

    private static let dayKey = "DhikrDay"
    private static let pendingKey = "DhikrPending"
    private static let shownKey = "DhikrShownToday"
    private static let missedKey = "DhikrMissed"

    static let startHourKey = "DhikrStartHour"
    static let endHourKey = "DhikrEndHour"
    static let defaultStartHour = 8
    static let defaultEndHour = 22
    static let startHourChoices = Array(0...23)
    static let endHourChoices = Array(1...24)              // 24 = midnight at the end of the day

    /// The active hours on the day containing `date`: `startHour` o'clock to `endHour` o'clock.
    nonisolated static func hours(from startHour: Int, to endHour: Int, on date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: startHour, to: midnight) ?? midnight.addingTimeInterval(Double(startHour) * 3600)
        let end = calendar.date(byAdding: .hour, value: endHour, to: midnight) ?? midnight.addingTimeInterval(Double(endHour) * 3600)
        return (start, end)
    }

    private let defaults: UserDefaults
    private let available: () -> Bool                  // is this a moment a popup could be shown (not locked, asleep, sharing)?
    private let show: () -> Bool                       // shows a popup; false = couldn't right now
    private let windowOverride: ((Date) -> (start: Date, end: Date))?        // tests only; normally the saved hours
    private let minGap: TimeInterval
    private let squeezeGap: TimeInterval               // the closest popups are packed when the rest of the day is short
    private let lead: TimeInterval                     // plans never start sooner than this from now
    private let returnLead: TimeInterval               // after you come back, nothing appears for at least this long
    private let retryEvery: TimeInterval               // while you are away, how often to look whether you are back
    private let grace: TimeInterval                    // how late a popup may still be shown (after sleep)
    private var timer: Timer?
    private var rng = SystemRandomNumberGenerator()

    init(defaults: UserDefaults = .standard,
         window: ((Date) -> (start: Date, end: Date))? = nil,
         minGap: TimeInterval = 15 * 60, squeezeGap: TimeInterval = 5 * 60, lead: TimeInterval = 60,
         returnLead: TimeInterval = 3 * 60, retryEvery: TimeInterval = 120, grace: TimeInterval = 10 * 60,
         available: @escaping () -> Bool = { true }, show: @escaping () -> Bool) {
        self.defaults = defaults
        self.windowOverride = window
        self.minGap = minGap
        self.squeezeGap = squeezeGap
        self.lead = lead
        self.returnLead = returnLead
        self.retryEvery = retryEvery
        self.grace = grace
        self.available = available
        self.show = show
    }

    // MARK: - settings and state

    /// Popups per day; 0 turns them off.
    var perDay: Int {
        get { defaults.integer(forKey: Self.perDayKey) }
        set {
            guard newValue != perDay else { return }
            defaults.set(newValue, forKey: Self.perDayKey)
            rebuild()
            scheduleNext()
        }
    }

    /// The hour popups may start appearing, 0...23.
    var startHour: Int {
        get { min(max(defaults.object(forKey: Self.startHourKey) as? Int ?? Self.defaultStartHour, 0), 23) }
        set {
            let hour = min(max(newValue, 0), 23)
            guard hour != startHour else { return }
            defaults.set(hour, forKey: Self.startHourKey)
            if hour >= endHour { defaults.set(min(hour + 1, 24), forKey: Self.endHourKey) }      // keep start before end
            hoursChanged()
        }
    }

    /// The hour popups stop, 1...24 (24 = midnight at the end of the day).
    var endHour: Int {
        get { min(max(defaults.object(forKey: Self.endHourKey) as? Int ?? Self.defaultEndHour, 1), 24) }
        set {
            let hour = min(max(newValue, 1), 24)
            guard hour != endHour else { return }
            defaults.set(hour, forKey: Self.endHourKey)
            if hour <= startHour { defaults.set(max(hour - 1, 0), forKey: Self.startHourKey) }
            hoursChanged()
        }
    }

    private func hoursChanged() {
        guard perDay > 0 else { return }
        rebuild()
        scheduleNext()
    }

    /// The active hours on the day containing `date`.
    private func window(_ date: Date) -> (start: Date, end: Date) {
        windowOverride?(date) ?? Self.hours(from: startHour, to: endHour, on: date)
    }

    private var day: String {
        get { defaults.string(forKey: Self.dayKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.dayKey) }
    }
    private var shownToday: Int {
        get { defaults.integer(forKey: Self.shownKey) }
        set { defaults.set(newValue, forKey: Self.shownKey) }
    }
    /// Popups that came due while you were away and are waiting to be re-planned.
    private var missed: Int {
        get { defaults.integer(forKey: Self.missedKey) }
        set { defaults.set(newValue, forKey: Self.missedKey) }
    }
    private var pending: [Date] {
        get { (defaults.array(forKey: Self.pendingKey) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }.sorted() }
        set { defaults.set(newValue.map { $0.timeIntervalSince1970 }, forKey: Self.pendingKey) }
    }

    /// True while popups are waiting to be re-planned for when you are back, so there is no exact time to show yet.
    var isCatchingUp: Bool { perDay > 0 && missed > 0 }

    /// When the next popup is due, for the menu. nil when they're off.
    var nextPopup: Date? {
        guard perDay > 0 else { return nil }
        return pending.first ?? window(tomorrow(after: Date())).start
    }

    // MARK: - scheduling

    /// Call at launch, and again after the Mac wakes (the clock may have jumped).
    func start() { scheduleNext() }

    private static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func tomorrow(after date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
    }

    private func rollDayIfNeeded() {
        let today = Self.dayString(Date())
        guard day != today else { return }
        day = today
        shownToday = 0
        rebuild()
    }

    /// Plans what's left of today: the popups still owed, spread over the rest of the active hours. Anything that
    /// was waiting to be made up is covered by this, since the popups owed are the number chosen minus those shown.
    private func rebuild(lead: TimeInterval? = nil) {
        day = Self.dayString(Date())
        missed = 0
        let now = Date()
        let hours = window(now)
        let from = max(now.addingTimeInterval(lead ?? self.lead), hours.start)
        let owed = max(0, perDay - shownToday)
        pending = from < hours.end
            ? DhikrPlan.fitting(count: owed, from: from, to: hours.end, minGap: minGap, squeezeGap: squeezeGap, using: &rng)
            : []
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = nil
        guard perDay > 0 else { return }
        rollDayIfNeeded()
        let now = Date()
        let kept = pending.filter { $0 > now.addingTimeInterval(-grace) }
        if kept.count < pending.count {                       // slept through these, or the app was closed
            missed += pending.count - kept.count
            pending = kept
        }
        if missed > 0 {
            if now >= window(now).end {                       // the day is over: tomorrow starts fresh
                missed = 0
                pending = []
            } else if available() {                           // you're back: plan what's owed over the rest of the day
                rebuild(lead: returnLead)
            } else {                                          // still away: nothing queues up, look again in a bit
                pending = []
                fire(at: now.addingTimeInterval(retryEvery))
                return
            }
        }
        // nothing left today: wake up at the start of tomorrow's hours (never "now", which would spin)
        let tomorrowStart = window(tomorrow(after: now)).start
        fire(at: pending.first ?? (tomorrowStart > now ? tomorrowStart : now.addingTimeInterval(3600)))
    }

    private func fire(at date: Date) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.timerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerFired() {
        rollDayIfNeeded()
        let now = Date()
        var queue = pending
        if let first = queue.first, first <= now.addingTimeInterval(1) {
            queue.removeFirst()
            if now.timeIntervalSince(first) <= grace, show() {
                shownToday += 1
            } else {
                missed += 1                                   // couldn't: made up once you are back, not retried
            }
        }
        pending = queue
        scheduleNext()
    }
}
