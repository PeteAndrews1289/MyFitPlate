import XCTest
@testable import MyFitPlateCore

final class NutritionLogModelsTests: XCTestCase {

    // MARK: - DailyLog Tests

    func testDailyLogTotalMicronutrients() {
        let item1 = FoodItem(name: "Apple", calcium: 10, iron: 5, vitaminC: 20)
        let item2 = FoodItem(name: "Banana", calcium: 5, potassium: 15, vitaminC: 10)
        
        let meal = Meal(name: "Snack", foodItems: [item1, item2])
        let log = DailyLog(date: Date(), meals: [meal])
        
        let totals = log.totalMicronutrients()
        
        XCTAssertEqual(totals.calcium, 15)
        XCTAssertEqual(totals.iron, 5)
        XCTAssertEqual(totals.potassium, 15)
        XCTAssertEqual(totals.vitaminC, 30)
        XCTAssertEqual(totals.sodium, 0)
    }

    func testDailyLogTotalFatTypes() {
        let item1 = FoodItem(name: "Nuts", saturatedFat: 2, polyunsaturatedFat: 4, monounsaturatedFat: 6)
        let item2 = FoodItem(name: "Oil", saturatedFat: 1, polyunsaturatedFat: 2, monounsaturatedFat: 3)
        
        let meal = Meal(name: "Snack", foodItems: [item1, item2])
        let log = DailyLog(date: Date(), meals: [meal])
        
        XCTAssertEqual(log.totalSaturatedFat(), 3)
        XCTAssertEqual(log.totalPolyunsaturatedFat(), 6)
        XCTAssertEqual(log.totalMonounsaturatedFat(), 9)
    }

    func testDailyLogTotalCaloriesBurnedFromManualExercises() {
        let ex1 = LoggedExercise(name: "Run", durationMinutes: 30, caloriesBurned: 300, date: Date(), source: "manual")
        let ex2 = LoggedExercise(name: "Walk", durationMinutes: 20, caloriesBurned: 100, date: Date(), source: "HealthKit")
        let ex3 = LoggedExercise(name: "Swim", durationMinutes: 45, caloriesBurned: 400, date: Date(), source: "manual")
        
        let log = DailyLog(date: Date(), meals: [], exercises: [ex1, ex2, ex3])
        
        XCTAssertEqual(log.totalCaloriesBurnedFromManualExercises(), 700)
    }

    func testDailyLogTotalCaloriesBurnedFromHealthKitWorkouts() {
        let ex1 = LoggedExercise(name: "Run", durationMinutes: 30, caloriesBurned: 300, date: Date(), source: "manual")
        let ex2 = LoggedExercise(name: "Walk", durationMinutes: 20, caloriesBurned: 100, date: Date(), source: "HealthKit")
        
        let log = DailyLog(date: Date(), meals: [], exercises: [ex1, ex2])
        
        XCTAssertEqual(log.totalCaloriesBurnedFromHealthKitWorkouts(), 100)
    }

    // MARK: - ServingNutritionCalculator Tests

    func testServingNutritionCalculatorParseQuantity() {
        let parsed1 = ServingNutritionCalculator.parseQuantity(from: "2 x slices")
        XCTAssertEqual(parsed1.quantity, 2.0)
        XCTAssertEqual(parsed1.baseDescription, "slices")
        
        let parsed2 = ServingNutritionCalculator.parseQuantity(from: "1.5 x cup")
        XCTAssertEqual(parsed2.quantity, 1.5)
        XCTAssertEqual(parsed2.baseDescription, "cup")
        
        let parsed3 = ServingNutritionCalculator.parseQuantity(from: "bowl")
        XCTAssertEqual(parsed3.quantity, 1.0)
        XCTAssertEqual(parsed3.baseDescription, "bowl")
    }

    func testServingNutritionCalculatorBaseServing() {
        let item = FoodItem(name: "Rice", calories: 200, protein: 4, carbs: 45, fats: 1, servingSize: "2 x cups", servingWeight: 200)
        
        let baseOption = ServingNutritionCalculator.baseServing(from: item)
        
        XCTAssertEqual(baseOption.description, "cups")
        XCTAssertEqual(baseOption.servingWeightGrams, 100)
        XCTAssertEqual(baseOption.calories, 100)
        XCTAssertEqual(baseOption.protein, 2)
        XCTAssertEqual(baseOption.carbs, 22.5)
        XCTAssertEqual(baseOption.fats, 0.5)
    }

