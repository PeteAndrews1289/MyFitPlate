import Foundation

public struct MealPhotoAnalysisResponse: Decodable, Sendable {
    public let imageUsable: Bool
    public let overallConfidence: Double
    public let analysisNotes: String
    public let clarificationQuestions: [String]
    public let foods: [MealPhotoFoodEstimate]

    public init(
        imageUsable: Bool,
        overallConfidence: Double,
        analysisNotes: String,
        clarificationQuestions: [String],
        foods: [MealPhotoFoodEstimate]
    ) {
        self.imageUsable = imageUsable
        self.overallConfidence = overallConfidence
        self.analysisNotes = analysisNotes
        self.clarificationQuestions = clarificationQuestions
        self.foods = foods
    }
}

public struct MealPhotoFoodEstimate: Decodable, Equatable, Sendable {
    public let itemName: String
    public let preparation: String
    public let servingSize: String
    public let estimatedGrams: Double?
    public let portionLowGrams: Double?
    public let portionHighGrams: Double?
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public let confidence: Double
    public let visibleEvidence: String
    public let hiddenIngredientRisks: [String]
    public let requiresConfirmation: Bool
    public let clarificationQuestion: String?

    public init(
        itemName: String,
        preparation: String,
        servingSize: String,
        estimatedGrams: Double?,
        portionLowGrams: Double?,
        portionHighGrams: Double?,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        confidence: Double,
        visibleEvidence: String,
        hiddenIngredientRisks: [String],
        requiresConfirmation: Bool,
        clarificationQuestion: String?
    ) {
        self.itemName = itemName
        self.preparation = preparation
        self.servingSize = servingSize
        self.estimatedGrams = estimatedGrams
        self.portionLowGrams = portionLowGrams
        self.portionHighGrams = portionHighGrams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.confidence = confidence
        self.visibleEvidence = visibleEvidence
        self.hiddenIngredientRisks = hiddenIngredientRisks
        self.requiresConfirmation = requiresConfirmation
        self.clarificationQuestion = clarificationQuestion
    }
}

public struct MealPhotoGroundingOutcome: Sendable {
    public let item: FoodItem
    public let modelConfidence: Double
    public let portionLowGrams: Double?
    public let portionHighGrams: Double?
    public let requiresConfirmation: Bool
    public let clarificationQuestion: String?
    public let hiddenIngredientRisks: [String]
    public let referenceSourceName: String?

    public var usedNutrientReference: Bool { referenceSourceName != nil }

    public init(
        item: FoodItem,
        modelConfidence: Double,
        portionLowGrams: Double?,
        portionHighGrams: Double?,
        requiresConfirmation: Bool,
        clarificationQuestion: String?,
        hiddenIngredientRisks: [String],
        referenceSourceName: String?
    ) {
        self.item = item
        self.modelConfidence = modelConfidence
        self.portionLowGrams = portionLowGrams
        self.portionHighGrams = portionHighGrams
        self.requiresConfirmation = requiresConfirmation
        self.clarificationQuestion = clarificationQuestion
        self.hiddenIngredientRisks = hiddenIngredientRisks
        self.referenceSourceName = referenceSourceName
    }
}

public enum MealPhotoGrounding {
    private static let preparationTerms: Set<String> = [
        "baked", "boiled", "braised", "breaded", "fried", "grilled", "raw", "roasted",
        "sauteed", "steamed", "stewed"
    ]
    private static let ignoredTerms: Set<String> = [
        "a", "an", "and", "cooked", "food", "of", "plain", "prepared", "serving", "the", "with"
    ]

    public static func makeOutcome(
        estimate: MealPhotoFoodEstimate,
        candidates: [FoodItem]
    ) -> MealPhotoGroundingOutcome? {
        guard let fallback = fallbackItem(from: estimate) else { return nil }
        let confidence = bounded(estimate.confidence, lower: 0, upper: 1) ?? 0
        let portionWeights = [
            validWeight(estimate.portionLowGrams),
            validWeight(estimate.estimatedGrams),
            validWeight(estimate.portionHighGrams)
        ].compactMap { $0 }
        let rangeBounds = portionWeights.count >= 2
            ? (portionWeights.min(), portionWeights.max())
            : (nil, nil)
        let portionLow = rangeBounds.0
        let portionHigh = rangeBounds.1

        let reference = confidence >= 0.55
            ? bestReferenceMatch(for: estimate, candidates: candidates)
            : nil
        let grounded = reference.flatMap { candidate in
            groundedItem(from: candidate, estimate: estimate, confidence: confidence)
        }
        let finalItem = grounded?.item ?? fallback

        return MealPhotoGroundingOutcome(
            item: finalItem,
            modelConfidence: confidence,
            portionLowGrams: portionLow,
            portionHighGrams: portionHigh,
            requiresConfirmation: requiresConfirmation(for: estimate, confidence: confidence),
            clarificationQuestion: cleanOptionalText(estimate.clarificationQuestion),
            hiddenIngredientRisks: estimate.hiddenIngredientRisks
                .compactMap(cleanOptionalText)
                .prefix(5)
                .map { $0 },
            referenceSourceName: grounded?.referenceSourceName
        )
    }

