import Foundation

/// Stable event names and dimensions used by the 2.3 acquisition, activation, and
/// release-health dashboards. Values describe product behavior only; nutrition,
/// body, workout-detail, location, and account identifiers remain excluded.
public enum ProductAnalytics {
    public static let schemaVersion = "2.3.2"

    public enum Event: String, CaseIterable, Sendable {
        case appSessionStarted = "app_session_started"
        case appStartupCompleted = "app_startup_completed"
        case nonfatalErrorRecorded = "nonfatal_error_recorded"
        case onboardingCompleted = "onboarding_completed"
        case firstFoodLogged = "first_food_logged"
        case firstWorkoutCompleted = "first_workout_completed"
        case nutritionTrainingLoopCompleted = "nutrition_training_loop_completed"
        case loggingDayActive = "logging_day_active"
        case trainingSessionCompleted = "training_session_completed"
        case foodLogged = "food_logged"
        case foodLoggedBulk = "food_logged_bulk"
        case barcodeLookupOutcome = "barcode_lookup_outcome"
        case barcodeMissRecovery = "barcode_miss_recovery"
        case importStarted = "mfp_import_started"
        case importCompleted = "mfp_import_completed"
        case trustCardViewed = "food_trust_card_viewed"
        case trustAction = "food_trust_action"
        case correctionAction = "food_correction_action"
        case trustHubViewed = "trust_hub_viewed"
        case deepLinkOpened = "deep_link_opened"
        case trainingFuelPlannerOpened = "training_fuel_planner_opened"
        case trainingFuelPlanSaved = "training_fuel_plan_saved"
        case trainingFuelHandoffSelected = "training_fuel_handoff_selected"
        case trainingFuelSessionOutcome = "training_fuel_session_outcome"
        case trainingFuelNotificationScheduled = "training_fuel_notification_scheduled"
        case trainingFuelNotificationOpened = "training_fuel_notification_opened"
        case watchMealRepeatResult = "watch_meal_repeat_result"
        case accountDeletionStarted = "account_deletion_started"
        case accountDeletionCompleted = "account_deletion_completed"
        case accountDeletionFailed = "account_deletion_failed"
    }

    public enum TrainingMode: String, Sendable {
        case strength
        case recordedRun = "recorded_run"
        case treadmillRun = "treadmill_run"
    }

    /// Firebase receives a schema marker even when every supplied parameter is removed
    /// by the privacy allowlist. This makes mixed-version dashboard data detectable.
    public static func firebaseParameters(_ parameters: [String: Any]?) -> [String: Any] {
        var result = AnalyticsPrivacy.sanitizedParameters(parameters) ?? [:]
        result["analytics_schema"] = schemaVersion
        return result
    }

    public static func durationBucket(milliseconds: Int) -> String {
        switch max(milliseconds, 0) {
        case ..<500:
            return "under_500ms"
        case ..<1_000:
            return "500ms_to_1s"
        case ..<2_000:
            return "1s_to_2s"
        case ..<4_000:
            return "2s_to_4s"
        default:
            return "over_4s"
        }
    }
}

/// Emits one canonical active-logger event per app instance and local calendar day.
/// Firebase can then count distinct active users without summing every food item or
/// mixing single-item logs with bulk meal imports.
@MainActor
public enum ProductEngagementTelemetry {
    private static let lastLoggingDayKey = "product_analytics_last_logging_day"

    public static func recordFoodLoggingDay(
        source: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        userDefaults: UserDefaults = .standard,
        analyticsManager: AnalyticsManagerProtocol? = nil
    ) {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return }

        let dayStamp = String(format: "%04d-%02d-%02d", year, month, day)
        guard userDefaults.string(forKey: lastLoggingDayKey) != dayStamp else { return }
        guard let manager = analyticsManager ?? DIContainer.shared.analyticsManager else { return }

        userDefaults.set(dayStamp, forKey: lastLoggingDayKey)
        manager.logEvent(
            ProductAnalytics.Event.loggingDayActive.rawValue,
            parameters: ["entry_source": source]
        )
    }
}
