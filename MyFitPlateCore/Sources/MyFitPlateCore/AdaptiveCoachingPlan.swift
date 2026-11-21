import Foundation

public struct AdaptiveCoachingPlan: Equatable, Sendable {
    public enum ActionKind: String, Codable, Sendable {
        case logFood, reviewMeal, reviewTraining
    }
    public let title: String
    public let subtitle: String
    public let patternNote: String
    public let primaryAction: String
    public let mealMove: String
    public let trainingMove: String
    public let recoveryMove: String
    public let confidence: String
    public let dataPoints: [String]
    public let actionKind: ActionKind
    public let generatedAt: Date

    public init(
        title: String,
        subtitle: String,
        patternNote: String = "",
        primaryAction: String,
        mealMove: String,
        trainingMove: String,
        recoveryMove: String,
        confidence: String,
        dataPoints: [String],
        actionKind: ActionKind = .logFood,
        generatedAt: Date = Date()
    ) {
        self.title = title
        self.subtitle = subtitle
        self.patternNote = patternNote
        self.primaryAction = primaryAction
        self.mealMove = mealMove
        self.trainingMove = trainingMove
        self.recoveryMove = recoveryMove
        self.confidence = confidence
        self.dataPoints = dataPoints
        self.actionKind = actionKind
        self.generatedAt = generatedAt
    }
}

public extension InsightsRules {
    static func adaptiveCoachingPlan(
        today: DailyLog?,
        recentLogs: [DailyLog],
        recovery: RecoveryEvidence = .unavailable,
        goals: GoalSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AdaptiveCoachingPlan {
        let currentDay = calendar.startOfDay(for: now)
        let todayLog = today.flatMap { NutritionDayEvidence.civilDate(for: $0, calendar: calendar) == currentDay ? $0 : nil }
            ?? recentLogs.first { NutritionDayEvidence.civilDate(for: $0, calendar: calendar) == currentDay }
        let windowStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let windowLogs = NutritionDayEvidence.days(recentLogs, from: windowStart, through: now, now: now, calendar: calendar)
        let foodLogs = windowLogs.filter { NutritionDayEvidence.isComplete($0, now: now, calendar: calendar) }
        let loggedDays = Set(foodLogs.compactMap { NutritionDayEvidence.civilDate(for: $0, calendar: calendar) }).count
        let averageCalories = foodLogs.isEmpty ? 0 : foodLogs.reduce(0) { $0 + $1.totalCalories() } / Double(foodLogs.count)
        let averageProtein = foodLogs.isEmpty ? 0 : foodLogs.reduce(0) { $0 + $1.totalMacros().protein } / Double(foodLogs.count)
        let todayCalories = todayLog?.totalCalories() ?? 0
        let todayProtein = todayLog?.totalMacros().protein ?? 0
        let calorieGoal = max(goals.calories, 1)
        let proteinGoal = max(goals.protein, 1)
        let caloriesRemaining = calorieGoal - todayCalories
        let proteinRemaining = proteinGoal - todayProtein
        let workouts = windowLogs.flatMap { $0.exercises ?? [] }
        let lastWorkout = workouts.max { $0.date < $1.date }
        let daysSinceWorkout = lastWorkout.map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: calendar.startOfDay(for: now)).day ?? 0
        }
        let averageSleep = recovery.sleepHoursForGuidance
        let hour = calendar.component(.hour, from: now)
        let proteinAlignedDays = foodLogs.filter { $0.totalMacros().protein >= proteinGoal * 0.9 }.count
        let calorieAlignedDays = foodLogs.filter {
            abs($0.totalCalories() - calorieGoal) <= max(150, calorieGoal * 0.08)
        }.count

        let signal = loggedDays >= 5 ? "High signal" : loggedDays >= 3 ? "Useful signal" : "Building signal"
        let patternNote = coachingPatternNote(
            foodLogCount: foodLogs.count,
            proteinAlignedDays: proteinAlignedDays,
            calorieAlignedDays: calorieAlignedDays,
            workoutCount: workouts.count
        )
        let dataPoints = planDataPoints(
            loggedDays: loggedDays,
            averageCalories: averageCalories,
            calorieGoal: calorieGoal,
            averageProtein: averageProtein,
            proteinGoal: proteinGoal,
            foodLogCount: foodLogs.count,
            proteinAlignedDays: proteinAlignedDays,
            calorieAlignedDays: calorieAlignedDays,
            workouts: workouts.count,
            recovery: recovery
        )

