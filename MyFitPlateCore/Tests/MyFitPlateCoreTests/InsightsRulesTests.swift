import XCTest
@testable import MyFitPlateCore

final class InsightsRulesTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_767_225_600)

    func testLocalInsightsGenerateActionableFallbacksFromNutritionWorkoutAndWater() {
        let logs = [
            dailyLog(
                dayOffset: 0,
                calories: 2_300,
                protein: 120,
                water: 80,
                workoutCalories: 250
            ),
            dailyLog(
                dayOffset: 1,
                calories: 2_100,
                protein: 130,
                water: 64,
                workoutCalories: nil
            ),
            dailyLog(
                dayOffset: 2,
                calories: 2_200,
                protein: 125,
                water: 70,
                workoutCalories: 180
            )
        ]

        let insights = InsightsRules.localInsights(
            from: logs,
            sleepHours: [7.5, 8.0],
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 160, weightGoal: "Gain")
        )

        XCTAssertEqual(insights.count, 5)
        XCTAssertEqual(insights.map(\.priority), [100, 90, 85, 75, 70])
        XCTAssertEqual(insights[0].title, "Your Logging Base Is Building")
        XCTAssertEqual(insights[0].category, .positiveReinforcement)
        XCTAssertEqual(insights[0].sourceData, "3 logged days across 3 days analyzed")

        XCTAssertEqual(insights[1].title, "Protein Is the Easiest Lever")
        XCTAssertTrue(insights[1].message.contains("35g under"))
        XCTAssertEqual(insights[1].category, .macroBalance)

        XCTAssertEqual(insights[2].title, "Training and Nutrition Are Connected")
        XCTAssertTrue(insights[2].sourceData?.contains("2 workout entries") ?? false)

        XCTAssertEqual(insights[3].title, "Calorie Trend Check")
        XCTAssertTrue(insights[3].message.contains("200 kcal above"))

        XCTAssertEqual(insights[4].title, "Hydration Signal")
        XCTAssertTrue(insights[4].sourceData?.contains("71 oz") ?? false)
    }

    func testLocalInsightsIncludeSleepWhenOtherSignalsAreSparse() {
        let insights = InsightsRules.localInsights(
            from: [],
            sleepHours: [6.25, 7.75],
            goals: InsightsRules.GoalSnapshot(calories: 2_200, protein: 140, weightGoal: "Maintain")
        )

        XCTAssertEqual(insights.count, 2)
        XCTAssertEqual(insights[0].title, "Your Logging Base Is Building")
        XCTAssertEqual(insights[0].sourceData, "0 logged days across 0 days analyzed")
        XCTAssertEqual(insights[1].title, "Sleep Context Matters")
        XCTAssertEqual(insights[1].category, .sleep)
        XCTAssertTrue(insights[1].message.contains("7.0 hours"))
    }

    func testLocalInsightsUsePositiveProteinAndCloseCalorieMessaging() {
        let logs = [
            dailyLog(dayOffset: 0, calories: 1_980, protein: 150, water: nil, workoutCalories: nil),
            dailyLog(dayOffset: 1, calories: 2_040, protein: 170, water: nil, workoutCalories: nil)
        ]

        let insights = InsightsRules.localInsights(
            from: logs,
            sleepHours: [],
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 150, weightGoal: "Maintain")
        )

        XCTAssertEqual(insights.count, 3)
        XCTAssertEqual(insights[1].title, "Protein Is Carrying Well")
        XCTAssertTrue(insights[1].message.contains("at or above target"))
        XCTAssertEqual(insights[2].title, "Calorie Trend Check")
        XCTAssertTrue(insights[2].message.contains("close to target"))
    }

    func testNotificationPlanPrioritizesRecoveryAndPerformanceBeforeOtherHooks() {
        let recovery = InsightsRules.notificationPlan(
            for: signals(wellnessScore: 42, sleepScore: 95, phase: .ovulatory, caloriesRemaining: 900),
            hour: 19
        )
        XCTAssertEqual(recovery.strategy, "Recovery Warning")
        XCTAssertTrue(recovery.dataFocus.contains("42"))

        let peak = InsightsRules.notificationPlan(
            for: signals(wellnessScore: 94, sleepScore: 30, daysSinceLastWorkout: 6),
            hour: 19
        )
        XCTAssertEqual(peak.strategy, "Peak Performance")
        XCTAssertTrue(peak.tone.contains("Hype"))
    }

    func testNotificationPlanUsesSleepThenCycleThenNutritionPriority() {
        let sleep = InsightsRules.notificationPlan(
            for: signals(sleepScore: 45, phase: .follicular, caloriesRemaining: 700),
            hour: 19
        )
        XCTAssertEqual(sleep.strategy, "Sleep Recovery")

        let rested = InsightsRules.notificationPlan(
            for: signals(sleepScore: 90),
            hour: 12
        )
        XCTAssertEqual(rested.strategy, "Rested Momentum")

        let cycle = InsightsRules.notificationPlan(
            for: signals(phase: .luteal, caloriesRemaining: 800),
            hour: 19
        )
        XCTAssertEqual(cycle.strategy, "Cycle Syncing")
        XCTAssertEqual(cycle.tone, "Nurturing, validate their low energy.")

        let dinner = InsightsRules.notificationPlan(
            for: signals(caloriesRemaining: 700, proteinRemaining: 45),
            hour: 18
        )
        XCTAssertEqual(dinner.strategy, "Dinner Suggestion")
        XCTAssertTrue(dinner.dataFocus.contains("700 calories"))
    }

    func testNotificationPlanHandlesWorkoutLapseStepWarningCelebrationAndDefault() {
        let reengagement = InsightsRules.notificationPlan(
            for: signals(gender: "Male", daysSinceLastWorkout: 5, lastWorkoutName: "Pull Day"),
            hour: 14
        )
        XCTAssertEqual(reengagement.strategy, "Re-engagement")
        XCTAssertTrue(reengagement.tone.contains("tough love"))
        XCTAssertTrue(reengagement.dataFocus.contains("Pull Day"))

        let staleWorkoutDate = InsightsRules.notificationPlan(
            for: signals(daysSinceLastWorkout: 401, stepsToday: 3_000),
            hour: 19
        )
        XCTAssertEqual(staleWorkoutDate.strategy, "Step Goal Warning")

        let stepCelebration = InsightsRules.notificationPlan(
            for: signals(stepsToday: 12_500),
            hour: 12
        )
        XCTAssertEqual(stepCelebration.strategy, "Step Goal Celebration")

        let general = InsightsRules.notificationPlan(for: signals(), hour: 10)
        XCTAssertEqual(general.strategy, "General Motivation")
        XCTAssertEqual(general.tone, "Encouraging")
    }

    func testAdaptiveCoachingPlanPrioritizesProteinWhenDayHasRoom() {
        let now = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: fixedDate)!
        let today = dailyLog(dayOffset: 0, calories: 800, protein: 70, water: 40, workoutCalories: 250)

        let plan = InsightsRules.adaptiveCoachingPlan(
            today: today,
            recentLogs: [
                today,
                dailyLog(dayOffset: 1, calories: 2_000, protein: 120, water: nil, workoutCalories: nil),
                dailyLog(dayOffset: 2, calories: 2_100, protein: 125, water: nil, workoutCalories: nil)
            ],
            sleepHours: [7.2, 7.8],
            goals: InsightsRules.GoalSnapshot(calories: 2_300, protein: 160, weightGoal: "Gain"),
            now: now
        )

        XCTAssertEqual(plan.title, "Anchor protein next")
        XCTAssertTrue(plan.primaryAction.contains("protein"))
        XCTAssertTrue(plan.dataPoints.contains("3 logged days"))
        XCTAssertTrue(plan.patternNote.contains("protein"))
        XCTAssertTrue(plan.dataPoints.contains("0/3 protein days"))
    }

    func testAdaptiveCoachingPlanFallsBackToBaselineWhenTodayIsEmpty() {
        let now = Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: fixedDate)!

        let plan = InsightsRules.adaptiveCoachingPlan(
            today: nil,
            recentLogs: [dailyLog(dayOffset: 1, calories: 2_000, protein: 120, water: nil, workoutCalories: nil)],
            sleepHours: [],
            goals: InsightsRules.GoalSnapshot(calories: 2_100, protein: 150, weightGoal: "Maintain"),
            now: now
        )

        XCTAssertEqual(plan.title, "Get today's baseline")
        XCTAssertEqual(plan.primaryAction, "Log the next thing you eat")
        XCTAssertEqual(plan.confidence, "Building signal")
        XCTAssertEqual(plan.patternNote, "Pattern: still building enough data for a weekly read.")
    }

    func testAdaptiveCoachingPlanPrioritizesRecoveryOnLowSleep() {
        let now = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: fixedDate)!
        let today = dailyLog(dayOffset: 0, calories: 1_500, protein: 145, water: 64, workoutCalories: nil)

        let plan = InsightsRules.adaptiveCoachingPlan(
            today: today,
            recentLogs: [
                today,
                dailyLog(dayOffset: 1, calories: 1_950, protein: 150, water: nil, workoutCalories: nil),
                dailyLog(dayOffset: 2, calories: 2_020, protein: 155, water: nil, workoutCalories: nil),
                dailyLog(dayOffset: 3, calories: 1_980, protein: 150, water: nil, workoutCalories: nil),
                dailyLog(dayOffset: 4, calories: 2_010, protein: 152, water: nil, workoutCalories: nil)
            ],
            sleepHours: [5.8, 6.1, 6.0],
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 150, weightGoal: "Maintain"),
            now: now
        )

        XCTAssertEqual(plan.title, "Protect recovery")
        XCTAssertEqual(plan.confidence, "High signal")
        XCTAssertTrue(plan.dataPoints.contains("6.0h sleep avg"))
        XCTAssertEqual(plan.patternNote, "Pattern: calories are landing close to target on most logged days.")
    }

    func testAdaptiveCoachingPlanRecognizesStrongTrainingRhythmPattern() {
        let now = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: fixedDate)!
        let today = dailyLog(dayOffset: 0, calories: 1_850, protein: 150, water: 64, workoutCalories: 200)

        let plan = InsightsRules.adaptiveCoachingPlan(
            today: today,
            recentLogs: [
                today,
                dailyLog(dayOffset: 1, calories: 1_700, protein: 152, water: nil, workoutCalories: 220),
                dailyLog(dayOffset: 2, calories: 2_350, protein: 151, water: nil, workoutCalories: 180)
            ],
            sleepHours: [7.0, 7.2],
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 150, weightGoal: "Maintain"),
            now: now
        )

        XCTAssertEqual(plan.patternNote, "Pattern: training rhythm is strong; recovery food matters more now.")
        XCTAssertTrue(plan.dataPoints.contains("3/3 protein days"))
    }

    private func dailyLog(
        dayOffset: Int,
        calories: Double,
        protein: Double,
        water: Double?,
        workoutCalories: Double?
    ) -> DailyLog {
        let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: fixedDate)!
        let food = FoodItem(
            id: "food-\(dayOffset)",
            name: "Logged Food \(dayOffset)",
            calories: calories,
            protein: protein,
            carbs: 200,
            fats: 60
        )
        let exercises = workoutCalories.map {
            [LoggedExercise(
                id: "exercise-\(dayOffset)",
                name: "Workout",
                durationMinutes: 45,
                caloriesBurned: $0,
                date: date,
                source: "manual"
            )]
        }
        let waterTracker = water.map {
            WaterTracker(totalOunces: $0, goalOunces: 64, date: date)
        }
        return DailyLog(
            id: "log-\(dayOffset)",
            date: date,
            meals: [Meal(name: "Meals", foodItems: [food])],
            waterTracker: waterTracker,
            exercises: exercises
        )
    }

    private func signals(
        gender: String = "Female",
        wellnessScore: Int? = nil,
        sleepScore: Int? = nil,
        phase: MenstrualPhase? = nil,
        caloriesRemaining: Double = 0,
        proteinRemaining: Double = 0,
        daysSinceLastWorkout: Int = 0,
        lastWorkoutName: String? = nil,
        stepsToday: Double = 6_000
    ) -> InsightsRules.NotificationSignals {
        InsightsRules.NotificationSignals(
            gender: gender,
            phase: phase,
            wellnessScore: wellnessScore,
            sleepScore: sleepScore,
            caloriesRemaining: caloriesRemaining,
            proteinRemaining: proteinRemaining,
            daysSinceLastWorkout: daysSinceLastWorkout,
            lastWorkoutName: lastWorkoutName,
            stepsToday: stepsToday,
            activeEnergyToday: 250
        )
    }

    // MARK: - Prompt Generation Tests

    func testCreateMealSuggestionPrompt() {
        let prompt = InsightsRules.createMealSuggestionPrompt(
            remainingCalories: 500, remainingProtein: 30, remainingCarbs: 40, remainingFats: 15,
            mealType: "Dinner", proteinPrefs: "Chicken, Beef", carbPrefs: "Rice", veggiePrefs: "Broccoli", cuisinePrefs: "Mexican"
        )
        
        XCTAssertTrue(prompt.contains("Dinner"))
        XCTAssertTrue(prompt.contains("Calories: 500"))
        XCTAssertTrue(prompt.contains("Protein: 30g"))
        XCTAssertTrue(prompt.contains("Carbs: 40g"))
        XCTAssertTrue(prompt.contains("Fats: 15g"))
        XCTAssertTrue(prompt.contains("Chicken, Beef"))
        XCTAssertTrue(prompt.contains("Mexican"))
        XCTAssertFalse(prompt.contains("on hand"), "No pantry section when no items are passed")
    }

    func testCreateMealSuggestionPromptIncludesPantry() {
        let prompt = InsightsRules.createMealSuggestionPrompt(
            remainingCalories: 650, remainingProtein: 40, remainingCarbs: 50, remainingFats: 20,
            mealType: "Dinner", proteinPrefs: "any", carbPrefs: "any", veggiePrefs: "any", cuisinePrefs: "any",
            pantryItems: ["Ground turkey", "Bell peppers", "Brown rice"]
        )

        XCTAssertTrue(prompt.contains("on hand"))
        XCTAssertTrue(prompt.contains("Ground turkey, Bell peppers, Brown rice"))
        XCTAssertTrue(prompt.contains("build the meal primarily from these"))
    }

    func testCreateOperatorPrompt() {
        let prompt = InsightsRules.createOperatorPrompt(message: "Log an apple", context: "User is in maintenance")
        XCTAssertTrue(prompt.contains("Log an apple"))
        XCTAssertTrue(prompt.contains("User is in maintenance"))
        XCTAssertTrue(prompt.contains("log_food"))
        XCTAssertTrue(prompt.contains("adjust_goal"))
    }

    func testCreateSmartNotificationPrompt() {
        let plan = InsightsRules.NotificationPlan(strategy: "Test Strategy", tone: "Hype", dataFocus: "Hit goal")
        let prompt = InsightsRules.createSmartNotificationPrompt(plan: plan, gender: "Female")
        XCTAssertTrue(prompt.contains("Female"))
        XCTAssertTrue(prompt.contains("Test Strategy"))
        XCTAssertTrue(prompt.contains("Hype"))
        XCTAssertTrue(prompt.contains("Hit goal"))
    }

    func testCreateDailyBriefingPrompt() {
        let prompt = InsightsRules.createDailyBriefingPrompt(wellnessScoreSummary: "Excellent", todaysWorkout: "Upper Body")
        XCTAssertTrue(prompt.contains("Excellent"))
        XCTAssertTrue(prompt.contains("Upper Body"))
    }

    func testCreateAIPrompt() {
        let prompt = InsightsRules.createAIPrompt(
            dailyNutritionSummary: "Nutri Summary",
            dailyWorkoutSummary: "Workout Summary",
            sleepSummaryString: "Sleep Summary",
            journalSummary: "Journal Summary",
            userGoals: "Goals Summary"
        )
        XCTAssertTrue(prompt.contains("Nutri Summary"))
        XCTAssertTrue(prompt.contains("Workout Summary"))
        XCTAssertTrue(prompt.contains("Sleep Summary"))
        XCTAssertTrue(prompt.contains("Journal Summary"))
        XCTAssertTrue(prompt.contains("Goals Summary"))
    }

    func testDetermineMealType() {
        var components = DateComponents()
        components.hour = 8
        let breakfastTime = Calendar.current.date(from: components)!
        XCTAssertEqual(InsightsRules.determineMealType(for: breakfastTime), "Breakfast")

        components.hour = 13
        let lunchTime = Calendar.current.date(from: components)!
        XCTAssertEqual(InsightsRules.determineMealType(for: lunchTime), "Lunch")

        components.hour = 18
        let dinnerTime = Calendar.current.date(from: components)!
        XCTAssertEqual(InsightsRules.determineMealType(for: dinnerTime), "Dinner")

        components.hour = 22
        let snackTime = Calendar.current.date(from: components)!
        XCTAssertEqual(InsightsRules.determineMealType(for: snackTime), "Snack")
    }

    func testDetermineSmartSuggestion() {
        let insightNoLog = InsightsRules.determineSmartSuggestion(log: nil, isToday: true, hour: 10, proteinGoal: 150)
        XCTAssertEqual(insightNoLog.title, "Welcome!")

        let log = dailyLog(dayOffset: 0, calories: 1500, protein: 120, water: nil, workoutCalories: nil)
        let insightLateProtein = InsightsRules.determineSmartSuggestion(log: log, isToday: true, hour: 20, proteinGoal: 150)
        XCTAssertEqual(insightLateProtein.title, "Hit Your Protein Goal")

        let insightGreatWork = InsightsRules.determineSmartSuggestion(log: log, isToday: true, hour: 10, proteinGoal: 150)
        XCTAssertEqual(insightGreatWork.title, "Keep Up the Great Work!")
    }

    func testAdaptiveCoachingPlanHRVRedRecoveryAlert() {
        let now = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: fixedDate)!
        let today = dailyLog(dayOffset: 0, calories: 1_800, protein: 140, water: 64, workoutCalories: nil)

        let plan = InsightsRules.adaptiveCoachingPlan(
            today: today,
            recentLogs: [today],
            sleepHours: [6.5, 7.0],
            hrvAverage: 32.0,
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 150, weightGoal: "Maintain"),
            now: now
        )

        XCTAssertEqual(plan.title, "Red Recovery Alert")
        XCTAssertEqual(plan.primaryAction, "Switch to active recovery or rest")
        XCTAssertTrue(plan.subtitle.contains("32 ms"))
    }

    func testAdaptiveCoachingPlanHRVPeakGreenRecovery() {
        let now = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: fixedDate)!
        let today = dailyLog(dayOffset: 0, calories: 1_800, protein: 140, water: 64, workoutCalories: nil)

        let plan = InsightsRules.adaptiveCoachingPlan(
            today: today,
            recentLogs: [today],
            sleepHours: [7.5, 8.0],
            hrvAverage: 62.0,
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 150, weightGoal: "Maintain"),
            now: now
        )

        XCTAssertEqual(plan.title, "Peak Recovery State (Green)")
        XCTAssertEqual(plan.primaryAction, "Push intensity or tackle progressive overload")
        XCTAssertTrue(plan.subtitle.contains("62 ms"))
    }
}
