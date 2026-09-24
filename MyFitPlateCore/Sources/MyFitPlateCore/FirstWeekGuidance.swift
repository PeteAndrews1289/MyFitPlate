import Foundation

/// When to offer adaptive targets to someone still on the formula estimate. The weekly check-in
/// only reaches accounts already on adaptive targets, so without this offer most people never
/// see what they really burn.
public enum AdaptiveTargetsOfferRules {
    public static let snoozeInterval: TimeInterval = 14 * 24 * 60 * 60

    public static func shouldOffer(
        method: CalorieGoalMethod,
        confidence: AdaptiveGoalService.DataConfidence,
        isEstimateActionable: Bool,
        calculatedTDEE: Double?,
        lastDeclinedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard method == .mifflinWithActivity,
              isEstimateActionable,
              calculatedTDEE != nil,
              confidence == .high || confidence == .medium else {
            return false
        }
        if let lastDeclinedAt, now.timeIntervalSince(lastDeclinedAt) < snoozeInterval {
            return false
        }
        return true
    }
}

public enum SetupChecklistItem: String, CaseIterable, Sendable {
    case firstMeal = "first_meal"
    case dailyReminder = "daily_reminder"
    case appleHealth = "apple_health"
    case firstWorkout = "first_workout"
}

public struct SetupChecklistState: Equatable, Sendable {
    public var hasLoggedFood: Bool
    /// The reminder is on, or the person already answered the system prompt.
    public var reminderResolved: Bool
    /// Apple Health has already shown its connection prompt.
    public var healthResolved: Bool
    public var healthAvailable: Bool
    public var hasCompletedWorkout: Bool

    public init(
        hasLoggedFood: Bool,
        reminderResolved: Bool,
        healthResolved: Bool,
        healthAvailable: Bool,
        hasCompletedWorkout: Bool
    ) {
        self.hasLoggedFood = hasLoggedFood
        self.reminderResolved = reminderResolved
        self.healthResolved = healthResolved
        self.healthAvailable = healthAvailable
        self.hasCompletedWorkout = hasCompletedWorkout
    }
}

/// The first-week "Get set up" card. Permission requests live here, behind a tap, instead of
/// interrupting onboarding: the reminder comes right after the first meal, when its value is clear.
public enum SetupChecklistRules {
    public static let visibleDays = 21

    public static func items(for state: SetupChecklistState) -> [SetupChecklistItem] {
        SetupChecklistItem.allCases.filter { $0 != .appleHealth || state.healthAvailable }
    }

    public static func isComplete(_ item: SetupChecklistItem, state: SetupChecklistState) -> Bool {
        switch item {
        case .firstMeal: return state.hasLoggedFood
        case .dailyReminder: return state.reminderResolved
        case .appleHealth: return state.healthResolved
        case .firstWorkout: return state.hasCompletedWorkout
        }
    }

    public static func nextItem(for state: SetupChecklistState) -> SetupChecklistItem? {
        items(for: state).first { !isComplete($0, state: state) }
    }

    public static func completedCount(for state: SetupChecklistState) -> Int {
        items(for: state).filter { isComplete($0, state: state) }.count
    }

    /// Shown for new accounts only, until every step is done, the person hides it, or three weeks
    /// pass. Accounts that onboarded before this card existed have no completion date and never see it.
    public static func shouldShow(
        state: SetupChecklistState,
        onboardingCompletedAt: Date?,
        dismissedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard dismissedAt == nil,
              let onboardingCompletedAt,
              now.timeIntervalSince(onboardingCompletedAt) <= TimeInterval(visibleDays) * 24 * 60 * 60 else {
            return false
        }
        return nextItem(for: state) != nil
    }
}

/// Per-account memory for first-week guidance, so a second account on the same device starts fresh.
public final class FirstWeekGuidanceStore: @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func checklistDismissedAt(userID: String?) -> Date? {
        date(prefix: "setup_checklist_dismissed_at", userID: userID)
    }

    public func dismissChecklist(userID: String?, now: Date = Date()) {
        set(now, prefix: "setup_checklist_dismissed_at", userID: userID)
    }

    public func adaptiveOfferDeclinedAt(userID: String?) -> Date? {
        date(prefix: "adaptive_targets_offer_declined_at", userID: userID)
    }

    public func declineAdaptiveOffer(userID: String?, now: Date = Date()) {
        set(now, prefix: "adaptive_targets_offer_declined_at", userID: userID)
    }

    private func date(prefix: String, userID: String?) -> Date? {
        guard let key = AccountScopedStorageKey.make(prefix: prefix, userID: userID) else { return nil }
        return userDefaults.object(forKey: key) as? Date
    }

    private func set(_ date: Date, prefix: String, userID: String?) {
        guard let key = AccountScopedStorageKey.make(prefix: prefix, userID: userID) else { return }
        userDefaults.set(date, forKey: key)
    }
}
