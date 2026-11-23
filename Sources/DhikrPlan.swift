import Foundation

/// Picks the random moments for a day's dhikr popups.
enum DhikrPlan {
    /// `count` random times between `start` and `end`, in order.
    ///
    /// The span is cut into `count` equal slices and one time is drawn from the middle 80% of each, so the
    /// popups are random but spread over the whole day rather than bunched together. If the span is too short
    /// for slices of `minGap`, fewer are planned. `separation` keeps neighbouring popups at least that far apart
    /// (it widens the margins of each slice, so it needs slices at least that long); 0 keeps the plain 80%.
    static func times(count: Int, from start: Date, to end: Date, minGap: TimeInterval = 15 * 60,
                      separation: TimeInterval = 0, using rng: inout some RandomNumberGenerator) -> [Date] {
        let span = end.timeIntervalSince(start)
        guard count > 0, span > 0 else { return [] }
        let n = min(count, max(1, Int(span / minGap)))
        let slice = span / Double(n)
        let margin = min(max(slice * 0.1, separation / 2), slice / 2)
        return (0..<n).map { i in
            let low = slice * Double(i) + margin, high = slice * Double(i + 1) - margin
            return start.addingTimeInterval(Double.random(in: low...high, using: &rng))
        }
    }

    /// Like `times`, but tries to fit all `count` popups in: when the span is too short for the usual spacing
    /// (`minGap`), it packs them closer, though never closer than `squeezeGap` apart. Only if even that doesn't
    /// fit are fewer planned.
    static func fitting(count: Int, from start: Date, to end: Date, minGap: TimeInterval = 15 * 60,
                        squeezeGap: TimeInterval = 5 * 60, using rng: inout some RandomNumberGenerator) -> [Date] {
        let usual = times(count: count, from: start, to: end, minGap: minGap, using: &rng)
        guard usual.count < count, squeezeGap < minGap else { return usual }
        return times(count: count, from: start, to: end, minGap: squeezeGap, separation: squeezeGap, using: &rng)
    }
}
