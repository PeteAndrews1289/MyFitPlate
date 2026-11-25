import Foundation

public struct AdaptiveWeightEvidence: Codable, Equatable, Identifiable {
    public let id: String
    public let date: Date
    public let pounds: Double
    public init(id: String, date: Date, pounds: Double) { self.id = id; self.date = date; self.pounds = pounds }
    public var fingerprint: String { (try? PlanFingerprint.make(self)) ?? "" }
}

public struct AdaptiveIntakeEvidence: Codable, Equatable {
    public let date: Date
    public let calories: Double?
    public let complete: Bool
    public init(date: Date, calories: Double?, complete: Bool) {
        self.date = date; self.calories = calories; self.complete = complete
    }
}

/// Records the inspected inputs. These are evidence copies, never edits to weight or diary history.
public struct AdaptiveEstimateInputs: Codable, Equatable {
    public let start: Date
    public let end: Date
    public let weights: [AdaptiveWeightEvidence]
    public let intake: [AdaptiveIntakeEvidence]
    public init(weights: [AdaptiveWeightEvidence], intake: [AdaptiveIntakeEvidence], now: Date = Date(), calendar: Calendar = .current) {
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -41, to: end) ?? end
        self.end = end; self.start = start
        self.weights = weights.filter { $0.date >= start && calendar.startOfDay(for: $0.date) <= end && $0.pounds.isFinite && $0.pounds > 0 }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        self.intake = intake.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
    }
    public init(weightHistory: [(id: String, date: Date, weight: Double)], dailyLogs: [DailyLog], now: Date = Date(), calendar: Calendar = .current) {
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -41, to: end) ?? end
        self.init(weights: weightHistory.map { AdaptiveWeightEvidence(id: $0.id, date: $0.date, pounds: $0.weight) },
                  intake: NutritionDayEvidence.days(dailyLogs, from: start, through: end, now: now, calendar: calendar).map {
                    AdaptiveIntakeEvidence(date: calendar.startOfDay(for: NutritionDayReviewRules.displayDate($0, calendar: calendar)),
                        calories: $0.totalCalories().isFinite ? $0.totalCalories() : nil,
                        complete: NutritionDayEvidence.isComplete($0, now: now, calendar: calendar))
                  }, now: now, calendar: calendar)
    }
}

public struct AdaptiveWeightExclusion: Codable, Equatable, Identifiable {
    public var id: String { source.id }
    public let source: AdaptiveWeightEvidence
    public let reason: String
    public let reviewedAt: Date
}

public struct AdaptiveEvidenceReview: Codable, Equatable {
    public var revision: Int = 0
    public var excludedWeights: [AdaptiveWeightExclusion] = []
    public init() {}
    public func excludes(_ weight: AdaptiveWeightEvidence) -> Bool { excludedWeights.contains { $0.source == weight } }
}

/// A robustness comparison, not a second prescribed target or a physiological confidence interval.
/// The long-standing energy-balance coefficient is retained solely for like-for-like comparison.
/// Water shifts and intake error remain unresolved; no population accuracy claim follows.
public struct AdaptiveShadowEstimate: Codable, Equatable {
    public static let version = "robust-pair-slope-shadow-v2"
    public let estimatedBurn: Double?
    public let slopeSpreadCalories: Double?
    public let evidenceDays: Int
    public let completeDays: Int
    public let weighInDays: Int
    public let message: String

    public static func calculate(inputs: AdaptiveEstimateInputs, review: AdaptiveEvidenceReview,
                                 goalChangedAt: Date? = nil, calendar: Calendar = .current) -> Self {
        var byDay: [Date: AdaptiveWeightEvidence] = [:]
        for weight in inputs.weights where !review.excludes(weight) {
            let day = calendar.startOfDay(for: weight.date)
            guard goalChangedAt.map({ day >= calendar.startOfDay(for: $0) }) ?? true else { continue }
            byDay[day] = weight
        }
        let dates = byDay.keys.sorted()
        let start = max(inputs.start, dates.first ?? inputs.end)
        let span = (calendar.dateComponents([.day], from: start, to: inputs.end).day ?? 0) + 1
        let complete = inputs.intake.filter { $0.date >= start && $0.complete && ($0.calories.map { $0.isFinite && $0 >= 0 } ?? false) }
        func result(_ message: String, burn: Double? = nil, spread: Double? = nil) -> Self {
            Self(estimatedBurn: burn, slopeSpreadCalories: spread, evidenceDays: span,
                 completeDays: complete.count, weighInDays: dates.count, message: message)
        }
        guard span >= 21, dates.count >= 12 else {
            return result(goalChangedAt == nil ? "Comparison needs at least 21 days and 12 weigh-in days." : "Building evidence after the change in goal intent.")
        }
        guard Double(complete.count) / Double(span) >= 0.8 else {
            return result("Comparison paused: fewer than 80% of days are confirmed complete. Missing intake is not treated as zero.")
        }
        var gaps = zip(dates, dates.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? span }
        gaps.append(calendar.dateComponents([.day], from: dates.last ?? inputs.end, to: inputs.end).day ?? span)
        guard (gaps.max() ?? span) <= 7 else { return result("Comparison paused because the weigh-in record has a gap longer than a week.") }
        var slopes = WeightTrendRules.sortedSlopes(Array(byDay.values), minimumSeparationDays: 7, calendar: calendar)
        guard !slopes.isEmpty else { return result("Comparison needs weigh-ins separated by at least a week.") }
        slopes.sort()
        func quantile(_ q: Double) -> Double { slopes[min(slopes.count - 1, Int(Double(slopes.count - 1) * q))] }
        let average = complete.compactMap(\.calories).reduce(0, +) / Double(complete.count)
        let burn = average - quantile(0.5) * 3_500
        let spread = abs(quantile(0.9) - quantile(0.1)) * 3_500
        guard burn.isFinite, (1_000...5_000).contains(burn) else { return result("Comparison falls outside the supported range; inspect the underlying records.") }
        guard spread <= 500 else { return result("Comparison is unstable across the observed weight slopes. No target is inferred.", spread: spread) }
        return result("Robust comparison only. Weight-slope spread does not measure food-log accuracy or physiological uncertainty.", burn: burn, spread: spread)
    }
}

