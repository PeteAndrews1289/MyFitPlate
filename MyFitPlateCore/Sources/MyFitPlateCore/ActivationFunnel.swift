import Foundation

/// One-shot activation-funnel analytics. With no external testers, the funnel
/// (onboarding_completed -> first_food_logged -> first_workout_completed) is the clearest
/// signal of where new users drop off. Each event fires at most once per install.
public enum ActivationFunnel {
    public static let onboardingCompleted = "onboarding_completed"
    public static let firstFoodLogged = "first_food_logged"
    public static let firstWorkoutCompleted = "first_workout_completed"
    public static let nutritionTrainingLoopCompleted = "nutrition_training_loop_completed"

    private static let onboardingCompletedAtKey = "activation_funnel_onboarding_completed_at"

    @MainActor
    public static func logOnce(
        _ eventName: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        let key = "activation_funnel_" + eventName
        if !userDefaults.bool(forKey: key) {
            if eventName == onboardingCompleted {
                userDefaults.set(now, forKey: onboardingCompletedAtKey)
            }
            userDefaults.set(true, forKey: key)
            DIContainer.shared.analyticsManager?.logEvent(
                eventName,
                parameters: eventName == onboardingCompleted
                    ? nil
                    : elapsedParameters(now: now, userDefaults: userDefaults)
            )
        }

        if eventName == firstFoodLogged || eventName == firstWorkoutCompleted {
            logNutritionTrainingLoopIfReady(now: now, userDefaults: userDefaults)
        }
    }

    private static func elapsedParameters(
        now: Date,
        userDefaults: UserDefaults
    ) -> [String: Any]? {
        guard let onboardingCompletedAt = userDefaults.object(forKey: onboardingCompletedAtKey) as? Date else {
            return nil
        }
        let elapsed = max(0, Int(now.timeIntervalSince(onboardingCompletedAt).rounded()))
        return ["elapsed_seconds": elapsed]
    }

    @MainActor
    private static func logNutritionTrainingLoopIfReady(
        now: Date,
        userDefaults: UserDefaults
    ) {
        let foodKey = "activation_funnel_" + firstFoodLogged
        let workoutKey = "activation_funnel_" + firstWorkoutCompleted
        let loopKey = "activation_funnel_" + nutritionTrainingLoopCompleted
        guard userDefaults.bool(forKey: foodKey),
              userDefaults.bool(forKey: workoutKey),
              !userDefaults.bool(forKey: loopKey) else { return }

        userDefaults.set(true, forKey: loopKey)
        DIContainer.shared.analyticsManager?.logEvent(
            nutritionTrainingLoopCompleted,
            parameters: elapsedParameters(now: now, userDefaults: userDefaults)
        )
    }
}
