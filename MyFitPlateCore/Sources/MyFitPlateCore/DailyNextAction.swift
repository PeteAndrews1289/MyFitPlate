import Foundation

/// One privacy-conscious action suitable for compact surfaces such as widgets and Watch.
/// It carries no food names, workout names, account identifiers, or health samples.
public struct DailyNextAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case preWorkoutFuel = "pre_workout_fuel"
        case recoveryMeal = "recovery_meal"
        case proteinCatchUp = "protein_catch_up"
        case trustReview = "trust_review"
        case steadyDay = "steady_day"
    }

    public let kind: Kind
    public let title: String
    public let detail: String
    public let deepLink: String
    public let proteinGrams: Int?
    public let carbGrams: Int?

    public init(
        kind: Kind,
        title: String,
        detail: String,
        deepLink: String,
        proteinGrams: Int? = nil,
        carbGrams: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.deepLink = deepLink
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
    }
}

public enum DailyNextActionRules {
    public static let proteinCatchUpMinimumGrams = 20
    public static let proteinCatchUpMinimumCalories = 150

    /// Priority is intentional: an active training window is time-sensitive, unresolved Trust
    /// data affects every downstream total, a meaningful protein gap comes next, and only then
    /// does the surface show a neutral steady-day state.
    public static func makeAction(
        plan: TrainingFuelConfirmedPlan?,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyNextAction {
        if let plan {
            let progress = TrainingFuelPlanProgressRules.makeProgress(
                plan: plan,
                today: today,
                goals: goals,
                now: now,
                calendar: calendar
            )
            if let action = trainingAction(plan: plan, progress: progress) {
                return action
            }
        }

        let reviewCount = today?.meals
            .flatMap(\.foodItems)
            .compactMap(\.sourceMetadata)
            .filter {
                $0.reviewStatus != .notRequired &&
                    $0.reviewStatus != .userConfirmed &&
                    $0.reviewStatus != .userEdited
            }
            .count ?? 0
        if reviewCount > 0 {
            return DailyNextAction(
                kind: .trustReview,
                title: "Review food data",
                detail: "\(reviewCount) \(reviewCount == 1 ? "entry needs" : "entries need") your review",
                deepLink: "myfitplate://trust"
            )
        }

        let consumedCalories = today?.totalCalories() ?? 0
        let consumedProtein = today?.totalMacros().protein ?? 0
        if goals.calories.isFinite,
           goals.calories > 0,
           goals.protein.isFinite,
           goals.protein > 0,
           consumedCalories.isFinite,
           consumedCalories >= 0,
           consumedProtein.isFinite,
           consumedProtein >= 0 {
            let caloriesRemaining = goals.calories - consumedCalories
            let proteinRemaining = Int(ceil(max(0, goals.protein - consumedProtein)))
            if caloriesRemaining >= Double(proteinCatchUpMinimumCalories),
               proteinRemaining >= proteinCatchUpMinimumGrams {
                return DailyNextAction(
                    kind: .proteinCatchUp,
                    title: "Close your protein gap",
                    detail: "\(proteinRemaining) g protein left today",
                    deepLink: "myfitplate://food-search",
                    proteinGrams: proteinRemaining
                )
            }
        }

        return DailyNextAction(
            kind: .steadyDay,
            title: "Stay steady today",
            detail: "Keep logging as you go",
            deepLink: "myfitplate://home"
        )
    }

    private static func trainingAction(
        plan: TrainingFuelConfirmedPlan,
        progress: TrainingFuelPlanProgress
    ) -> DailyNextAction? {
        let phase: TrainingFuelAllocation.Phase
        let kind: DailyNextAction.Kind
        let title: String
        switch progress.status {
        case .upcoming:
            phase = .beforeTraining
            kind = .preWorkoutFuel
            title = "Fuel before training"
        case .recovery:
            phase = .afterTraining
            kind = .recoveryMeal
            title = "Log recovery fuel"
        case .inSession, .awaitingOutcome, .awaitingRecoveryData, .complete, .skipped,
             .stale, .overTarget, .invalidDiary, .invalidTargets, .budgetUsedElsewhere:
            return nil
        }

        guard let target = progress.target(for: phase, plan: plan) else { return nil }
        return DailyNextAction(
            kind: kind,
            title: title,
            detail: targetDetail(protein: target.proteinGrams, carbs: target.carbGrams),
            deepLink: "myfitplate://training-fuel",
            proteinGrams: target.proteinGrams,
            carbGrams: target.carbGrams
        )
    }

    private static func targetDetail(protein: Int, carbs: Int) -> String {
        switch (protein > 0, carbs > 0) {
        case (true, true):
            return "\(protein) g protein + \(carbs) g carbs"
        case (true, false):
            return "\(protein) g protein"
        case (false, true):
            return "\(carbs) g carbs"
        case (false, false):
            return "Review today's target"
        }
    }
}
