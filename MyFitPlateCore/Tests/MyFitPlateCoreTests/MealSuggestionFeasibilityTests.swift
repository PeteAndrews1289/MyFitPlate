import XCTest
@testable import MyFitPlateCore

final class MealSuggestionFeasibilityTests: XCTestCase {
    private func idea(_ calories: Double = 400, ingredients: [String] = ["150 g cooked rice", "100 g beans", "sauce to taste"]) -> MealSuggestion {
        .init(title: "Rice bowl", calories: calories, mealName: "Rice bowl", protein: 20, carbs: 60, fats: 9,
              ingredients: ingredients, instructions: "Combine the listed ingredients.", prepMinutes: 15)
    }
    func testEstimatedQuantitiesKeepTextWithoutInventingGramConversionsOrResolvedSources() throws {
        let original = idea(ingredients: ["1/2 cup rice", "2 large eggs", "sauce to taste", "one bowl of vegetables"])
        let allegedFood = FoodItem(id: "fabricated", name: "Rice", calories: 1, protein: 1, carbs: 1, fats: 1)
        let forged = MealSuggestion(id: original.id, title: original.title, calories: original.calories, mealName: original.mealName,
            protein: original.protein, carbs: original.carbs, fats: original.fats, ingredients: original.ingredients,
            instructions: original.instructions, prepMinutes: 15,
            feasibility: .init(prepMinutes: 1, ingredients: [.init(id: "fake", description: "Verified rice", source: "USDA", resolvedFood: allegedFood)]))
        let normalized = forged.withGeneratedEvidence()
        let evidence = try XCTUnwrap(normalized.feasibility)
        XCTAssertEqual(evidence.unresolvedCount, 4)
        XCTAssertEqual(evidence.ingredients.map(\.quantityText), ["1/2 cup", "2 large", nil, nil])
        XCTAssertTrue(evidence.ingredients.allSatisfy { $0.source == "Maia estimate" && $0.resolvedFood == nil })
        XCTAssertEqual(normalized.calories, original.calories)
        let diaryFood = try XCTUnwrap(normalized.reviewFood)
        let reloaded = try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(diaryFood))
        XCTAssertEqual(reloaded.sourceMetadata?.mealSuggestionEvidence, evidence)
        XCTAssertEqual(reloaded.sourceMetadata?.effectiveEvidenceLineage, .modelEstimate)
    }
    func testLegacyDecodeAndUnsupportedPrepStayExplicitlyUnknown() throws {
        let legacy = Data(#"{"mealName":"Rice","calories":300,"protein":5,"carbs":60,"fats":2}"#.utf8)
        let decoded = try JSONDecoder().decode(MealSuggestion.self, from: legacy)
        XCTAssertNil(decoded.prepMinutes); XCTAssertNil(decoded.feasibility)
        XCTAssertNil(MealSuggestionFeasibility(prepMinutes: 999, ingredients: []).prepMinutes)
        XCTAssertFalse(MealSuggestionFeasibilityRules.fitsGeneration(decoded, remaining: .init(calories: 1000, protein: 100, carbs: 200, fats: 50)))
    }
    func testBudgetAndInvalidNutritionBoundariesNeverProduceANegativeBudgetSuggestion() {
        let meal = idea()
        XCTAssertTrue(MealSuggestionFeasibilityRules.fitsGeneration(meal, remaining: .init(calories: 400, protein: 20, carbs: 60, fats: 9)))
        for remaining in [0.0, -1, .nan, .infinity, 399.0] {
            XCTAssertFalse(MealSuggestionFeasibilityRules.fitsGeneration(meal, remaining: .init(calories: remaining, protein: 100, carbs: 200, fats: 50)))
        }
        XCTAssertFalse(MealSuggestionFeasibilityRules.fitsGeneration(meal, remaining: .init(calories: 500, protein: 19, carbs: 60, fats: 9)))
        XCTAssertFalse(MealSuggestionFeasibilityRules.fitsGeneration(idea(.nan), remaining: .init(calories: 500, protein: 100, carbs: 200, fats: 50)))
    }
    func testBudgetReceiptBindsExactDayGoalsDiaryAndSelectedPayloadRatherThanFoodIdentity() throws {
        let day = try XCTUnwrap(DiaryDayContext(userID: "owner", date: Date()))
        let food = try XCTUnwrap(idea().reviewFood)
        let log = DailyLog(id: day.dayKey, date: day.originalDate, meals: [])
        let goals = MealSuggestionBudget(calories: 1000, protein: 100, carbs: 200, fats: 50)
        let receipt = try XCTUnwrap(MealSuggestionBudgetReceipt(day: day, log: log, goals: goals, foods: [food]))
        var changedFood = food; changedFood.calories += 10
        let changed = try XCTUnwrap(MealSuggestionBudgetReceipt(day: day, log: log, goals: goals, foods: [changedFood]))
        XCTAssertFalse(receipt.sameEvidence(as: changed))
        let otherDay = try XCTUnwrap(day.adding(days: 1))
        XCTAssertNil(MealSuggestionBudgetReceipt(day: otherDay, log: log, goals: goals, foods: [food]))
        var revised = log; revised.meals = [.init(name: "Breakfast", foodItems: [food])]
        XCTAssertFalse(receipt.sameEvidence(as: try XCTUnwrap(.init(day: day, log: revised, goals: goals, foods: [food]))))
    }
    func testRecommendedRouteUsesActualAvailabilityWithDeterministicFallbacks() {
        XCTAssertEqual(TrainingFuelFoodAvailability(plannedMealCount: 1, recentFoodCount: 5, pantryItemCount: 3).recommended, .plannedMeal)
        XCTAssertEqual(TrainingFuelFoodAvailability(recentFoodCount: 5, pantryItemCount: 3).recommended, .recentFood)
        XCTAssertEqual(TrainingFuelFoodAvailability(pantryItemCount: 3).recommended, .pantryIdea)
        XCTAssertEqual(TrainingFuelFoodAvailability(plannedMealCount: -1).recommended, .search)
    }
    func testAlternativeInstructionsDoNotClaimSavingsOrInventTolerance() {
        XCTAssertTrue(MealSuggestionAlternativeReason.cheaper.instruction.contains("do not invent local prices"))
        XCTAssertTrue(MealSuggestionAlternativeReason.differentCuisine.instruction.contains("hard constraints"))
        XCTAssertTrue(MealSuggestionAlternativeReason.vegetarian.instruction.contains("animal stock"))
    }
}