    public static func bestReferenceMatch(
        for estimate: MealPhotoFoodEstimate,
        candidates: [FoodItem]
    ) -> FoodItem? {
        let query = [estimate.itemName, estimate.preparation]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let queryTokens = meaningfulTokens(query)
        guard !queryTokens.isEmpty else { return nil }

        return candidates.compactMap { candidate -> (FoodItem, Double)? in
            let candidateTokens = meaningfulTokens(candidate.name)
            guard !candidateTokens.isEmpty else { return nil }

            let queryPreparation = queryTokens.intersection(preparationTerms)
            let candidatePreparation = candidateTokens.intersection(preparationTerms)
            if !queryPreparation.isEmpty {
                guard !candidatePreparation.isEmpty,
                      !queryPreparation.isDisjoint(with: candidatePreparation) else {
                    return nil
                }
            }

            let identityQuery = queryTokens.subtracting(preparationTerms)
            let identityCandidate = candidateTokens.subtracting(preparationTerms)
            guard !identityQuery.isEmpty else { return nil }

            let matchingIdentity = identityQuery.intersection(identityCandidate)
            let coverage = Double(matchingIdentity.count) / Double(identityQuery.count)
            let union = identityQuery.union(identityCandidate)
            let similarity = union.isEmpty ? 0 : Double(matchingIdentity.count) / Double(union.count)
            guard coverage >= 0.66 else { return nil }

            var score = coverage * 75 + similarity * 20
            if normalized(candidate.name) == normalized(estimate.itemName) {
                score += 30
            }
            if !queryPreparation.isEmpty && queryPreparation.isSubset(of: candidatePreparation) {
                score += 12
            }
            if candidate.servingWeight >= 5, candidate.servingWeight <= 2_500 {
                score += 4
            }
            score += min(Double(candidate.reportedMicronutrientCount), 20) * 0.25
            return score >= 58 ? (candidate, score) : nil
        }
        .max { lhs, rhs in lhs.1 < rhs.1 }?
        .0
    }

    private static func fallbackItem(from estimate: MealPhotoFoodEstimate) -> FoodItem? {
        let name = estimate.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let calories = bounded(estimate.calories, lower: 0, upper: 10_000),
              let protein = bounded(estimate.protein, lower: 0, upper: 1_000),
              let carbs = bounded(estimate.carbs, lower: 0, upper: 1_500),
              let fats = bounded(estimate.fats, lower: 0, upper: 1_000) else {
            return nil
        }

        let grams = validWeight(estimate.estimatedGrams) ?? 0
        let serving = estimate.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = FoodItem(
            id: UUID().uuidString,
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            servingSize: serving.isEmpty ? fallbackServing(for: grams) : serving,
            servingWeight: grams
        ).normalizedForEstimatedSource("ai_image")

        let confidence = bounded(estimate.confidence, lower: 0, upper: 1) ?? 0
        let notes = evidenceNotes(
            estimate: estimate,
            nutrientReferenceName: nil
        )
        item.sourceMetadata = FoodSourceMetadata(
            sourceType: .aiImage,
            confidence: requiresConfirmation(for: estimate, confidence: confidence) ? .needsReview : .estimated,
            reviewStatus: .unreviewed,
            sourceName: "Maia Vision",
            sourceObservedAt: Date(),
            evidenceLineage: .modelEstimate,
            notes: notes,
            originalEstimate: item.nutritionSnapshot
        )
        return item
    }

