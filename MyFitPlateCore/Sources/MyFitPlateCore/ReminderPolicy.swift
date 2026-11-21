import Foundation
import CryptoKit

public enum ReminderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dailyLog, hydration, weighIn, beforeTraining, recovery, eveningProtein, experimentCheckIn
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dailyLog: return "Food diary"
        case .hydration: return "Water"
        case .weighIn: return "Weight"
        case .beforeTraining: return "Before training"
        case .recovery: return "Recovery fuel"
        case .eveningProtein: return "Evening protein"
        case .experimentCheckIn: return "Meal comparison check-in"
        }
    }
    public var isFuel: Bool { [.beforeTraining, .recovery, .eveningProtein].contains(self) }
    public var defaultMinutes: [Int] {
        switch self {
        case .dailyLog: return [20 * 60]
        case .hydration: return [10 * 60, 13 * 60, 16 * 60, 19 * 60]
        case .weighIn: return [7 * 60 + 30]
        case .eveningProtein: return [19 * 60 + 30]
        case .beforeTraining, .recovery, .experimentCheckIn: return []
        }
    }
    var priority: Int {
        switch self {
        case .beforeTraining, .recovery: return 0
        case .weighIn: return 1
        case .dailyLog: return 2
        case .hydration: return 3
        case .eveningProtein: return 4
        case .experimentCheckIn: return 2
        }
    }
}

public struct ReminderSchedule: Codable, Equatable, Sendable {
    public var enabled = false
    public var minutes: [Int]
    public var weekdays = Set(1...7)
    public var quietStart = 22 * 60
    public var quietEnd = 7 * 60
    public init(kind: ReminderKind) { minutes = kind.defaultMinutes }
    public func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if quietStart == quietEnd { return false }
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(minute) : minute >= quietStart || minute < quietEnd
    }
    public var isValid: Bool {
        minutes.count <= 4 && minutes.allSatisfy { (0..<1_440).contains($0) }
            && weekdays.isSubset(of: Set(1...7)) && !weekdays.isEmpty
            && (0..<1_440).contains(quietStart) && (0..<1_440).contains(quietEnd)
    }
}

public struct ReminderPreferences: Codable, Equatable, Sendable {
    public enum DiaryRule: String, Codable, CaseIterable, Sendable { case anyFood, completeDay }
    public var schedules: [ReminderKind: ReminderSchedule]
    public var diaryRule: DiaryRule = .anyFood
    public var maximumPerDay = 6
    public var legacyReviewCompleted = false
    public init() { schedules = Dictionary(uniqueKeysWithValues: ReminderKind.allCases.map { ($0, ReminderSchedule(kind: $0)) }) }
    public subscript(kind: ReminderKind) -> ReminderSchedule {
        get { schedules[kind] ?? ReminderSchedule(kind: kind) }
        set { schedules[kind] = newValue }
    }
    public var isValid: Bool { (1...8).contains(maximumPerDay) && ReminderKind.allCases.allSatisfy { self[$0].isValid } }
}

public struct ReminderTarget: Codable, Equatable, Identifiable, Sendable {
    public var id: String { kind.rawValue + dayKey + (planRevisionID ?? "") + (experimentTrialID ?? "") }
    public let ownerID: String
    public let kind: ReminderKind
    public let dayKey: String
    public let timeZoneID: String
    public let expiresAt: Date
    public var planID: String?
    public var planRevisionID: String?
    public var experimentID: String?
    public var experimentTrialID: String?
    public var experimentSessionID: String?
    public var experimentFingerprint: String?
    public func day() -> DiaryDayContext? {
        DiaryDayContext(userID: ownerID, date: expiresAt.addingTimeInterval(-1),
                        timeZone: TimeZone(identifier: timeZoneID) ?? .current, dayKey: dayKey)
    }
    public func isAvailable(ownerID: String?, now: Date) -> Bool {
        self.ownerID == ownerID && now < expiresAt && day() != nil
    }
}

