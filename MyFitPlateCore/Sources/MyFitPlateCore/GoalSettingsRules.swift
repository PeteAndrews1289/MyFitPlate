import Foundation

public struct MicronutrientGoals: Equatable {
    public let calcium: Double?
    public let iron: Double?
    public let potassium: Double?
    public let sodium: Double?
    public let vitaminA: Double?
    public let vitaminC: Double?
    public let vitaminD: Double?
    public let vitaminB12: Double?
    public let folate: Double?
    public let water: Double
}

public struct MacroGoals: Equatable {
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public let validPercentages: Bool
}

public enum GoalSettingsRules {
    public static func calculateBMR(age: Int, weightKg: Double, heightCm: Double, gender: String) -> Double {
        guard age > 0 else { return 1500 }
        if gender.lowercased() == "male" {
            return (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + 5
        } else {
            return (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) - 161
        }
    }
    
    public static func calculateCalorieGoal(
        bmr: Double,
        goal: String,
        gender: String,
        calorieGoalMethod: CalorieGoalMethod,
        activityLevel: Double,
        adaptiveTDEE: Double?,
        manualCaloriesBurned: Double,
        currentCalories: Double?
    ) -> Double {
        var calculatedCalories: Double = 0
        var calorieAdjustmentForWeightGoal: Double = 0
        
        switch goal {
        case "Lose": calorieAdjustmentForWeightGoal = -250
        case "Gain": calorieAdjustmentForWeightGoal = 250
        default: break
        }
        
        let minimumGoal: Double = (gender.lowercased() == "male") ? 1500 : 1200
        
        switch calorieGoalMethod {
        case .custom:
            var cal = currentCalories ?? 2000
            if cal < minimumGoal {
                cal = minimumGoal
            }
            return cal
        case .mifflinWithActivity:
            let maintenanceCalories = bmr * activityLevel
            calculatedCalories = maintenanceCalories + calorieAdjustmentForWeightGoal
            
        case .dynamicTDEE:
            if let adaptiveTDEE = adaptiveTDEE {
                calculatedCalories = adaptiveTDEE + calorieAdjustmentForWeightGoal
            } else {
                calculatedCalories = bmr + manualCaloriesBurned + calorieAdjustmentForWeightGoal
            }
        }

        return max(minimumGoal, calculatedCalories)
    }
    
    public static func updateMacros(calories: Double?, proteinPercentage: Double, carbsPercentage: Double, fatsPercentage: Double) -> MacroGoals {
        guard let calGoal = calories, calGoal > 0 else {
            return MacroGoals(protein: 150, carbs: 250, fats: 70, validPercentages: true)
        }
        let totalPct = proteinPercentage + carbsPercentage + fatsPercentage
        guard abs(totalPct - 100.0) < 1.0 else {
            // Invalid percentages
            return MacroGoals(protein: 150, carbs: 250, fats: 70, validPercentages: false)
        }
        let pCals = (proteinPercentage / 100) * calGoal
        let cCals = (carbsPercentage / 100) * calGoal
        let fCals = (fatsPercentage / 100) * calGoal
        return MacroGoals(protein: pCals / 4, carbs: cCals / 4, fats: fCals / 9, validPercentages: true)
    }
    
    public static func calculateMicronutrientGoals(age: Int, gender: String) -> MicronutrientGoals {
        let genderLower = gender.lowercased()
        
        let calciumGoal: Double
        switch age {
            case 0...3: calciumGoal = 700; case 4...8: calciumGoal = 1000; case 9...18: calciumGoal = 1300
            case 19...50: calciumGoal = 1000; case 51...70: calciumGoal = (genderLower == "female") ? 1200 : 1000
            case 71...: calciumGoal = 1200; default: calciumGoal = 1000
        }
        
        let ironGoal: Double
        switch age {
            case 0...3: ironGoal = 7; case 4...8: ironGoal = 10; case 9...13: ironGoal = 8
            case 14...18: ironGoal = (genderLower == "female") ? 15 : 11
            case 19...50: ironGoal = (genderLower == "female") ? 18 : 8
            case 51...: ironGoal = 8; default: ironGoal = (genderLower == "female") ? 18 : 8
        }
        
        let potassiumGoal: Double
        switch age {
            case 0...3: potassiumGoal = 2000; case 4...8: potassiumGoal = 2300
            case 9...13: potassiumGoal = (genderLower == "female") ? 2300 : 2500
            case 14...18: potassiumGoal = (genderLower == "female") ? 2300 : 3000
            case 19...: potassiumGoal = (genderLower == "female") ? 2600 : 3400
            default: potassiumGoal = (genderLower == "female") ? 2600 : 3400
        }
        
        let sodiumGoal: Double = 2300
        
        let vitaminAGoal: Double
        switch age {
            case 0...3: vitaminAGoal = 300; case 4...8: vitaminAGoal = 400; case 9...13: vitaminAGoal = 600
            case 14...18: vitaminAGoal = (genderLower == "female") ? 700 : 900
            case 19...: vitaminAGoal = (genderLower == "female") ? 700 : 900
            default: vitaminAGoal = (genderLower == "female") ? 700 : 900
        }
        
        let vitaminCGoal: Double
        switch age {
            case 0...3: vitaminCGoal = 15; case 4...8: vitaminCGoal = 25; case 9...13: vitaminCGoal = 45
            case 14...18: vitaminCGoal = (genderLower == "female") ? 65 : 75
            case 19...: vitaminCGoal = (genderLower == "female") ? 75 : 90
            default: vitaminCGoal = (genderLower == "female") ? 75 : 90
        }
        
        let vitaminDGoal: Double
        switch age {
            case 0...70: vitaminDGoal = 15; case 71...: vitaminDGoal = 20; default: vitaminDGoal = 15
        }
        
        return MicronutrientGoals(
            calcium: calciumGoal,
            iron: ironGoal,
            potassium: potassiumGoal,
            sodium: sodiumGoal,
            vitaminA: vitaminAGoal,
            vitaminC: vitaminCGoal,
            vitaminD: vitaminDGoal,
            vitaminB12: 2.4,
            folate: 400,
            water: 64.0
        )
    }
}
