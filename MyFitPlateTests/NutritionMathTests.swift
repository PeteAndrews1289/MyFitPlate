import XCTest
@testable import MyFitPlate

// MARK: - Shared fixtures

private func makeFood(
    cal: Double,
    p: Double = 0,
    c: Double = 0,
    f: Double = 0,
    serving: String = "1 serving",
    weight: Double = 100,
    fiber: Double? = nil,
    quantityValue: Double? = nil,
    unit: String? = nil
) -> FoodItem {
    FoodItem(
        id: UUID().uuidString, name: "Test", calories: cal, protein: p, carbs: c, fats: f,
        saturatedFat: nil, polyunsaturatedFat: nil, monounsaturatedFat: nil, fiber: fiber,
        servingSize: serving, servingWeight: weight, timestamp: nil,
        calcium: nil, iron: nil, potassium: nil, sodium: nil, vitaminA: nil, vitaminC: nil,
        vitaminD: nil, vitaminB12: nil, folate: nil, magnesium: nil, phosphorus: nil, zinc: nil,
        copper: nil, manganese: nil, selenium: nil, vitaminB1: nil, vitaminB2: nil, vitaminB3: nil,
        vitaminB5: nil, vitaminB6: nil, vitaminE: nil, vitaminK: nil,
        quantityValue: quantityValue, servingUnit: unit
    )
}

// MARK: - Calorie / macro consistency engine

final class NutritionConsistencyTests: XCTestCase {

    func testMacroDerivedCaloriesUses4_4_9() {
        // 10g protein, 20g carbs, 5g fat => 40 + 80 + 45 = 165
        XCTAssertEqual(NutritionCalorieConsistency.macroDerivedCalories(protein: 10, carbs: 20, fats: 5), 165, accuracy: 0.001)
    }

    func testMacroDerivedCaloriesClampsNegativesToZero() {
        // Negative macros must not subtract calories.
        XCTAssertEqual(NutritionCalorieConsistency.macroDerivedCalories(protein: -10, carbs: 20, fats: 5), 125, accuracy: 0.001)
    }

    func testConsistentMacrosProduceNoMismatch() {
        let status = NutritionCalorieConsistency.status(calories: 165, protein: 10, carbs: 20, fats: 5)
        XCTAssertEqual(status.delta, 0, accuracy: 0.001)
        XCTAssertFalse(status.hasMeaningfulMismatch)
    }

    func testAbsoluteThresholdFlagsLargeGap() {
        // delta = 80 (>= 75 absolute) even though relative (80/1080 ≈ 0.074) is below 0.12.
        let status = NutritionCalorieConsistency.status(calories: 1000, protein: 0, carbs: 0, fats: 120)
        XCTAssertEqual(status.macroDerivedCalories, 1080, accuracy: 0.001)
        XCTAssertTrue(status.hasMeaningfulMismatch)
    }

    func testRelativeThresholdBoundary() {
        // delta 50 / 450 ≈ 0.111  -> below 0.12, and |delta| < 75 -> NOT a mismatch.
        let below = NutritionCalorieConsistency.status(calories: 400, protein: 0, carbs: 0, fats: 50)
        XCTAssertFalse(below.hasMeaningfulMismatch)
        // delta 60 / 460 ≈ 0.130  -> at/above 0.12 -> mismatch.
        let above = NutritionCalorieConsistency.status(calories: 400, protein: 0, carbs: 0, fats: 51.111)
        XCTAssertTrue(above.hasMeaningfulMismatch)
    }

    func testIsEstimatedSource() {
        XCTAssertTrue(NutritionCalorieConsistency.isEstimatedSource("ai_chat"))
        XCTAssertTrue(NutritionCalorieConsistency.isEstimatedSource("manual_add"))
        XCTAssertTrue(NutritionCalorieConsistency.isEstimatedSource("AI"))      // case-insensitive
        XCTAssertFalse(NutritionCalorieConsistency.isEstimatedSource("fatsecret"))
        XCTAssertFalse(NutritionCalorieConsistency.isEstimatedSource("barcode_scan"))
    }

    func testEstimatedSourceWithZeroCaloriesAdoptsMacroCalories() {
        let result = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
            calories: 0, protein: 10, carbs: 20, fats: 5, source: "ai_chat"
        )
        XCTAssertEqual(result, 165, accuracy: 0.001)
    }

    func testEstimatedSourceWithUnderstatedCaloriesAdoptsMacroCalories() {
        // Macros imply 165 but logged 100 -> meaningful positive delta -> normalize up to 165.
        let result = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
            calories: 100, protein: 10, carbs: 20, fats: 5, source: "ai_chat"
        )
        XCTAssertEqual(result, 165, accuracy: 0.001)
    }

    func testEstimatedSourceWithOverstatedCaloriesKeepsLoggedValue() {
        // Logged 200 exceeds macro-derived 165 (delta negative) -> keep the logged calories.
        let result = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
            calories: 200, protein: 10, carbs: 20, fats: 5, source: "ai_chat"
        )
        XCTAssertEqual(result, 200, accuracy: 0.001)
    }

    func testDatabaseSourceCaloriesAreAuthoritative() {
        // Non-estimated sources are never rewritten, even with a mismatch.
        let result = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
            calories: 120, protein: 10, carbs: 20, fats: 5, source: "fatsecret"
        )
        XCTAssertEqual(result, 120, accuracy: 0.001)
    }
}

