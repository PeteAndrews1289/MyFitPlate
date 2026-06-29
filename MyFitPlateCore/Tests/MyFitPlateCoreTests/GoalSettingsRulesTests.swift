import XCTest
@testable import MyFitPlateCore

final class GoalSettingsRulesTests: XCTestCase {

    func testCalculateBMR() {
        // Male: (10 * 80) + (6.25 * 180) - (5 * 30) + 5 = 800 + 1125 - 150 + 5 = 1780
        let bmrMale = GoalSettingsRules.calculateBMR(age: 30, weightKg: 80, heightCm: 180, gender: "Male")
        XCTAssertEqual(bmrMale, 1780)
        
        // Female: (10 * 60) + (6.25 * 165) - (5 * 25) - 161 = 600 + 1031.25 - 125 - 161 = 1345.25
        let bmrFemale = GoalSettingsRules.calculateBMR(age: 25, weightKg: 60, heightCm: 165, gender: "Female")
        XCTAssertEqual(bmrFemale, 1345.25)
        
        // Invalid age
        let bmrInvalidAge = GoalSettingsRules.calculateBMR(age: 0, weightKg: 80, heightCm: 180, gender: "Male")
        XCTAssertEqual(bmrInvalidAge, 1500)
    }

    func testCalculateCalorieGoalCustom() {
        let maleGoal = GoalSettingsRules.calculateCalorieGoal(
            bmr: 2000, goal: "Maintain", gender: "Male",
            calorieGoalMethod: .custom, activityLevel: 1.2,
            adaptiveTDEE: nil, manualCaloriesBurned: 0, currentCalories: 1000
        )
        // Minimum for male is 1500
        XCTAssertEqual(maleGoal, 1500)
        
        let femaleGoal = GoalSettingsRules.calculateCalorieGoal(
            bmr: 1500, goal: "Maintain", gender: "Female",
            calorieGoalMethod: .custom, activityLevel: 1.2,
            adaptiveTDEE: nil, manualCaloriesBurned: 0, currentCalories: 1000
        )
        // Minimum for female is 1200
        XCTAssertEqual(femaleGoal, 1200)

        let customGoal = GoalSettingsRules.calculateCalorieGoal(
            bmr: 2000, goal: "Maintain", gender: "Male",
            calorieGoalMethod: .custom, activityLevel: 1.2,
            adaptiveTDEE: nil, manualCaloriesBurned: 0, currentCalories: 2500
        )
        XCTAssertEqual(customGoal, 2500)
    }

    func testCalculateCalorieGoalMifflin() {
        let goalLose = GoalSettingsRules.calculateCalorieGoal(
            bmr: 2000, goal: "Lose", gender: "Male",
            calorieGoalMethod: .mifflinWithActivity, activityLevel: 1.2,
            adaptiveTDEE: nil, manualCaloriesBurned: 0, currentCalories: nil
        )
        // 2000 * 1.2 = 2400. Lose = -250 -> 2150
        XCTAssertEqual(goalLose, 2150)
        
        let goalGain = GoalSettingsRules.calculateCalorieGoal(
            bmr: 2000, goal: "Gain", gender: "Male",
            calorieGoalMethod: .mifflinWithActivity, activityLevel: 1.2,
            adaptiveTDEE: nil, manualCaloriesBurned: 0, currentCalories: nil
        )
        // 2000 * 1.2 = 2400. Gain = +250 -> 2650
        XCTAssertEqual(goalGain, 2650)
    }

    func testCalculateCalorieGoalDynamicTDEE() {
        // With adaptive TDEE
        let goalAdaptive = GoalSettingsRules.calculateCalorieGoal(
            bmr: 1800, goal: "Maintain", gender: "Female",
            calorieGoalMethod: .dynamicTDEE, activityLevel: 1.2,
            adaptiveTDEE: 2200, manualCaloriesBurned: 500, currentCalories: nil
        )
        XCTAssertEqual(goalAdaptive, 2200)
        
        // Without adaptive TDEE (Fallback)
        let goalFallback = GoalSettingsRules.calculateCalorieGoal(
            bmr: 1800, goal: "Lose", gender: "Female",
            calorieGoalMethod: .dynamicTDEE, activityLevel: 1.2,
            adaptiveTDEE: nil, manualCaloriesBurned: 300, currentCalories: nil
        )
        // BMR(1800) + ManualBurned(300) - 250(Lose) = 1850
        XCTAssertEqual(goalFallback, 1850)
    }

