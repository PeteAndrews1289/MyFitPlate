import Foundation
import SwiftUI
import FirebaseAnalytics

/// Central, typed wrapper around Firebase Analytics.
///
/// Event and parameter names are intentionally verbose and self-describing so the Firebase
/// dashboard reads like plain English ("screen_viewed", "ai_feature_used") instead of cryptic
/// codes. Add new cases to `AppScreen` / `AppEvent` rather than scattering string literals.
enum AnalyticsManager {

    // MARK: - Screen views (what users actually open)

    static func screenViewed(_ screen: AppScreen) {
        Analytics.logEvent("screen_viewed", parameters: ["screen_name": screen.rawValue])
    }

    // MARK: - Feature / action events

    static func log(_ event: AppEvent, _ parameters: [String: Any] = [:]) {
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
    }

    /// Convenience for the most common pattern: "which AI feature was used."
    static func aiFeatureUsed(_ feature: AIFeature) {
        Analytics.logEvent(AppEvent.aiFeatureUsed.rawValue, parameters: ["ai_feature": feature.rawValue])
    }

    // MARK: - User properties (for segmenting the dashboards)

    static func setUserProperty(_ value: String?, for property: UserProperty) {
        Analytics.setUserProperty(value, forName: property.rawValue)
    }
}

// MARK: - Screens

/// Every meaningful screen. Names are snake_case and describe the screen in human terms.
enum AppScreen: String {
    case homeDashboard = "home_dashboard"
    case maiaChat = "maia_chat"
    case workoutsHome = "workouts_home"
    case mealPlanner = "meal_planner"
    case reports = "reports"
    case foodSearch = "food_search"
    case foodDetail = "food_detail"
    case settings = "settings"
    case workoutPlayer = "workout_player"
    case workoutHistory = "workout_history"
    case recipeList = "recipe_list"
    case groceryList = "grocery_list"
    case adaptiveMetabolism = "adaptive_metabolism"
    case onboardingSurvey = "onboarding_survey"
}

// MARK: - Events

/// Action/feature events. Keep names readable and past-tense where it's a completed action.
enum AppEvent: String {
    // AI features (your differentiators — currently the least-tracked, most-interesting flows)
    case aiFeatureUsed = "ai_feature_used"
    case maiaMessageSent = "maia_message_sent"
    case aiTextLogUsed = "ai_text_log_used"

    // Camera / scanning
    case barcodeScanned = "barcode_scanned"
    case nutritionLabelScanned = "nutrition_label_scanned"
    case mealPhotoAnalyzed = "meal_photo_analyzed"
    case menuPhotoAnalyzed = "menu_photo_analyzed"
    case receiptScanned = "grocery_receipt_scanned"

    // Workouts (session-level — the daily log only stores a routine summary)
    case workoutStarted = "workout_started"
    case workoutCompleted = "workout_completed"
    case workoutInsightsViewed = "workout_insights_viewed"

    // Body / goals
    case weightLogged = "weight_logged"
    case adaptiveTdeeAccepted = "adaptive_tdee_accepted"
}

/// The specific AI capability invoked, attached to `ai_feature_used`.
enum AIFeature: String {
    case maiaChat = "maia_chat"
    case textLog = "text_log"
    case mealPhoto = "meal_photo"
    case menuPhoto = "menu_photo"
    case nutritionLabel = "nutrition_label"
    case groceryReceipt = "grocery_receipt"
    case mealPlan = "meal_plan"
    case recipeGenerator = "recipe_generator"
    case workoutGenerator = "workout_generator"
    case workoutInsights = "workout_insights"
    case dailyBriefing = "daily_briefing"
}

// MARK: - User properties

enum UserProperty: String {
    case goalType = "goal_type"             // lose / maintain / gain
    case calorieMethod = "calorie_method"   // custom / dynamic_tdee / mifflin
    case hasActiveProgram = "has_active_program"
    case biologicalSex = "biological_sex"
}

// MARK: - Screen-view modifier

extension View {
    /// Logs a `screen_viewed` event when this view appears. Apply to top-level screens:
    /// `SomeView().trackScreen(.homeDashboard)`
    func trackScreen(_ screen: AppScreen) -> some View {
        self.onAppear { AnalyticsManager.screenViewed(screen) }
    }
}
