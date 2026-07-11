import Foundation

public struct TodayFuelPlan: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case runRecovery = "run_recovery"
        case workoutRecovery = "workout_recovery"
        case proteinCatchUp = "protein_catch_up"
        case planDinner = "plan_dinner"
        case overTargetReview = "over_target_review"
        case steadyDay = "steady_day"
    }

    public enum Action: String, Equatable, Sendable {
        case openRecoverySearch = "open_recovery_search"
        case fillMacros = "fill_macros"
        case reviewDay = "review_day"
        case none
    }

    public let kind: Kind
    public let title: String
    public let summary: String
    public let detail: String
    public let statusLabel: String
    public let actionTitle: String
    public let action: Action
    public let remainingCalories: Double
    public let targetProteinGrams: Int?
    public let targetCarbGrams: Int?
    public let targetWaterOunces: Int?

    public init(
        kind: Kind,
        title: String,
        summary: String,
        detail: String,
        statusLabel: String,
        actionTitle: String,
        action: Action,
        remainingCalories: Double,
        targetProteinGrams: Int? = nil,
        targetCarbGrams: Int? = nil,
        targetWaterOunces: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.detail = detail
        self.statusLabel = statusLabel
        self.actionTitle = actionTitle
        self.action = action
        self.remainingCalories = remainingCalories
        self.targetProteinGrams = targetProteinGrams
        self.targetCarbGrams = targetCarbGrams
        self.targetWaterOunces = targetWaterOunces
    }
}

public struct TodayFuelPlanGoals: Codable, Equatable, Sendable {
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fats: Double

    public init(calories: Double, protein: Double, carbs: Double, fats: Double) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
    }
}