        if recovery.hrvComparison == .belowUsual {
            return AdaptiveCoachingPlan(
                title: "Check in before training",
                subtitle: "Recent HRV is below your own recorded range. This is context, not a measure of today's readiness.",
                patternNote: patternNote,
                primaryAction: "Check how you feel during your warm-up",
                mealMove: "Keep regular meals and hydration in place.",
                trainingMove: "Keep your planned session flexible. Ease back if you feel unusually tired or unwell.",
                recoveryMove: "Consider sleep, stress, and how you feel alongside this trend. HRV alone cannot choose your training intensity.",
                confidence: "Personal HRV trend",
                dataPoints: dataPoints, actionKind: .reviewTraining, generatedAt: now
            )
        }

        if todayLog == nil && hour >= 11 {
            return AdaptiveCoachingPlan(
                title: "Get today's baseline",
                subtitle: "Maia needs one real food entry before the rest of the day gets precise.",
                patternNote: patternNote,
                primaryAction: "Log the next thing you eat",
                mealMove: "Start with the meal you are most confident about, even if the serving is approximate.",
                trainingMove: daysSinceWorkout.map { $0 >= 3 ? "Keep training simple today: one planned session or a brisk walk." : "Training rhythm is active. Do not force extra work just to fill the log." } ?? "If you train today, log it once so recovery advice can adapt.",
                recoveryMove: averageSleep > 0 && averageSleep < 6.5 ? "Lower sleep is in the data. Keep caffeine and hydration boringly consistent today." : "Keep water moving early so the evening does not carry the whole target.",
                confidence: signal,
                dataPoints: dataPoints, actionKind: .logFood, generatedAt: now
            )
        }

        if hour >= 15 && proteinRemaining > 35 && caloriesRemaining > 250 {
            return AdaptiveCoachingPlan(
                title: "Anchor protein next",
                subtitle: "The highest-value move is a protein-forward meal that still leaves room for dinner.",
                patternNote: patternNote,
                primaryAction: "Build the next meal around \(Int(min(max(proteinRemaining * 0.45, 25), 55)))g protein",
                mealMove: "Choose a lean protein first, then add carbs or fat only after the protein is covered.",
                trainingMove: workouts.isEmpty ? "A short walk after the meal is enough to create activity signal today." : "Training is logged. Treat this meal as recovery support.",
                recoveryMove: averageSleep > 0 && averageSleep < 6.5 ? "Keep the meal easy to digest and avoid turning low sleep into a harder training day." : "Hydrate with the meal so the protein target does not come with a late-night water scramble.",
                confidence: signal,
                dataPoints: dataPoints, actionKind: .reviewMeal, generatedAt: now
            )
        }

        if averageSleep > 0 && averageSleep < 6.5 {
            return AdaptiveCoachingPlan(
                title: "Protect recovery",
                subtitle: "Recorded nights have been shorter recently. Check how rested you feel before choosing today's effort.",
                patternNote: patternNote,
                primaryAction: "Keep today controlled and repeatable",
                mealMove: "Prioritize a normal calorie day with protein spread across two or three meals.",
                trainingMove: "Train at maintenance effort or choose lower-impact work if soreness is high.",
                recoveryMove: "Move bedtime earlier before adding more volume. Recovery is the multiplier here.",
                confidence: "Recent sleep trend",
                dataPoints: dataPoints, actionKind: .reviewTraining, generatedAt: now
            )
        }

        if let daysSinceWorkout, daysSinceWorkout >= 3 && daysSinceWorkout < 30 {
            return AdaptiveCoachingPlan(
                title: "Restart training rhythm",
                subtitle: "Nutrition is easier to steer when activity is not drifting.",
                patternNote: patternNote,
                primaryAction: "Do the next scheduled workout or a 20-minute run/walk",
                mealMove: "Keep calories close to target and put protein near the session.",
                trainingMove: "Make the win showing up, not setting a record.",
                recoveryMove: "Log sleep or water after the session so tomorrow's plan can adjust.",
                confidence: signal,
                dataPoints: dataPoints, actionKind: .reviewTraining, generatedAt: now
            )
        }

