import XCTest
@testable import MyFitPlate

// MARK: - Fixtures

private func sampleFood(
    id: String = UUID().uuidString,
    cal: Double = 0, p: Double = 0, c: Double = 0, f: Double = 0,
    satFat: Double? = nil, fiber: Double? = nil,
    calcium: Double? = nil, iron: Double? = nil,
    serving: String = "1 serving", weight: Double = 100,
    quantityValue: Double? = nil, unit: String? = nil
) -> FoodItem {
    FoodItem(
        id: id, name: "Test", calories: cal, protein: p, carbs: c, fats: f,
        saturatedFat: satFat, polyunsaturatedFat: nil, monounsaturatedFat: nil, fiber: fiber,
        servingSize: serving, servingWeight: weight, timestamp: nil,
        calcium: calcium, iron: iron, potassium: nil, sodium: nil, vitaminA: nil, vitaminC: nil,
        vitaminD: nil, vitaminB12: nil, folate: nil, magnesium: nil, phosphorus: nil, zinc: nil,
        copper: nil, manganese: nil, selenium: nil, vitaminB1: nil, vitaminB2: nil, vitaminB3: nil,
        vitaminB5: nil, vitaminB6: nil, vitaminE: nil, vitaminK: nil,
        quantityValue: quantityValue, servingUnit: unit
    )
}

// MARK: - DailyLog model math

final class DailyLogModelTests: XCTestCase {

    func testTotalCaloriesSumsAcrossMeals() {
        let log = DailyLog(date: Date(), meals: [
            Meal(name: "Breakfast", foodItems: [sampleFood(cal: 300), sampleFood(cal: 150)]),
            Meal(name: "Lunch", foodItems: [sampleFood(cal: 500)])
        ])
        XCTAssertEqual(log.totalCalories(), 950, accuracy: 0.001)
    }

    func testTotalMacrosSums() {
        let log = DailyLog(date: Date(), meals: [
            Meal(name: "M", foodItems: [sampleFood(p: 20, c: 30, f: 10), sampleFood(p: 5, c: 5, f: 2)])
        ])
        let m = log.totalMacros()
        XCTAssertEqual(m.protein, 25, accuracy: 0.001)
        XCTAssertEqual(m.carbs, 35, accuracy: 0.001)
        XCTAssertEqual(m.fats, 12, accuracy: 0.001)
    }

    func testEmptyLogIsAllZero() {
        let log = DailyLog(date: Date(), meals: [])
        XCTAssertEqual(log.totalCalories(), 0, accuracy: 0.001)
        XCTAssertEqual(log.totalMacros().protein, 0, accuracy: 0.001)
        XCTAssertEqual(log.macroDerivedCalories(), 0, accuracy: 0.001)
    }

    func testMacroDerivedCaloriesUses4_4_9() {
        let log = DailyLog(date: Date(), meals: [Meal(name: "M", foodItems: [sampleFood(cal: 999, p: 10, c: 20, f: 5)])])
        XCTAssertEqual(log.macroDerivedCalories(), 165, accuracy: 0.001) // 40 + 80 + 45
    }

    func testTotalMicronutrientsSum() {
        let log = DailyLog(date: Date(), meals: [Meal(name: "M", foodItems: [
            sampleFood(calcium: 100, iron: 5), sampleFood(calcium: 50, iron: 3)
        ])])
        let micros = log.totalMicronutrients()
        XCTAssertEqual(micros.calcium, 150, accuracy: 0.001)
        XCTAssertEqual(micros.iron, 8, accuracy: 0.001)
    }

    func testSaturatedFatSum() {
        let log = DailyLog(date: Date(), meals: [Meal(name: "M", foodItems: [sampleFood(satFat: 3), sampleFood(satFat: 2)])])
        XCTAssertEqual(log.totalSaturatedFat(), 5, accuracy: 0.001)
    }

