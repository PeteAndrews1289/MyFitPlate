import XCTest
@testable import MyFitPlateCore

final class NutritionLogModelTests: XCTestCase {
    func testCalorieConsistencyUsesMacroCaloriesAndFlagsMeaningfulMismatch() {
        XCTAssertEqual(
            NutritionCalorieConsistency.macroDerivedCalories(protein: 25, carbs: 40, fats: 10),
            350,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NutritionCalorieConsistency.macroDerivedCalories(protein: -10, carbs: 5, fats: -2),
            20,
            accuracy: 0.001
        )

        let status = NutritionCalorieConsistency.status(calories: 100, protein: 20, carbs: 20, fats: 20)
        XCTAssertEqual(status.loggedCalories, 100)
        XCTAssertEqual(status.macroDerivedCalories, 340)
        XCTAssertEqual(status.delta, 240)
        XCTAssertEqual(status.directionText, "higher")
        XCTAssertEqual(status.mismatchAmount, 240)
        XCTAssertTrue(status.hasMeaningfulMismatch)

        let lowerStatus = NutritionCalorieConsistency.status(calories: 500, protein: 20, carbs: 20, fats: 10)
        XCTAssertEqual(lowerStatus.directionText, "lower")
        XCTAssertTrue(lowerStatus.hasMeaningfulMismatch)
    }