public struct ReminderCandidate: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let target: ReminderTarget
    public let title: String
    public let body: String
    public var fireDate: Date
    public let evidenceID: String
    public var budgetKey: String
    public var fingerprint: String { (try? PlanFingerprint.make(self)) ?? "invalid" }
}

public struct ReminderDecision: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable {
        case ready, scheduled, observedDelivered, opened, handled, snoozed, suppressed, failed, expired
        public var label: String {
            switch self {
            case .ready: return "Ready to schedule"
            case .scheduled: return "Scheduled with iOS"
            case .observedDelivered: return "Observed in Notification Center"
            case .opened: return "Opened"
            case .handled: return "Marked handled"
            case .snoozed: return "Snoozed"
            case .suppressed: return "Not scheduled"
            case .failed: return "Could not schedule"
            case .expired: return "Window ended"
            }
        }
    }
    public let id: String
    public var candidate: ReminderCandidate
    public var state: State
    public var reason: String
    public var updatedAt: Date
    public var snoozeCount = 0
}

public struct ReminderReservation: Codable, Equatable, Sendable {
    public let key: String
    public let dayKey: String
    public let kind: ReminderKind
    public let reservedAt: Date
}

public struct ReminderAccountRecord: Codable, Equatable, Sendable {
    public var version = 1
    public var preferences = ReminderPreferences()
    public var decisions: [String: ReminderDecision] = [:]
    public var reservations: [ReminderReservation] = []
    public init() {}
}

public struct ReminderEvidence {
    /// Only exact accepted sessions for an unobserved, unskipped trial; no guessed or legacy session matching.
    public var experimentCheckIns: [ReminderExperimentEvidence] = []
    /// Logs include accepted records plus real queued mutations from the existing diary repository.
    public var logs: [String: DailyLog]
    public var unavailableDays: Set<String>
    public var weightDayKeys: Set<String>
    public var pendingWeightDayKeys: Set<String>
    public var pendingFoodDayKeys: Set<String>
    public var fuelPlans: [TrainingFuelConfirmedPlan]
    public var goals: TodayFuelPlanGoals
    public var waterGoal: Double
    /// Receipt times for accepted local diary writes, not inferred drinking times.
    public var recentWaterAcceptedAt: [String: Date] = [:]
    public var pendingWaterDayKeys = Set<String>()
    public var waterEvidenceUnavailable = false
    public init(logs: [String: DailyLog] = [:], unavailableDays: Set<String> = [], weightDayKeys: Set<String> = [],
                pendingWeightDayKeys: Set<String> = [], pendingFoodDayKeys: Set<String> = [],
                fuelPlans: [TrainingFuelConfirmedPlan] = [], goals: TodayFuelPlanGoals, waterGoal: Double) {
        self.logs = logs; self.unavailableDays = unavailableDays; self.weightDayKeys = weightDayKeys
        self.pendingWeightDayKeys = pendingWeightDayKeys; self.pendingFoodDayKeys = pendingFoodDayKeys
        self.fuelPlans = fuelPlans; self.goals = goals; self.waterGoal = waterGoal
    }
}

