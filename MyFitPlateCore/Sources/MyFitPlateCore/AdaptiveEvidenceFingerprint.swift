import Foundation

/// Captures all inputs that can alter an estimate, not just its rounded result.
/// Missing/partial days and changed records invalidate an open weekly review.
public enum AdaptiveEvidenceFingerprint {
    private struct Weight: Codable { let id: String; let date: Date; let pounds: Double? }
    private struct Day: Codable {
        let date: Date
        let intake: Double?
        let complete: Bool
        let status: NutritionDayStatus
        let workoutCount: Int
    }
    private struct Inputs: Codable { let start: Date; let end: Date; let weights: [Weight]; let days: [Day] }
    public static func make(weightHistory: [(id: String, date: Date, weight: Double)], dailyLogs: [DailyLog],
                            now: Date = Date(), calendar: Calendar = .current) throws -> String {
        let end = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -20, to: end) else { throw WeeklyTargetReviewError.invalid }
        let weights = weightHistory.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day <= end
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            .map { Weight(id: $0.id, date: $0.date, pounds: $0.weight.isFinite ? $0.weight : nil) }
        let days = NutritionDayEvidence.days(dailyLogs, from: start, through: end, now: now, calendar: calendar).map {
            Day(date: calendar.startOfDay(for: NutritionDayReviewRules.displayDate($0, calendar: calendar)), intake: $0.totalCalories().isFinite ? $0.totalCalories() : nil,
                complete: NutritionDayEvidence.isComplete($0, now: now, calendar: calendar),
                status: NutritionDayEvidence.status(of: $0), workoutCount: $0.exercises?.count ?? 0)
        }
        return try PlanFingerprint.make(Inputs(start: start, end: end, weights: weights, days: days))
    }
}
