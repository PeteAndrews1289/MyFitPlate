import Foundation

public struct AdaptiveCoachingPlan: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let patternNote: String
    public let primaryAction: String
    public let mealMove: String
    public let trainingMove: String
    public let recoveryMove: String
    public let confidence: String
    public let dataPoints: [String]

    public init(
        title: String,
        subtitle: String,
        patternNote: String = "",
        primaryAction: String,
        mealMove: String,
        trainingMove: String,
        recoveryMove: String,
        confidence: String,
        dataPoints: [String]
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
    }
}

public extension InsightsRules {
    static func adaptiveCoachingPlan(
        today: DailyLog?,
        recentLogs: [DailyLog],
        sleepHours: [Double],
        hrvAverage: Double? = nil,
        goals: GoalSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AdaptiveCoachingPlan {
        let todayLog = today ?? recentLogs.first { calendar.isDate($0.date, inSameDayAs: now) }
        let loggedDays = Set(recentLogs.map { calendar.startOfDay(for: $0.date) }).count
        let foodLogs = recentLogs.filter { !$0.meals.flatMap(\.foodItems).isEmpty }
        let averageCalories = foodLogs.isEmpty ? 0 : foodLogs.reduce(0) { $0 + $1.totalCalories() } / Double(foodLogs.count)
        let averageProtein = foodLogs.isEmpty ? 0 : foodLogs.reduce(0) { $0 + $1.totalMacros().protein } / Double(foodLogs.count)
        let todayCalories = todayLog?.totalCalories() ?? 0
        let todayProtein = todayLog?.totalMacros().protein ?? 0
        let calorieGoal = max(goals.calories, 1)
        let proteinGoal = max(goals.protein, 1)
        let caloriesRemaining = calorieGoal - todayCalories
        let proteinRemaining = proteinGoal - todayProtein
        let workouts = recentLogs.flatMap { $0.exercises ?? [] }
        let lastWorkout = workouts.max { $0.date < $1.date }
        let daysSinceWorkout = lastWorkout.map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: calendar.startOfDay(for: now)).day ?? 0
        }
        let averageSleep = sleepHours.isEmpty ? 0 : sleepHours.reduce(0, +) / Double(sleepHours.count)
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
            averageSleep: averageSleep,
            hrvAverage: hrvAverage
        )

        if let hrv = hrvAverage, hrv > 0 && hrv < 38.0 {
            return AdaptiveCoachingPlan(
                title: "Red Recovery Alert",
                subtitle: "HRV is suppressed (\(Int(hrv.rounded())) ms). Autonomic nervous system recovery is compromised today.",
                patternNote: patternNote,
                primaryAction: "Switch to active recovery or rest",
                mealMove: "Prioritize anti-inflammatory whole foods and keep protein intake high (\(Int(proteinGoal.rounded()))g) to support tissue repair.",
                trainingMove: "Avoid high-intensity intervals or heavy lifting. Choose mobility work, zone 1 cardio, or complete rest today.",
                recoveryMove: "Target 8+ hours of sleep tonight. Hydrate early and consider magnesium before bed.",
                confidence: signal,
                dataPoints: dataPoints
            )
        }

        if let hrv = hrvAverage, hrv >= 55.0 && averageSleep >= 7.0 {
            return AdaptiveCoachingPlan(
                title: "Peak Recovery State (Green)",
                subtitle: "HRV is strong (\(Int(hrv.rounded())) ms) and sleep is solid (\(String(format: "%.1f", averageSleep))h). Your body is primed for adaptation.",
                patternNote: patternNote,
                primaryAction: "Push intensity or tackle progressive overload",
                mealMove: "Ensure pre- and post-workout carbohydrates match your training strain.",
                trainingMove: "Great day for PR attempts, heavy compound lifts, or high-intensity interval training.",
                recoveryMove: "Capitalize on high recovery capacity. Do not skip post-workout hydration and refueling.",
                confidence: signal,
                dataPoints: dataPoints
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
                dataPoints: dataPoints
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
                dataPoints: dataPoints
            )
        }

        if averageSleep > 0 && averageSleep < 6.5 {
            return AdaptiveCoachingPlan(
                title: "Protect recovery",
                subtitle: "Recent sleep is the limiter, so the plan should support consistency instead of heroics.",
                patternNote: patternNote,
                primaryAction: "Keep today controlled and repeatable",
                mealMove: "Prioritize a normal calorie day with protein spread across two or three meals.",
                trainingMove: "Train at maintenance effort or choose lower-impact work if soreness is high.",
                recoveryMove: "Move bedtime earlier before adding more volume. Recovery is the multiplier here.",
                confidence: signal,
                dataPoints: dataPoints
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
                dataPoints: dataPoints
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
                dataPoints: dataPoints
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
                dataPoints: dataPoints
            )
        }

        return AdaptiveCoachingPlan(
            title: "Hold the rhythm",
            subtitle: "The current pattern is workable. Keep the next choice simple and repeatable.",
            patternNote: patternNote,
            primaryAction: "Repeat the thing that made today easiest",
            mealMove: proteinRemaining > 20 ? "Nudge the next meal toward protein." : "Keep servings honest and do not over-optimize.",
            trainingMove: workouts.isEmpty ? "Add one easy activity entry if movement happens today." : "Training signal is in place.",
            recoveryMove: averageSleep > 0 ? "Use sleep trend as the guardrail for intensity." : "Add sleep data when available for sharper coaching.",
            confidence: signal,
            dataPoints: dataPoints
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
        averageSleep: Double,
        hrvAverage: Double? = nil
    ) -> [String] {
        var points = ["\(loggedDays) logged day\(loggedDays == 1 ? "" : "s")"]
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
        if averageSleep > 0 {
            points.append("\(String(format: "%.1f", averageSleep))h sleep avg")
        }
        if let hrv = hrvAverage, hrv > 0 {
            points.append("\(Int(hrv.rounded())) ms HRV avg")
        }
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
