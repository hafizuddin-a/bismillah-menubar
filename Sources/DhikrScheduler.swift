import Foundation

/// Decides when the dhikr popup appears: N random times a day, within the active hours (08:00 to 22:00 by default).
///
/// The day's plan is saved, so quitting and reopening the app doesn't reshuffle it or repeat popups. A time
/// that passes while the Mac is asleep or the app is closed is skipped, not shown late. Changing the number
/// mid-day, or the hours, re-plans only the popups still to come (what was already shown today counts toward the total).
@MainActor
final class DhikrScheduler {
    static let perDayKey = "DhikrPerDay"
    static let choices = [0, 1, 3, 5, 10, 15, 20, 30]           // 0 = off

    private static let dayKey = "DhikrDay"
    private static let pendingKey = "DhikrPending"
    private static let shownKey = "DhikrShownToday"

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
    private let show: () -> Bool                       // shows a popup; false = couldn't right now, try again soon
    private let windowOverride: ((Date) -> (start: Date, end: Date))?        // tests only; normally the saved hours
    private let minGap: TimeInterval
    private let lead: TimeInterval                     // plans never start sooner than this from now
    private let grace: TimeInterval                    // how late a popup may still be shown (after sleep)
    private var timer: Timer?
    private var rng = SystemRandomNumberGenerator()

    init(defaults: UserDefaults = .standard,
         window: ((Date) -> (start: Date, end: Date))? = nil,
         minGap: TimeInterval = 15 * 60, lead: TimeInterval = 60, grace: TimeInterval = 10 * 60,
         show: @escaping () -> Bool) {
        self.defaults = defaults
        self.windowOverride = window
        self.minGap = minGap
        self.lead = lead
        self.grace = grace
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
    private var pending: [Date] {
        get { (defaults.array(forKey: Self.pendingKey) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }.sorted() }
        set { defaults.set(newValue.map { $0.timeIntervalSince1970 }, forKey: Self.pendingKey) }
    }

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

    /// Plans what's left of today: the popups still owed, spread over the rest of the active hours.
    private func rebuild() {
        day = Self.dayString(Date())
        let now = Date()
        let hours = window(now)
        let from = max(now.addingTimeInterval(lead), hours.start)
        let owed = max(0, perDay - shownToday)
        pending = from < hours.end ? DhikrPlan.times(count: owed, from: from, to: hours.end, minGap: minGap, using: &rng) : []
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = nil
        guard perDay > 0 else { return }
        rollDayIfNeeded()
        let now = Date()
        pending = pending.filter { $0 > now.addingTimeInterval(-grace) }       // slept through these: skip
        // nothing left today: wake up at the start of tomorrow's hours (never "now", which would spin)
        let tomorrowStart = window(tomorrow(after: now)).start
        let due = pending.first ?? (tomorrowStart > now ? tomorrowStart : now.addingTimeInterval(3600))
        let timer = Timer(fire: due, interval: 0, repeats: false) { [weak self] _ in
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
            if now.timeIntervalSince(first) <= grace {
                if show() {
                    shownToday += 1
                } else if now.addingTimeInterval(120) < window(now).end {        // busy or locked: try again in a bit
                    queue.insert(now.addingTimeInterval(120), at: 0)
                }
            }
        }
        pending = queue
        scheduleNext()
    }
}
