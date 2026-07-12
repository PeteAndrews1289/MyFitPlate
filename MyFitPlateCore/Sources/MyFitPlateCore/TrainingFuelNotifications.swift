import Foundation

public enum TrainingFuelNotificationPreferenceKey {
    public static let preSessionEnabled = "trainingFuelPreSessionNotificationsEnabled"
    public static let recoveryEnabled = "trainingFuelRecoveryNotificationsEnabled"
    public static let eveningCatchUpEnabled = "trainingFuelEveningNotificationsEnabled"
    public static let quietStartMinutes = "trainingFuelQuietStartMinutes"
    public static let quietEndMinutes = "trainingFuelQuietEndMinutes"
    public static let eveningMinutes = "trainingFuelEveningReminderMinutes"
}

public struct TrainingFuelNotificationPreferences: Codable, Equatable, Sendable {
    public var preSessionEnabled: Bool
    public var recoveryEnabled: Bool
    public var eveningCatchUpEnabled: Bool
    public var quietStartMinutes: Int
    public var quietEndMinutes: Int
    public var eveningMinutes: Int

    public init(
        preSessionEnabled: Bool = false,
        recoveryEnabled: Bool = false,
        eveningCatchUpEnabled: Bool = false,
        quietStartMinutes: Int = 22 * 60,
        quietEndMinutes: Int = 7 * 60,
        eveningMinutes: Int = 19 * 60 + 30
    ) {
        self.preSessionEnabled = preSessionEnabled
        self.recoveryEnabled = recoveryEnabled
        self.eveningCatchUpEnabled = eveningCatchUpEnabled
        self.quietStartMinutes = Self.validMinute(quietStartMinutes, fallback: 22 * 60)
        self.quietEndMinutes = Self.validMinute(quietEndMinutes, fallback: 7 * 60)
        self.eveningMinutes = Self.validMinute(eveningMinutes, fallback: 19 * 60 + 30)
    }

    public var hasAnyEnabled: Bool {
        preSessionEnabled || recoveryEnabled || eveningCatchUpEnabled
    }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            preSessionEnabled: defaults.bool(forKey: TrainingFuelNotificationPreferenceKey.preSessionEnabled),
            recoveryEnabled: defaults.bool(forKey: TrainingFuelNotificationPreferenceKey.recoveryEnabled),
            eveningCatchUpEnabled: defaults.bool(forKey: TrainingFuelNotificationPreferenceKey.eveningCatchUpEnabled),
            quietStartMinutes: defaults.object(forKey: TrainingFuelNotificationPreferenceKey.quietStartMinutes) as? Int ?? 22 * 60,
            quietEndMinutes: defaults.object(forKey: TrainingFuelNotificationPreferenceKey.quietEndMinutes) as? Int ?? 7 * 60,
            eveningMinutes: defaults.object(forKey: TrainingFuelNotificationPreferenceKey.eveningMinutes) as? Int ?? 19 * 60 + 30
        )
    }

    private static func validMinute(_ value: Int, fallback: Int) -> Int {
        (0..<(24 * 60)).contains(value) ? value : fallback
    }
}

public struct TrainingFuelNotificationCandidate: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case preSession = "pre_session"
        case recovery
        case eveningCatchUp = "evening_catch_up"

        public var identifier: String {
            "training_fuel.\(rawValue)"
        }
    }

    public let kind: Kind
    public let title: String
    public let body: String
    public let fireDate: Date
    public let deepLink: String

    public init(kind: Kind, title: String, body: String, fireDate: Date, deepLink: String) {
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.deepLink = deepLink
    }
}

public enum TrainingFuelNotificationRules {
    public static let maximumPerDay = 2

