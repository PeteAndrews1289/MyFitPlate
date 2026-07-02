import Foundation

public enum FoodSearchRanking {
    public static func trustedLocalMatches(
        query: String,
        savedFoods: [FoodItem],
        recentFoods: [FoodItem],
        limit: Int = 6
    ) -> [FoodItem] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }

        var ranked: [RankedFood] = []
        var seenIDs = Set<String>()

        for (index, food) in savedFoods.enumerated() {
            guard seenIDs.insert(food.id).inserted else { continue }
            if let score = score(food, query: normalizedQuery, tokens: tokens(normalizedQuery), isSaved: true) {
                ranked.append(RankedFood(food: food, score: score, originalIndex: index))
            }
        }

        let recentOffset = savedFoods.count
        for (index, food) in recentFoods.enumerated() {
            guard seenIDs.insert(food.id).inserted else { continue }
            if let score = score(food, query: normalizedQuery, tokens: tokens(normalizedQuery), isSaved: false) {
                ranked.append(RankedFood(food: food, score: score, originalIndex: recentOffset + index))
            }
        }

        return ranked
            .sorted {
                if $0.score == $1.score {
                    return $0.originalIndex < $1.originalIndex
                }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map(\.food)
    }

    private static func score(
        _ food: FoodItem,
        query: String,
        tokens queryTokens: [String],
        isSaved: Bool
    ) -> Int? {
        let name = normalized(food.name)
        guard !name.isEmpty else { return nil }

        var score = 0
        if name == query {
            score += 1_000
        } else if name.hasPrefix(query) {
            score += 760
        } else if name.contains(query) {
            score += 620
        } else if queryTokens.allSatisfy({ name.contains($0) }) {
            score += 500
        } else if barcodeMatches(food, query: query) {
            score += 700
        } else {
            return nil
        }

        if isSaved {
            score += 140
        }

        switch food.sourceMetadata?.reviewStatus {
        case .userEdited:
            score += 90
        case .userConfirmed:
            score += 60
        case .notRequired, .unreviewed, nil:
            break
        }

        if food.sourceMetadata?.sourceType == .custom || food.sourceMetadata?.sourceType == .manual {
            score += 40
        }

        return score
    }

    private static func barcodeMatches(_ food: FoodItem, query: String) -> Bool {
        guard query.allSatisfy(\.isNumber),
              let barcode = food.sourceMetadata?.barcode else {
            return false
        }

        return BarcodeCorrectionRules.normalizedBarcode(barcode).contains(query)
    }

    private static func tokens(_ normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : " "
            }
            .reduce(into: "") { partialResult, character in
                if character == " ", partialResult.last == " " {
                    return
                }
                partialResult.append(character)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct RankedFood {
        let food: FoodItem
        let score: Int
        let originalIndex: Int
    }

    // MARK: - Search-source merging + quick-log hydration

    /// Combines branded FatSecret results with USDA whole-food results. FatSecret leads
    /// (brands, portion-friendly servings); USDA appends entries whose names FatSecret
    /// doesn't already cover — they carry the full micronutrient spectrum that FatSecret's
    /// preview strings never have.
    public static func mergedSearchResults(
        fatSecret: [FoodItem],
        usda: [FoodItem],
        usdaLimit: Int = 8
    ) -> [FoodItem] {
        let existingNames = Set(fatSecret.map { normalized($0.name) })
        let distinctUSDA = usda
            .filter { !existingNames.contains(normalized($0.name)) }
            .prefix(usdaLimit)
        return fatSecret + distinctUSDA
    }

    /// Builds the item a quick-log should record once food details have been fetched.
    /// Prefers the serving that matches what the search row previewed (so logged calories
    /// match what the user saw); falls back to the details' base serving.
    public static func hydratedQuickLogItem(
        preview: FoodItem,
        detailBase: FoodItem,
        availableServings: [ServingSizeOption]
    ) -> FoodItem {
        let previewServing = normalized(preview.servingSize)
        guard !previewServing.isEmpty,
              let match = availableServings.first(where: { normalized($0.description) == previewServing }) else {
            return detailBase
        }

        let adjusted = ServingNutritionCalculator.adjustedNutrition(base: match, quantityValue: 1)
        return FoodItem(
            id: detailBase.id,
            name: detailBase.name,
            calories: adjusted.calories,
            protein: adjusted.protein,
            carbs: adjusted.carbs,
            fats: adjusted.fats,
            saturatedFat: adjusted.saturatedFat,
            polyunsaturatedFat: adjusted.polyunsaturatedFat,
            monounsaturatedFat: adjusted.monounsaturatedFat,
            fiber: adjusted.fiber,
            servingSize: adjusted.servingDescription,
            servingWeight: adjusted.servingWeightGrams,
            timestamp: nil,
            sourceMetadata: detailBase.sourceMetadata,
            calcium: adjusted.calcium,
            iron: adjusted.iron,
            potassium: adjusted.potassium,
            sodium: adjusted.sodium,
            vitaminA: adjusted.vitaminA,
            vitaminC: adjusted.vitaminC,
            vitaminD: adjusted.vitaminD,
            vitaminB12: adjusted.vitaminB12,
            folate: adjusted.folate,
            magnesium: adjusted.magnesium,
            phosphorus: adjusted.phosphorus,
            zinc: adjusted.zinc,
            copper: adjusted.copper,
            manganese: adjusted.manganese,
            selenium: adjusted.selenium,
            vitaminB1: adjusted.vitaminB1,
            vitaminB2: adjusted.vitaminB2,
            vitaminB3: adjusted.vitaminB3,
            vitaminB5: adjusted.vitaminB5,
            vitaminB6: adjusted.vitaminB6,
            vitaminE: adjusted.vitaminE,
            vitaminK: adjusted.vitaminK,
            quantityValue: adjusted.quantityValue,
            servingUnit: adjusted.servingUnit
        )
    }

    /// Whether a search result still needs a details fetch before it carries real nutrition:
    /// FatSecret previews (numeric ids) with no micronutrient data.
    public static func needsNutritionHydration(_ food: FoodItem) -> Bool {
        let hasAnyMicro = food.calcium != nil || food.sodium != nil
            || food.potassium != nil || food.iron != nil
        let isFatSecretID = !food.id.isEmpty && food.id.allSatisfy(\.isNumber)
        return isFatSecretID && !hasAnyMicro
    }
}