public enum ReminderPolicy {
    public static let identifierPrefix = "account_reminder."
    public static func accountScope(_ ownerID: String) -> String {
        SHA256.hash(data: Data(ownerID.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        DiaryDayContext.dayKey(for: date, timeZone: calendar.timeZone) ?? "invalid-day"
    }

    /// Generates at most seven civil days. Reconciliation is repeated on foreground, changes and local queue events.
    public static func decisions(ownerID: String, record: ReminderAccountRecord, evidence: ReminderEvidence,
                                 now: Date = Date(), calendar: Calendar = .current) -> [ReminderDecision] {
        guard !ownerID.isEmpty, record.preferences.isValid else { return [] }
        let start = calendar.startOfDay(for: now)
        var candidates: [ReminderCandidate] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  let end = calendar.date(byAdding: .day, value: 1, to: date) else { continue }
            let key = dayKey(date, calendar: calendar)
            for kind in [ReminderKind.dailyLog, .hydration, .weighIn, .eveningProtein] {
                let schedule = record.preferences[kind]
                guard schedule.enabled else { continue }
                for (slot, minute) in schedule.minutes.sorted().enumerated() {
                    guard let fire = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date), fire > now else { continue }
                    let target = ReminderTarget(ownerID: ownerID, kind: kind, dayKey: key, timeZoneID: calendar.timeZone.identifier, expiresAt: end)
                    let id = identifierPrefix + accountScope(ownerID) + ".\(kind.rawValue).\(key).\(slot)"
                    let body: String
                    switch kind {
                    case .dailyLog: body = record.preferences.diaryRule == .completeDay ? "Review whether your food diary is fully logged for this day." : "Open your food diary and add what you ate."
                    case .hydration: body = "Review your water for this day and add what you drank."
                    case .weighIn: body = "Record a measurement when it suits you."
                    default: body = "Review your remaining protein target before choosing food."
                    }
                    candidates.append(.init(id: id, target: target, title: kind.title, body: body,
                        fireDate: fire, evidenceID: "day:\(key)", budgetKey: id))
                }
            }
        }
        for plan in evidence.fuelPlans where plan.ownerID == ownerID && plan.revisionID != nil {
            let recovery = plan.outcome?.status == .completed
            let kind: ReminderKind = recovery ? .recovery : .beforeTraining
            guard record.preferences[kind].enabled else { continue }
            let reference = recovery ? (plan.outcome?.actualEndAt ?? plan.outcome?.recordedAt ?? plan.estimatedEndAt) : plan.draft.scheduledAt
            let key = dayKey(reference, calendar: calendar)
            guard let horizon = calendar.date(byAdding: .day, value: 7, to: start), reference < horizon else { continue }
            // A future session uses only its matching diary day, never today's consumed totals.
            let evaluationTime = recovery ? now : max(now, calendar.startOfDay(for: reference))
            let prefs = TrainingFuelNotificationPreferences(preSessionEnabled: !recovery, recoveryEnabled: recovery,
                quietStartMinutes: 0, quietEndMinutes: 0)
            for candidate in TrainingFuelNotificationRules.candidates(preferences: prefs, plan: plan, today: evidence.logs[key],
                goals: evidence.goals, now: evaluationTime, calendar: calendar) {
                let end = recovery ? reference.addingTimeInterval(6 * 3_600) : plan.draft.scheduledAt
                let id = identifierPrefix + accountScope(ownerID) + ".\(kind.rawValue)." + accountScope(plan.id)
                let target = ReminderTarget(ownerID: ownerID, kind: kind, dayKey: key, timeZoneID: calendar.timeZone.identifier,
                    expiresAt: end, planID: plan.id, planRevisionID: plan.revisionID)
                candidates.append(.init(id: id, target: target, title: candidate.title, body: candidate.body,
                    fireDate: candidate.fireDate, evidenceID: plan.revisionID!, budgetKey: id + ".\(key)"))
            }
        }
        if record.preferences[.experimentCheckIn].enabled {
            for evidence in evidence.experimentCheckIns where evidence.ownerID == ownerID && evidence.expiresAt > now {
                let id = identifierPrefix + accountScope(ownerID) + ".experimentCheckIn." + accountScope(evidence.trialID)
                let previous = record.decisions[id]?.candidate
                let fire = previous?.evidenceID == evidence.fingerprint ? previous!.fireDate : max(evidence.sessionDate.addingTimeInterval(20 * 60), now.addingTimeInterval(60))
                let target = ReminderTarget(ownerID: ownerID, kind: .experimentCheckIn,
                    dayKey: dayKey(evidence.sessionDate, calendar: calendar), timeZoneID: calendar.timeZone.identifier,
                    expiresAt: evidence.expiresAt, experimentID: evidence.experimentID, experimentTrialID: evidence.trialID,
                    experimentSessionID: evidence.sessionID, experimentFingerprint: evidence.fingerprint)
                candidates.append(.init(id: id, target: target, title: "How did that meal feel?",
                    body: "Review energy and comfort for your completed comparison workout. No check-in is recorded automatically.",
                    fireDate: fire, evidenceID: evidence.fingerprint, budgetKey: previous?.evidenceID == evidence.fingerprint ? previous!.budgetKey : id))
            }
        }
        let ids = Set(candidates.map(\.id))
        for decision in record.decisions.values where decision.snoozeCount > 0 && decision.state != .handled
            && decision.candidate.fireDate > now && !ids.contains(decision.id) {
            let target = decision.candidate.target
            if let planID = target.planID,
               !evidence.fuelPlans.contains(where: { $0.id == planID && $0.revisionID == target.planRevisionID }) { continue }
            candidates.append(decision.candidate)
        }
        var reserved = record.reservations
        return candidates.sorted {
            let leftDay = dayKey($0.fireDate, calendar: calendar), rightDay = dayKey($1.fireDate, calendar: calendar)
            if leftDay != rightDay { return leftDay < rightDay }
            if $0.target.kind.priority != $1.target.kind.priority { return $0.target.kind.priority < $1.target.kind.priority }
            return $0.fireDate < $1.fireDate
        }.map { candidate in
            var candidate = candidate
            let previous = record.decisions[candidate.id]
            if let previous, previous.snoozeCount > 0, previous.candidate.fireDate > now, previous.candidate.evidenceID == candidate.evidenceID {
                candidate.fireDate = previous.candidate.fireDate; candidate.budgetKey = previous.candidate.budgetKey
            }
            if let previous, previous.candidate.fireDate <= now, previous.candidate.fireDate != candidate.fireDate,
               previous.candidate.budgetKey == candidate.budgetKey {
                candidate.budgetKey += ".rescheduled.\(Int(candidate.fireDate.timeIntervalSince1970))"
            }
            if let previous, previous.candidate.fingerprint == candidate.fingerprint,
               previous.state == .opened || previous.state == .observedDelivered {
                // Keep observed delivery/open evidence; a refresh must not schedule
                // the same task again or turn delivery into an unobserved claim.
                return previous
            }
            var reason = suppression(candidate, preferences: record.preferences, evidence: evidence, now: now, calendar: calendar)
            if let previous, previous.state == .handled, previous.candidate.evidenceID == candidate.evidenceID { reason = "Marked handled; no diary entry was created." }
            if candidate.fireDate <= now || candidate.fireDate >= candidate.target.expiresAt { reason = "The useful window has ended." }
            let key = dayKey(candidate.fireDate, calendar: calendar)
            if reason == nil && !reserved.contains(where: { $0.key == candidate.budgetKey }) {
                let day = reserved.filter { $0.dayKey == key }
                if day.count >= record.preferences.maximumPerDay || (candidate.target.kind.isFuel && day.filter({ $0.kind.isFuel }).count >= 2) {
                    reason = "The daily reminder budget is already used."
                } else { reserved.append(.init(key: candidate.budgetKey, dayKey: key, kind: candidate.target.kind, reservedAt: now)) }
            }
            return ReminderDecision(id: candidate.id, candidate: candidate,
                state: reason == nil ? .ready : previous?.state == .handled ? .handled : .suppressed,
                reason: reason ?? "Ready for iOS scheduling. Delivery depends on system settings.", updatedAt: now,
                snoozeCount: previous?.snoozeCount ?? 0)
        }
    }