    func testEstimatedSourcesNormalizeMissingOrUnderreportedCalories() {
        XCTAssertTrue(NutritionCalorieConsistency.isEstimatedSource("ai_chat"))
        XCTAssertTrue(NutritionCalorieConsistency.isEstimatedSource("manual_entry"))
        XCTAssertFalse(NutritionCalorieConsistency.isEstimatedSource("fatsecret"))

        XCTAssertEqual(
            NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
                calories: 0,
                protein: 10,
                carbs: 20,
                fats: 5,
                source: "ai_chat"
            ),
            165,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
                calories: 100,
                protein: 20,
                carbs: 20,
                fats: 20,
                source: "manual_entry"
            ),
            340,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
                calories: 100,
                protein: 20,
                carbs: 20,
                fats: 20,
                source: "fatsecret"
            ),
            100,
            accuracy: 0.001
        )
    }

    func testFoodItemNormalizationReturnsUpdatedCopyOnlyForEstimatedSources() {
        let item = FoodItem(id: "food-1", name: "Manual Bowl", calories: 100, protein: 20, carbs: 20, fats: 20)

        let normalized = item.normalizedForEstimatedSource("manual")
        XCTAssertEqual(normalized.id, item.id)
        XCTAssertEqual(normalized.calories, 340, accuracy: 0.001)
        XCTAssertEqual(item.calories, 100, accuracy: 0.001)
        XCTAssertTrue(item.hasMeaningfulCalorieMacroMismatch)

        let database = item.normalizedForEstimatedSource("open_food_facts")
        XCTAssertEqual(database.calories, 100, accuracy: 0.001)
    }

    func testDailyLogAggregatesMacrosMicrosFatsAndExerciseBurn() {
        let breakfast = FoodItem(
            id: "breakfast",
            name: "Breakfast",
            calories: 300,
            protein: 30,
            carbs: 35,
            fats: 8,
            saturatedFat: 2,
            polyunsaturatedFat: 1,
            monounsaturatedFat: 3,
            fiber: 6,
            calcium: 100,
            iron: 2,
            potassium: 300,
            sodium: 250,
            vitaminA: 400,
            vitaminC: 20,
            vitaminD: 5,
            vitaminB12: 1,
            folate: 80,
            magnesium: 40,
            phosphorus: 120,
            zinc: 3,
            copper: 0.2,
            manganese: 0.5,
            selenium: 12,
            vitaminB1: 0.3,
            vitaminB2: 0.4,
            vitaminB3: 5,
            vitaminB5: 1,
            vitaminB6: 0.6,
            vitaminE: 2,
            vitaminK: 15
        )
        let dinner = FoodItem(
            id: "dinner",
            name: "Dinner",
            calories: 500,
            protein: 45,
            carbs: 50,
            fats: 14,
            saturatedFat: 4,
            polyunsaturatedFat: 2,
            monounsaturatedFat: 5,
            fiber: 8,
            calcium: 150,
            iron: 3,
            potassium: 500,
            sodium: 400,
            vitaminA: 200,
            vitaminC: 30,
            vitaminD: 3,
            vitaminB12: 2,
            folate: 120,
            magnesium: 60,
            phosphorus: 180,
            zinc: 4,
            copper: 0.4,
            manganese: 0.8,
            selenium: 18,
            vitaminB1: 0.4,
            vitaminB2: 0.5,
            vitaminB3: 6,
            vitaminB5: 1.5,
            vitaminB6: 0.7,
            vitaminE: 3,
            vitaminK: 20
        )
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let log = DailyLog(
            id: "log",
            date: date,
            meals: [
                Meal(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Breakfast", foodItems: [breakfast]),
                Meal(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Dinner", foodItems: [dinner])
            ],
            exercises: [
                LoggedExercise(id: "manual", name: "Walk", durationMinutes: 30, caloriesBurned: 120, date: date, source: "manual"),
                LoggedExercise(id: "health", name: "Run", durationMinutes: 20, caloriesBurned: 220, date: date, source: "HealthKit"),
                LoggedExercise(id: "routine", name: "Lift", durationMinutes: 45, caloriesBurned: 180, date: date, source: "routine")
            ]
        )

        XCTAssertEqual(log.totalCalories(), 800, accuracy: 0.001)
        let macros = log.totalMacros()
        XCTAssertEqual(macros.protein, 75, accuracy: 0.001)
        XCTAssertEqual(macros.carbs, 85, accuracy: 0.001)
        XCTAssertEqual(macros.fats, 22, accuracy: 0.001)
        XCTAssertEqual(log.macroDerivedCalories(), 838, accuracy: 0.001)
        XCTAssertFalse(log.calorieConsistencyStatus().hasMeaningfulMismatch)

        let micros = log.totalMicronutrients()
        XCTAssertEqual(micros.calcium, 250, accuracy: 0.001)
        XCTAssertEqual(micros.iron, 5, accuracy: 0.001)
        XCTAssertEqual(micros.potassium, 800, accuracy: 0.001)
        XCTAssertEqual(micros.sodium, 650, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminA, 600, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminC, 50, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminD, 8, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminB12, 3, accuracy: 0.001)
        XCTAssertEqual(micros.folate, 200, accuracy: 0.001)
        XCTAssertEqual(micros.fiber, 14, accuracy: 0.001)
        XCTAssertEqual(micros.magnesium, 100, accuracy: 0.001)
        XCTAssertEqual(micros.phosphorus, 300, accuracy: 0.001)
        XCTAssertEqual(micros.zinc, 7, accuracy: 0.001)
        XCTAssertEqual(micros.copper, 0.6, accuracy: 0.001)
        XCTAssertEqual(micros.manganese, 1.3, accuracy: 0.001)
        XCTAssertEqual(micros.selenium, 30, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminB1, 0.7, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminB2, 0.9, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminB3, 11, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminB5, 2.5, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminB6, 1.3, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminE, 5, accuracy: 0.001)
        XCTAssertEqual(micros.vitaminK, 35, accuracy: 0.001)

        XCTAssertEqual(log.totalSaturatedFat(), 6, accuracy: 0.001)
        XCTAssertEqual(log.totalPolyunsaturatedFat(), 3, accuracy: 0.001)
        XCTAssertEqual(log.totalMonounsaturatedFat(), 8, accuracy: 0.001)
        XCTAssertEqual(log.totalCaloriesBurnedFromManualExercises(), 120, accuracy: 0.001)
        XCTAssertEqual(log.totalCaloriesBurnedFromHealthKitWorkouts(), 220, accuracy: 0.001)
    }

    func testServingNutritionCalculatorParsesBaseAndAdjustedServings() {
        XCTAssertEqual(ServingNutritionCalculator.parseQuantity(from: "2 x scoop").quantity, 2)
        XCTAssertEqual(ServingNutritionCalculator.parseQuantity(from: "2 x scoop").baseDescription, "scoop")
        XCTAssertEqual(ServingNutritionCalculator.parseQuantity(from: "0 x broken").quantity, 1)
        XCTAssertEqual(ServingNutritionCalculator.parseQuantity(from: "0 x broken").baseDescription, "0 x broken")

        let item = FoodItem(
            name: "Protein Powder",
            calories: 240,
            protein: 48,
            carbs: 8,
            fats: 4,
            saturatedFat: 2,
            polyunsaturatedFat: 0.5,
            monounsaturatedFat: 1,
            fiber: 6,
            servingSize: "2 x scoop",
            servingWeight: 60,
            calcium: 200,
            iron: 4,
            potassium: 300,
            sodium: 180,
            vitaminA: 100,
            vitaminC: 10,
            vitaminD: 8,
            vitaminB12: 2,
            folate: 80,
            magnesium: 60,
            phosphorus: 220,
            zinc: 6,
            copper: 0.4,
            manganese: 0.6,
            selenium: 20,
            vitaminB1: 0.8,
            vitaminB2: 1,
            vitaminB3: 4,
            vitaminB5: 2,
            vitaminB6: 1.2,
            vitaminE: 3,
            vitaminK: 12
        )

        let base = ServingNutritionCalculator.baseServing(from: item)
        XCTAssertEqual(base.description, "scoop")
        assertOptionalEqual(base.servingWeightGrams, 30)
        XCTAssertEqual(base.calories, 120, accuracy: 0.001)
        XCTAssertEqual(base.protein, 24, accuracy: 0.001)
        assertOptionalEqual(base.fiber, 3)
        assertOptionalEqual(base.calcium, 100)

        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: base, quantityValue: 2.5)
        XCTAssertEqual(adjusted.servingDescription, "2.5 x scoop")
        XCTAssertEqual(adjusted.servingWeightGrams, 75, accuracy: 0.001)
        XCTAssertEqual(adjusted.calories, 300, accuracy: 0.001)
        XCTAssertEqual(adjusted.protein, 60, accuracy: 0.001)
        XCTAssertEqual(adjusted.carbs, 10, accuracy: 0.001)
        XCTAssertEqual(adjusted.fats, 5, accuracy: 0.001)
        assertOptionalEqual(adjusted.saturatedFat, 2.5)
        assertOptionalEqual(adjusted.polyunsaturatedFat, 0.625)
        assertOptionalEqual(adjusted.monounsaturatedFat, 1.25)
        assertOptionalEqual(adjusted.fiber, 7.5)
        assertOptionalEqual(adjusted.calcium, 250)
        assertOptionalEqual(adjusted.iron, 5)
        assertOptionalEqual(adjusted.potassium, 375)
        assertOptionalEqual(adjusted.sodium, 225)
        assertOptionalEqual(adjusted.vitaminA, 125)
        assertOptionalEqual(adjusted.vitaminC, 12.5)
        assertOptionalEqual(adjusted.vitaminD, 10)
        assertOptionalEqual(adjusted.vitaminB12, 2.5)
        assertOptionalEqual(adjusted.folate, 100)
        assertOptionalEqual(adjusted.magnesium, 75)
        assertOptionalEqual(adjusted.phosphorus, 275)
        assertOptionalEqual(adjusted.zinc, 7.5)
        assertOptionalEqual(adjusted.copper, 0.5)
        assertOptionalEqual(adjusted.manganese, 0.75)
        assertOptionalEqual(adjusted.selenium, 25)
        assertOptionalEqual(adjusted.vitaminB1, 1)
        assertOptionalEqual(adjusted.vitaminB2, 1.25)
        assertOptionalEqual(adjusted.vitaminB3, 5)
        assertOptionalEqual(adjusted.vitaminB5, 2.5)
        assertOptionalEqual(adjusted.vitaminB6, 1.5)
        assertOptionalEqual(adjusted.vitaminE, 3.75)
        assertOptionalEqual(adjusted.vitaminK, 15)
        XCTAssertEqual(adjusted.quantityValue, 2.5, accuracy: 0.001)
        XCTAssertEqual(adjusted.servingUnit, "scoop")

        let fallback = ServingNutritionCalculator.adjustedNutrition(base: base, quantityText: "  -3 ")
        XCTAssertEqual(fallback.quantityValue, 1, accuracy: 0.001)
        XCTAssertEqual(fallback.servingDescription, "scoop")
    }

    private func assertOptionalEqual(
        _ actual: Double?,
        _ expected: Double,
        accuracy: Double = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected \(expected), got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }
}