public struct AdaptiveEstimateRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public let userID: String
    public let calculatedAt: Date
    public let inputFingerprint: String
    public let baselineVersion: String
    public let baseline: AdaptiveGoalService.ExpenditureSnapshot
    public let inputs: AdaptiveEstimateInputs
    public let review: AdaptiveEvidenceReview
    public let goalIntent: String
    public let goalChangedAt: Date?
    public let shadow: AdaptiveShadowEstimate
    public init(userID: String, inputs: AdaptiveEstimateInputs, review: AdaptiveEvidenceReview,
                baseline: AdaptiveGoalService.ExpenditureSnapshot, goalIntent: String, previous: Self?, now: Date = Date()) throws {
        guard !userID.isEmpty else { throw WeeklyTargetReviewError.accountChanged }
        id = UUID(); self.userID = userID; calculatedAt = now
        self.inputs = inputs; self.review = review; self.baseline = baseline
        baselineVersion = "complete-days-linear-v1"; self.goalIntent = goalIntent
        goalChangedAt = previous.map { $0.goalIntent != goalIntent ? now : $0.goalChangedAt } ?? nil
        inputFingerprint = try PlanFingerprint.make(inputs) + ":" + PlanFingerprint.make(review) + ":" + goalIntent
        shadow = .calculate(inputs: inputs, review: review, goalChangedAt: goalChangedAt)
    }
}

@MainActor
public final class AdaptiveEstimateHistoryStore {
    private let store: EditorDraftStore
    private let historyScope = "adaptive-estimate-history-v1"
    private let reviewScope = "adaptive-evidence-review-v1"
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func records(userID: String) throws -> [AdaptiveEstimateRecord] {
        let records = try store.load([AdaptiveEstimateRecord].self, userID: userID, scope: historyScope)?.value ?? []
        guard records.allSatisfy({ $0.userID == userID }) else { throw WeeklyTargetReviewError.accountChanged }
        return records
    }
    public func review(userID: String) throws -> AdaptiveEvidenceReview {
        try store.load(AdaptiveEvidenceReview.self, userID: userID, scope: reviewScope)?.value ?? AdaptiveEvidenceReview()
    }
    public func record(_ record: AdaptiveEstimateRecord, currentUserID: String?) throws {
        guard record.userID == currentUserID else { throw WeeklyTargetReviewError.accountChanged }
        var existing = try records(userID: record.userID)
        if let latest = existing.first, latest.inputFingerprint == record.inputFingerprint,
           latest.baselineVersion == record.baselineVersion,
           Calendar.current.isDate(latest.calculatedAt, inSameDayAs: record.calculatedAt) { return }
        existing.insert(record, at: 0)
        try store.save(existing, userID: record.userID, scope: historyScope)
    }
    public func setExclusion(_ weight: AdaptiveWeightEvidence, excluded: Bool, reason: String,
                             userID: String, currentUserID: String?, expectedRevision: Int, now: Date = Date()) throws {
        guard userID == currentUserID else { throw WeeklyTargetReviewError.accountChanged }
        var current = try review(userID: userID)
        guard current.revision == expectedRevision,
              try records(userID: userID).first?.inputs.weights.contains(weight) == true else { throw WeeklyTargetReviewError.changed }
        let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !excluded || !note.isEmpty && note.count <= 200 else { throw WeeklyTargetReviewError.invalid }
        current.excludedWeights.removeAll { $0.id == weight.id }
        if excluded { current.excludedWeights.append(AdaptiveWeightExclusion(source: weight, reason: note, reviewedAt: now)) }
        current.excludedWeights.sort { $0.id < $1.id }; current.revision += 1
        try store.save(current, userID: userID, scope: reviewScope)
    }
}
