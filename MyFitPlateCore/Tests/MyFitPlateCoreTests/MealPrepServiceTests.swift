import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPrepServiceTests: XCTestCase {

    private func day(_ id: String, _ meals: [PlannedMeal]) -> MealPlanDay {
        MealPlanDay(id: id, date: Date(), meals: meals)
    }

    func testAggregatesAndMergesIngredientsAcrossDays() {
        let service = MealPrepService()
        let days = [
            day("d1", [
                PlannedMeal(mealType: "Chicken Bowl",
                            ingredients: ["200 g Chicken", "1 cup Rice"],
                            instructions: "1. Cook chicken\n2. Cook rice")
            ]),
            day("d2", [
                PlannedMeal(mealType: "Chicken Salad",
                            ingredients: ["100 g Chicken"],
                            instructions: "1. Chop")
            ])
        ]

        service.aggregate(days: days)

        let allBulk = service.bulkIngredients.values.flatMap { $0 }
        XCTAssertEqual(allBulk.count, 2, "Chicken (merged across both days) + Rice")

        let chicken = allBulk.first { $0.name.localizedCaseInsensitiveContains("chicken") }
        XCTAssertEqual(chicken?.quantity ?? 0, 300, accuracy: 0.01, "200 g + 100 g")
        XCTAssertEqual(chicken?.originalRecipes.count, 2, "appears in both recipes")

        // Steps: leading "N. " numbering stripped, all non-empty.
        XCTAssertEqual(service.prepSteps.count, 3)
        XCTAssertTrue(service.prepSteps.contains { $0.step == "Cook chicken" })
        XCTAssertTrue(service.prepSteps.contains { $0.step == "Chop" })
        XCTAssertFalse(
            service.prepSteps.contains { $0.step.range(of: "^\\d+\\.", options: .regularExpression) != nil },
            "leading numbering must be stripped"
        )
    }

    func testEmptyDaysProduceNothing() {
        let service = MealPrepService()
        service.aggregate(days: [])
        XCTAssertTrue(service.bulkIngredients.isEmpty)
        XCTAssertTrue(service.prepSteps.isEmpty)
    }

    func testMealWithoutFoodItemUsesMealTypeAsRecipeName() {
        let service = MealPrepService()
        service.aggregate(days: [day("d", [
            PlannedMeal(mealType: "Snack", ingredients: ["1 Apple"], instructions: nil)
        ])])
        let bulk = service.bulkIngredients.values.flatMap { $0 }
        XCTAssertEqual(bulk.first?.originalRecipes, ["Snack"])
    }

    func testReaggregateReplacesPreviousResult() {
        let service = MealPrepService()
        service.aggregate(days: [day("d", [
            PlannedMeal(mealType: "A", ingredients: ["100 g Beef"], instructions: nil)
        ])])
        XCTAssertEqual(service.bulkIngredients.values.flatMap { $0 }.count, 1)

        // A second call must replace, not accumulate.
        service.aggregate(days: [day("d2", [
            PlannedMeal(mealType: "B", ingredients: ["50 g Tofu"], instructions: nil)
        ])])
        let names = service.bulkIngredients.values.flatMap { $0 }.map { $0.name.lowercased() }
        XCTAssertTrue(names.contains { $0.contains("tofu") })
        XCTAssertFalse(names.contains { $0.contains("beef") }, "stale result from first call must be gone")
    }
}
