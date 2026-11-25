import Foundation

/// Account preferences for proposal selection. Personal ingredient reviews do not
/// certify labels, preparation, allergens or cross-contact.
public struct MealConstraintProfile: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var revisionID: String
    public var diet: PlanningDiet
    public var hardExclusions: [String]
    public init(schemaVersion: Int = 1, revisionID: String = UUID().uuidString,
                diet: PlanningDiet = .unrestricted, hardExclusions: [String] = []) {
        self.schemaVersion = schemaVersion; self.revisionID = revisionID
        self.diet = diet; self.hardExclusions = hardExclusions
    }
    public var hasRestrictions: Bool { schemaVersion != 1 || diet != .unrestricted || !hardExclusions.isEmpty }
    public func validate() throws {
        guard schemaVersion == 1, !revisionID.isEmpty, revisionID.count <= 160,
              hardExclusions.count <= 30,
              hardExclusions.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 100 && !MealConstraintRules.normalized($0).isEmpty }) else { throw MealConstraintError.invalidProfile }
    }
    public var fingerprint: String { (try? PlanFingerprint.make(self)) ?? "invalid-profile" }
    public var fields: [String: Any] {
        ["schemaVersion": schemaVersion, "revisionID": revisionID, "diet": diet.rawValue, "hardExclusions": hardExclusions]
    }
    public static func decodeField(_ value: Any?) throws -> MealConstraintProfile? {
        guard let value, !(value is NSNull) else { return nil }
        guard let map = value as? [String: Any], JSONSerialization.isValidJSONObject(map) else { throw MealConstraintError.invalidProfile }
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: map))
    }
    public var prompt: String {
        guard hasRestrictions else { return "No hard ingredient exclusions are saved. Food likes are soft preferences." }
        return """
        Hard ingredient constraints (override soft preferences and pantry suggestions):
        - Ingredient pattern: \(diet.title).
        - Excluded ingredient names (data): \(String(data: (try? JSONEncoder().encode(hardExclusions)) ?? Data(), encoding: .utf8) ?? "[]").
        Include quantities and specific ingredients, including sauces and toppings. Do not include excluded ingredients as optional alternatives. Never claim allergen or cross-contact safety. Unknown composition needs personal review. Return no safety certifications or user-review claims.
        """
    }
    /// A one-week brief may tighten a saved profile, never silently relax it.
    public func adding(diet additionalDiet: PlanningDiet, exclusions: [String]) -> MealConstraintProfile {
        var result = self
        let order: [PlanningDiet] = [.unrestricted, .pescatarian, .vegetarian, .vegan]
        result.diet = order[max(order.firstIndex(of: diet) ?? 0, order.firstIndex(of: additionalDiet) ?? 0)]
        var seen = Set<String>()
        result.hardExclusions = (hardExclusions + exclusions).filter { seen.insert(MealConstraintRules.normalized($0)).inserted }
        return result
    }
}

public enum MealConstraintError: Error, LocalizedError {
    case invalidProfile, reviewRequired, blocked
    public var errorDescription: String? {
        switch self {
        case .invalidProfile: "Your saved ingredient constraints need review in Food preferences. Existing meals and logs are kept."
        case .reviewRequired: "Review this meal's exact ingredients against your current food constraints before saving."
        case .blocked: "This idea conflicts with your ingredient constraints. Choose another idea or edit the ingredients."
        }
    }
}

public struct MealConstraintCandidate: Codable, Equatable, Sendable {
    public let name: String
    public let ingredients: [String]
    public let instructions: String
    public let food: FoodItem?
    public init(name: String, ingredients: [String], instructions: String, food: FoodItem?) {
        self.name = name; self.ingredients = ingredients; self.instructions = instructions
        self.food = food.map(RecipePortionRules.revisionIngredient)
    }
    public var fingerprint: String { (try? PlanFingerprint.make(self)) ?? "invalid-candidate" }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.fingerprint == rhs.fingerprint }
}