    func testExerciseCaloriesSplitBySource() {
        let log = DailyLog(date: Date(), meals: [], exercises: [
            LoggedExercise(name: "Run", caloriesBurned: 300, date: Date(), source: "manual"),
            LoggedExercise(name: "Walk", caloriesBurned: 100, date: Date(), source: "manual"),
            LoggedExercise(name: "Ring", caloriesBurned: 250, date: Date(), source: "HealthKit")
        ])
        XCTAssertEqual(log.totalCaloriesBurnedFromManualExercises(), 400, accuracy: 0.001)
        XCTAssertEqual(log.totalCaloriesBurnedFromHealthKitWorkouts(), 250, accuracy: 0.001)
    }

    func testFoodsWithMeaningfulMismatchAreFlagged() {
        // 100 logged cal but macros imply 165 -> meaningful mismatch.
        let bad = sampleFood(cal: 100, p: 10, c: 20, f: 5)
        let good = sampleFood(cal: 165, p: 10, c: 20, f: 5)
        let log = DailyLog(date: Date(), meals: [Meal(name: "M", foodItems: [bad, good])])
        let flagged = log.foodsWithMeaningfulCalorieMacroMismatch()
        XCTAssertEqual(flagged.count, 1)
        XCTAssertEqual(flagged.first?.id, bad.id)
    }
}

// MARK: - FoodItem serialization

final class FoodItemCodableTests: XCTestCase {

