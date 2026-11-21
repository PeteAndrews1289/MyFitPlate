import Foundation

extension FoodItem {
    /// Show a reason to open the portion editor only when the serving or nutrition needs attention.
    public func loggingPortionNotice(source: String? = nil) -> String? {
        if servingSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Choose a serving" }
        if let finding = FoodDataSanity.findings(for: self).first(where: { $0.severity == .warning }) {
            return finding.message
        }
        let metadata = sourceMetadata
        let descriptor = FoodSourceClassifier.descriptor(for: source ?? "", foodID: id, metadata: metadata)
        if descriptor.isEstimated || metadata?.confidence == .estimated,
           metadata?.reviewStatus != .userConfirmed, metadata?.reviewStatus != .userEdited {
            return "Confirm estimated portion"
        }
        return nil
    }
}

public enum FoodSearchRanking {
    /// A trailing labeled size limits the matching variants. A leading amount still
    /// describes what the person ate and is handled by productTokens.
    private struct SizedQuery {
        static let measure = try? NSRegularExpression(
            pattern: #"(?i)(?<![\w.,/\-])(\d+(?:\.\d+)?)\s*(fl\.?\s*oz|ounces?|oz|grams?|g|millilit(?:er|re)s?|ml)\b"#)
        let product: String
        let quantity: Double
        let unit: String

        init?(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed as NSString
            guard let measure = Self.measure, let match = measure.matches(in: trimmed, range: NSRange(location: 0, length: value.length)).last,
                  NSMaxRange(match.range) == value.length,
                  let amount = Double(value.substring(with: match.range(at: 1))), amount > 0 else { return nil }
            let product = value.substring(to: match.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            guard product.contains(where: \.isLetter) else { return nil }
            self.product = product
            quantity = amount
            unit = Self.unit(value.substring(with: match.range(at: 2)))
        }

        private static func unit(_ raw: String) -> String {
            let unit = raw.lowercased()
            if unit.hasPrefix("fl") { return "fl oz" }
            if unit.hasPrefix("g") { return "g" }
            if unit.hasPrefix("m") { return "ml" }
            return "oz"
        }

        func matches(_ food: FoodItem) -> Bool {
            let label = [food.name, food.sourceMetadata?.labeledServing ?? food.servingSize].joined(separator: " ")
            let text = label as NSString
            guard let measure = Self.measure else { return false }
            return measure.matches(in: label, range: NSRange(location: 0, length: text.length)).contains {
                Double(text.substring(with: $0.range(at: 1))) == quantity && Self.unit(text.substring(with: $0.range(at: 2))) == unit
            }
        }
    }

    public static func catalogQuery(_ query: String) -> String {
        SizedQuery(query)?.product ?? query
    }

    /// Meal-specific history first, then saved and recent foods. Keep distinct portions and
    /// providers separate, but collapse the same food copied to the diary under a new entry ID.
    public static func repeatSuggestions(recommended: [FoodItem], saved: [FoodItem], recent: [FoodItem]) -> [FoodItem] {
        var seen = Set<String>()
        return (recommended + saved + recent).filter { food in
            let metadata = food.sourceMetadata
            let key = [normalized(food.name), normalized(food.servingSize), String(food.servingWeight),
                       String(food.calories), String(food.protein), String(food.carbs), String(food.fats),
                       metadata?.sourceType.rawValue ?? "", metadata?.sourceID ?? "", metadata?.barcode ?? ""]
                .joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    /// Later providers may improve metadata, but should not reshuffle rows under a finger.
    public static func preservingVisibleOrder(previous: [FoodItem], updated: [FoodItem]) -> [FoodItem] {
        let previousIDs = Set(previous.map(\.id))
        let updatedByID = Dictionary(updated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return previous.compactMap { updatedByID[$0.id] }
            + updated.filter { !previousIDs.contains($0.id) }
    }

    public static func trustedLocalMatches(
        query: String,
        savedFoods: [FoodItem],
        recentFoods: [FoodItem],
        limit: Int = 6
    ) -> [FoodItem] {
        let size = SizedQuery(query)
        let normalizedQuery = normalized(size?.product ?? query)
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }
        let queryTokens = productTokens(normalizedQuery)

        var ranked: [RankedFood] = []
        var seenIDs = Set<String>()

        for (index, food) in savedFoods.enumerated() {
            guard size?.matches(food) != false, seenIDs.insert(food.id).inserted else { continue }
            if let score = score(food, query: normalizedQuery, tokens: queryTokens, isSaved: true) {
                ranked.append(RankedFood(food: food, score: score, originalIndex: index))
            }
        }

        let recentOffset = savedFoods.count
        for (index, food) in recentFoods.enumerated() {
            guard size?.matches(food) != false, seenIDs.insert(food.id).inserted else { continue }
            if let score = score(food, query: normalizedQuery, tokens: queryTokens, isSaved: false) {
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
        guard !name.isEmpty,
              remoteRelevance(food, query: query, queryTokens: queryTokens) > 0 else { return nil }

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
            // The typed final prefix, plural, or separately supplied brand matched above.
            score += 450
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

        if food.sourceMetadata?.sourceType == .custom ||
            food.sourceMetadata?.sourceType == .manual ||
            food.sourceMetadata?.sourceType == .chainBuilder {
            score += 40
        }

        let descriptor = FoodSourceClassifier.descriptor(
            for: "search",
            foodID: food.id,
            metadata: food.sourceMetadata
        )
        let trust = FoodTrustEvaluation.evaluate(
            item: food,
            descriptor: descriptor,
            metadata: food.sourceMetadata
        )
        score += trust.score / 5
        if trust.requiresCorrection {
            score -= 180
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

    /// A leading measure describes the user's portion, not the name on the package.
    private static func productTokens(_ query: String) -> [String] {
        let words = tokens(query)
        guard words.first?.allSatisfy(\.isNumber) == true,
              let unitIndex = words.firstIndex(where: { !$0.allSatisfy(\.isNumber) }),
              unitIndex + 1 < words.count else { return words }
        let units: Set<String> = ["g", "gram", "grams", "kg", "oz", "ounce", "ounces", "lb", "lbs",
                                  "ml", "l", "cup", "cups", "tsp", "tbsp", "bar", "bars", "scoop", "scoops",
                                  "slice", "slices", "serving", "servings", "container", "containers"]
        guard units.contains(words[unitIndex]) else { return words }
        let remaining = words[(unitIndex + 1)...].drop(while: { $0 == "of" })
        return remaining.isEmpty ? words : Array(remaining)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0 != "'" && $0 != "’" }
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

    /// Only an actual provider brand can receive product priority. These placeholder values
    /// describe missing branding, rather than a manufacturer named "Generic".
    public static func reportedBrandName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = normalized(trimmed)
        let placeholders: Set<String> = ["", "generic", "unbranded", "no brand", "none", "unknown", "n a", "na", "not specified"]
        return placeholders.contains(name) ? nil : trimmed
    }

    /// Search rows must expose the identity being ranked, including products whose providers
    /// return the brand separately from an otherwise generic-looking description.
    public static func productDisplayName(_ name: String, brandName: String?) -> String {
        guard let brand = reportedBrandName(brandName) else { return name }
        let paddedName = " \(normalized(name)) "
        return paddedName.contains(" \(normalized(brand)) ") ? name : "\(brand) \(name)"
    }

    public static func rankedRemoteMatches(query: String, foods: [FoodItem]) -> [FoodItem] {
        let size = SizedQuery(query)
        let normalizedQuery = normalized(size?.product ?? query)
        guard !normalizedQuery.isEmpty else { return foods }
        let queryTokens = productTokens(normalizedQuery)
        return foods.filter { size?.matches($0) != false }.enumerated()
            .map { index, food in
                RemoteRankedFood(food: food, relevance: remoteRelevance(food, query: normalizedQuery, queryTokens: queryTokens),
                                 branded: reportedBrandName(food.sourceMetadata?.brandName) != nil,
                                 score: score(food, query: normalizedQuery, tokens: queryTokens, isSaved: false) ?? 0,
                                 extraWords: extraProductWords(food, query: normalizedQuery, tokens: queryTokens),
                                 originalIndex: index)
            }
            .sorted {
                if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
                if $0.relevance > 0, $0.branded != $1.branded { return $0.branded }
                if $0.extraWords != $1.extraWords { return $0.extraWords < $1.extraWords }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.originalIndex < $1.originalIndex
            }
            .map(\.food)
    }

    private static func extraProductWords(_ food: FoodItem, query: String, tokens queryTokens: [String]) -> Int {
        guard let brand = reportedBrandName(food.sourceMetadata?.brandName),
              (" " + query + " ").contains(" " + normalized(brand) + " ") else { return .max }
        let words = Set(tokens(normalized(food.name)))
        return words.filter { word in !queryTokens.contains { fullTokenMatch(word, $0) || word.hasPrefix($0) } }.count
    }

    private struct RemoteRankedFood {
        let food: FoodItem
        let relevance: Int
        let branded: Bool
        let score: Int
        let extraWords: Int
        let originalIndex: Int
    }

    private static func remoteRelevance(_ food: FoodItem, query: String, queryTokens: [String]) -> Int {
        if barcodeMatches(food, query: query) { return 4 }
        let nameTokens = tokens(normalized(food.name + " " + (reportedBrandName(food.sourceMetadata?.brandName) ?? "")))
        guard !conflictsWithRawIngredientIntent(food, query: query, queryTokens: queryTokens, nameTokens: nameTokens) else { return 0 }
        // Only one incomplete or misspelled word may survive, and exact product words win.
        var missing: String?
        for word in queryTokens where !nameTokens.contains(where: { fullTokenMatch($0, word) }) {
            guard missing == nil else { return 0 }
            missing = word
        }
        guard let missing else { return 3 }
        if missing == queryTokens.last, !missing.allSatisfy(\.isNumber), nameTokens.contains(where: { $0.hasPrefix(missing) }) { return 2 }
        guard missing.count >= (queryTokens.count == 1 ? 6 : 4), missing.allSatisfy(\.isLetter) else { return 0 }
        return nameTokens.contains { isSingleSpellingEdit(missing, $0) } ? 1 : 0
    }

    private static func isSingleSpellingEdit(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.first == rhs.first, abs(lhs.count - rhs.count) <= 1 else { return false }
        let shorter = Array(lhs.count <= rhs.count ? lhs : rhs)
        let longer = Array(lhs.count <= rhs.count ? rhs : lhs)
        var first = 0
        while first < shorter.count, shorter[first] == longer[first] { first += 1 }
        if shorter.count != longer.count {
            return shorter[first...].elementsEqual(longer[(first + 1)...])
        }
        guard first < shorter.count else { return true }
        if shorter[(first + 1)...].elementsEqual(longer[(first + 1)...]) { return true }
        return first + 1 < shorter.count && shorter[first] == longer[first + 1] && shorter[first + 1] == longer[first]
            && shorter[(first + 2)...].elementsEqual(longer[(first + 2)...])
    }

    /// "Raw strawberries" is not a request for raw strawberry juice or kombucha.
    /// Keep this narrow: explicit raw queries only, recognizable prepared forms only,
    /// and an explicitly requested form or full product brand remains eligible.
    private static func conflictsWithRawIngredientIntent(_ food: FoodItem, query: String,
                                                         queryTokens: [String], nameTokens: [String]) -> Bool {
        guard queryTokens.contains("raw") || queryTokens.contains("uncooked") else { return false }
        if let brand = reportedBrandName(food.sourceMetadata?.brandName) {
            let brand = normalized(brand)
            // A brand named "Raw" collides with the preparation qualifier; that alone
            // cannot establish that the user asked for this manufacturer's product.
            if brand != "raw", (" " + query + " ").contains(" " + brand + " ") { return false }
        }
        let preparedForms = ["juice", "kombucha", "smoothie", "drink", "beverage", "tea",
                             "jam", "jelly", "puree", "sauce", "syrup", "bar", "powder"]
        return preparedForms.contains { form in
            nameTokens.contains { fullTokenMatch($0, form) }
                && !queryTokens.contains { fullTokenMatch($0, form) }
        }
    }

    private static func fullTokenMatch(_ name: String, _ query: String) -> Bool {
        if name == "yoghurt" && query == "yogurt" || name == "yogurt" && query == "yoghurt" { return true }
        if query == "cooked", ["grilled", "roasted", "boiled", "baked", "steamed"].contains(name) { return true }
        if name == "uncooked" && query == "raw" || name == "raw" && query == "uncooked" { return true }
        if name == query || name == query + "s" || name == query + "es" || query == name + "s" || query == name + "es" { return true }
        return (query.hasSuffix("y") && name == String(query.dropLast()) + "ies") || (name.hasSuffix("y") && query == String(name.dropLast()) + "ies")
    }

    /// Loading providers enrich visible rows without moving them. On completion, publish the
    /// deterministic full-provider ranking so an early generic batch cannot pin itself first.
    public static func publishingRemoteMatches(query: String, previous: [FoodItem], updated: [FoodItem], providersComplete: Bool) -> [FoodItem] {
        let ranked = rankedRemoteMatches(query: query, foods: updated)
        return providersComplete ? ranked : preservingVisibleOrder(previous: previous, updated: ranked)
    }

    public struct SearchPresentation {
        public let exactPersonalMatches: [FoodItem]
        public let brandedMatches: [FoodItem]
        public let otherPersonalMatches: [FoodItem]
        public let otherRemoteMatches: [FoodItem]
    }

    /// Provider ranking must also govern the visible sections. A catalog-derived usual food
    /// does not become a preferred product simply because it was logged before. Explicitly
    /// authored/corrected exact personal matches retain their intentional priority.
    public static func searchPresentation(query: String, trustedMatches: [FoodItem], remoteMatches: [FoodItem],
                                          providersComplete: Bool) -> SearchPresentation {
        let size = SizedQuery(query)
        let query = normalized(size?.product ?? query), queryTokens = productTokens(query)
        let candidates = query.isEmpty ? remoteMatches : remoteMatches.filter {
            size?.matches($0) != false && remoteRelevance($0, query: query, queryTokens: queryTokens) > 0
        }
        guard providersComplete, !query.isEmpty else {
            return SearchPresentation(exactPersonalMatches: [], brandedMatches: [],
                                      otherPersonalMatches: trustedMatches, otherRemoteMatches: candidates)
        }
        let strongestRelevance = (trustedMatches + candidates).map {
            remoteRelevance($0, query: query, queryTokens: queryTokens)
        }.max() ?? 0
        let exact = trustedMatches.filter { isIntentionalExactPersonalMatch($0, query: query) }
        let exactIDs = Set(exact.map(\.id))
        let brands = candidates.filter {
            !exactIDs.contains($0.id) && reportedBrandName($0.sourceMetadata?.brandName) != nil
                && strongestRelevance > 0 && remoteRelevance($0, query: query, queryTokens: queryTokens) == strongestRelevance
        }
        guard !brands.isEmpty else {
            return SearchPresentation(exactPersonalMatches: [], brandedMatches: [],
                                      otherPersonalMatches: trustedMatches, otherRemoteMatches: candidates)
        }
        let promotedIDs = exactIDs.union(brands.map(\.id))
        return SearchPresentation(exactPersonalMatches: exact, brandedMatches: brands,
            otherPersonalMatches: trustedMatches.filter { !promotedIDs.contains($0.id) },
            otherRemoteMatches: candidates.filter { !promotedIDs.contains($0.id) })
    }

    private static func isIntentionalExactPersonalMatch(_ food: FoodItem, query: String) -> Bool {
        guard normalized(food.name) == query, let metadata = food.sourceMetadata else { return false }
        if metadata.reviewStatus == .userEdited { return true }
        switch metadata.sourceType {
        case .manual, .recipe: return true
        case .custom:
            return metadata.originSourceType.map { [.custom, .manual, .recipe].contains($0) } ?? true
        case .recent:
            return metadata.originSourceType.map { [.custom, .manual, .recipe].contains($0) } ?? false
        default: return false
        }
    }

    // MARK: - Search-source merging + quick-log hydration

    /// Combines branded FatSecret results with richer USDA, Health Canada, and Open Food Facts
    /// records. Brand identity is part of the merge key: a richer generic composition record must
    /// not replace a named product, nor can two manufacturers' homonyms collapse into one food.
    public static func mergedSearchResults(
        fatSecret: [FoodItem],
        usda: [FoodItem],
        healthCanada: [FoodItem] = [],
        openFoodFacts: [FoodItem] = [],
        query: String = "",
        usdaLimit: Int = 8,
        healthCanadaLimit: Int = 8,
        openFoodFactsLimit: Int = 10
    ) -> [FoodItem] {
        var merged = fatSecret
        var indicesByName: [String: Int] = [:]
        for (index, food) in merged.enumerated() {
            indicesByName[mergeIdentity(food)] = index
        }

        func merge(_ foods: [FoodItem], additionLimit: Int) {
            var additions = 0
            let ordered = foods.count > additionLimit ? rankedRemoteMatches(query: query, foods: foods) : foods
            for food in ordered {
                let name = mergeIdentity(food)
                if let existingIndex = indicesByName[name] {
                    if food.reportedMicronutrientCount > merged[existingIndex].reportedMicronutrientCount {
                        merged[existingIndex] = food
                    }
                } else if additions < additionLimit {
                    indicesByName[name] = merged.count
                    merged.append(food)
                    additions += 1
                }
            }
        }

        merge(usda, additionLimit: usdaLimit)
        merge(healthCanada, additionLimit: healthCanadaLimit)
        merge(openFoodFacts, additionLimit: openFoodFactsLimit)
        return attachingCrossSourceAgreement(
            to: merged,
            query: query,
            candidates: fatSecret + usda + healthCanada + openFoodFacts
        )
    }

    private static func mergeIdentity(_ food: FoodItem) -> String {
        let barcode = food.sourceMetadata?.barcode.map(BarcodeCorrectionRules.normalizedBarcode) ?? ""
        let brand = normalized(reportedBrandName(food.sourceMetadata?.brandName) ?? "")
        let serving = barcode.isEmpty && !brand.isEmpty ? normalized(food.sourceMetadata?.labeledServing ?? food.servingSize) : ""
        return [normalized(food.name), brand, barcode, serving].joined(separator: "|")
    }

    private static func canCompareProductIdentity(_ primary: FoodItem, _ candidate: FoodItem) -> Bool {
        let primaryBrand = reportedBrandName(primary.sourceMetadata?.brandName).map(normalized)
        let candidateBrand = reportedBrandName(candidate.sourceMetadata?.brandName).map(normalized)
        if let first = primary.sourceMetadata?.barcode, let second = candidate.sourceMetadata?.barcode {
            let firstCode = BarcodeCorrectionRules.normalizedBarcode(first)
            let secondCode = BarcodeCorrectionRules.normalizedBarcode(second)
            if BarcodeCorrectionRules.isValidGTIN(firstCode), BarcodeCorrectionRules.isValidGTIN(secondCode) {
                return !Set(BarcodeCorrectionRules.lookupCandidates(for: firstCode)).isDisjoint(with: BarcodeCorrectionRules.lookupCandidates(for: secondCode))
            }
            if !firstCode.isEmpty, !secondCode.isEmpty, firstCode != secondCode { return false }
        }
        guard primaryBrand != nil || candidateBrand != nil else { return true }
        return primaryBrand != nil && primaryBrand == candidateBrand && normalized(primary.name) == normalized(candidate.name)
    }

    private static func attachingCrossSourceAgreement(
        to foods: [FoodItem],
        query: String,
        candidates: [FoodItem]
    ) -> [FoodItem] {
        let normalizedQuery = normalized(query)
        let queryTokens = tokens(normalizedQuery)
        let queryTokenSet = Set(queryTokens)

        return foods.map { primary in
            let primaryName = normalized(primary.name)
            let primaryTokens = Set(tokens(primaryName))
            let eligibleCandidates = candidates.compactMap { candidate -> (String, FoodItem?)? in
                guard candidate.id != primary.id,
                      canCompareProductIdentity(primary, candidate),
                      let sourceName = candidate.sourceMetadata?.sourceName else {
                    return nil
                }

                let candidateName = normalized(candidate.name)
                let namesMatch: Bool
                if queryTokens.isEmpty {
                    namesMatch = primaryName == candidateName
                } else {
                    let candidateTokens = Set(tokens(candidateName))
                    let bothMatchQuery = queryTokenSet.isSubset(of: primaryTokens) &&
                        queryTokenSet.isSubset(of: candidateTokens)
                    let sharedDescriptors = primaryTokens
                        .intersection(candidateTokens)
                        .subtracting(queryTokenSet)
                    namesMatch = bothMatchQuery && (
                        queryTokens.count > 1 ||
                        primaryName == candidateName ||
                        !sharedDescriptors.isEmpty
                    )
                }
                return namesMatch ? (sourceName, candidate) : nil
            }

            let newEvidence = FoodSourceAgreement.agreeingEvidence(
                primary: primary,
                candidates: eligibleCandidates
            )
            guard !newEvidence.isEmpty else { return primary }

            let existingEvidence = primary.sourceMetadata?.validatedCrossVerificationEvidence ?? []
            return primary.withCrossVerificationEvidence(existingEvidence + newEvidence)
        }
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
        return isFatSecretID(food.id) && !hasAnyMicro
    }

    public static func isFatSecretID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isNumber)
    }
}
