import Foundation

public enum FoodPreferencesError: LocalizedError {
    case accountChanged, alreadySaving, changed, invalid, unavailable

    public var errorDescription: String? {
        switch self {
        case .accountChanged: return "Your account changed. Reopen food preferences from the correct account."
        case .alreadySaving: return "Your preferences are already saving."
        case .changed: return "Your food preferences changed while this editor was open. Reopen it to review the latest choices."
        case .invalid: return "Check your food choices and try again."
        case .unavailable: return "Preferences couldn't be saved. Your choices are still here; try again."
        }
    }
}

/// Food likes remain soft preferences. The optional ingredient profile is a separate,
/// versioned set of hard proposal constraints; favorites never override those limits.
public struct FoodPreferencesDraft: Codable, Equatable, Sendable {
    public var proteins: [String]
    public var carbs: [String]
    public var vegetables: [String]
    public var cuisines: [String]
    public var mealConstraintProfile: MealConstraintProfile?
    /// Nil is legacy/unknown; existing arrays never establish that a person chose them.
    public var selectionOrigin: String?

    public init(proteins: [String], carbs: [String], vegetables: [String], cuisines: [String], mealConstraintProfile: MealConstraintProfile? = nil, selectionOrigin: String? = nil) {
        self.proteins = proteins; self.carbs = carbs; self.vegetables = vegetables; self.cuisines = cuisines
        self.mealConstraintProfile = mealConstraintProfile
        self.selectionOrigin = selectionOrigin
    }

    public static let defaults = FoodPreferencesDraft(proteins: ["Chicken", "Beef", "Fish"], carbs: ["Rice", "Potatoes", "Pasta"],
                                                      vegetables: ["Broccoli", "Bell Peppers"], cuisines: ["Any"])

    public func validated() throws -> FoodPreferencesDraft {
        try mealConstraintProfile?.validate()
        guard [proteins, carbs, vegetables, cuisines].allSatisfy({ values in
            values.count <= 100 && values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 120 }
        }) else { throw FoodPreferencesError.invalid }
        return self
    }

    /// Only present preference fields participate in the comparison, so old profiles retain
    /// their defaults. A malformed present field fails closed. Unknown saved choices survive.
    public func matchesPersistedPreferences(_ profile: [String: Any]) -> Bool {
        let goals: [String: Any]
        if let value = profile["goals"] {
            guard let stored = value as? [String: Any] else { return false }
            goals = stored
        } else { goals = [:] }
        let persistedOrigin = goals["foodPreferenceOrigin"]
        guard persistedOrigin == nil || persistedOrigin is NSNull || persistedOrigin is String,
              (persistedOrigin as? String) == selectionOrigin else { return false }
        guard let persistedProfile = try? MealConstraintProfile.decodeField(goals["mealConstraintProfile"]),
              persistedProfile == mealConstraintProfile else {
            return mealConstraintProfile == nil && (goals["mealConstraintProfile"] == nil || goals["mealConstraintProfile"] is NSNull) && fields.allSatisfy { key, expected in
                guard let stored = goals[key] else { return true }; return (stored as? [String]) == expected
            }
        }
        return fields.allSatisfy { key, expected in
            guard let stored = goals[key] else { return true }
            return (stored as? [String]) == expected
        }
    }

    public var fields: [String: [String]] {
        ["suggestionProteins": proteins, "suggestionCarbs": carbs,
         "suggestionVeggies": vegetables, "suggestionCuisines": cuisines]
    }

    public func profilePatch(updatedAt: Date) -> [String: Any] {
        var patch: [String: Any] = fields.reduce(into: [:]) { $0["goals.\($1.key)"] = $1.value }
        patch["goals.mealConstraintProfile"] = mealConstraintProfile?.fields ?? NSNull()
        patch["goals.foodPreferenceOrigin"] = selectionOrigin ?? NSNull()
        patch["goals.updatedAt"] = updatedAt
        return patch
    }
}

/// Captures exactly whose preferences the editor opened and its compare-and-set baseline.
public struct FoodPreferencesRevision: Codable, Equatable, Sendable {
    public let userID: String
    public let baseline: FoodPreferencesDraft

    public init(userID: String, baseline: FoodPreferencesDraft) {
        self.userID = userID; self.baseline = baseline
    }
}

/// An interrupted editor retains its original comparison baseline. Restoring a draft
/// must never silently authorize overwriting preferences saved on another device.
public struct FoodPreferencesEditorCheckpoint: Codable, Equatable, Sendable {
    public static let scope = "food-preferences-editor"
    public let revision: FoodPreferencesRevision
    public var draft: FoodPreferencesDraft
    public var exclusionsText: String
    public var ingredientPattern: PlanningDiet
    public var customChoices: [String: String]

    public init(revision: FoodPreferencesRevision, draft: FoodPreferencesDraft,
                exclusionsText: String, ingredientPattern: PlanningDiet,
                customChoices: [String: String] = [:]) {
        self.revision = revision; self.draft = draft; self.exclusionsText = exclusionsText
        self.ingredientPattern = ingredientPattern; self.customChoices = customChoices
    }
    public func canRestore(for userID: String) -> Bool { !userID.isEmpty && revision.userID == userID }
    public func requiresConflictReview(current: FoodPreferencesDraft) -> Bool { revision.baseline != current }
}
