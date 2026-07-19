import XCTest
@testable import MyFitPlateCore

final class LivingDaySnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var day: Date {
        Date(timeIntervalSince1970: 1_768_435_200)
    }

    private var goals: TodayFuelPlanGoals {
        TodayFuelPlanGoals(calories: 2_100, protein: 160, carbs: 230, fats: 60)
    }

    func testBuildsSortedMealAndActivityPathWithBudgets() throws {
        let breakfastTime = day.addingTimeInterval(8 * 60 * 60)
        let lunch = FoodItem(
            id: "lunch",
            name: "Chicken bowl",
            calories: 620,
            protein: 52,
            carbs: 70,
            fats: 16,
            servingSize: "1 bowl",
            servingWeight: 420,
            timestamp: day.addingTimeInterval(12.5 * 60 * 60),
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "1")
        )
        let breakfast = FoodItem(
            id: "breakfast",
            name: "Protein oats",
            calories: 410,
            protein: 34,
            carbs: 52,
            fats: 10,
            servingSize: "1 bowl",
            servingWeight: 330,
            timestamp: breakfastTime,
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "2")
        )
        let log = DailyLog(
            date: day,
            meals: [
                Meal(name: "Lunch", foodItems: [lunch]),
                Meal(name: "Breakfast", foodItems: [breakfast])
            ]
        )
        let plannedFood = FoodItem(
            name: "Salmon dinner",
            calories: 540,
            protein: 45,
            carbs: 48,
            fats: 19,
            servingSize: "1 plate",
            servingWeight: 390,
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "3")
        )
        let planned = PlannedMeal(mealType: "Dinner", foodItem: plannedFood)
        let walk = LivingDayActivityInput(
            id: "walk",
            kind: .walk,
            title: "Outdoor walk",
            detail: "3.3 mi, route approximate indoors",
            startDate: day.addingTimeInterval(15 * 60 * 60),
            endDate: day.addingTimeInterval(16.5 * 60 * 60),
            state: .completed,
            destination: .runs
        )

        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(17 * 60 * 60),
            dailyLog: log,
            goals: goals,
            plannedMeals: [planned],
            activities: [walk],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.events.map(\.kind), [.meal, .meal, .walk, .plannedMeal])
        XCTAssertEqual(snapshot.events.first?.title, "Breakfast")
        XCTAssertEqual(snapshot.events.first?.timing, .exact)
        XCTAssertEqual(snapshot.budget.calories.consumed, 1_030)
        XCTAssertEqual(snapshot.budget.calories.planned, 540)
        XCTAssertEqual(snapshot.budget.calories.remaining, 530)
        XCTAssertEqual(snapshot.budget.protein.remaining, 29)
        XCTAssertEqual(snapshot.nextAction.proteinGrams, 29)
        XCTAssertEqual(snapshot.nextAction.detail, "29 g protein left today")
        XCTAssertEqual(snapshot.currentTime, day.addingTimeInterval(17 * 60 * 60))
        XCTAssertTrue(snapshot.events.allSatisfy { snapshot.pathWindow.position(for: $0.startDate) >= 0 })
    }

    func testMissingMealTimestampsBecomeApproximatePeriods() {
        let food = FoodItem(name: "Toast", calories: 200, protein: 8, carbs: 34, fats: 4)
        let log = DailyLog(date: day, meals: [Meal(name: "Breakfast", foodItems: [food])])

        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(9 * 60 * 60),
            dailyLog: log,
            goals: goals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.events.first?.timing, .approximate)
        XCTAssertEqual(
            calendar.component(.hour, from: snapshot.events[0].startDate),
            8
        )
    }

    func testFractionalProteinGoalKeepsBudgetAndActionInAgreement() {
        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(17 * 60 * 60),
            dailyLog: nil,
            goals: TodayFuelPlanGoals(calories: 2_100, protein: 146.4, carbs: 230, fats: 60),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.budget.protein.remaining, 146.4)
        XCTAssertEqual(snapshot.nextAction.proteinGrams, 146)
        XCTAssertEqual(snapshot.nextAction.detail, "146 g protein left today")
    }

    func testContradictoryFoodUsesCorrectionEvidence() {
        let food = FoodItem(
            name: "Broken label",
            calories: 150,
            protein: 2,
            carbs: 20,
            fats: 4,
            saturatedFat: 12,
            servingSize: "1 serving",
            servingWeight: 30,
            sourceMetadata: .database(.openFoodFacts, sourceName: "Open Food Facts", sourceID: "bad")
        )
        let log = DailyLog(date: day, meals: [Meal(name: "Snack", foodItems: [food])])

        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(14 * 60 * 60),
            dailyLog: log,
            goals: goals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.events.first?.evidence, .correction)
        XCTAssertEqual(snapshot.nextAction.kind, .trustReview)
    }

    func testInvalidNutritionAndGoalsStayUnavailableInsteadOfZero() {
        let invalid = FoodItem(name: "Invalid", calories: .nan, protein: 10, carbs: 20, fats: 5)
        let log = DailyLog(date: day, meals: [Meal(name: "Lunch", foodItems: [invalid])])
        let invalidGoals = TodayFuelPlanGoals(calories: .infinity, protein: 0, carbs: 200, fats: 60)

        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day,
            dailyLog: log,
            goals: invalidGoals,
            calendar: calendar
        )

        XCTAssertNil(snapshot.budget.calories.consumed)
        XCTAssertNil(snapshot.budget.calories.target)
        XCTAssertNil(snapshot.budget.protein.target)
        XCTAssertFalse(snapshot.budget.isFullyAvailable)
    }

    func testHistoricalDayDoesNotExposeCurrentTimeMarker() {
        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(2 * 86_400),
            dailyLog: nil,
            goals: goals,
            calendar: calendar
        )

        XCTAssertNil(snapshot.currentTime)
    }

    func testPathWindowExpandsForEarlyEventAndClampsToDay() {
        let activity = LivingDayActivityInput(
            id: "early",
            kind: .run,
            title: "Early run",
            detail: "Easy",
            startDate: day.addingTimeInterval(5 * 60 * 60),
            endDate: day.addingTimeInterval(6 * 60 * 60),
            state: .completed,
            destination: .runs
        )
        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(12 * 60 * 60),
            dailyLog: nil,
            goals: goals,
            activities: [activity],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.pathWindow.start, day.addingTimeInterval(4 * 60 * 60))
        XCTAssertLessThanOrEqual(snapshot.pathWindow.end, day.addingTimeInterval(86_400))
    }

    func testLoggedPlannedFoodIsNotCountedOrShownTwice() {
        var food = FoodItem(
            id: "planned-dinner",
            name: "Salmon dinner",
            calories: 540,
            protein: 45,
            carbs: 48,
            fats: 19,
            servingSize: "1 plate",
            servingWeight: 390
        )
        let planned = PlannedMeal(mealType: "Dinner", foodItem: food)
        food.timestamp = day.addingTimeInterval(18.5 * 60 * 60)
        let log = DailyLog(date: day, meals: [Meal(name: "Dinner", foodItems: [food])])

        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(20 * 60 * 60),
            dailyLog: log,
            goals: goals,
            plannedMeals: [planned],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.events.map(\.kind), [.meal])
        XCTAssertEqual(snapshot.budget.calories.consumed, 540)
        XCTAssertEqual(snapshot.budget.calories.planned, 0)
    }

    func testLoggingOneRepeatedPlannedFoodKeepsTheOtherPlannedOccurrence() {
        var food = FoodItem(
            id: "repeat-meal",
            name: "Chicken bowl",
            calories: 500,
            protein: 40,
            carbs: 55,
            fats: 14
        )
        let plannedLunch = PlannedMeal(mealType: "Lunch", foodItem: food)
        let plannedDinner = PlannedMeal(mealType: "Dinner", foodItem: food)
        food.timestamp = day.addingTimeInterval(12 * 60 * 60)
        let log = DailyLog(date: day, meals: [Meal(name: "Lunch", foodItems: [food])])

        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(14 * 60 * 60),
            dailyLog: log,
            goals: goals,
            plannedMeals: [plannedLunch, plannedDinner],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.events.map(\.kind), [.meal, .plannedMeal])
        XCTAssertEqual(snapshot.events.last?.title, "Chicken bowl")
        XCTAssertEqual(snapshot.budget.calories.consumed, 500)
        XCTAssertEqual(snapshot.budget.calories.planned, 500)
    }

    func testLoggedExerciseUsesSourceTimeSemanticsAndClassifiesActivity() {
        let healthWalk = LoggedExercise(
            id: "walk",
            name: "Outdoor Walk",
            durationMinutes: 45,
            caloriesBurned: 210,
            date: day.addingTimeInterval(9 * 60 * 60),
            source: "HealthKit"
        )
        let manualLift = LoggedExercise(
            id: "lift",
            name: "Upper Body Strength",
            durationMinutes: 60,
            caloriesBurned: 300,
            date: day.addingTimeInterval(19 * 60 * 60),
            source: "routine"
        )

        let walk = LivingDayActivityInput(exercise: healthWalk)
        let lift = LivingDayActivityInput(exercise: manualLift)

        XCTAssertEqual(walk.kind, .walk)
        XCTAssertEqual(walk.destination, .runs)
        XCTAssertEqual(walk.startDate, healthWalk.date)
        XCTAssertEqual(walk.endDate, healthWalk.date.addingTimeInterval(45 * 60))
        XCTAssertEqual(lift.kind, .strength)
        XCTAssertEqual(lift.destination, .workouts)
        XCTAssertEqual(lift.startDate, manualLift.date.addingTimeInterval(-60 * 60))
        XCTAssertEqual(lift.endDate, manualLift.date)
        XCTAssertEqual(lift.detail, "60 min · 300 active cal")
    }

    func testPlannedMealsCanCloseProteinGapWithoutContradictoryAction() {
        let loggedFood = FoodItem(
            id: "breakfast",
            name: "Breakfast",
            calories: 700,
            protein: 50,
            carbs: 80,
            fats: 20,
            timestamp: day.addingTimeInterval(8 * 60 * 60)
        )
        let plannedFood = FoodItem(
            id: "dinner",
            name: "Dinner",
            calories: 650,
            protein: 115,
            carbs: 55,
            fats: 20
        )
        let log = DailyLog(date: day, meals: [Meal(name: "Breakfast", foodItems: [loggedFood])])

        let snapshot = LivingDaySnapshotBuilder.make(
            date: day,
            now: day.addingTimeInterval(14 * 60 * 60),
            dailyLog: log,
            goals: goals,
            plannedMeals: [PlannedMeal(mealType: "Dinner", foodItem: plannedFood)],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.budget.protein.remaining, -5)
        XCTAssertEqual(snapshot.nextAction.kind, .steadyDay)
        XCTAssertEqual(snapshot.nextAction.title, "Your Plan Covers Protein")
        XCTAssertEqual(snapshot.nextAction.deepLink, "myfitplate://meal-plan")
    }

    func testSnapshotAndPrivacyProjectionStayWithinLocalRenderBudget() {
        let breakfast = FoodItem(
            id: "performance-breakfast",
            name: "Breakfast",
            calories: 510,
            protein: 34,
            carbs: 58,
            fats: 16,
            timestamp: day.addingTimeInterval(8 * 60 * 60)
        )
        let log = DailyLog(
            date: day,
            meals: [Meal(name: "Breakfast", foodItems: [breakfast])]
        )
        let activity = LivingDayActivityInput(
            id: "performance-run",
            kind: .run,
            title: "Easy run",
            detail: "45 min",
            startDate: day.addingTimeInterval(17 * 60 * 60),
            endDate: day.addingTimeInterval(17.75 * 60 * 60),
            state: .planned,
            destination: .runs
        )

        let startedAt = Date().timeIntervalSinceReferenceDate
        var projectedEventCount = 0
        for _ in 0..<300 {
            let snapshot = LivingDaySnapshotBuilder.make(
                date: day,
                now: day.addingTimeInterval(12 * 60 * 60),
                dailyLog: log,
                goals: goals,
                activities: [activity],
                calendar: calendar
            )
            projectedEventCount += WidgetPathProjection.make(from: snapshot).count
            projectedEventCount += LivingDayShareBuilder.make(
                from: snapshot,
                selection: [.budget, .path, .trust, .action]
            ).events.count
        }
        let elapsed = Date().timeIntervalSinceReferenceDate - startedAt

        XCTAssertEqual(projectedEventCount, 1_200)
        XCTAssertLessThan(elapsed, 3, "Living Day assembly must remain presentation-local and fast.")
    }
}