// MARK: - FoodItem normalization extension

final class FoodItemNormalizationTests: XCTestCase {

    func testNormalizedForEstimatedSourceRewritesUnderstatedCalories() {
        let item = makeFood(cal: 100, p: 10, c: 20, f: 5)
        let normalized = item.normalizedForEstimatedSource("ai_chat")
        XCTAssertEqual(normalized.calories, 165, accuracy: 0.001)
    }

    func testNormalizedForDatabaseSourceUnchanged() {
        let item = makeFood(cal: 100, p: 10, c: 20, f: 5)
        let normalized = item.normalizedForEstimatedSource("fatsecret")
        XCTAssertEqual(normalized.calories, 100, accuracy: 0.001)
    }

    func testMacroDerivedCaloriesProperty() {
        let item = makeFood(cal: 999, p: 10, c: 20, f: 5)
        XCTAssertEqual(item.macroDerivedCalories, 165, accuracy: 0.001)
    }
}

// MARK: - Serving math edge cases

final class ServingCalculatorEdgeTests: XCTestCase {

    func testParseQuantityStandard() {
        let parsed = ServingNutritionCalculator.parseQuantity(from: "2 x cup")
        XCTAssertEqual(parsed.quantity, 2, accuracy: 0.001)
        XCTAssertEqual(parsed.baseDescription, "cup")
    }

    func testParseQuantityFractional() {
        let parsed = ServingNutritionCalculator.parseQuantity(from: "2.5 x slice")
        XCTAssertEqual(parsed.quantity, 2.5, accuracy: 0.001)
        XCTAssertEqual(parsed.baseDescription, "slice")
    }

    func testParseQuantityNoMultiplierDefaultsToOne() {
        let parsed = ServingNutritionCalculator.parseQuantity(from: "1 cup")
        XCTAssertEqual(parsed.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.baseDescription, "1 cup")
    }

    func testParseQuantityZeroIsRejected() {
        // "0 x cup" must not yield a zero quantity (would divide-by-zero downstream).
        let parsed = ServingNutritionCalculator.parseQuantity(from: "0 x cup")
        XCTAssertEqual(parsed.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.baseDescription, "0 x cup")
    }

    func testBaseServingTreatsZeroQuantityAsOne() {
        // quantityValue 0 must be coerced to 1 so per-unit nutrients aren't infinite/NaN.
        let item = makeFood(cal: 200, p: 20, c: 30, f: 10, weight: 200, quantityValue: 0, unit: "bar")
        let serving = ServingNutritionCalculator.baseServing(from: item)
        XCTAssertEqual(serving.calories, 200, accuracy: 0.001)
        XCTAssertEqual(serving.servingWeightGrams ?? 0, 200, accuracy: 0.001)
    }

    func testAdjustedNutritionQuantityOneOmitsMultiplierLabel() {
        let base = ServingNutritionCalculator.baseServing(from: makeFood(cal: 100, serving: "1 serving"))
        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: base, quantityText: "1")
        XCTAssertFalse(adjusted.servingDescription.contains(" x "))
    }

    func testAdjustedNutritionEmptyQuantityDefaultsToOne() {
        let base = ServingNutritionCalculator.baseServing(from: makeFood(cal: 100))
        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: base, quantityText: "")
        XCTAssertEqual(adjusted.quantityValue, 1, accuracy: 0.001)
        XCTAssertEqual(adjusted.calories, 100, accuracy: 0.001)
    }

    func testBaseThenAdjustRoundTripsToOriginalTotals() {
        // A 4-serving item, taken back to per-unit then scaled by 4, must equal the original totals.
        let item = makeFood(cal: 800, p: 40, c: 100, f: 20, serving: "4 x scoop", weight: 400, quantityValue: 4, unit: "scoop")
        let base = ServingNutritionCalculator.baseServing(from: item)
        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: base, quantityValue: 4)
        XCTAssertEqual(adjusted.calories, 800, accuracy: 0.001)
        XCTAssertEqual(adjusted.protein, 40, accuracy: 0.001)
        XCTAssertEqual(adjusted.carbs, 100, accuracy: 0.001)
        XCTAssertEqual(adjusted.fats, 20, accuracy: 0.001)
        XCTAssertEqual(adjusted.servingWeightGrams, 400, accuracy: 0.001)
    }
}

// MARK: - Goal / macro / TDEE math

final class GoalCalorieMathTests: XCTestCase {

    var goalSettings: GoalSettings!
    var mockHealthKit: MockHealthKitManager!

    @MainActor
    override func setUpWithError() throws {
        mockHealthKit = MockHealthKitManager()
        goalSettings = GoalSettings(healthKitManager: mockHealthKit)
    }

    override func tearDownWithError() throws {
        goalSettings = nil
        mockHealthKit = nil
    }

