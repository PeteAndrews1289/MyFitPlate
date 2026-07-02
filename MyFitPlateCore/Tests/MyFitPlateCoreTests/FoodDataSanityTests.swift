import XCTest
@testable import MyFitPlateCore

final class FoodDataSanityTests: XCTestCase {

    private func food(
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fats: Double = 0,
        fiber: Double? = nil,
        servingWeight: Double = 1.0,
        sodium: Double? = nil,
        potassium: Double? = nil
    ) -> FoodItem {
        FoodItem(
            name: "Test Food",
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            fiber: fiber,
            servingWeight: servingWeight,
            potassium: potassium,
            sodium: sodium
        )
    }

    private func findingIDs(_ item: FoodItem) -> [String] {
        FoodDataSanity.findings(for: item).map(\.id)
    }

    // MARK: - Clean foods stay clean

    func testAccurateFoodHasNoFindings() {
        // Chicken breast, 100g: 165 cal, 31P/0C/3.6F -> derived 156.4, within tolerance.
        let item = food(calories: 165, protein: 31, carbs: 0, fats: 3.6, servingWeight: 100)
        XCTAssertTrue(findingIDs(item).isEmpty)
        XCTAssertFalse(FoodDataSanity.isSuspicious(item))
    }

    func testZeroCalorieZeroMacroFoodIsClean() {
        // Water/black coffee style entries: all zeros is legitimate.
        let item = food(calories: 0, servingWeight: 240)
        XCTAssertTrue(findingIDs(item).isEmpty)
    }

    // MARK: - Calorie/macro rules

    func testMacrosWithoutCaloriesIsWarning() {
        let item = food(calories: 0, protein: 10, carbs: 20, fats: 5, servingWeight: 100)
        XCTAssertEqual(findingIDs(item), ["macros_without_calories"])
        XCTAssertTrue(FoodDataSanity.isSuspicious(item))
    }

    func testCalorieUndercountIsWarning() {
        // Macros derive 400 cal but the entry claims 150.
        let item = food(calories: 150, protein: 25, carbs: 25, fats: 20, servingWeight: 200)
        XCTAssertTrue(findingIDs(item).contains("calories_undercount"))
        XCTAssertTrue(FoodDataSanity.isSuspicious(item))
    }

    func testAlcoholLikeCalorieExcessIsInfoNotWarning() {
        // Wine: 125 cal, ~4g carbs. Calories >> macro-derived, but that's alcohol, not bad data.
        let item = food(calories: 125, carbs: 4, servingWeight: 150)
        let findings = FoodDataSanity.findings(for: item)
        XCTAssertEqual(findings.map(\.id), ["calories_exceed_macros"])
        XCTAssertEqual(findings.first?.severity, .info)
        XCTAssertFalse(FoodDataSanity.isSuspicious(item), "Info findings must not mark a food suspicious")
    }

    // MARK: - Physical impossibility rules

    func testMacroMassExceedingServingWeightIsWarning() {
        // 60g of macros claimed in a 40g serving.
        let item = food(calories: 250, protein: 20, carbs: 30, fats: 10, servingWeight: 40)
        XCTAssertTrue(findingIDs(item).contains("macros_exceed_serving_weight"))
    }

    func testEnergyDensityAbovePureFatIsWarning() {
        // 1000 cal in 50g = 20 kcal/g; pure fat is 9.
        let item = food(calories: 1000, fats: 111, servingWeight: 50)
        XCTAssertTrue(findingIDs(item).contains("energy_density_impossible"))
    }

    func testPlaceholderServingWeightSkipsWeightRules() {
        // servingWeight defaults to 1.0 (unknown) - weight-based rules must stay quiet.
        let item = food(calories: 200, protein: 20, carbs: 20, fats: 4, servingWeight: 1.0)
        XCTAssertFalse(findingIDs(item).contains("macros_exceed_serving_weight"))
        XCTAssertFalse(findingIDs(item).contains("energy_density_impossible"))
    }

    func testImplausiblyLargeServingWeightIsInfo() {
        let item = food(calories: 300, protein: 10, carbs: 40, fats: 10, servingWeight: 3000)
        let findings = FoodDataSanity.findings(for: item)
        XCTAssertTrue(findings.contains { $0.id == "serving_weight_implausible" && $0.severity == .info })
    }

    // MARK: - Unit-slip rules

    func testSodiumGramVsMilligramSlipIsWarning() {
        // 45,000 "mg" is a 45g sodium claim - a g-vs-mg slip.
        let item = food(calories: 100, protein: 5, carbs: 15, fats: 2, servingWeight: 100, sodium: 45_000)
        XCTAssertTrue(findingIDs(item).contains("sodium_unit_suspect"))
    }

    func testPotassiumGramVsMilligramSlipIsWarning() {
        let item = food(calories: 100, protein: 5, carbs: 15, fats: 2, servingWeight: 100, potassium: 12_000)
        XCTAssertTrue(findingIDs(item).contains("potassium_unit_suspect"))
    }

    func testNormalSodiumIsClean() {
        // Salty soup: 900mg sodium is high but real.
        let item = food(calories: 120, protein: 6, carbs: 18, fats: 3, servingWeight: 250, sodium: 900)
        XCTAssertFalse(findingIDs(item).contains("sodium_unit_suspect"))
    }

    // MARK: - Aggregates

    func testMultipleFindingsStack() {
        let item = food(calories: 0, protein: 30, carbs: 30, fats: 10, servingWeight: 50, sodium: 20_000)
        let ids = findingIDs(item)
        XCTAssertTrue(ids.contains("macros_without_calories"))
        XCTAssertTrue(ids.contains("macros_exceed_serving_weight"))
        XCTAssertTrue(ids.contains("sodium_unit_suspect"))
    }

    func testTelemetryKindsJoinsIDs() {
        let item = food(calories: 0, protein: 10, carbs: 20, fats: 5, servingWeight: 100, sodium: 20_000)
        let kinds = FoodDataSanity.telemetryKinds(for: item)
        XCTAssertTrue(kinds.contains("macros_without_calories"))
        XCTAssertTrue(kinds.contains("sodium_unit_suspect"))
        XCTAssertTrue(kinds.contains(","))
    }
}