public enum TodayFuelPlanRules {
    public static func makePlan(
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        runRecoveryTarget: RunRecoveryTarget? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayFuelPlan {
        let caloriesLogged = today?.totalCalories() ?? 0
        let macros = today?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        let remainingCalories = goals.calories - caloriesLogged
        let remainingProtein = max(0, goals.protein - macros.protein)
        let remainingCarbs = max(0, goals.carbs - macros.carbs)
        let hour = calendar.component(.hour, from: now)
        let workoutsToday = today?.exercises?.filter { calendar.isDate($0.date, inSameDayAs: now) } ?? []

        guard remainingCalories > 0 else {
            return TodayFuelPlan(
                kind: .overTargetReview,
                title: "Tighten the finish",
                summary: "You are \(Int(abs(remainingCalories).rounded()).formatted()) cal over target.",
                detail: "Keep the next choice light and high-satiety. A walk can help momentum, but do not treat extra exercise as a reset button.",
                statusLabel: "Review",
                actionTitle: "Review today",
                action: .reviewDay,
                remainingCalories: remainingCalories
            )
        }

        if let target = runRecoveryTarget, !target.isExpired(at: now) {
            let proteinTarget = boundedMacroTarget(
                desired: Double(target.targetProteinGrams),
                remainingCalories: remainingCalories,
                calorieShare: 0.45,
                gramsPerCalorie: 4,
                floor: 12
            )
            let caloriesAfterProtein = remainingCalories - Double(proteinTarget ?? 0) * 4
            let carbTarget = boundedMacroTarget(
                desired: min(Double(target.targetCarbGrams), remainingCarbs),
                remainingCalories: max(0, caloriesAfterProtein),
                calorieShare: 1.0,
                gramsPerCalorie: 4,
                floor: 10
            )
            return TodayFuelPlan(
                kind: .runRecovery,
                title: "Recovery fuel now",
                summary: "\(target.remainingMinutes(at: now)) min left in the run recovery window.",
                detail: "Use the remaining calorie budget for protein, carbs, and fluids. Keep it planned inside today's target.",
                statusLabel: "Run",
                actionTitle: "Find recovery food",
                action: .openRecoverySearch,
                remainingCalories: remainingCalories,
                targetProteinGrams: proteinTarget,
                targetCarbGrams: carbTarget,
                targetWaterOunces: max(0, Int((Double(target.rehydrateMilliLiters) / 29.5735).rounded()))
            )
        }

        if !workoutsToday.isEmpty && remainingCalories >= 150 {
            let proteinTarget = boundedMacroTarget(
                desired: min(max(remainingProtein * 0.55, 24), 45),
                remainingCalories: remainingCalories,
                calorieShare: 0.60,
                gramsPerCalorie: 4,
                floor: 15
            )
            let caloriesAfterProtein = remainingCalories - Double(proteinTarget ?? 0) * 4
            let carbTarget = boundedMacroTarget(
                desired: min(max(remainingCarbs * 0.35, 15), 60),
                remainingCalories: max(0, caloriesAfterProtein),
                calorieShare: 0.75,
                gramsPerCalorie: 4,
                floor: 10
            )
            return TodayFuelPlan(
                kind: .workoutRecovery,
                title: "Build the recovery meal",
                summary: "Training is logged. Make the next meal do recovery work.",
                detail: "Anchor protein first, add carbs if they fit, and keep the meal inside the remaining calorie budget.",
                statusLabel: "Training",
                actionTitle: "Fill macros",
                action: .fillMacros,
                remainingCalories: remainingCalories,
                targetProteinGrams: proteinTarget,
                targetCarbGrams: carbTarget
            )
        }

        if remainingProtein >= 30 && remainingCalories >= 250 {
            let proteinTarget = boundedMacroTarget(
                desired: min(max(remainingProtein * 0.45, 25), 55),
                remainingCalories: remainingCalories,
                calorieShare: 0.70,
                gramsPerCalorie: 4,
                floor: 20
            )
            return TodayFuelPlan(
                kind: .proteinCatchUp,
                title: "Anchor protein next",
                summary: "\(Int(remainingProtein.rounded()).formatted())g protein left today.",
                detail: "Choose the protein first, then spend the rest of the calories on carbs or fats only if they fit.",
                statusLabel: "Protein",
                actionTitle: "Fill macros",
                action: .fillMacros,
                remainingCalories: remainingCalories,
                targetProteinGrams: proteinTarget
            )
        }

        if hour >= 16 && remainingCalories >= 500 {
            return TodayFuelPlan(
                kind: .planDinner,
                title: "Plan the landing",
                summary: "\(Int(remainingCalories.rounded()).formatted()) cal left for the rest of today.",
                detail: "Use most of the budget on a real meal and leave a small snack buffer.",
                statusLabel: "Dinner",
                actionTitle: "Fill macros",
                action: .fillMacros,
                remainingCalories: remainingCalories
            )
        }

        return TodayFuelPlan(
            kind: .steadyDay,
            title: "Hold the rhythm",
            summary: "\(Int(remainingCalories.rounded()).formatted()) cal left today.",
            detail: "Keep servings honest and make the next choice easy to repeat.",
            statusLabel: "Steady",
            actionTitle: "No action needed",
            action: .none,
            remainingCalories: remainingCalories
        )
    }

    public static func makeWorkoutCompletionPlan(
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        sessionLog: WorkoutSessionLog,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayFuelPlan {
        var todayWithWorkout = today ?? DailyLog(date: calendar.startOfDay(for: now), meals: [])
        let knownSessionID = sessionLog.id
        let alreadyLogged = todayWithWorkout.exercises?.contains { exercise in
            guard let knownSessionID else { return false }
            return exercise.sessionID == knownSessionID
        } ?? false

        if !alreadyLogged {
            var exercises = todayWithWorkout.exercises ?? []
            exercises.append(LoggedExercise(
                name: workoutName(for: sessionLog),
                durationMinutes: estimatedDurationMinutes(for: sessionLog),
                caloriesBurned: 0,
                date: now,
                source: "routine",
                workoutID: sessionLog.routineID,
                sessionID: sessionLog.id
            ))
            todayWithWorkout.exercises = exercises
        }

        return makePlan(
            today: todayWithWorkout,
            goals: goals,
            runRecoveryTarget: nil,
            now: now,
            calendar: calendar
        )
    }

    private static func boundedMacroTarget(
        desired: Double,
        remainingCalories: Double,
        calorieShare: Double,
        gramsPerCalorie: Double,
        floor: Int
    ) -> Int? {
        guard desired > 0, remainingCalories > 0 else { return nil }
        let calorieBudget = max(0, remainingCalories * calorieShare)
        let maxGrams = Int((calorieBudget / gramsPerCalorie).rounded(.down))
        let grams = min(Int(desired.rounded()), maxGrams)
        return grams >= floor ? grams : nil
    }

    private static func workoutName(for sessionLog: WorkoutSessionLog) -> String {
        let names = sessionLog.completedExercises.prefix(2).map(\.exerciseName)
        guard !names.isEmpty else { return "Workout" }
        let suffix = sessionLog.completedExercises.count > names.count ? " +" : ""
        return names.joined(separator: ", ") + suffix
    }

    private static func estimatedDurationMinutes(for sessionLog: WorkoutSessionLog) -> Int {
        let setCount = sessionLog.completedExercises.reduce(0) { $0 + $1.sets.count }
        let seconds = sessionLog.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { setSum, set in
                setSum + (set.durationInSeconds ?? 0)
            }
        }
        return max(seconds / 60, setCount * 2, 1)
    }
}
