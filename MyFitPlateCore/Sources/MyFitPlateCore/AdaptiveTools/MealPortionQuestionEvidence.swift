import Foundation

/// A resolved source serving, never a visual size guessed by the photo model.
public struct MealPortionAnchor: Codable, Hashable, Sendable {
    public enum Unit: String, Codable, Hashable, Sendable { case package, cup, tablespoon, teaspoon, piece }
    public let unit: Unit
    public let gramsPerUnit: Double
    public let sourceID: String
    public let sourceName: String
    public init(unit: Unit, gramsPerUnit: Double, sourceID: String, sourceName: String) {
        self.unit = unit; self.gramsPerUnit = gramsPerUnit; self.sourceID = sourceID; self.sourceName = sourceName
    }
    public var isValid: Bool {
        gramsPerUnit.isFinite && gramsPerUnit >= 0.1 && gramsPerUnit <= 10_000 &&
            !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sourceName.isEmpty
    }
    public func answerCounts(lowGrams: Double, highGrams: Double) -> [Double] {
        guard isValid else { return [] }
        let choices: [Double] = unit == .package ? [0.25, 0.5, 1] : [0.5, 1, 1.5, 2, 3]
        return choices.filter { gramsPerUnit * $0 >= lowGrams && gramsPerUnit * $0 <= highGrams }
    }
    public func label(count: Double) -> String {
        let amount: String
        switch count {
        case 0.25: amount = "¼"
        case 0.5: amount = "½"
        case 1.5: amount = "1½"
        default: amount = String(format: "%g", count)
        }
        return "\(amount) \(unit.rawValue)\(count > 1 ? "s" : "")"
    }
}

public enum MealPortionAnchorRules {
    /// Only exact, one-unit provider serving descriptions are accepted. No volume-to-mass guess.
    public static func referenceAnchors(for item: FoodItem) -> [MealPortionAnchor] {
        guard let metadata = item.sourceMetadata, metadata.effectiveEvidenceLineage != .modelEstimate,
              metadata.effectiveEvidenceLineage != .unknown, item.servingWeight.isFinite,
              item.servingWeight >= 0.1, item.servingWeight <= 10_000 else { return [] }
        let text = item.servingSize.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let names: [(MealPortionAnchor.Unit, [String])] = [(.package, ["package", "packet", "pack"]),
            (.cup, ["cup"]), (.tablespoon, ["tablespoon", "tbsp"]), (.teaspoon, ["teaspoon", "tsp"]), (.piece, ["piece"])]
        for (unit, aliases) in names where aliases.contains(where: { alias in
            text == "1 \(alias)" || text.range(of: "^1 " + alias + " \\([0-9.]+ ?g\\)$", options: .regularExpression) != nil
        }) {
            if let opening = text.firstIndex(of: "(") {
                let stated = text[text.index(after: opening)...].replacingOccurrences(of: "g)", with: "").trimmingCharacters(in: .whitespaces)
                guard let grams = Double(stated), abs(grams - item.servingWeight) <= 0.1 else { return [] }
            }
            let anchor = MealPortionAnchor(unit: unit, gramsPerUnit: item.servingWeight,
                sourceID: metadata.sourceID ?? item.id, sourceName: metadata.sourceName ?? "Resolved serving")
            return anchor.isValid ? [anchor] : []
        }
        return []
    }
}

public enum MealQuestionUncertainty: String, Codable, Hashable, Sendable {
    case portion, separateCookingAddition, unresolvedPreparation
}

public enum MealQuestionUncertaintyRules {
    public static func kind(for item: FoodItem, hasUnresolvedPreparation: Bool) -> MealQuestionUncertainty {
        let anchors = item.sourceMetadata?.portionAnchors ?? []
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let separateOils: Set<String> = ["oil", "cooking oil", "olive oil", "extra virgin olive oil", "canola oil",
            "vegetable oil", "avocado oil", "sesame oil", "sunflower oil"]
        if anchors.contains(where: \.isValid), separateOils.contains(name) { return .separateCookingAddition }
        if anchors.isEmpty, hasUnresolvedPreparation { return .unresolvedPreparation }
        return .portion
    }
}

public enum MealQuestionAnswer: Codable, Hashable, Sendable {
    case anchor(index: Int, count: Double)
    case measuredGrams(Double)
    case skip
}

/// The full before/after payloads are encoded to avoid recursive FoodItem metadata values.
/// They preserve micronutrients and source evidence, not just the four displayed macros.
public struct MealQuestionReceipt: Codable, Hashable, Sendable {
    public let rulesetVersion: String
    public let question: UsefulMealQuestion
    public let answer: MealQuestionAnswer
    public let originalFoodData: Data
    public let revisedFoodData: Data
    public let recordedAt: Date
    public var originalFood: FoodItem? { try? JSONDecoder().decode(FoodItem.self, from: originalFoodData) }
    public var revisedFood: FoodItem? { try? JSONDecoder().decode(FoodItem.self, from: revisedFoodData) }
    public var summary: String {
        guard answer != .skip, let revisedFood else { return "Kept the photo estimate. You can still edit it below." }
        return "Portion updated to about \(Int(revisedFood.servingWeight.rounded())) g. Other nutrition uncertainty remains."
    }
}

public struct MealPortionQuestionState: Codable, Hashable, Sendable {
    public let question: UsefulMealQuestion
    public var receipt: MealQuestionReceipt?
    public init(question: UsefulMealQuestion) { self.question = question }
}

public struct MealQuestionPreview: Sendable {
    public let food: FoodItem
    public let receipt: MealQuestionReceipt
}
