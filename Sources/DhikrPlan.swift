import Foundation

/// Picks the random moments for a day's dhikr popups.
enum DhikrPlan {
    /// `count` random times between `start` and `end`, in order.
    ///
    /// The span is cut into `count` equal slices and one time is drawn from the middle 80% of each, so the
    /// popups are random but spread over the whole day rather than bunched together. If the span is too short
    /// to keep `minGap` between popups, fewer are planned.
    static func times(count: Int, from start: Date, to end: Date, minGap: TimeInterval = 15 * 60,
                      using rng: inout some RandomNumberGenerator) -> [Date] {
        let span = end.timeIntervalSince(start)
        guard count > 0, span > 0 else { return [] }
        let n = min(count, max(1, Int(span / minGap)))
        let slice = span / Double(n)
        return (0..<n).map { i in
            let low = slice * (Double(i) + 0.1), high = slice * (Double(i) + 0.9)
            return start.addingTimeInterval(Double.random(in: low...high, using: &rng))
        }
    }
}