        if todayCalories > calorieGoal + 250 {
            return AdaptiveCoachingPlan(
                title: "Tighten the finish",
                subtitle: "You are above target today, so the best move is a clean landing.",
                patternNote: patternNote,
                primaryAction: "Keep the next choice light and high-satiety",
                mealMove: "Go lean protein, vegetables, or a low-calorie snack instead of trying to erase the day.",
                trainingMove: "A walk helps digestion and momentum, but do not punish-log exercise.",
                recoveryMove: "Close the day normally. One high day is data, not a derailment.",
                confidence: signal,
                dataPoints: dataPoints, actionKind: .logFood, generatedAt: now
            )
        }

        if hour >= 18 && caloriesRemaining > 700 {
            return AdaptiveCoachingPlan(
                title: "Plan the rest of today",
                subtitle: "There is enough room left that an intentional dinner beats grazing.",
                patternNote: patternNote,
                primaryAction: "Use Fill my macros or plan dinner now",
                mealMove: "Spend most of the remaining calories on a real meal, then leave a small snack buffer.",
                trainingMove: workouts.isEmpty ? "If steps are low, add a relaxed walk after dinner." : "Training is already represented. Keep recovery food steady.",
                recoveryMove: "Avoid saving too much protein for the final hour of the day.",
                confidence: signal,
                dataPoints: dataPoints, actionKind: .reviewMeal, generatedAt: now
            )
        }

        return AdaptiveCoachingPlan(
            title: "Hold the rhythm",
            subtitle: "The current pattern is workable. Keep the next choice simple and repeatable.",
            patternNote: patternNote,
            primaryAction: "Repeat the thing that made today easiest",
            mealMove: proteinRemaining > 20 ? "Nudge the next meal toward protein." : "Keep servings honest and do not over-optimize.",
            trainingMove: workouts.isEmpty ? "Add one easy activity entry if movement happens today." : "Training signal is in place.",
            recoveryMove: averageSleep > 0 ? "Consider recorded sleep alongside how rested you feel." : "There is not enough current sleep data to guide recovery. Use how you feel today.",
            confidence: signal,
            dataPoints: dataPoints, actionKind: .reviewMeal, generatedAt: now
        )
    }

    private static func planDataPoints(
        loggedDays: Int,
        averageCalories: Double,
        calorieGoal: Double,
        averageProtein: Double,
        proteinGoal: Double,
        foodLogCount: Int,
        proteinAlignedDays: Int,
        calorieAlignedDays: Int,
        workouts: Int,
        recovery: RecoveryEvidence
    ) -> [String] {
        var points = ["\(loggedDays) fully logged day\(loggedDays == 1 ? "" : "s")"]
        if averageCalories > 0 {
            points.append("\(Int(averageCalories.rounded())) cal avg vs \(Int(calorieGoal.rounded())) goal")
        }
        if averageProtein > 0 {
            points.append("\(Int(averageProtein.rounded()))g protein avg vs \(Int(proteinGoal.rounded()))g goal")
        }
        if foodLogCount >= 3 {
            points.append("\(proteinAlignedDays)/\(foodLogCount) protein days")
            points.append("\(calorieAlignedDays)/\(foodLogCount) calorie days")
        }
        points.append("\(workouts) workout\(workouts == 1 ? "" : "s") logged")
        points.append(contentsOf: recovery.dataPoints)
        return points
    }

    private static func coachingPatternNote(
        foodLogCount: Int,
        proteinAlignedDays: Int,
        calorieAlignedDays: Int,
        workoutCount: Int
    ) -> String {
        guard foodLogCount >= 3 else {
            return "Pattern: still building enough data for a weekly read."
        }

        if proteinAlignedDays < max(1, Int(ceil(Double(foodLogCount) * 0.45))) {
            return "Pattern: protein is the least consistent lever this week."
        }

        if calorieAlignedDays >= max(1, foodLogCount - 1) {
            return "Pattern: calories are landing close to target on most logged days."
        }

        if workoutCount >= 3 {
            return "Pattern: training rhythm is strong; recovery food matters more now."
        }

        return "Pattern: logging is consistent enough to steer one habit at a time."
    }
}
