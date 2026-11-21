import XCTest
@testable import MyFitPlateCore

final class MealExecutionActionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_800_000)

    private func batchMeal() -> PlannedMeal {
        let batch = MealCookingBatch(id: "batch", sourceMealID: "meal", cookingDate: now, name: "Rice",
            totalPortions: 4, ingredientsPerPortion: [], instructions: nil,
            allocations: [.init(mealID: "meal", date: now, portions: 1)])
        return PlannedMeal(id: "meal", mealType: "Dinner", cookingBatch: batch)
    }

    private func stock(_ meal: PlannedMeal) -> PantryItem {
        var item = PantryItem(name: "Rice", quantity: 4, unit: "portion")
        item.cookedBatch = meal.cookingBatch
        item.quantityVerified = true
        return item
    }

    func testPlanningDoesNotImplyCookingOrEating() {
        let meal = batchMeal()
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now.addingTimeInterval(86_400), isLogged: false,
            stock: [], stockLoaded: true, now: now), .review)
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: false,
            stock: [], stockLoaded: true, now: now), .cook)
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: false,
            stock: [], stockLoaded: false, now: now), .loadingStock)
    }

    func testCookedAndLoggedAreIndependentActions() {
        let meal = batchMeal()
        var item = stock(meal)
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: false,
            stock: [item], stockLoaded: true, now: now), .useStock)
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: true,
            stock: [item], stockLoaded: true, now: now), .recordStockUse)
        item.recordedPlannedPortions = [PreparedMealStockRules.consumptionKey(meal: meal, date: now, batchID: "batch")]
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: false,
            stock: [item], stockLoaded: true, now: now), .log)
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: true,
            stock: [item], stockLoaded: true, now: now), .logged)
    }

    func testUnknownExpiredAndInsufficientStockNeverOffersConsumption() {
        let meal = batchMeal()
        let valid = stock(meal)
        var unknown = valid; unknown.quantityUnknown = true
        var expired = valid; expired.bestBefore = now.addingTimeInterval(-86_400)
        var short = valid; short.quantity = 0.5
        var archived = valid; archived.isArchived = true
        for item in [unknown, expired, short, archived] {
            XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: false,
                stock: [item], stockLoaded: true, now: now), .checkStock)
        }
    }

    func testOrdinaryFoodRetainsDirectLogging() {
        let meal = PlannedMeal(mealType: "Breakfast")
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: false,
            stock: [], stockLoaded: false, now: now), .log)
        XCTAssertEqual(MealExecutionAction.resolve(meal: meal, date: now, isLogged: true,
            stock: [], stockLoaded: false, now: now), .logged)
    }
}
