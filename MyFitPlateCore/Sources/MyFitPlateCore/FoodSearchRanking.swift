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
}
