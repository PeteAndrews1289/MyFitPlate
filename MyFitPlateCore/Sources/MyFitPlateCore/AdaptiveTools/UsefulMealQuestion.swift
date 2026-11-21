import Foundation

public struct MealPortionEvidence: Equatable, Sendable {
    public let itemID: String
    public let lowGrams: Double
    public let highGrams: Double
    public let anchors: [MealPortionAnchor]
    public let uncertainty: MealQuestionUncertainty
    public let canUseMeasuredGrams: Bool
    public init(itemID: String, lowGrams: Double, highGrams: Double, anchors: [MealPortionAnchor] = [],
                uncertainty: MealQuestionUncertainty = .portion, canUseMeasuredGrams: Bool = true) {
        self.itemID = itemID
        self.lowGrams = lowGrams
        self.highGrams = highGrams
        self.anchors = anchors; self.uncertainty = uncertainty; self.canUseMeasuredGrams = canUseMeasuredGrams
    }
}

public struct UsefulMealQuestion: Codable, Hashable, Sendable {
    public let itemID: String
    public let name: String
    public let lowGrams: Double
    public let estimatedGrams: Double
    public let highGrams: Double
    public let lowCalories: Double
    public let highCalories: Double
    public let reason: String
    public let itemFingerprint: String
    public let anchors: [MealPortionAnchor]
    public let uncertainty: MealQuestionUncertainty
    public let canUseMeasuredGrams: Bool
    public let rulesetVersion: String
}

public enum UsefulMealQuestionRules {
    public static let version = "answerable-portion-v2"
    /// A range is a scenario supplied by the photo estimate, never a confidence interval.
    /// Ask about the single portion with the greatest decision-relevant energy uncertainty.
    public static func choose(
        items: [FoodItem], evidence: [MealPortionEvidence], loggedCalories: Double?, calorieGuide: Double?
    ) -> UsefulMealQuestion? {
        let total = items.reduce(0) { $0 + max($1.calories, 0) }
        guard total.isFinite else { return nil }
        return evidence.compactMap { range -> UsefulMealQuestion? in
            guard range.uncertainty != .unresolvedPreparation,
                  range.canUseMeasuredGrams || range.anchors.contains(where: { !$0.answerCounts(lowGrams: range.lowGrams, highGrams: range.highGrams).isEmpty }),
                  let item = items.first(where: { $0.id == range.itemID }), item.servingWeight.isFinite,
                  item.servingWeight >= 0.1, item.servingWeight <= 100_000, item.calories.isFinite, item.calories > 0, item.calories <= 100_000,
                  range.lowGrams.isFinite, range.highGrams.isFinite, range.lowGrams > 0, range.highGrams <= 100_000,
                  range.lowGrams <= item.servingWeight, range.highGrams >= item.servingWeight,
                  range.highGrams > range.lowGrams, range.highGrams / range.lowGrams <= 6 else { return nil }
            let low = item.calories * range.lowGrams / item.servingWeight
            let high = item.calories * range.highGrams / item.servingWeight
            let spread = high - low
            var crossesGuide = false
            if let loggedCalories, let calorieGuide, loggedCalories.isFinite, loggedCalories >= 0,
               calorieGuide.isFinite, calorieGuide > 0 {
                let remainder = loggedCalories + total - item.calories
                crossesGuide = remainder + low < calorieGuide && remainder + high >= calorieGuide
            }
            // Small uncertainty stays quiet, including tiny ranges that straddle a target.
            guard spread >= 100, crossesGuide || spread >= max(150, total * 0.25),
                  let fingerprint = try? PlanFingerprint.make(item) else { return nil }
            return UsefulMealQuestion(itemID: item.id, name: item.name, lowGrams: range.lowGrams,
                                      estimatedGrams: item.servingWeight, highGrams: range.highGrams,
                                      lowCalories: low, highCalories: high,
                                      reason: crossesGuide
                                      ? "This portion could change how this meal sits against today's energy guide. The guide is flexible."
                                      : "This portion accounts for a large share of the uncertainty in this meal.",
                                      itemFingerprint: fingerprint, anchors: range.anchors.filter(\.isValid),
                                      uncertainty: range.uncertainty, canUseMeasuredGrams: range.canUseMeasuredGrams, rulesetVersion: version)
        }.max { ($0.highCalories - $0.lowCalories) < ($1.highCalories - $1.lowCalories) }
    }

    public static func applying(grams: Double, to item: FoodItem) -> FoodItem? {
        guard grams.isFinite, grams > 0, grams <= 100_000, item.servingWeight.isFinite, item.servingWeight >= 0.1,
              (0.05...20).contains(grams / item.servingWeight),
              [item.calories, item.protein, item.carbs, item.fats].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        var updated = item.scalingNutritionAndServing(by: grams / item.servingWeight)
        updated.servingWeight = grams
        updated.servingSize = "\(Int(grams.rounded())) g"
        updated.quantityValue = grams
        updated.servingUnit = "g"
        guard [updated.calories, updated.protein, updated.carbs, updated.fats].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100_000 }),
              MicronutrientKey.allCases.allSatisfy({ key in updated.micronutrientValue(for: key).map { $0.isFinite && $0 >= 0 } ?? true }) else { return nil }
        return updated
    }

    public static func preview(answer: MealQuestionAnswer, question: UsefulMealQuestion, item: FoodItem,
                               now: Date = Date()) -> MealQuestionPreview? {
        guard question.rulesetVersion == version, question.itemID == item.id,
              (try? PlanFingerprint.make(item)) == question.itemFingerprint,
              question.uncertainty != .unresolvedPreparation else { return nil }
        let changed: FoodItem
        switch answer {
        case .skip: changed = item
        case let .anchor(index, count):
            guard question.anchors.indices.contains(index), question.anchors[index].isValid,
                  question.anchors[index].answerCounts(lowGrams: question.lowGrams, highGrams: question.highGrams).contains(count),
                  let scaled = applying(grams: question.anchors[index].gramsPerUnit * count, to: item) else { return nil }
            changed = scaled.markedUserEdited(sourceType: .aiImage, originalItem: item)
        case let .measuredGrams(grams):
            guard question.canUseMeasuredGrams, let scaled = applying(grams: grams, to: item) else { return nil }
            changed = scaled.markedUserEdited(sourceType: .aiImage, originalItem: item)
        }
        guard let originalData = try? JSONEncoder().encode(item), let revisedData = answer == .skip ? originalData : try? JSONEncoder().encode(changed),
              originalData.count <= 128_000, revisedData.count <= 128_000 else { return nil }
        let receipt = MealQuestionReceipt(rulesetVersion: version, question: question, answer: answer,
            originalFoodData: originalData, revisedFoodData: revisedData, recordedAt: Date(timeIntervalSince1970: floor(now.timeIntervalSince1970)))
        var result = changed
        result.portionQuestionReceipt = receipt
        return MealQuestionPreview(food: result, receipt: receipt)
    }

}
