import Foundation

public enum RunActivityTimerRules {
    public static let freshnessSeconds: TimeInterval = 25

    public static func freshnessDeadline(reportedAt: Date?) -> Date? {
        guard let reportedAt, reportedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let deadline = reportedAt.addingTimeInterval(freshnessSeconds)
        return deadline.timeIntervalSinceReferenceDate.isFinite && deadline > reportedAt ? deadline : nil
    }

    /// The numeric clock has its own fixed bound. A delayed OS stale-context update
    /// cannot keep counting for hours after the recording process has disappeared.
    public static func elapsedInterval(startTime: Date, reportedAt: Date?) -> ClosedRange<Date>? {
        guard startTime.timeIntervalSinceReferenceDate.isFinite, let reportedAt,
              startTime <= reportedAt, let deadline = freshnessDeadline(reportedAt: reportedAt) else { return nil }
        return startTime...deadline
    }

    public static func isFresh(reportedAt: Date?, now: Date = Date()) -> Bool {
        guard let reportedAt, now.timeIntervalSinceReferenceDate.isFinite,
              let deadline = freshnessDeadline(reportedAt: reportedAt) else { return false }
        return now >= reportedAt && now < deadline
    }
}
