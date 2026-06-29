import Foundation

public protocol AnalyticsManagerProtocol {
    func logEvent(_ name: String, parameters: [String: Any]?)
    func setUserProperty(_ value: String, forName name: String)
    func setUserID(_ id: String)
    func log(_ event: AppEvent, _ parameters: [String: Any])
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
}
