import Foundation

public enum GoalEditorError: LocalizedError {
    case accountChanged, alreadySaving, changed, invalid, unavailable
    public var errorDescription: String? {
        switch self {
        case .accountChanged: return "Your account changed. Reopen goals from the correct account."
        case .alreadySaving: return "Your goals are already saving."
        case .changed: return "Your goals changed while this editor was open. Close and reopen it before saving."
        case .invalid: return "Check your age, weights, calorie target, and macro percentages. Percentages must total 100%."
        case .unavailable: return "Goals could not be saved. Your draft is still here; try again."
        }
    }
}

/// Value-only editing state. Changing this proposal never mutates current or historical goals.
public struct GoalEditorDraft: Codable, Equatable {
    public var age: Int
    public var gender: String
    public var weight: Double
    public var height: Double
    public var activityLevel: Double
    public var goal: String
    public var targetWeight: Double?
    public var weeklyChangeLbs: Double
    public var method: CalorieGoalMethod
    public var calories: Double
    public var proteinPercentage: Double
    public var carbsPercentage: Double
    public var fatsPercentage: Double

    /// Recognize only shipped legacy labels in a value copy. The original remains
    /// the compare-and-set baseline until the user explicitly saves this proposal.
    public func normalizedForEditing() -> GoalEditorDraft {
        var result = self
        switch goal {
        case "Lose Weight": result.goal = "Lose"
        case "Gain Weight": result.goal = "Gain"
        case "Maintain Weight": result.goal = "Maintain"
        default: break
        }
        return result
    }

    public func resolved(adaptiveTDEE: Double?, manualCaloriesBurned: Double) throws -> GoalEditorDraft {
        guard (1...120).contains(age), ["Male", "Female"].contains(gender),
              weight.isFinite, weight > 0, weight <= 2_200, height.isFinite, height > 0, height <= 300,
              activityLevel.isFinite, activityLevel > 0, activityLevel <= 4,
              ["Lose", "Maintain", "Gain"].contains(goal), weeklyChangeLbs.isFinite,
              targetWeight.map({ $0.isFinite && $0 > 0 && $0 <= 2_200 }) ?? true,
              calories.isFinite, calories > 0, calories <= 100_000,
              [proteinPercentage, carbsPercentage, fatsPercentage].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100 }),
              abs(proteinPercentage + carbsPercentage + fatsPercentage - 100) < 0.01 else { throw GoalEditorError.invalid }
        var result = self
        result.weeklyChangeLbs = GoalSettingsRules.normalizedWeeklyChange(weeklyChangeLbs, forGoal: goal)
        result.calories = GoalSettingsRules.calculateCalorieGoal(
            bmr: GoalSettingsRules.calculateBMR(age: age, weightKg: weight * 0.453592, heightCm: height, gender: gender),
            goal: goal, gender: gender, calorieGoalMethod: method, activityLevel: activityLevel,
            adaptiveTDEE: adaptiveTDEE?.isFinite == true ? adaptiveTDEE : nil,
            manualCaloriesBurned: manualCaloriesBurned.isFinite ? manualCaloriesBurned : 0,
            currentCalories: calories, weeklyChangeLbs: result.weeklyChangeLbs
        )
        return result
    }

    /// Derived targets may refresh while a formula/adaptive editor is open; inputs may not.
    public func hasSameInputs(as other: GoalEditorDraft) -> Bool {
        var lhs = self
        var rhs = other
        if method != .custom && other.method != .custom { lhs.calories = 0; rhs.calories = 0 }
        return lhs == rhs
    }

    public var macros: MacroGoals {
        GoalSettingsRules.updateMacros(calories: calories, proteinPercentage: proteinPercentage,
                                       carbsPercentage: carbsPercentage, fatsPercentage: fatsPercentage)
    }

    public func payload(updatedAt: Date) -> [String: Any] {
        ["age": age, "gender": gender, "weight": weight, "height": height,
         "calorieGoalMethod": method.rawValue, "activityLevel": activityLevel, "goal": goal,
         "calories": calories, "goalSettingsUpdatedAt": updatedAt,
         "goals": ["calories": calories, "protein": macros.protein, "carbs": macros.carbs, "fats": macros.fats,
                   "proteinPercentage": proteinPercentage, "carbsPercentage": carbsPercentage, "fatsPercentage": fatsPercentage,
                   "activityLevel": activityLevel, "goal": goal, "targetWeight": targetWeight.map { $0 as Any } ?? NSNull(),
                   "weeklyChangeLbs": weeklyChangeLbs, "updatedAt": updatedAt]]
    }

    /// Compare only present editable fields, retaining compatibility with incomplete legacy profiles.
    public func matchesPersistedInputs(_ data: [String: Any]) -> Bool {
        let goals = data["goals"] as? [String: Any] ?? [:]
        func number(_ value: Any?, _ expected: Double) -> Bool {
            guard let value else { return true }
            return (value as? NSNumber).map { abs($0.doubleValue - expected) < 0.0001 } ?? false
        }
        func string(_ value: Any?, _ expected: String) -> Bool { value == nil || value as? String == expected }
        return number(data["age"], Double(age)) && number(data["weight"], weight) && number(data["height"], height)
            && string(data["gender"], gender) && string(data["calorieGoalMethod"], method.rawValue)
            && number(goals["activityLevel"] ?? data["activityLevel"], activityLevel)
            && string(goals["goal"] ?? data["goal"], goal)
            && number(goals["weeklyChangeLbs"], weeklyChangeLbs)
            && number(goals["proteinPercentage"], proteinPercentage) && number(goals["carbsPercentage"], carbsPercentage)
            && number(goals["fatsPercentage"], fatsPercentage)
            && (goals["targetWeight"] == nil || (goals["targetWeight"] is NSNull && targetWeight == nil)
                || (targetWeight.map { number(goals["targetWeight"], $0) } ?? false))
            && (method != .custom || number(goals["calories"] ?? data["calories"], calories))
    }
}