    @MainActor
    func testMacroSplitFollowsPercentages() async throws {
        goalSettings.gender = "Male"
        goalSettings.calorieGoalMethod = .custom
        goalSettings.proteinPercentage = 30
        goalSettings.carbsPercentage = 50
        goalSettings.fatsPercentage = 20
        goalSettings.calories = 2000
        goalSettings.recalculateAllGoals()
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(goalSettings.protein, 0.30 * 2000 / 4, accuracy: 0.5) // 150g
        XCTAssertEqual(goalSettings.carbs, 0.50 * 2000 / 4, accuracy: 0.5)   // 250g
        XCTAssertEqual(goalSettings.fats, 0.20 * 2000 / 9, accuracy: 0.5)    // ~44.4g
    }

    @MainActor
    func testWeightGoalAdjustmentIsPlusMinus250() async throws {
        func calories(for goal: String) async throws -> Double {
            goalSettings.gender = "Male"
            goalSettings.age = 25
            goalSettings.weight = 180
            goalSettings.height = 180
            goalSettings.activityLevel = 1.55
            goalSettings.calorieGoalMethod = .mifflinWithActivity
            goalSettings.goal = goal
            goalSettings.recalculateAllGoals()
            try await Task.sleep(nanoseconds: 300_000_000)
            return goalSettings.calories ?? 0
        }

        let maintain = try await calories(for: "Maintain")
        let lose = try await calories(for: "Lose")
        let gain = try await calories(for: "Gain")

        XCTAssertEqual(lose, maintain - 250, accuracy: 1.0)
        XCTAssertEqual(gain, maintain + 250, accuracy: 1.0)
    }

    @MainActor
    func testCalorieFloorForMale() async throws {
        // Stats that compute well below the 1500 male floor must clamp up to 1500.
        goalSettings.gender = "Male"
        goalSettings.age = 80
        goalSettings.weight = 90
        goalSettings.height = 140
        goalSettings.activityLevel = 1.2
        goalSettings.goal = "Lose"
        goalSettings.calorieGoalMethod = .mifflinWithActivity
        goalSettings.recalculateAllGoals()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(goalSettings.calories ?? 0, 1500, accuracy: 0.5)
    }

    @MainActor
    func testDynamicTDEEUsesAdaptiveExpenditure() async throws {
        let adaptive = AdaptiveGoalService()
        adaptive.calculatedTDEE = 2500
        goalSettings.adaptiveGoalService = adaptive
        goalSettings.gender = "Male"
        goalSettings.goal = "Maintain"
        goalSettings.calorieGoalMethod = .dynamicTDEE
        goalSettings.recalculateAllGoals()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(goalSettings.calories ?? 0, 2500, accuracy: 1.0)
    }
}

// MARK: - Adaptive TDEE expenditure (EMA)

final class AdaptiveTDEETests: XCTestCase {

    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    private func log(cal: Double, daysAgo n: Int) -> DailyLog {
        DailyLog(date: daysAgo(n), meals: [Meal(name: "Lunch", foodItems: [makeFood(cal: cal)])])
    }

    @MainActor
    func testFlatWeightYieldsTDEEEqualToIntake() async throws {
        let service = AdaptiveGoalService()
        // 8 stable weigh-ins (no trend) + 12 days logging 2000 kcal => TDEE ≈ intake.
        let weights = (1...8).map { (id: "\($0)", date: daysAgo($0), weight: 180.0) }
        let logs = (1...12).map { log(cal: 2000, daysAgo: $0) }

        service.calculateExpenditure(weightHistory: weights, dailyLogs: logs)
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNotNil(service.calculatedTDEE)
        XCTAssertEqual(service.calculatedTDEE ?? 0, 2000, accuracy: 1.0)
        XCTAssertEqual(service.last21DaysCalorieAverage ?? 0, 2000, accuracy: 1.0)
    }

    @MainActor
    func testWeightLossImpliesTDEEAboveIntake() async throws {
        let service = AdaptiveGoalService()
        // Declining weight on 2000 kcal/day means the body burns MORE than intake.
        let weights = (1...10).map { (id: "\($0)", date: daysAgo($0), weight: 176.0 + Double($0) * 0.8) }
        let logs = (1...12).map { log(cal: 2000, daysAgo: $0) }

        service.calculateExpenditure(weightHistory: weights, dailyLogs: logs)
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNotNil(service.calculatedTDEE)
        XCTAssertGreaterThan(service.calculatedTDEE ?? 0, 2000)
    }

    @MainActor
    func testInsufficientDataYieldsNoEstimate() async throws {
        let service = AdaptiveGoalService()
        // Only 3 weigh-ins — below the 7-weight minimum.
        let weights = (1...3).map { (id: "\($0)", date: daysAgo($0), weight: 180.0) }
        let logs = (1...12).map { log(cal: 2000, daysAgo: $0) }

        service.calculateExpenditure(weightHistory: weights, dailyLogs: logs)
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNil(service.calculatedTDEE)
        XCTAssertEqual(service.dataConfidence, .insufficient)
    }
}
