import Foundation

public func capitalizedFirstLetter(of string: String) -> String {
    guard let first = string.first else { return "" }
    return first.uppercased() + string.dropFirst()
}

public struct ChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let text: String
    public let isUser: Bool

    public init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
}

public enum MaiaContextScope: String, Codable, CaseIterable, Equatable {
    case todayLog = "today_log"
    case nutritionGoals = "nutrition_goals"
    case nutritionAudit = "nutrition_audit"
    case water = "water"
    case loggedTraining = "logged_training"
    case healthKit = "healthkit"
    case pantry = "pantry"
    case coachingPreferences = "coaching_preferences"
    case aiEstimates = "ai_estimates"

    public var promptLabel: String {
        switch self {
        case .todayLog:
            return "today's food totals"
        case .nutritionGoals:
            return "nutrition goals"
        case .nutritionAudit:
            return "nutrition audit flags"
        case .water:
            return "water progress"
        case .loggedTraining:
            return "logged training"
        case .healthKit:
            return "passive HealthKit signals"
        case .pantry:
            return "pantry item names"
        case .coachingPreferences:
            return "coaching preferences"
        case .aiEstimates:
            return "AI-estimate counts"
        }
    }
}

public struct MaiaContextContract: Codable, Equatable {
    public let action: String
    public let scopes: [MaiaContextScope]

    public init(action: String, scopes: [MaiaContextScope]) {
        self.action = action
        self.scopes = MaiaContextScope.allCases.filter { scopes.contains($0) }
    }

    public func allows(_ scope: MaiaContextScope) -> Bool {
        scopes.contains(scope)
    }

    public func respectingHealthDataConsent(_ isAllowed: Bool) -> MaiaContextContract {
        guard !isAllowed else { return self }
        return MaiaContextContract(action: action, scopes: scopes.filter { $0 != .healthKit })
    }

    public var telemetryScopeList: String {
        scopes.map(\.rawValue).joined(separator: ",")
    }

    public var promptSummary: String {
        let labels = scopes.map(\.promptLabel).joined(separator: ", ")
        return """
        Context boundary for this request:
        - Action: \(action)
        - Allowed context: \(labels)
        Use only the allowed context included below. If another data source would be helpful, ask instead of assuming.
        """
    }

    public static func generalChat(includeHealthKit: Bool = true) -> MaiaContextContract {
        var scopes: [MaiaContextScope] = [
            .todayLog,
            .nutritionGoals,
            .nutritionAudit,
            .water,
            .loggedTraining,
            .coachingPreferences,
            .aiEstimates
        ]
        if includeHealthKit {
            scopes.append(.healthKit)
        }
        return MaiaContextContract(action: "general_chat", scopes: scopes)
    }

    public static let proteinAnchor = MaiaContextContract(
        action: "protein_anchor",
        scopes: [.todayLog, .nutritionGoals, .water, .coachingPreferences, .aiEstimates]
    )

    public static let recoveryMeal = MaiaContextContract(
        action: "recovery_meal",
        scopes: [.todayLog, .nutritionGoals, .water, .loggedTraining, .coachingPreferences, .aiEstimates]
    )

    public static let trustAudit = MaiaContextContract(
        action: "trust_audit",
        scopes: [.todayLog, .nutritionGoals, .nutritionAudit, .aiEstimates]
    )

    public static func dailyRead(includeHealthKit: Bool) -> MaiaContextContract {
        var scopes: [MaiaContextScope] = [
            .todayLog,
            .nutritionGoals,
            .nutritionAudit,
            .water,
            .loggedTraining,
            .coachingPreferences,
            .aiEstimates
        ]
        if includeHealthKit {
            scopes.append(.healthKit)
        }
        return MaiaContextContract(action: "daily_read", scopes: scopes)
    }

    public static let fillMacros = MaiaContextContract(
        action: "fill_macros",
        scopes: [.todayLog, .nutritionGoals, .water, .pantry, .aiEstimates]
    )

    public static let hydration = MaiaContextContract(
        action: "log_water",
        scopes: [.water, .nutritionGoals]
    )
}

public struct MaiaActionPayload: Codable, Identifiable {
    public var id: UUID { UUID() }
    public let type: String?
    public let mealName: String?
    public let calories: Double?
    public let protein: Double?
    public let carbs: Double?
    public let fats: Double?
    
    public let exerciseName: String?
    public let durationMinutes: Int?
    public let caloriesBurned: Double?
    
    public let amountOunces: Double?
    public let fastHours: Int?
    public let weightPounds: Double?
}

public extension MaiaActionPayload {
    var validationIssueKind: String? {
        switch type {
        case "meal_suggestion", nil:
            guard let mealName, !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let calories, calories >= 0,
                  let protein, protein >= 0,
                  let carbs, carbs >= 0,
                  let fats, fats >= 0 else {
                return "meal_suggestion_missing_fields"
            }
        case "generate_meal_plan", "stop_fast":
            return nil
        case "log_workout":
            guard let exerciseName, !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let durationMinutes, durationMinutes > 0,
                  let caloriesBurned, caloriesBurned >= 0 else {
                return "log_workout_missing_fields"
            }
        case "log_water":
            guard let amountOunces, amountOunces > 0 else {
                return "log_water_missing_fields"
            }
        case "start_fast":
            guard fastHours == nil || (fastHours ?? 0) > 0 else {
                return "start_fast_invalid_hours"
            }
        case "log_weight":
            guard let weightPounds, weightPounds > 0 else {
                return "log_weight_missing_fields"
            }
        default:
            return "unknown_action_type"
        }

        return nil
    }

    var isRenderableAction: Bool {
        validationIssueKind == nil
    }
}

public enum MaiaAction {
    case generateMealPlan
    case logWorkout(exerciseName: String, durationMinutes: Int, caloriesBurned: Double)
    case logWater(amountOunces: Double)
    case startFast(hours: Int)
    case stopFast
    case logWeight(weightPounds: Double)
}
