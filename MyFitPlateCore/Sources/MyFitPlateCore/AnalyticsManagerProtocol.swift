import Foundation

public protocol AnalyticsManagerProtocol {
    func logEvent(_ name: String, parameters: [String: Any]?)
    func setUserProperty(_ value: String, forName name: String)
    func setUserID(_ id: String?)
    func log(_ event: AppEvent, _ parameters: [String: Any])
}

public enum AnalyticsPrivacy {
    private static let sensitiveKeyFragments = [
        "calorie", "protein", "carb", "fat", "weight", "height", "age", "gender",
        "sleep", "step", "active_energy", "water", "wellness", "heart", "distance",
        "pace", "route", "workout", "exercise", "volume", "body", "health"
    ]

    // Several older events used generic keys whose values were still health, journal,
    // or training details. Keep these aliases explicit so operational duration_ms and
    // elapsed_seconds metrics remain available without reopening those privacy gaps.
    private static let sensitiveExactKeys: Set<String> = [
        "account_id",
        "amount",
        "auth_uid",
        "barcode",
        "category",
        "completed_sets",
        "content",
        "data_point_count",
        "description",
        "days_per_week",
        "delta",
        "duration",
        "email",
        "error",
        "error_message",
        "fitness_level",
        "food_id",
        "food_name",
        "goal",
        "has_pattern_note",
        "journal_entry",
        "matched_food_id",
        "message",
        "name",
        "notes",
        "program_name",
        "prompt",
        "prs",
        "query",
        "response",
        "routine_name",
        "set_count",
        "should_adjust",
        "source_id",
        "text",
        "title",
        "training_load",
        "uid",
        "user_id",
        "weigh_ins"
    ]

    public static func sanitizedParameters(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let parameters else { return nil }
        let sanitized = parameters.filter { key, _ in
            let normalizedKey = key.lowercased()
            return !sensitiveExactKeys.contains(normalizedKey) &&
                !sensitiveKeyFragments.contains(where: normalizedKey.contains)
        }
        return sanitized.isEmpty ? nil : sanitized
    }
}

public enum AppScreen: String {
    case homeDashboard = "home_dashboard"
    case maiaChat = "maia_chat"
    case workoutsHome = "workouts_home"
    case mealPlanner = "meal_planner"
    case reports = "reports"
}

public enum AppEvent: String {
    case aiFeatureUsed = "ai_feature_used"
    case workoutStarted = "workout_started"
    case workoutCompleted = "workout_completed"
    case barcodeScanned = "barcode_scanned"
}

public enum AIFeature: String {
    case generatedWorkout = "generated_workout"
    case loggedMeal = "logged_meal"
    case nutritionLabel = "nutrition_label"
    case maiaChat = "maia_chat"
    case mealPhoto = "meal_photo"
    case menuPhoto = "menu_photo"
}

public extension AnalyticsManagerProtocol {
    func aiFeatureUsed(_ feature: AIFeature) {
        log(.aiFeatureUsed, ["feature": feature.rawValue])
    }

    func barcodeLookupOutcome(_ outcome: BarcodeLookupOutcome) {
        logEvent(BarcodeLookupOutcome.eventName, parameters: outcome.analyticsParameters)
    }

    func barcodeMissRecovery(_ outcome: BarcodeRecoveryOutcome) {
        logEvent(BarcodeRecoveryOutcome.eventName, parameters: outcome.analyticsParameters)
    }
}
