import Foundation

/// A dated snapshot of an accepted goal. Earlier periods are never rewritten when
/// targets or display units change. Observed legacy goals deliberately start now:
/// an account's profile update time cannot prove when its weight goal began.
public struct WeightGoalPeriod: Codable, Equatable, Identifiable {
    public enum Source: String, Codable { case observed, accepted }
    public struct Selection: Codable, Equatable {
        public let intent: String
        public let targetPounds: Double?
        public let weeklyChangePounds: Double
        public let metricAtAcceptance: Bool
        public let acceptedCalories: Double?
        public init(intent: String, targetPounds: Double?, weeklyChangePounds: Double,
                    metricAtAcceptance: Bool, acceptedCalories: Double? = nil) {
            self.intent = intent; self.targetPounds = targetPounds
            self.weeklyChangePounds = weeklyChangePounds; self.metricAtAcceptance = metricAtAcceptance
            self.acceptedCalories = acceptedCalories
        }
        public var desiredWeeklyChange: Double {
            switch intent.lowercased() {
            case "lose": return -weeklyChangePounds
            case "gain": return weeklyChangePounds
            default: return 0
            }
        }
        var isValid: Bool {
            ["lose", "gain", "maintain"].contains(intent.lowercased())
                && weeklyChangePounds.isFinite && (0...5).contains(weeklyChangePounds)
                && (targetPounds == nil || (targetPounds!.isFinite && targetPounds! > 0))
                && (acceptedCalories == nil || (acceptedCalories!.isFinite && acceptedCalories! > 0))
        }
        /// A formula recalculation or ordinary weigh-in does not start a new goal.
        func sameGoal(as other: Self) -> Bool {
            intent.lowercased() == other.intent.lowercased() && targetPounds == other.targetPounds
                && weeklyChangePounds == other.weeklyChangePounds && metricAtAcceptance == other.metricAtAcceptance
        }
    }
    public let id: UUID
    public let ownerID: String
    public let recordedAt: Date
    public let selection: Selection
    public let source: Source
    public init(id: UUID = UUID(), ownerID: String, recordedAt: Date, selection: Selection, source: Source) {
        self.id = id; self.ownerID = ownerID; self.recordedAt = recordedAt
        self.selection = selection; self.source = source
    }
}

@MainActor
public final class WeightGoalHistoryStore {
    private let drafts: EditorDraftStore
    private let scope = "weight-goal-periods-v1"
    public init(drafts: EditorDraftStore = EditorDraftStore()) { self.drafts = drafts }
    public func load(userID: String, currentUserID: String?) throws -> [WeightGoalPeriod] {
        guard !userID.isEmpty, userID == currentUserID else { throw CocoaError(.fileReadNoPermission) }
        let records = try drafts.load([WeightGoalPeriod].self, userID: userID, scope: scope)?.value ?? []
        guard Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ $0.ownerID == userID && $0.selection.isValid && $0.recordedAt.timeIntervalSince1970.isFinite }),
              zip(records, records.dropFirst()).allSatisfy({ $0.0.recordedAt <= $0.1.recordedAt }) else { throw CocoaError(.coderReadCorrupt) }
        return records
    }
    @discardableResult
    public func record(userID: String, currentUserID: String?, selection: WeightGoalPeriod.Selection,
                       source: WeightGoalPeriod.Source, now: Date = Date()) throws -> [WeightGoalPeriod] {
        var records = try load(userID: userID, currentUserID: currentUserID)
        guard selection.isValid, now.timeIntervalSince1970.isFinite else { throw CocoaError(.coderInvalidValue) }
        if let previous = records.last {
            guard now >= previous.recordedAt else { throw CocoaError(.coderInvalidValue) }
            if previous.selection.sameGoal(as: selection) { return records }
        }
        records.append(.init(ownerID: userID, recordedAt: now, selection: selection, source: source))
        try drafts.save(records, userID: userID, scope: scope, now: now)
        return records
    }
}

