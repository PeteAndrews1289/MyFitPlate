import Foundation

/// One-shot activation-funnel analytics. With no external testers, the funnel
/// (onboarding_completed -> first_food_logged -> first_workout_completed) is the clearest
/// signal of where new users drop off. Each event fires at most once per install.
public enum ActivationFunnel {
    public static let onboardingCompleted = ProductAnalytics.Event.onboardingCompleted.rawValue
    public static let firstFoodLogged = ProductAnalytics.Event.firstFoodLogged.rawValue
    public static let firstWorkoutCompleted = ProductAnalytics.Event.firstWorkoutCompleted.rawValue
    public static let nutritionTrainingLoopCompleted = ProductAnalytics.Event.nutritionTrainingLoopCompleted.rawValue

    private static let onboardingCompletedAtKey = "activation_funnel_onboarding_completed_at"

    @MainActor
    public static func logOnce(
        _ eventName: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard,
        parameters: [String: Any] = [:]
    ) {
        let key = "activation_funnel_" + eventName
        if !userDefaults.bool(forKey: key) {
            if eventName == onboardingCompleted {
                userDefaults.set(now, forKey: onboardingCompletedAtKey)
            }
            userDefaults.set(true, forKey: key)
            DIContainer.shared.analyticsManager?.logEvent(
                eventName,
                parameters: eventParameters(
                    eventName: eventName,
                    now: now,
                    userDefaults: userDefaults,
                    additional: parameters
                )
            )
        }

        if eventName == firstFoodLogged || eventName == firstWorkoutCompleted {
            logNutritionTrainingLoopIfReady(now: now, userDefaults: userDefaults)
        }
    }

    /// Records every in-app training completion while preserving the existing one-shot
    /// activation milestone. Imported historical HealthKit workouts intentionally do not
    /// count as an in-app completion.
    @MainActor
    public static func recordTrainingCompletion(
        _ mode: ProductAnalytics.TrainingMode,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        let dimensions: [String: Any] = ["training_mode": mode.rawValue]
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trainingSessionCompleted.rawValue,
            parameters: dimensions
        )
        logOnce(
            firstWorkoutCompleted,
            now: now,
            userDefaults: userDefaults,
            parameters: dimensions
        )
    }

    private static func eventParameters(
        eventName: String,
        now: Date,
        userDefaults: UserDefaults,
        additional: [String: Any]
    ) -> [String: Any]? {
        var parameters = additional
        if eventName != onboardingCompleted,
           let elapsed = elapsedParameters(now: now, userDefaults: userDefaults) {
            parameters.merge(elapsed) { _, new in new }
        }
        return parameters.isEmpty ? nil : parameters
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
