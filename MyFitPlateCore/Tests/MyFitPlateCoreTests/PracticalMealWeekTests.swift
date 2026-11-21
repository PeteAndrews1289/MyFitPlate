import XCTest
@testable import MyFitPlateCore

final class PracticalMealWeekTests: XCTestCase {
    private var start: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_900_000_000)) }
    private func date(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: start)! }
    private func recipe() throws -> Recipe {
        var value = Recipe(id: "rice-beans", name: "Rice and beans", ingredients: ["100 g rice", "200 g beans"],
            instructions: ["Cook and combine."], nutrition: .init(calories: 500, protein: 40, carbs: 60, fats: 10),
            servings: 1, nutritionBasis: .perServing)
        value.planningProfile = .init(prepMinutes: 20, equipment: ["stove"], diet: .vegan, costPerServing: 2,
            reviewedAt: start, contentFingerprint: try RecipePlanningProfile.fingerprint(value))
        return value
    }
    private func constraints() -> MealPlanConstraints {
        var value = MealPlanConstraints(calories: 2_000, protein: 120, carbs: 250, fats: 60)
        value.practicalWeek = .init(mealTypes: ["Lunch", "Dinner"],
            days: (0..<7).map { .init(offset: $0, cookingMinutes: [0, 3].contains($0) ? 30 : 0,
                openMealTypes: $0 == 5 ? ["Dinner"] : []) }, notBefore: start)
        return value
    }
    private func stock(quantity: Double = 3) throws -> PantryItem {
        let recipe = try recipe()
        var source = PlannedMeal(id: "historical-cook", mealType: "Dinner", foodItem: try RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings)),
            ingredients: recipe.ingredients, instructions: "Cook and combine.")
        source = try MealPlanCookingRules.configuring(source, date: date(-1), cookingPortions: 20)
        var item = PantryItem(name: "Existing cooked rice and beans", quantity: quantity, unit: "portion", dateAdded: date(-1))
        item.cookedBatch = source.cookingBatch; item.portionFood = source.foodItem
        item.quantityVerified = true; item.cookedAt = date(-1); item.bestBefore = date(7); item.revisionID = "stock-revision"
        return item
    }
    func testTwoCookingDaysRepeatedLunchesOpenDinnerAndVerifiedLeftovers() throws {
        var request = constraints(); request.householdPortions = 3
        let existingStock = try stock()
        let originalStock = try PlanFingerprint.make(existingStock)
        let days = try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: request, starting: start,
            stock: [existingStock], now: start)
        XCTAssertEqual(days.count, 7)
        XCTAssertFalse(days[5].meals.contains { $0.mealType == "Dinner" })
        XCTAssertEqual(days.flatMap(\.meals).filter { $0.preparedStock != nil }.count, 2)
        let requirements = MealPlanCookingRules.requirements(from: days, starting: start)
        XCTAssertEqual(requirements.count, 2)
        XCTAssertEqual(Set(requirements.map { MealPlanEditingRules.dayID($0.date) }), Set([start, date(3)].map { MealPlanEditingRules.dayID($0) }))
        XCTAssertTrue(days.flatMap(\.meals).compactMap(\.cookingBatch).allSatisfy { $0.totalPortions >= 3 && $0.allocatedPortions <= $0.totalPortions })
        XCTAssertEqual(try PlanFingerprint.make(existingStock), originalStock)
        let report = MealPlanConstraintRules.report(days: days, constraints: request)
        XCTAssertTrue(report.canSave, report.issues.map(\.message).joined(separator: "; "))
        let draft = MealPlanWeekDraft(days: days, title: "Two cooking days", constraints: request, preserveCookingBatches: true)
        let accepted = try MealPlanWeekReviewRules.merging(draft, existing: days.map { MealPlanEditingRules.emptyDay($0.date) }, replace: false)
        try MealPlanEditingRules.validate(accepted)
        try PreparedMealStockRules.validate(plans: accepted.after, stock: [existingStock], now: start)
        XCTAssertEqual(MealPlanCookingRules.requirements(from: accepted.after, starting: start).count, 2)
        XCTAssertEqual(Set(accepted.after.flatMap(\.meals).compactMap { $0.preparedStock?.stockID }), [existingStock.id])
    }
    func testLockedMealAndPastDayRemainByteIdentical() throws {
        var request = constraints(); request.practicalWeek?.notBefore = date(1)
        let source = try recipe()
        var lockedDay = MealPlanEditingRules.emptyDay(start)
        let oldFood = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .servings, amount: 1.2))
        var old = PlannedMeal(id: "owner-lunch", mealType: "Lunch", foodItem: oldFood, ingredients: source.ingredients)
        old.planningEvidence = try .init(profile: source.planningProfile!, meal: old)
        lockedDay.meals = [old]
        request.practicalWeek?.days[1].cookingMinutes = 30
        request.practicalWeek?.days[0].cookingMinutes = 30
        let days = try SavedRecipeWeekPlanner.make(recipes: [source], constraints: request, starting: start, locked: [lockedDay], now: start)
        XCTAssertEqual(try PlanFingerprint.make(days[0]), try PlanFingerprint.make(lockedDay))
        XCTAssertEqual(days[0].meals.count, 1)
    }
    func testUnknownExpiredUndoneAndReservedStockNeverBecomeAvailability() throws {
        let good = try stock()
        var unknown = good; unknown.quantityVerified = nil
        var expired = good; expired.bestBefore = date(-1)
        var undone = good; undone.creationUndone = true
        for item in [unknown, expired, undone] {
            let days = try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: constraints(), starting: start, stock: [item], now: start)
            XCTAssertTrue(days.flatMap(\.meals).allSatisfy { $0.preparedStock == nil })
        }
        var reservedMeal = PlannedMeal(id: "other-week-reservation", mealType: "Lunch", foodItem: good.portionFood, portionMultiplier: 3)
        reservedMeal.preparedStock = try .init(item: good, reviewedAt: start)
        let reserved = MealPlanDay(id: MealPlanEditingRules.dayID(date(7)), date: date(7), meals: [reservedMeal])
        let days = try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: constraints(), starting: start,
            stock: [good], savedPlans: [reserved], now: start)
        XCTAssertTrue(days.flatMap(\.meals).allSatisfy { $0.preparedStock == nil })
    }
    func testStockOnlyWeekHasNoCookingOrGroceryDemandAndFailsIfUnknown() throws {
        var request = constraints()
        request.practicalWeek = .init(mealTypes: ["Lunch"], days: (0..<7).map { .init(offset: $0, cookingMinutes: 0) })
        let known = try stock(quantity: 15)
        let days = try SavedRecipeWeekPlanner.make(recipes: [], constraints: request, starting: start, stock: [known], now: start)
        XCTAssertEqual(days.flatMap(\.meals).count, 7)
        XCTAssertTrue(MealPlanCookingRules.requirements(from: days, starting: start).isEmpty)
        let reservations = try InventoryReservationRules.snapshot(plans: days, stock: [known], referenceDayID: MealPlanEditingRules.dayID(start), now: start)
        XCTAssertTrue(reservations.requirements.isEmpty)
        XCTAssertTrue(reservations.allocations.isEmpty)
        var unknown = known; unknown.quantityUnknown = true
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [], constraints: request, starting: start, stock: [unknown], now: start))
    }
    func testPreparedPortionUseUsesExactLotAndStableDuplicateReceipt() throws {
        let item = try stock()
        var meal = PlannedMeal(id: "planned-leftover", mealType: "Lunch", foodItem: item.portionFood, portionMultiplier: 1.2)
        meal.preparedStock = try .init(item: item, reviewedAt: start)
        meal.foodItem?.id = "remapped-plan-food"
        XCTAssertTrue(meal.preparedStock?.matches(item, meal: meal) == true)
        try MealPlanCookingRules.validate(meal, on: start)
        let operation = try InventoryPlanningRules.reducing(item: item, amount: 1.2, reason: .consume, userID: "test", plannedMeal: meal, date: start)
        XCTAssertEqual(operation.after[0].quantity, 1.8, accuracy: 0.000001)
        XCTAssertThrowsError(try InventoryPlanningRules.reducing(item: operation.after[0], amount: 1.2, reason: .consume, userID: "test", plannedMeal: meal, date: start))
        var changed = item; changed.portionFood?.calories += 100
        XCTAssertThrowsError(try InventoryPlanningRules.reducing(item: changed, amount: 1.2, reason: .consume, userID: "test", plannedMeal: meal, date: start))
        XCTAssertNil(MealPlanEditingRules.duplicate(meal).preparedStock)
        XCTAssertNoThrow(try MealPlanCookingRules.configuring(meal, date: start, cookingPortions: nil))
        XCTAssertThrowsError(try MealPlanCookingRules.configuring(meal, date: start, cookingPortions: 5))
    }
    func testLegacyConstraintsAndMealsDecodeWithoutNewFields() throws {
        let old = MealPlanConstraints(calories: 2_000, protein: 100, carbs: 250, fats: 60)
        let value = try JSONDecoder().decode(MealPlanConstraints.self, from: JSONEncoder().encode(old))
        XCTAssertNil(value.practicalWeek)
        let meal = PlannedMeal(id: "legacy", mealType: "Lunch")
        XCTAssertNil(try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(meal)).preparedStock)
        var invalid = constraints(); invalid.practicalWeek?.days[0].offset = 1
        XCTAssertThrowsError(try invalid.validate())
    }
    func testInsufficientCookingTimeCannotCreatePhantomBatches() throws {
        var request = constraints(); request.practicalWeek?.days[0].cookingMinutes = 5
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: request, starting: start, now: start))
    }
}