    public static func candidates(
        preferences: TrainingFuelNotificationPreferences,
        plan: TrainingFuelConfirmedPlan?,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TrainingFuelNotificationCandidate] {
        guard preferences.hasAnyEnabled else { return [] }
        var candidates: [TrainingFuelNotificationCandidate] = []

        if let plan {
            let action = DailyNextActionRules.makeAction(
                plan: plan,
                today: today,
                goals: goals,
                now: now,
                calendar: calendar
            )
            if preferences.preSessionEnabled,
               action.kind == .preWorkoutFuel,
               let candidate = preSessionCandidate(plan: plan, action: action, now: now) {
                candidates.append(candidate)
            }
            if preferences.recoveryEnabled,
               action.kind == .recoveryMeal,
               let candidate = recoveryCandidate(plan: plan, action: action, now: now) {
                candidates.append(candidate)
            }
        }

        if preferences.eveningCatchUpEnabled,
           let candidate = eveningCandidate(
               preferences: preferences,
               today: today,
               goals: goals,
               now: now,
               calendar: calendar
           ) {
            candidates.append(candidate)
        }

        return candidates
            .filter { $0.fireDate > now && !isQuiet($0.fireDate, preferences: preferences, calendar: calendar) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maximumPerDay)
            .map { $0 }
    }

    public static func isQuiet(
        _ date: Date,
        preferences: TrainingFuelNotificationPreferences,
        calendar: Calendar = .current
    ) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = preferences.quietStartMinutes
        let end = preferences.quietEndMinutes
        guard start != end else { return false }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    private static func preSessionCandidate(
        plan: TrainingFuelConfirmedPlan,
        action: DailyNextAction,
        now: Date
    ) -> TrainingFuelNotificationCandidate? {
        guard plan.draft.preference.wantsPreSessionFuel,
              let allocation = plan.allocations.first(where: { $0.phase == .beforeTraining }) else { return nil }
        let leadMinutes: Int
        switch allocation.timing {
        case .within30Minutes: leadMinutes = 20
        case .thirtyTo120Minutes: leadMinutes = 75
        case .overTwoHours: leadMinutes = 120
        case .afterSession: return nil
        }
        let ideal = plan.draft.scheduledAt.addingTimeInterval(Double(-leadMinutes * 60))
        let earliestAfterConfirmation = plan.confirmedAt.addingTimeInterval(60)
        let fireDate = max(ideal, earliestAfterConfirmation)
        guard fireDate < plan.draft.scheduledAt, fireDate > now else { return nil }
        return TrainingFuelNotificationCandidate(
            kind: .preSession,
            title: "Fuel before training",
            body: "Your confirmed target is \(action.detail). Review it before you train.",
            fireDate: fireDate,
            deepLink: action.deepLink
        )
    }

    private static func recoveryCandidate(
        plan: TrainingFuelConfirmedPlan,
        action: DailyNextAction,
        now: Date
    ) -> TrainingFuelNotificationCandidate? {
        guard plan.draft.preference.wantsPostSessionFuel,
              let outcome = plan.outcome,
              outcome.status == .completed else { return nil }
        let end = outcome.actualEndAt ?? outcome.recordedAt
        let fireDate = max(
            end.addingTimeInterval(10 * 60),
            outcome.recordedAt.addingTimeInterval(60)
        )
        guard fireDate > now else { return nil }
        return TrainingFuelNotificationCandidate(
            kind: .recovery,
            title: "Recovery target ready",
            body: "Your confirmed target is \(action.detail). Log what you choose.",
            fireDate: fireDate,
            deepLink: action.deepLink
        )
    }

    private static func eveningCandidate(
        preferences: TrainingFuelNotificationPreferences,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date,
        calendar: Calendar
    ) -> TrainingFuelNotificationCandidate? {
        let action = DailyNextActionRules.makeAction(
            plan: nil,
            today: today,
            goals: goals,
            now: now,
            calendar: calendar
        )
        guard action.kind == .proteinCatchUp else { return nil }
        let hour = preferences.eveningMinutes / 60
        let minute = preferences.eveningMinutes % 60
        guard let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now),
              fireDate > now else { return nil }
        return TrainingFuelNotificationCandidate(
            kind: .eveningCatchUp,
            title: "Protein target still open",
            body: action.detail,
            fireDate: fireDate,
            deepLink: action.deepLink
        )
    }
}
