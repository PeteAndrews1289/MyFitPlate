import Foundation

public enum WorkoutActivityTimerRules {
    /// Widget state can outlive its deadline while the app is suspended. Never build
    /// Date()...deadline when that would be a reversed ClosedRange and trap the extension.
    public static func restInterval(endingAt deadline: Date, now: Date = Date()) -> ClosedRange<Date> {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            let fallback = Date(timeIntervalSince1970: 0)
            return fallback...fallback
        }
        guard deadline.timeIntervalSinceReferenceDate.isFinite else { return now...now }
        return min(now, deadline)...deadline
    }
}
