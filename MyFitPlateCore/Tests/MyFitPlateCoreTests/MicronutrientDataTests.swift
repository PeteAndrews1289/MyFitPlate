import XCTest
@testable import MyFitPlateCore

final class MicronutrientDataTests: XCTestCase {
    func testCoverageDistinguishesUnknownFromReportedZero() {
        let unknown = FoodItem(id: "unknown", name: "Unknown", calories: 100)
        let reportedZero = FoodItem(id: "zero", name: "Zero", calories: 100, vitaminC: 0)
        let reportedValue = FoodItem(id: "value", name: "Value", calories: 100, vitaminC: 12)
        let log = DailyLog(
            date: Date(),
            meals: [Meal(name: "Meal", foodItems: [unknown, reportedZero, reportedValue])]
        )

        XCTAssertEqual(log.totalMicronutrient(.vitaminC), 12)
        XCTAssertEqual(
            log.micronutrientCoverage(for: .vitaminC),
            MicronutrientCoverage(reportedFoodCount: 2, totalFoodCount: 3)
        )
        XCTAssertFalse(log.micronutrientCoverage(for: .vitaminC).isComplete)
        XCTAssertEqual(log.micronutrientCoverage(for: .vitaminC).fraction, 2.0 / 3.0, accuracy: 0.001)
    }

    func testReportedCountsIncludeExplicitZero() {
        let item = FoodItem(
            name: "Fortified food",
            fiber: 0,
            calcium: 100,
            vitaminD: 0
        )

        XCTAssertEqual(item.reportedMicronutrientCount, 3)
        XCTAssertEqual(item.reportedVitaminMineralCount, 2)
        XCTAssertEqual(MicronutrientKey.vitaminAndMineralKeys.count, 22)
    }

    func testVitaminAndMineralCategoriesCoverEveryReferenceNutrientOnce() {
        let categorized = MicronutrientKey.vitaminKeys + MicronutrientKey.mineralKeys

        XCTAssertEqual(categorized.count, 22)
        XCTAssertEqual(Set(categorized).count, categorized.count)
        XCTAssertEqual(Set(categorized), Set(MicronutrientKey.vitaminAndMineralKeys))
        XCTAssertTrue(MicronutrientKey.vitaminKeys.allSatisfy { $0.category == .vitamin })
        XCTAssertTrue(MicronutrientKey.mineralKeys.allSatisfy { $0.category == .mineral })
        XCTAssertEqual(MicronutrientKey.fiber.category, .other)
    }

    func testDailyValueReferenceCalculatesPercentWithoutInventingInvalidData() {
        XCTAssertEqual(MicronutrientKey.vitaminC.percentDailyValue(for: 45), 50)
        XCTAssertEqual(MicronutrientKey.calcium.percentDailyValue(for: 1_300), 100)
        XCTAssertEqual(MicronutrientKey.copper.percentDailyValue(for: 225), 25)
        XCTAssertNil(MicronutrientKey.iron.percentDailyValue(for: .nan))
        XCTAssertNil(MicronutrientKey.iron.percentDailyValue(for: -1))
        XCTAssertTrue(MicronutrientKey.allCases.allSatisfy { $0.dailyValue > 0 })
    }

    func testRecipeNutritionAggregationPreservesUnknownAndFullPanelValues() {
        let sparse = FoodItem(name: "Sparse", calories: 100, calcium: 0, magnesium: 30)
        let rich = FoodItem(name: "Rich", calories: 200, calcium: 120, vitaminB6: 0.5)

        let nutrition = Nutrition.total(for: [sparse, rich])

        XCTAssertEqual(nutrition.calories, 300)
        XCTAssertEqual(nutrition.calcium, 120, "A reported zero participates without becoming unknown")
        XCTAssertEqual(nutrition.magnesium, 30)
        XCTAssertEqual(nutrition.vitaminB6, 0.5)
        XCTAssertNil(nutrition.vitaminK, "No reported ingredient value must stay unknown")
        XCTAssertEqual(nutrition.reportedVitaminMineralCount, 3)
    }