    func testCodableRoundTripPreservesFields() throws {
        let item = sampleFood(cal: 250, p: 20, c: 30, f: 10, satFat: 3, fiber: 5, calcium: 100, iron: 5,
                              serving: "1 cup", weight: 240, quantityValue: 2, unit: "cup")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(FoodItem.self, from: data)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.calories, 250, accuracy: 0.001)
        XCTAssertEqual(decoded.fiber ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(decoded.calcium ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(decoded.quantityValue ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(decoded.servingUnit, "cup")
    }

    func testEqualityAndHashUseIDOnly() {
        let a = sampleFood(id: "same", cal: 100)
        var b = sampleFood(id: "same", cal: 999) // different nutrients, same id
        b.name = "Renamed"
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)

        let c = sampleFood(id: "other", cal: 100)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - FatSecret response parsing

final class FatSecretParsingTests: XCTestCase {

    private func serving(_ json: [String: String]) throws -> FatSecretServing {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(FatSecretServing.self, from: data)
    }

    func testParsedNutrientTreatsNAasZero() throws {
        let s = try serving(["calories": "n/a", "protein": "20"])
        XCTAssertEqual(s.parsedNutrient(.calories), 0, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.protein), 20, accuracy: 0.001)
    }

    func testParsedNutrientHandlesCommaDecimal() throws {
        let s = try serving(["fat": "1,5"])
        XCTAssertEqual(s.parsedNutrient(.fat), 1.5, accuracy: 0.001)
    }

    func testParsedNutrientStripsLessAndGreaterThan() throws {
        let s = try serving(["fiber": "<1", "sodium": ">500"])
        XCTAssertEqual(s.parsedNutrient(.fiber), 1, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.sodium), 500, accuracy: 0.001)
    }

    func testParsedNutrientNormalValue() throws {
        let s = try serving(["carbohydrate": "42.5"])
        XCTAssertEqual(s.parsedNutrient(.carbohydrate), 42.5, accuracy: 0.001)
    }

    func testServingWeightGramsUnitConversions() throws {
        XCTAssertEqual(try serving(["metric_serving_amount": "100", "metric_serving_unit": "g"]).parsedServingWeightGrams ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(try serving(["metric_serving_amount": "150", "metric_serving_unit": "ml"]).parsedServingWeightGrams ?? -1, 150, accuracy: 0.01)
        XCTAssertEqual(try serving(["metric_serving_amount": "2", "metric_serving_unit": "oz"]).parsedServingWeightGrams ?? -1, 2 * 28.3495, accuracy: 0.01)
        XCTAssertEqual(try serving(["metric_serving_amount": "8", "metric_serving_unit": "fl oz"]).parsedServingWeightGrams ?? -1, 8 * 29.5735, accuracy: 0.01)
    }

    func testServingWeightGramsNilForUnknownUnit() throws {
        XCTAssertNil(try serving(["metric_serving_amount": "5", "metric_serving_unit": "cup"]).parsedServingWeightGrams)
        XCTAssertNil(try serving(["metric_serving_unit": "g"]).parsedServingWeightGrams) // no amount
    }
}

// MARK: - Weight stats & progress

final class WeightStatsTests: XCTestCase {

    private func day(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: Date())! }

    @MainActor
    func testGetWeightStatsTrendHighLowRate() {
        let gs = GoalSettings(healthKitManager: MockHealthKitManager())
        let data: [(id: String, date: Date, weight: Double)] = [
            ("1", day(10), 160.0), ("2", day(5), 158.0), ("3", day(0), 156.0)
        ]
        let stats = gs.getWeightStats(for: data)
        XCTAssertEqual(stats.highest ?? 0, 160, accuracy: 0.001)
        XCTAssertEqual(stats.lowest ?? 0, 156, accuracy: 0.001)
        XCTAssertEqual(stats.trend ?? 0, -4, accuracy: 0.001)            // 156 - 160
        XCTAssertEqual(stats.dailyRate ?? 0, -4.0 / 10.0, accuracy: 0.001) // -4 lb over 10 days
    }

    @MainActor
    func testGetWeightStatsEmptyIsNil() {
        let gs = GoalSettings(healthKitManager: MockHealthKitManager())
        let stats = gs.getWeightStats(for: [])
        XCTAssertNil(stats.trend)
        XCTAssertNil(stats.highest)
        XCTAssertNil(stats.dailyRate)
    }

    @MainActor
    func testGetWeightStatsSingleEntryHasNoTrend() {
        let gs = GoalSettings(healthKitManager: MockHealthKitManager())
        let stats = gs.getWeightStats(for: [("1", day(0), 170.0)])
        XCTAssertEqual(stats.highest ?? 0, 170, accuracy: 0.001)
        XCTAssertNil(stats.trend)
        XCTAssertNil(stats.dailyRate)
    }

    @MainActor
    func testWeightProgressIsPercentOfGoal() {
        let gs = GoalSettings(healthKitManager: MockHealthKitManager())
        gs.weightHistory = [("1", day(20), 180.0)] // initial 180
        gs.weight = 170                             // current
        gs.targetWeight = 160                       // goal
        // totalNeeded 20, changeSoFar 10 -> 50%
        XCTAssertEqual(gs.calculateWeightProgress() ?? 0, 50, accuracy: 0.5)
    }

    @MainActor
    func testWeightProgressClampsToHundred() {
        let gs = GoalSettings(healthKitManager: MockHealthKitManager())
        gs.weightHistory = [("1", day(20), 180.0)]
        gs.weight = 150          // past the goal
        gs.targetWeight = 160
        XCTAssertEqual(gs.calculateWeightProgress() ?? 0, 100, accuracy: 0.5)
    }
}

// MARK: - Micronutrient goals by age/sex

final class MicronutrientGoalTests: XCTestCase {

    @MainActor
    func testIronAndCalciumGoalsForAdultFemale() async throws {
        let gs = GoalSettings(healthKitManager: MockHealthKitManager())
        gs.gender = "Female"
        gs.age = 30
        gs.recalculateAllGoals()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(gs.calciumGoal ?? 0, 1000, accuracy: 0.5)  // 19-50
        XCTAssertEqual(gs.ironGoal ?? 0, 18, accuracy: 0.5)       // female 19-50
    }

    @MainActor
    func testIronGoalLowerForAdultMale() async throws {
        let gs = GoalSettings(healthKitManager: MockHealthKitManager())
        gs.gender = "Male"
        gs.age = 30
        gs.recalculateAllGoals()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(gs.ironGoal ?? 0, 8, accuracy: 0.5)        // male 19-50
    }
}
