import XCTest
@testable import MyFitPlate

final class GoalSettingsTests: XCTestCase {

    var mockHealthKitManager: MockHealthKitManager!
    var goalSettings: GoalSettings!

    @MainActor
    override func setUpWithError() throws {
        mockHealthKitManager = MockHealthKitManager()
        goalSettings = GoalSettings(healthKitManager: mockHealthKitManager)
    }

    override func tearDownWithError() throws {
        mockHealthKitManager = nil
        goalSettings = nil
    }

    @MainActor
    func testBMRCalculation_Male() async throws {
        // Given
        goalSettings.gender = "Male"
        goalSettings.age = 25
        goalSettings.weight = 180.0
        goalSettings.height = 180.0 // cm
        goalSettings.activityLevel = 1.2
        goalSettings.goal = "Maintain"
        goalSettings.calorieGoalMethod = .mifflinWithActivity
        
        // When
        goalSettings.recalculateAllGoals() // Dispatches to main
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then
        XCTAssertNotNil(goalSettings.calories)
        let cals = goalSettings.calories ?? 0
        XCTAssertEqual(cals, 2185.76, accuracy: 1.0)
    }
    
    @MainActor
    func testBMRCalculation_Female() async throws {
        goalSettings.gender = "Female"
        goalSettings.age = 30
        goalSettings.weight = 140.0
        goalSettings.height = 165.0
        goalSettings.activityLevel = 1.55 // active
        goalSettings.goal = "Lose"
        goalSettings.calorieGoalMethod = .mifflinWithActivity
        
        goalSettings.recalculateAllGoals()
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertNotNil(goalSettings.calories)
        XCTAssertEqual(goalSettings.calories ?? 0, 1600.6, accuracy: 1.0)
    }
}

final class ServingNutritionCalculatorTests: XCTestCase {
    func testBaseServingUsesStructuredQuantityAndUnit() {
        let item = makeFoodItem(
            calories: 300,
            protein: 30,
            carbs: 45,
            fats: 9,
            servingSize: "3 x bowl",
            servingWeight: 450,
            fiber: 12,
            quantityValue: 3,
            servingUnit: "bowl"
        )

        let serving = ServingNutritionCalculator.baseServing(from: item)

        XCTAssertEqual(serving.description, "bowl")
        XCTAssertEqual(serving.calories, 100, accuracy: 0.001)
        XCTAssertEqual(serving.protein, 10, accuracy: 0.001)
        XCTAssertEqual(serving.carbs, 15, accuracy: 0.001)
        XCTAssertEqual(serving.fats, 3, accuracy: 0.001)
        XCTAssertEqual(serving.fiber ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(serving.servingWeightGrams ?? 0, 150, accuracy: 0.001)
    }

    func testAdjustedNutritionScalesServingOption() {
        let serving = ServingSizeOption(
            description: "cup",
            servingWeightGrams: 120,
            calories: 80,
            protein: 6,
            carbs: 14,
            fats: 2,
            saturatedFat: 0.5,
            polyunsaturatedFat: nil,
            monounsaturatedFat: nil,
            fiber: 3,
            calcium: nil,
            iron: nil,
            potassium: nil,
            sodium: 90,
            vitaminA: nil,
            vitaminC: nil,
            vitaminD: nil,
            vitaminB12: nil,
            folate: nil,
            magnesium: nil,
            phosphorus: nil,
            zinc: nil,
            copper: nil,
            manganese: nil,
            selenium: nil,
            vitaminB1: nil,
            vitaminB2: nil,
            vitaminB3: nil,
            vitaminB5: nil,
            vitaminB6: nil,
            vitaminE: nil,
            vitaminK: nil
        )

        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: serving, quantityText: "2.5")

        XCTAssertEqual(adjusted.servingDescription, "2.5 x cup")
        XCTAssertEqual(adjusted.quantityValue, 2.5, accuracy: 0.001)
        XCTAssertEqual(adjusted.servingWeightGrams, 300, accuracy: 0.001)
        XCTAssertEqual(adjusted.calories, 200, accuracy: 0.001)
        XCTAssertEqual(adjusted.protein, 15, accuracy: 0.001)
        XCTAssertEqual(adjusted.carbs, 35, accuracy: 0.001)
        XCTAssertEqual(adjusted.fats, 5, accuracy: 0.001)
        XCTAssertEqual(adjusted.fiber ?? 0, 7.5, accuracy: 0.001)
        XCTAssertEqual(adjusted.sodium ?? 0, 225, accuracy: 0.001)
    }

    private func makeFoodItem(
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        servingSize: String,
        servingWeight: Double,
        fiber: Double?,
        quantityValue: Double?,
        servingUnit: String?
    ) -> FoodItem {
        FoodItem(
            id: "test-food",
            name: "Test Food",
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            saturatedFat: nil,
            polyunsaturatedFat: nil,
            monounsaturatedFat: nil,
            fiber: fiber,
            servingSize: servingSize,
            servingWeight: servingWeight,
            timestamp: nil,
            calcium: nil,
            iron: nil,
            potassium: nil,
            sodium: nil,
            vitaminA: nil,
            vitaminC: nil,
            vitaminD: nil,
            vitaminB12: nil,
            folate: nil,
            magnesium: nil,
            phosphorus: nil,
            zinc: nil,
            copper: nil,
            manganese: nil,
            selenium: nil,
            vitaminB1: nil,
            vitaminB2: nil,
            vitaminB3: nil,
            vitaminB5: nil,
            vitaminB6: nil,
            vitaminE: nil,
            vitaminK: nil,
            quantityValue: quantityValue,
            servingUnit: servingUnit
        )
    }
}