    func testServingNutritionCalculatorAdjustedNutritionByText() {
        let baseOption = ServingSizeOption(description: "cup", servingWeightGrams: 100, calories: 150, protein: 5, carbs: 30, fats: 2)
        
        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: baseOption, quantityText: "2")
        
        XCTAssertEqual(adjusted.calories, 300)
        XCTAssertEqual(adjusted.protein, 10)
        XCTAssertEqual(adjusted.carbs, 60)
        XCTAssertEqual(adjusted.fats, 4)
        XCTAssertEqual(adjusted.servingWeightGrams, 200)
        XCTAssertEqual(adjusted.servingDescription, "2 x cup")
        XCTAssertEqual(adjusted.quantityValue, 2)
    }

    func testServingNutritionCalculatorAdjustedNutritionByValue() {
        let baseOption = ServingSizeOption(description: "slice", servingWeightGrams: 50, calories: 80, protein: 3, carbs: 15, fats: 1, fiber: 2, calcium: 10)
        
        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: baseOption, quantityValue: 1.5)
        
        XCTAssertEqual(adjusted.calories, 120)
        XCTAssertEqual(adjusted.protein, 4.5)
        XCTAssertEqual(adjusted.carbs, 22.5)
        XCTAssertEqual(adjusted.fats, 1.5)
        XCTAssertEqual(adjusted.fiber, 3.0)
        XCTAssertEqual(adjusted.calcium, 15)
        XCTAssertEqual(adjusted.servingWeightGrams, 75)
        XCTAssertEqual(adjusted.servingDescription, "1.5 x slice")
        XCTAssertEqual(adjusted.quantityValue, 1.5)
        XCTAssertEqual(adjusted.servingUnit, "slice")
    }

    // MARK: - NutritionCalorieConsistency Tests
    
    func testCalorieConsistencyStatusNoMismatch() {
        // 20p(80) + 20c(80) + 10f(90) = 250
        let status = NutritionCalorieConsistency.status(calories: 250, protein: 20, carbs: 20, fats: 10)
        
        XCTAssertEqual(status.macroDerivedCalories, 250)
        XCTAssertEqual(status.delta, 0)
        XCTAssertFalse(status.hasMeaningfulMismatch)
    }
    
    func testCalorieConsistencyStatusAbsoluteMismatch() {
        // 20p(80) + 20c(80) + 10f(90) = 250
        // Logged: 150. Delta: 100 (> absolute mismatch threshold 75)
        let status = NutritionCalorieConsistency.status(calories: 150, protein: 20, carbs: 20, fats: 10)
        
        XCTAssertEqual(status.delta, 100)
        XCTAssertTrue(status.hasMeaningfulMismatch)
    }

    func testCalorieConsistencyStatusRelativeMismatch() {
        // 20p(80) + 20c(80) + 10f(90) = 250
        // Logged: 210. Delta: 40. Relative delta: 40 / 250 = 0.16 (> relative mismatch threshold 0.12)
        let status = NutritionCalorieConsistency.status(calories: 210, protein: 20, carbs: 20, fats: 10)
        
        XCTAssertEqual(status.delta, 40)
        XCTAssertEqual(status.relativeDelta, 0.16)
        XCTAssertTrue(status.hasMeaningfulMismatch)
    }

    func testNormalizedCaloriesForEstimatedSourceValid() {
        // 20p(80) + 20c(80) + 10f(90) = 250
        let cal = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(calories: 150, protein: 20, carbs: 20, fats: 10, source: "ai_chat")
        
        // Mismatch is meaningful, delta > 0, so should return macro derived
        XCTAssertEqual(cal, 250)
    }
    
    func testNormalizedCaloriesForEstimatedSourceMissingCalories() {
        // 20p(80) + 20c(80) + 10f(90) = 250
        let cal = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(calories: 0, protein: 20, carbs: 20, fats: 10, source: "manual")
        
        // Missing calories should always map to macro derived
        XCTAssertEqual(cal, 250)
    }
    
    func testNormalizedCaloriesForDatabaseSource() {
        // 20p(80) + 20c(80) + 10f(90) = 250
        let cal = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(calories: 150, protein: 20, carbs: 20, fats: 10, source: "fatsecret")
        
        // Database sources are not normalized
        XCTAssertEqual(cal, 150)
    }
}
