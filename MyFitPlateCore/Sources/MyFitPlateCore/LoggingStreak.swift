import Foundation

/// The Home-screen logging streak, computed kindly: a single missed day bends the streak
/// (it doesn't count, but doesn't break it) — two consecutive missed days end it. An
/// unlogged *today* never punishes a morning open; the streak just waits.
public enum LoggingStreak {

    /// - Parameters:
    ///   - loggedDays: days with at least one food item logged (any time component; normalized internally).
    ///   - today: "now", injectable for tests.
    /// - Returns: the current streak length in logged days (0 when the streak is broken).
    public static func currentStreak(
        loggedDays: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(loggedDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let todayStart = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return 0 }

        // Anchor: today if logged, else yesterday (today still in progress), else the
        // grace day reaches back to the day before yesterday.
        let anchor: Date
        if days.contains(todayStart) {
            anchor = todayStart
        } else if days.contains(yesterday) {
            anchor = yesterday
        } else if let dayBefore = calendar.date(byAdding: .day, value: -2, to: todayStart),
                  days.contains(dayBefore) {
            // Yesterday was the single allowed miss; the streak survives but today must
            // be logged to keep it alive tomorrow.
            anchor = dayBefore
        } else {
            return 0
        }

        var streak = 0
        var cursor = anchor
        var graceUsed = false

        while true {
            if days.contains(cursor) {
                streak += 1
            } else if !graceUsed {
                graceUsed = true
            } else {
                break
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            // Two consecutive misses end the walk.
            if !days.contains(cursor) && !days.contains(previous) { break }
            cursor = previous
        }

        return streak
    }

    /// True when today is unlogged and the streak survives only via the grace day —
    /// the UI can nudge ("log today to keep your streak").
    public static func isOnGraceDay(
        loggedDays: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let days = Set(loggedDays.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)
        guard !days.contains(todayStart),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return false
        }
        return !days.contains(yesterday) && currentStreak(loggedDays: loggedDays, today: today, calendar: calendar) > 0
    }
}
