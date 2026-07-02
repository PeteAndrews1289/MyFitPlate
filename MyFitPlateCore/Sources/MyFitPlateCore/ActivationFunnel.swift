import Foundation

/// One-shot activation-funnel analytics. With no external testers, the funnel
/// (onboarding_completed -> first_food_logged -> first_workout_completed) is the clearest
/// signal of where new users drop off. Each event fires at most once per install.
public enum ActivationFunnel {
    public static let onboardingCompleted = "onboarding_completed"
    public static let firstFoodLogged = "first_food_logged"
    public static let firstWorkoutCompleted = "first_workout_completed"

    @MainActor
    public static func logOnce(_ eventName: String, userDefaults: UserDefaults = .standard) {
        let key = "activation_funnel_" + eventName
        guard !userDefaults.bool(forKey: key) else { return }
        userDefaults.set(true, forKey: key)
        DIContainer.shared.analyticsManager?.logEvent(eventName, parameters: nil)
    }
}
