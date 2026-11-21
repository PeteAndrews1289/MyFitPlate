import Foundation

/// A whole-day assertion records exactly which intake was inspected. Source accuracy
/// and micronutrient completeness remain independent of the person's assertion.
public struct NutritionDayReview: Codable, Equatable, Sendable {
    public let version: Int
    public let id: String
    public let ownerID: String
    public let day: DiaryDayContext
    public let status: NutritionDayStatus
    public let intakeFingerprint: String
    public let reviewedAt: Date

    public init(ownerID: String, day: DiaryDayContext, status: NutritionDayStatus, log: DailyLog, at date: Date = Date()) throws {
        guard date.timeIntervalSince1970.isFinite, day.isOwned(by: ownerID), !day.isFuture(now: date),
              log.id == nil || log.id == day.dayKey else { throw NutritionDayReviewError.changed }
        version = 1; id = UUID().uuidString; self.ownerID = ownerID; self.day = day
        self.status = status; intakeFingerprint = try NutritionDayReviewRules.fingerprint(log)
        // Whole seconds survive Date -> Firestore Timestamp -> Date exactly.
        // Receipt equality participates in both the checked write and its server
        // acknowledgement; floating-point subsecond drift must not turn an accepted
        // review into a false conflict. Synthesized decoding keeps legacy dates intact.
        reviewedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

public enum NutritionDayReviewError: LocalizedError {
    case changed
    public var errorDescription: String? { "This day's food or review changed. Open the current day before reviewing it again." }
}

public enum NutritionDayReviewRules {
    private struct Intake: Encodable { let meals: [Meal]; let totalCaloriesOverride: Double? }
    public static func fingerprint(_ log: DailyLog) throws -> String {
        try PlanFingerprint.make(Intake(meals: log.meals, totalCaloriesOverride: log.totalCaloriesOverride))
    }
    public static func isCurrent(_ receipt: NutritionDayReview, in log: DailyLog) -> Bool {
        receipt.version == 1 && !receipt.id.isEmpty && receipt.day.isOwned(by: receipt.ownerID)
            && key(log, timeZone: receipt.day.timeZone) == receipt.day.dayKey
            && receipt.status == log.nutritionDayStatus
            && receipt.intakeFingerprint == (try? fingerprint(log))
    }
    public static func requiresCheckedCommit(_ log: DailyLog) -> Bool {
        guard let data = log.mutationBase else { return log.nutritionDayReview != nil }
        guard let before = try? JSONDecoder().decode(DailyLog.self, from: data) else { return true }
        return before.nutritionDayReview != log.nutritionDayReview
    }
    public static func sameReviewedState(_ lhs: DailyLog, _ rhs: DailyLog) -> Bool {
        guard let leftDay = key(lhs), let rightDay = key(rhs), leftDay == rightDay,
              let left = try? fingerprint(lhs), let right = try? fingerprint(rhs) else { return false }
        return left == right && lhs.nutritionDayStatus == rhs.nutritionDayStatus && lhs.nutritionDayReview == rhs.nutritionDayReview
    }
    /// Checked inside the existing diary transaction. A repeated accepted operation
    /// is handled by its mutation ID before this precondition is evaluated.
    public static func validateChange(before: DailyLog, after: DailyLog, latest: DailyLog, ownerID: String, isUndo: Bool = false) throws {
        guard before.nutritionDayReview != after.nutritionDayReview else { return }
        guard sameReviewedState(before, latest),
              try fingerprint(before) == fingerprint(after) else { throw NutritionDayReviewError.changed }
        if let receipt = after.nutritionDayReview {
            guard receipt.version == 1, !receipt.id.isEmpty, receipt.ownerID == ownerID,
                  receipt.day.isOwned(by: ownerID), receipt.day.dayKey == after.id,
                  receipt.status == after.nutritionDayStatus,
                  !receipt.day.isFuture(now: receipt.reviewedAt) else { throw NutritionDayReviewError.changed }
            if isUndo {
                // Restoring an older stale assertion is legitimate Undo: it remains
                // effectively unknown. Ordinary new reviews must match current food.
                guard let accepted = before.nutritionDayReview, isCurrent(accepted, in: before),
                      receipt.reviewedAt <= accepted.reviewedAt else { throw NutritionDayReviewError.changed }
            } else if !isCurrent(receipt, in: after) { throw NutritionDayReviewError.changed }
        }
    }
    public static func key(_ log: DailyLog, timeZone: TimeZone = .current) -> String? {
        DiaryDayContext(userID: "day-projection", date: log.date, timeZone: timeZone, dayKey: log.id)?.dayKey
    }
    public static func displayDate(_ log: DailyLog, calendar: Calendar = .current) -> Date {
        DiaryDayContext(userID: "day-projection", date: log.date, timeZone: calendar.timeZone, dayKey: log.id)?.displayDate ?? log.date
    }
    /// Includes every requested civil key once. Stored keys win over timestamp offsets.
    /// Existing timestamps are retained; display conversion never mutates the saved day.
    public static func page(_ logs: [DailyLog], through end: Date, count: Int, now: Date = Date(), calendar: Calendar = .current) -> [DailyLog] {
        let end = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now))
        let count = min(31, max(1, count))
        var byDay: [String: DailyLog] = [:]
        for log in logs {
            guard let key = key(log, timeZone: calendar.timeZone) else { continue }
            if byDay[key] == nil || log.date > byDay[key]!.date { byDay[key] = log }
        }
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end),
                  let key = DiaryDayContext.dayKey(for: day, timeZone: calendar.timeZone) else { return nil }
            if var recorded = byDay[key] { if recorded.id == nil { recorded.id = key }; return recorded }
            return DailyLog(id: key, date: day, meals: [])
        }
    }
}
