import XCTest
@testable import MyFitPlateCore

final class PlannedMealLoggingRulesTests: XCTestCase {
    func testActualGramsScaleOnlyDiaryOccurrenceAndReopenInTheSameUnit() throws {
        let rice = FoodItem(name: "Cooked rice", calories: 325, protein: 7, fiber: 3,
                            servingSize: "250 g", servingWeight: 250)
        let meal = PlannedMeal(mealType: "Dinner", foodItem: rice)
        let original = try XCTUnwrap(PlannedMealLoggingRules.food(for: meal, date: Date()))
        let entry = try XCTUnwrap(PlannedMealLoggingRules.actualPortion(of: original, amount: 180))
        XCTAssertEqual(entry.id, original.id)
        XCTAssertEqual(entry.timestamp, original.timestamp)
        XCTAssertEqual(entry.calories, 234, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(entry.fiber), 2.16, accuracy: 0.001)
        XCTAssertNil(entry.calcium)
        XCTAssertEqual(PlannedMealLoggingRules.editablePortion(of: entry).amount, 180)
        XCTAssertEqual(PlannedMealLoggingRules.editablePortion(of: entry).unit, "g")
        XCTAssertEqual(ServingNutritionCalculator.displayPortion(entry.servingSize), "180 g")
        XCTAssertEqual(meal.plannedFood?.calories, 325)
        XCTAssertNil(PlannedMealLoggingRules.actualPortion(of: original, amount: 0))
        XCTAssertNil(PlannedMealLoggingRules.actualPortion(of: original, amount: 1e30))
    }

    func testReviewUsesPrintedServingWithoutInferringGramsFromLegacyWeight() throws {
        let food = FoodItem(name: "Oats", calories: 100, servingSize: "1 bowl")
        let result = try XCTUnwrap(PlannedMealLoggingRules.actualPortion(of: food, amount: 0.5))
        XCTAssertEqual(result.servingUnit, "bowl")
        XCTAssertEqual(result.calories, 50)
        let mixture = try MealCompositionRules.food(.init(title: "Breakfast", components: [food], sourceID: food.id))
        let half = try XCTUnwrap(PlannedMealLoggingRules.actualPortion(of: mixture, amount: 0.5))
        XCTAssertEqual(half.mealComposition?.components.first?.calories, 50)
    }

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