    private static func groundedItem(
        from candidate: FoodItem,
        estimate: MealPhotoFoodEstimate,
        confidence: Double
    ) -> (item: FoodItem, referenceSourceName: String)? {
        guard let grams = validWeight(estimate.estimatedGrams),
              candidate.servingWeight.isFinite,
              candidate.servingWeight >= 5,
              candidate.servingWeight <= 2_500 else {
            return nil
        }

        let multiplier = grams / candidate.servingWeight
        guard multiplier.isFinite, multiplier > 0, multiplier <= 100 else { return nil }

        let sourceName = candidate.sourceMetadata?.sourceName ?? referenceName(for: candidate)
        var item = candidate.scalingNutritionAndServing(by: multiplier)
        item.id = UUID().uuidString
        item.name = estimate.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        item.servingSize = estimate.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.servingSize.isEmpty {
            item.servingSize = fallbackServing(for: grams)
        }
        item.servingWeight = grams
        item.timestamp = nil
        item.quantityValue = 1
        item.servingUnit = "serving"

        let reference = FoodVerificationEvidence(
            sourceName: sourceName,
            sourceType: candidate.sourceMetadata?.sourceType ?? .unknown,
            lineage: candidate.sourceMetadata?.effectiveEvidenceLineage ?? .unknown,
            sourceID: candidate.sourceMetadata?.sourceID ?? candidate.id,
            observedAt: candidate.sourceMetadata?.sourceObservedAt ?? Date(),
            sourceUpdatedAt: candidate.sourceMetadata?.sourceUpdatedAt
        )
        item.sourceMetadata = FoodSourceMetadata(
            sourceType: .aiImage,
            confidence: requiresConfirmation(for: estimate, confidence: confidence) ? .needsReview : .estimated,
            reviewStatus: .unreviewed,
            sourceName: "Maia Vision",
            matchedFoodID: candidate.id,
            sourceObservedAt: Date(),
            evidenceLineage: .modelEstimate,
            notes: evidenceNotes(estimate: estimate, nutrientReferenceName: sourceName),
            originalEstimate: item.nutritionSnapshot,
            nutrientReferenceEvidence: reference
        )
        return (item, sourceName)
    }

    private static func evidenceNotes(
        estimate: MealPhotoFoodEstimate,
        nutrientReferenceName: String?
    ) -> String {
        var notes = ["Food identity and portion were estimated from a photo."]
        if let nutrientReferenceName {
            notes.append("Nutrient composition was scaled from \(nutrientReferenceName).")
        } else {
            notes.append("No sufficiently close composition record was found; nutrition remains a model estimate.")
        }
        if let grams = validWeight(estimate.estimatedGrams) {
            let low = validWeight(estimate.portionLowGrams)
            let high = validWeight(estimate.portionHighGrams)
            if let low, let high {
                notes.append("Estimated portion: \(wholeNumber(grams)) g (approximately \(wholeNumber(min(low, high)))-\(wholeNumber(max(low, high))) g).")
            } else {
                notes.append("Estimated portion: \(wholeNumber(grams)) g.")
            }
        }
        if !estimate.hiddenIngredientRisks.isEmpty {
            notes.append("Possible unmeasured additions: \(estimate.hiddenIngredientRisks.prefix(3).joined(separator: ", ")).")
        }
        return notes.joined(separator: " ")
    }

    private static func referenceName(for item: FoodItem) -> String {
        switch item.sourceMetadata?.sourceType {
        case .usda: return "USDA FoodData Central"
        case .healthCanadaCNF: return "Health Canada CNF"
        default: return "food composition reference"
        }
    }

    private static func meaningfulTokens(_ value: String) -> Set<String> {
        Set(normalized(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !ignoredTerms.contains($0) }
            .map(canonicalToken))
    }

    private static func canonicalToken(_ token: String) -> String {
        if token.count > 4, token.hasSuffix("ies") {
            return String(token.dropLast(3)) + "y"
        }
        if token.count > 4, token.hasSuffix("oes") {
            return String(token.dropLast(2))
        }
        if token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") {
            return String(token.dropLast())
        }
        return token
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { result, character in
                if character == " ", result.last == " " { return }
                result.append(character)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validWeight(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 1, value <= 2_500 else { return nil }
        return value
    }

    private static func bounded(_ value: Double, lower: Double, upper: Double) -> Double? {
        guard value.isFinite, value >= lower, value <= upper else { return nil }
        return value
    }

    private static func requiresConfirmation(
        for estimate: MealPhotoFoodEstimate,
        confidence: Double
    ) -> Bool {
        estimate.requiresConfirmation
            || confidence < 0.70
            || validWeight(estimate.estimatedGrams) == nil
    }

    private static func cleanOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fallbackServing(for grams: Double) -> String {
        grams > 0 ? "About \(wholeNumber(grams)) g" : "1 estimated serving"
    }

    private static func wholeNumber(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