public struct MealIngredientReview: Codable, Equatable, Sendable {
    public let candidateFingerprint: String
    public let profileFingerprint: String
    public let reviewedAt: Date
    public let rulesetVersion: String
    public init(candidate: MealConstraintCandidate, profile: MealConstraintProfile, reviewedAt: Date = Date()) {
        candidateFingerprint = candidate.fingerprint; profileFingerprint = profile.fingerprint
        self.reviewedAt = reviewedAt; rulesetVersion = MealConstraintRules.rulesetVersion
    }
}

public struct MealConstraintIssue: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case invalidProfile, excludedIngredient, missingIngredients, personalReview, invalidNutrition }
    public let id: String
    public let kind: Kind
    public let message: String
}

public struct MealConstraintAssessment: Codable, Equatable, Sendable {
    public let rulesetVersion: String
    public let profileFingerprint: String
    public let candidateFingerprint: String
    public let issues: [MealConstraintIssue]
    public var canAccept: Bool { issues.isEmpty }
    public var needsPersonalReview: Bool { !issues.isEmpty && issues.allSatisfy { $0.kind == .personalReview } }
    public var isBlocked: Bool { issues.contains { $0.kind != .personalReview } }
}

public enum MealConstraintRules {
    public static let rulesetVersion = "ingredient-constraints-v1"
    public static func normalized(_ text: String) -> String {
        let hidden = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")
        let visible = String(text.unicodeScalars.filter { !hidden.contains($0) })
        return visible.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func report(candidate: MealConstraintCandidate, profile: MealConstraintProfile?,
                              personalReview: MealIngredientReview? = nil,
                              recipeReview: RecipePlanningProfile? = nil) -> MealConstraintAssessment {
        let profile = profile ?? MealConstraintProfile(revisionID: "no-saved-constraints")
        var issues: [MealConstraintIssue] = []
        func issue(_ key: String, _ kind: MealConstraintIssue.Kind, _ message: String) {
            issues.append(.init(id: key, kind: kind, message: message))
        }
        do { try profile.validate() } catch { issue("profile", .invalidProfile, error.localizedDescription) }
        if candidate.food == nil || candidate.fingerprint == "invalid-candidate" {
            issue("nutrition-missing", .invalidNutrition, "Review this meal's nutrition and portion before saving.")
        }
        if let food = candidate.food,
           food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           ![food.calories, food.protein, food.carbs, food.fats].allSatisfy({ $0.isFinite && $0 >= 0 }) {
            issue("nutrition", .invalidNutrition, "Review this meal's nutrition and portion before saving.")
        }
        if profile.hasRestrictions {
            if candidate.ingredients.isEmpty || candidate.ingredients.allSatisfy({ normalized($0).isEmpty }) {
                issue("ingredients", .missingIngredients, "Ingredient details are missing for \(candidate.name). Add specific ingredients before reviewing this idea.")
            }
            let linked = candidate.food?.recipePortionSnapshot?.sourceIngredientFoods?.map(\.name) ?? []
            let texts = [candidate.name] + candidate.ingredients + linked + [candidate.instructions]
            for exclusion in profile.hardExclusions where contains(texts, exclusion: exclusion) {
                issue("excluded-" + normalized(exclusion), .excludedIngredient, "\(candidate.name) mentions \(exclusion) or a related ingredient you excluded.")
            }
            for group in prohibitedGroups(for: profile.diet) where contains(texts, exclusion: group) {
                issue("diet-" + group, .excludedIngredient, "\(candidate.name) includes an ingredient outside your \(profile.diet.title.lowercased()) pattern.")
            }
            let exactReview = personalReview.map {
                $0.candidateFingerprint == candidate.fingerprint && $0.profileFingerprint == profile.fingerprint && $0.rulesetVersion == rulesetVersion
            } ?? false
            let recipeReviewed = recipeReview.map { review in
                review.reviewedAt != nil && profile.diet.permits(review.diet) && profile.hardExclusions.allSatisfy { exclusion in
                    review.reviewedExclusions.contains { normalized($0) == normalized(exclusion) }
                }
            } ?? false
            if issues.isEmpty && !exactReview && !recipeReviewed {
                issue("review", .personalReview, "Personally review ingredients, sauces and product labels for your saved constraints. A generated description cannot verify them.")
            }
        }
        return .init(rulesetVersion: rulesetVersion, profileFingerprint: profile.fingerprint,
            candidateFingerprint: candidate.fingerprint, issues: issues)
    }
    public static func contains(_ texts: [String], exclusion: String) -> Bool {
        let key = normalized(exclusion)
        let words = aliases[key] ?? [key]
        return texts.contains { value in
            let text = " " + normalized(value) + " "
            return words.contains { word in
                for form in [word, word + "s"] {
                    var remaining = text[...]
                    while let range = remaining.range(of: " " + form + " ") {
                        let before = String(remaining[..<range.lowerBound])
                        let after = String(remaining[range.upperBound...])
                        let alternative = ["milk", "butter", "cheese", "cream", "yogurt"].contains(word)
                            && ["coconut", "almond", "oat", "cashew", "soy", "rice", "plant", "vegan"].contains(where: { before.hasSuffix(" " + $0) })
                        if !after.hasPrefix("free ") && !alternative { return true }
                        remaining = remaining[range.upperBound...]
                    }
                }
                return false
            }
        }
    }
    private static func prohibitedGroups(for diet: PlanningDiet) -> [String] {
        switch diet {
        case .unrestricted: []
        case .pescatarian: ["meat"]
        case .vegetarian: ["meat", "fish", "shellfish"]
        case .vegan: ["meat", "fish", "shellfish", "dairy", "egg", "honey"]
        }
    }
    // Deliberately bounded ingredient vocabulary, never a claim of exhaustive allergen detection.
    private static let aliases: [String: [String]] = [
        "peanut": ["peanut", "groundnut", "arachis", "cacahuete", "cacahuate", "cacahuete", "mani", "arachide", "erdnuss"], "peanuts": ["peanut", "groundnut", "arachis", "cacahuete", "cacahuate", "cacahuete", "mani", "arachide", "erdnuss"],
        "tree nuts": ["almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia", "brazil nut"],
        "dairy": ["milk", "butter", "cheese", "cream", "yogurt", "yoghurt", "whey", "casein", "ghee", "lait", "leche", "milch", "fromage", "queso"],
        "milk": ["milk", "whey", "casein", "lait", "leche", "milch"], "egg": ["egg", "albumen", "mayonnaise", "huevo", "oeuf", "œuf"], "eggs": ["egg", "albumen", "mayonnaise", "huevo", "oeuf", "œuf"],
        "soy": ["soy", "soya", "tofu", "tempeh", "edamame", "miso", "tamari", "soja"],
        "wheat": ["wheat", "semolina", "bulgur", "couscous", "farro", "spelt", "trigo", "ble", "weizen"],
        "gluten": ["wheat", "barley", "rye", "semolina", "bulgur", "couscous", "farro", "spelt", "seitan"],
        "sesame": ["sesame", "tahini", "sesamo"],
        "fish": ["fish", "salmon", "tuna", "cod", "anchovy", "anchovies", "sardine", "trout", "mackerel", "bonito", "pescado", "poisson", "fisch", "pesce"],
        "shellfish": ["shrimp", "prawn", "crab", "lobster", "clam", "mussel", "oyster", "scallop", "crayfish", "crevette", "camaron", "gamba"],
        "meat": ["beef", "chicken", "pork", "bacon", "ham", "lamb", "turkey", "duck", "gelatin", "lard", "veal", "venison"]
    ]
}

public extension MealSuggestion {
    var constraintCandidate: MealConstraintCandidate {
        .init(name: mealName, ingredients: ingredients, instructions: instructions,
            food: FoodItem(id: id.uuidString, name: mealName, calories: calories, protein: protein, carbs: carbs, fats: fats))
    }
}

public extension PlannedMeal {
    var constraintCandidate: MealConstraintCandidate {
        .init(name: foodItem?.name ?? mealType, ingredients: ingredients ?? foodItem?.recipePortionSnapshot?.ingredients ?? [],
            instructions: instructions ?? foodItem?.recipePortionSnapshot?.sourceInstructions?.joined(separator: "\n") ?? "", food: plannedFood)
    }
}