    public static func actionIsCurrent(_ candidate: ReminderCandidate, ownerID: String?, preferences: ReminderPreferences,
                                       evidence: ReminderEvidence, now: Date, calendar: Calendar) -> Bool {
        guard candidate.target.isAvailable(ownerID: ownerID, now: now), preferences[candidate.target.kind].enabled else { return false }
        if let planID = candidate.target.planID {
            guard let plan = evidence.fuelPlans.first(where: { $0.id == planID && $0.revisionID == candidate.target.planRevisionID }) else { return false }
            let action = DailyNextActionRules.makeAction(plan: plan, today: evidence.logs[candidate.target.dayKey],
                goals: evidence.goals, now: now, calendar: calendar)
            guard candidate.target.kind == .beforeTraining ? action.kind == .preWorkoutFuel : action.kind == .recoveryMeal else { return false }
        }
        return suppression(candidate, preferences: preferences, evidence: evidence, now: now, calendar: calendar) == nil
    }

    private static func suppression(_ candidate: ReminderCandidate, preferences: ReminderPreferences, evidence: ReminderEvidence,
                                    now: Date, calendar: Calendar) -> String? {
        let target = candidate.target, schedule = preferences[target.kind]
        if !schedule.enabled { return "This reminder is turned off." }
        if !schedule.weekdays.contains(calendar.component(.weekday, from: candidate.fireDate)) { return "This weekday is off." }
        if schedule.isQuiet(candidate.fireDate, calendar: calendar) { return "Inside your quiet hours." }
        if target.kind != .experimentCheckIn, evidence.unavailableDays.contains(target.dayKey) { return "Diary evidence is unavailable; no missing action is assumed." }
        let log = evidence.logs[target.dayKey]
        switch target.kind {
        case .dailyLog:
            if preferences.diaryRule == .anyFood, log?.meals.flatMap(\.foodItems).isEmpty == false { return "Food is already recorded, including queued local saves." }
            if let log, NutritionDayEvidence.isComplete(log, now: now, calendar: calendar) { return "This day is already marked fully logged." }
            if evidence.pendingFoodDayKeys.contains(target.dayKey) { return "A submitted food review is still waiting to save." }
        case .hydration:
            if evidence.waterGoal == 0 { return "Water is in tracking-only mode; target reminders are paused." }
            if !evidence.waterGoal.isFinite || evidence.waterGoal < 0 { return "The water target is unavailable; no missing action is assumed." }
            if evidence.waterEvidenceUnavailable { return "Recent water receipts are unavailable; no missing action is assumed." }
            if evidence.pendingWaterDayKeys.contains(target.dayKey) { return "A water entry is waiting to save." }
            let reference = max(now, candidate.fireDate)
            if let acceptedAt = evidence.recentWaterAcceptedAt[target.dayKey], acceptedAt <= now,
               reference.timeIntervalSince(acceptedAt) >= 0, reference.timeIntervalSince(acceptedAt) < 45 * 60 {
                return "A water entry was just saved. Hydration reminders pause for 45 minutes."
            }
            if evidence.waterGoal.isFinite, evidence.waterGoal > 0, (log?.waterTracker?.totalOunces ?? 0) >= evidence.waterGoal { return "The water target is already met, including queued local saves." }
        case .weighIn:
            if evidence.weightDayKeys.contains(target.dayKey) { return "A weight measurement is already recorded." }
            if evidence.pendingWeightDayKeys.contains(target.dayKey) { return "A measurement is still waiting to save." }
        case .eveningProtein:
            guard target.dayKey == dayKey(now, calendar: calendar) else { return "Protein reminders are evaluated on the actual day." }
            if evidence.pendingFoodDayKeys.contains(target.dayKey) { return "Food is still waiting to save." }
            if evidence.fuelPlans.contains(where: { plan in
                let action = DailyNextActionRules.makeAction(plan: plan, today: log, goals: evidence.goals, now: now, calendar: calendar)
                return action.kind == .preWorkoutFuel || action.kind == .recoveryMeal
            }) { return "The session fuel action takes priority." }
            if DailyNextActionRules.makeAction(plan: nil, today: log, goals: evidence.goals, now: now, calendar: calendar).kind != .proteinCatchUp { return "No eligible protein gap remains." }
        case .experimentCheckIn:
            if !evidence.experimentCheckIns.contains(where: { $0.matches(target, now: now) }) {
                return "This comparison or its completed workout changed, was already checked in, or is unavailable."
            }
        case .beforeTraining, .recovery:
            if evidence.pendingFoodDayKeys.contains(target.dayKey) { return "Food is still waiting to save." }
        }
        return nil
    }
}
