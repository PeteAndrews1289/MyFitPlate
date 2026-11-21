import Foundation

/// A user's assessment of the whole day, independent of a food's source or accuracy.
public enum NutritionDayStatus: String, Codable, CaseIterable, Sendable {
    case unknown, complete, partial

    public var title: String {
        switch self {
        case .unknown: return "Not reviewed"
        case .complete: return "Fully logged"
        case .partial: return "Partly logged"
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

public enum NutritionDayEvidence {
    /// Older logs remain unknown. A low total alone cannot distinguish a light day
    /// from missing meals; source confidence cannot establish whole-day completeness.
    public static func status(of log: DailyLog) -> NutritionDayStatus {
        if let review = log.nutritionDayReview, !NutritionDayReviewRules.isCurrent(review, in: log) { return .unknown }
        return log.nutritionDayStatus ?? .unknown
    }

    /// Derived analysis/display identity only. The saved timestamp and source bytes
    /// remain unchanged; a valid canonical diary key wins when the device travels.
    public static func civilDate(for log: DailyLog, calendar: Calendar = .current) -> Date? {
        guard log.date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return calendar.startOfDay(for: NutritionDayReviewRules.displayDate(log, calendar: calendar))
    }

    public static func isComplete(_ log: DailyLog, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let day = civilDate(for: log, calendar: calendar), day <= calendar.startOfDay(for: now), status(of: log) == .complete else { return false }
        let macros = log.totalMacros()
        guard [log.totalCalories(), macros.protein, macros.carbs, macros.fats].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        return log.meals.flatMap(\.foodItems).allSatisfy { food in
            [food.calories, food.protein, food.carbs, food.fats].allSatisfy { $0.isFinite && $0 >= 0 }
        }
    }

    /// The AI receives totals only for reviewed days. Missing intake cannot become
    /// an apparent deficit through a model-generated average.
    public static func historicalSummary(_ logs: [DailyLog], now: Date = Date(), calendar: Calendar = .current) -> String {
        let window = days(logs, from: logs.compactMap { civilDate(for: $0, calendar: calendar) }.min() ?? now, through: now, now: now, calendar: calendar)
        let confirmed = window.filter { isComplete($0, now: now, calendar: calendar) }.count
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let rows = window.map { log -> String in
            let day = NutritionDayReviewRules.key(log, timeZone: calendar.timeZone)
                ?? formatter.string(from: civilDate(for: log, calendar: calendar) ?? log.date)
            guard isComplete(log, now: now, calendar: calendar) else {
                return "- \(day): \(status(of: log).title); excluded from intake analysis."
            }
            let macros = log.totalMacros()
            func amount(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
            let fiber = log.micronutrientCoverage(for: .fiber).hasReportedData ? amount(log.totalMicronutrient(.fiber)) + "g" : "not reported"
            let sodium = log.micronutrientCoverage(for: .sodium).hasReportedData ? amount(log.totalMicronutrient(.sodium)) + "mg" : "not reported"
            return "- \(day): Fully logged. Cals: \(amount(log.totalCalories())), P: \(amount(macros.protein))g, C: \(amount(macros.carbs))g, F: \(amount(macros.fats))g, Fiber: \(fiber), Sodium: \(sodium)"
        }
        return "Confirmed nutrition coverage: \(confirmed) of \(window.count) recorded days.\n" + rows.joined(separator: "\n")
    }

    /// Use one record per canonical civil day, bounded by the requested window and
    /// today. Legacy records without a canonical key retain their timestamp day.
    public static func days(_ logs: [DailyLog], from start: Date, through end: Date, now: Date = Date(), calendar: Calendar = .current) -> [DailyLog] {
        let first = calendar.startOfDay(for: start)
        let last = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now))
        var byDay: [Date: DailyLog] = [:]
        for log in logs {
            guard let day = civilDate(for: log, calendar: calendar) else { continue }
            if day >= first && day <= last, byDay[day] == nil || log.date > (byDay[day]?.date ?? .distantPast) {
                byDay[day] = log
            }
        }
        return byDay.keys.sorted().compactMap { byDay[$0] }
    }
}