    func testScalingNutritionAndServingPreservesNilAndScalesFullPanel() {
        let original = FoodItem(
            name: "Ingredient",
            calories: 100,
            protein: 10,
            carbs: 15,
            fats: 4,
            fiber: 0,
            servingWeight: 50,
            magnesium: 20,
            vitaminK: 8
        )

        let scaled = original.scalingNutritionAndServing(by: 2.5)

        XCTAssertEqual(scaled.calories, 250)
        XCTAssertEqual(scaled.servingWeight, 125)
        XCTAssertEqual(scaled.fiber, 0)
        XCTAssertEqual(scaled.magnesium, 50)
        XCTAssertEqual(scaled.vitaminK, 20)
        XCTAssertNil(scaled.vitaminC)
    }

    func testRecipeQuantityUsesDisplayedServingWeightAsItsInitialDenominator() throws {
        let ingredient = FoodItem(
            name: "Ingredient",
            calories: 200,
            protein: 10,
            carbs: 30,
            fats: 4,
            servingSize: "100 g",
            servingWeight: 100,
            magnesium: 40
        )

        let adjusted = try XCTUnwrap(
            RecipeIngredientQuantityRules.adjustedIngredient(ingredient, newQuantity: 50)
        )

        XCTAssertEqual(adjusted.quantityValue, 50)
        XCTAssertEqual(adjusted.servingWeight, 50)
        XCTAssertEqual(adjusted.calories, 100)
        XCTAssertEqual(adjusted.magnesium, 20)
        XCTAssertNil(RecipeIngredientQuantityRules.adjustedIngredient(ingredient, newQuantity: 0))
    }

    func testExactProductEnrichmentScalesMissingValuesAndPreservesPrimaryData() {
        let primary = FoodItem(
            id: "primary",
            name: "Primary name",
            calories: 100,
            protein: 10,
            carbs: 10,
            fats: 3,
            servingSize: "1 bar",
            servingWeight: 50,
            calcium: 0
        ).withDatabaseSource(.fatSecret, sourceName: "FatSecret")
        let agreeingCandidate = FoodItem(
            id: "candidate",
            name: "Candidate name",
            calories: 200,
            protein: 20,
            carbs: 20,
            fats: 6,
            fiber: 8,
            servingSize: "100 g",
            servingWeight: 100,
            calcium: 300,
            vitaminC: 60,
            copper: 400
        ).withDatabaseSource(.usda, sourceName: "USDA FoodData Central")

        let enriched = FoodMicronutrientEnrichment.enrichExactProduct(
            primary: primary,
            with: [agreeingCandidate]
        )

        XCTAssertEqual(enriched.id, primary.id)
        XCTAssertEqual(enriched.name, primary.name)
        XCTAssertEqual(enriched.calories, primary.calories)
        XCTAssertEqual(enriched.protein, primary.protein)
        XCTAssertEqual(enriched.servingSize, primary.servingSize)
        XCTAssertEqual(enriched.sourceMetadata, primary.sourceMetadata)
        XCTAssertEqual(enriched.calcium, 0, "A reported primary zero must not be overwritten")
        XCTAssertEqual(enriched.fiber, 4)
        XCTAssertEqual(enriched.vitaminC, 30)
        XCTAssertEqual(enriched.copper, 200)
    }

    func testExactProductEnrichmentRejectsDisagreeingCandidate() {
        let primary = FoodItem(
            name: "Primary",
            calories: 100,
            protein: 10,
            carbs: 10,
            fats: 3,
            servingWeight: 50
        )
        let differentProduct = FoodItem(
            name: "Different",
            calories: 600,
            protein: 2,
            carbs: 80,
            fats: 20,
            servingWeight: 100,
            vitaminC: 90
        )

        let enriched = FoodMicronutrientEnrichment.enrichExactProduct(
            primary: primary,
            with: [differentProduct]
        )

        XCTAssertNil(enriched.vitaminC)
    }
}