    func testUpdateMacros() {
        // Normal case
        let validMacros = GoalSettingsRules.updateMacros(calories: 2000, proteinPercentage: 30, carbsPercentage: 50, fatsPercentage: 20)
        XCTAssertTrue(validMacros.validPercentages)
        XCTAssertEqual(validMacros.protein, 150) // 600 / 4
        XCTAssertEqual(validMacros.carbs, 250)   // 1000 / 4
        XCTAssertEqual(validMacros.fats, 44.444, accuracy: 0.001)  // 400 / 9
        
        // Invalid percentages case
        let invalidMacros = GoalSettingsRules.updateMacros(calories: 2000, proteinPercentage: 40, carbsPercentage: 40, fatsPercentage: 40)
        XCTAssertFalse(invalidMacros.validPercentages)
        XCTAssertEqual(invalidMacros.protein, 150) // Defaults
        XCTAssertEqual(invalidMacros.carbs, 250)
        XCTAssertEqual(invalidMacros.fats, 70)
        
        // Nil or 0 calories
        let noCaloriesMacros = GoalSettingsRules.updateMacros(calories: 0, proteinPercentage: 30, carbsPercentage: 50, fatsPercentage: 20)
        XCTAssertTrue(noCaloriesMacros.validPercentages)
        XCTAssertEqual(noCaloriesMacros.protein, 150)
        XCTAssertEqual(noCaloriesMacros.carbs, 250)
        XCTAssertEqual(noCaloriesMacros.fats, 70)
    }

    func testCalculateMicronutrientGoals() {
        // Child
        let child = GoalSettingsRules.calculateMicronutrientGoals(age: 2, gender: "Male")
        XCTAssertEqual(child.calcium, 700)
        XCTAssertEqual(child.iron, 7)
        XCTAssertEqual(child.potassium, 2000)
        XCTAssertEqual(child.vitaminA, 300)
        XCTAssertEqual(child.vitaminC, 15)
        
        // Teen Male
        let teenMale = GoalSettingsRules.calculateMicronutrientGoals(age: 15, gender: "Male")
        XCTAssertEqual(teenMale.calcium, 1300)
        XCTAssertEqual(teenMale.iron, 11)
        XCTAssertEqual(teenMale.potassium, 3000)
        XCTAssertEqual(teenMale.vitaminA, 900)
        XCTAssertEqual(teenMale.vitaminC, 75)
        
        // Teen Female
        let teenFemale = GoalSettingsRules.calculateMicronutrientGoals(age: 15, gender: "Female")
        XCTAssertEqual(teenFemale.calcium, 1300)
        XCTAssertEqual(teenFemale.iron, 15)
        XCTAssertEqual(teenFemale.potassium, 2300)
        XCTAssertEqual(teenFemale.vitaminA, 700)
        XCTAssertEqual(teenFemale.vitaminC, 65)

        // Adult Female (Pregnancy age typical)
        let adultFemale = GoalSettingsRules.calculateMicronutrientGoals(age: 30, gender: "Female")
        XCTAssertEqual(adultFemale.calcium, 1000)
        XCTAssertEqual(adultFemale.iron, 18)
        XCTAssertEqual(adultFemale.potassium, 2600)
        XCTAssertEqual(adultFemale.vitaminA, 700)
        XCTAssertEqual(adultFemale.vitaminC, 75)
        
        // Older Male
        let olderMale = GoalSettingsRules.calculateMicronutrientGoals(age: 75, gender: "Male")
        XCTAssertEqual(olderMale.calcium, 1200)
        XCTAssertEqual(olderMale.iron, 8)
        XCTAssertEqual(olderMale.potassium, 3400)
        XCTAssertEqual(olderMale.vitaminD, 20)
    }
}