extension GoalSettings {
    /// Called only after a checked save or hydration of persisted goals; never while
    /// editing a preview. A local history failure must not report a cloud save as failed.
    @MainActor public var weightGoalSelection: WeightGoalPeriod.Selection {
        .init(intent: goal, targetPounds: targetWeight, weeklyChangePounds: weeklyChangeLbs,
              metricAtAcceptance: BodyUnits.prefersMetric(), acceptedCalories: calories)
    }
    @MainActor public func captureWeightGoalPeriod(userID: String, source: WeightGoalPeriod.Source,
                                                   selection: WeightGoalPeriod.Selection? = nil) {
        guard isActiveAccount(userID), selection.map({ $0.sameGoal(as: weightGoalSelection) }) ?? true else { return }
        do {
            weightGoalPeriods = try WeightGoalHistoryStore().record(userID: userID,
                currentUserID: DIContainer.shared.authService.currentUserID,
                selection: selection ?? weightGoalSelection, source: source)
            weightGoalHistoryNotice = nil
        } catch {
            weightGoalHistoryNotice = "Goal history could not be updated on this device. Your saved targets and measurements are unchanged."
        }
    }
}

/// Descriptive scenario ranges only. This has no connection to the active calorie
/// estimator and does not recommend or change a target.
public enum WeightGoalComparisonRules {
    public static let version = "goal-period-slope-scenarios-v1"
    public struct Comparison: Equatable {
        public let desiredWeeklyChange: Double
        public let observedWeeklyChange: Double?
        public let measuredDays: Int
        public let spanDays: Int
        public let projectedPounds: ClosedRange<Double>?
        public let projectionDate: Date?
        public let explanation: String
    }
    public static func evaluate(period: WeightGoalPeriod, samples: [AdaptiveWeightEvidence],
                                asOf: Date = Date(), calendar: Calendar = .current) -> Comparison {
        let recentStart = calendar.date(byAdding: .day, value: -41, to: calendar.startOfDay(for: asOf)) ?? asOf
        let start = max(period.recordedAt, recentStart)
        let input = samples.filter { $0.date >= start && $0.date <= asOf }
        let trend = WeightTrendRules.project(input, calendar: calendar)
        let desired = period.selection.desiredWeeklyChange
        let observed = trend.measuredDays >= 3 && trend.spanDays >= 8 ? trend.ratePerDay.map { $0 * 7 } : nil
        func result(_ reason: String, range: ClosedRange<Double>? = nil, date: Date? = nil) -> Comparison {
            .init(desiredWeeklyChange: desired, observedWeeklyChange: observed,
                  measuredDays: trend.measuredDays, spanDays: trend.spanDays,
                  projectedPounds: range, projectionDate: date, explanation: reason)
        }
        guard period.selection.isValid, asOf >= period.recordedAt else { return result("The goal period is unavailable.") }
        guard trend.measuredDays >= 12, trend.spanDays >= 21 else {
            return result("A scenario range needs at least 12 measured days spanning 21 days within this goal period. Earlier goals are kept separate.")
        }
        guard trend.largestGapDays <= 7, let latest = trend.points.last,
              let freshness = calendar.dateComponents([.day], from: latest.date, to: asOf).day, freshness <= 3 else {
            return result("A recent weigh-in and no gaps longer than a week are needed for a scenario range.")
        }
        let slopes = WeightTrendRules.sortedSlopes(input, calendar: calendar)
        guard !slopes.isEmpty else { return result("There is not enough comparable weight evidence yet.") }
        let low = slopes[Int(Double(slopes.count - 1) * 0.1)]
        let high = slopes[Int(Double(slopes.count - 1) * 0.9)]
        guard low.isFinite, high.isFinite, max(abs(low), abs(high)) * 7 <= 3,
              (high - low) * 7 <= 2 else { return result("Recent weight rates vary too widely for a useful short-term scenario range.") }
        let horizon = 14 + max(0, freshness)
        let lower = latest.pounds + low * Double(horizon)
        let upper = latest.pounds + high * Double(horizon)
        guard lower.isFinite, upper.isFinite, lower > 0, lower <= upper,
              let date = calendar.date(byAdding: .day, value: 14, to: asOf) else {
            return result("A scenario range is unavailable for these measurements.")
        }
        return result("If recent rates continue: the middle 80% of observed pairwise rates projected 14 days ahead. This sensitivity range is not a confidence interval, a target date, or a promise; future water shifts and behavior can fall outside it. Calorie targets are unchanged.", range: lower...upper, date: date)
    }
}
