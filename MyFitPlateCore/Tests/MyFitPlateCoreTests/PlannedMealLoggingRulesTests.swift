import XCTest
@testable import MyFitPlateCore

final class PlannedMealLoggingRulesTests: XCTestCase {
    func testOriginalProviderIDDoesNotCountAsAConsumedPlanOccurrence() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let food = FoodItem(id: "shared-product", name: "Rice", calories: 200)
        let lunch = PlannedMeal(id: "lunch", mealType: "Lunch", foodItem: food)
        let dinner = PlannedMeal(id: "dinner", mealType: "Dinner", foodItem: food)
        XCTAssertFalse(PlannedMealLoggingRules.isLogged(lunch, date: date, loggedFoodIDs: [food.id]))
        let receipt = PlannedMealLoggingRules.entryID(for: lunch, date: date)
        XCTAssertTrue(PlannedMealLoggingRules.isLogged(lunch, date: date, loggedFoodIDs: [receipt]))
        XCTAssertFalse(PlannedMealLoggingRules.isLogged(dinner, date: date, loggedFoodIDs: [receipt]))
        XCTAssertFalse(PlannedMealLoggingRules.isLogged(lunch, date: date.addingTimeInterval(86400), loggedFoodIDs: [receipt]))
    }

    func testEachPlannedOccurrenceHasAStableIdentityPerDayEvenWhenFoodsMatch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let food = FoodItem(id: "recipe", name: "Rice bowl", calories: 400, protein: 30)
        let lunch = PlannedMeal(id: "lunch", mealType: "Lunch", foodItem: food)
        let dinner = PlannedMeal(id: "dinner", mealType: "Dinner", foodItem: food)
        let entry = try XCTUnwrap(PlannedMealLoggingRules.food(for: lunch, date: date, calendar: calendar))
        XCTAssertEqual(entry.id, PlannedMealLoggingRules.food(for: lunch, date: date, calendar: calendar)?.id)
        XCTAssertNotEqual(entry.id, PlannedMealLoggingRules.food(for: dinner, date: date, calendar: calendar)?.id)
        XCTAssertNotEqual(entry.id, PlannedMealLoggingRules.food(for: lunch, date: date.addingTimeInterval(86400), calendar: calendar)?.id)
        XCTAssertEqual(entry.calories, food.calories)

        let snapshot = LivingDaySnapshotBuilder.make(
            date: date,
            dailyLog: DailyLog(date: date, meals: [Meal(name: "Snacks", foodItems: [entry])]),
            goals: TodayFuelPlanGoals(calories: 2100, protein: 160, carbs: 230, fats: 60),
            plannedMeals: [lunch, dinner],
            calendar: calendar
        )
        XCTAssertEqual(snapshot.events.filter { $0.kind == .plannedMeal }.count, 1,
                       "Moving a logged planned meal does not count it again in the remaining plan")
    }
}
