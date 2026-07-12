import Foundation

public struct FoodSourceDescriptor: Equatable, Sendable {
    public let sourceKey: String
    public let title: String
    public let detail: String
    public let confidence: String
    public let systemImage: String
    public let isEstimated: Bool

    public init(
        sourceKey: String,
        title: String,
        detail: String,
        confidence: String,
        systemImage: String,
        isEstimated: Bool = false
    ) {
        self.sourceKey = sourceKey
        self.title = title
        self.detail = detail
        self.confidence = confidence
        self.systemImage = systemImage
        self.isEstimated = isEstimated
    }
}

public struct FoodTrustReason: Hashable, Identifiable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case evidence
        case caution
        case correction
    }

    public let text: String
    public let kind: Kind

    public var id: String { "\(kind.rawValue):\(text)" }

    public init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

public struct FoodTrustEvaluation: Equatable, Sendable {
    /// Increment whenever score semantics change so analytics from different models are not mixed.
    public static let modelVersion = 2

    public enum Level: String, Equatable, Sendable {
        case excellent
        case strong
        case review
        case low
    }

    public let score: Int
    public let level: Level
    public let label: String
    public let summary: String
    public let reasonDetails: [FoodTrustReason]
    public let action: String?
    public let requiresCorrection: Bool

    public var reasons: [String] { reasonDetails.map(\.text) }

    public init(
        score: Int,
        level: Level,
        label: String,
        summary: String,
        reasons: [String],
        action: String? = nil,
        requiresCorrection: Bool = false
    ) {
        self.score = score
        self.level = level
        self.label = label
        self.summary = summary
        self.reasonDetails = reasons.map { FoodTrustReason($0, kind: .evidence) }
        self.action = action
        self.requiresCorrection = requiresCorrection
    }

    public static func evaluate(
        item: FoodItem,
        descriptor: FoodSourceDescriptor,
        metadata: FoodSourceMetadata? = nil
    ) -> FoodTrustEvaluation {
        let sourceKey = trustedSourceKey(descriptor: descriptor, metadata: metadata)
        let isEstimated = descriptor.isEstimated || metadata?.confidence == .estimated
        let wasReviewed = metadata?.reviewStatus == .userConfirmed ||
            metadata?.reviewStatus == .userEdited
        let verifiedSources = metadata?.validatedCrossVerifiedBy ?? []
        let hasComparableServing = item.servingWeight.isFinite &&
            item.servingWeight >= FoodSourceAgreement.minimumComparableServingWeight
        let findings = FoodDataSanity.findings(for: item)
        let requiresCorrection = findings.contains { $0.severity == .warning }

        var score = baseScore(for: sourceKey)
        var evidenceReasons = baseReasons(
            for: sourceKey,
            descriptor: descriptor,
            metadata: metadata
        ).map { FoodTrustReason($0, kind: .evidence) }
        var cautionReasons: [FoodTrustReason] = []
        var correctionReasons: [FoodTrustReason] = []

        if !verifiedSources.isEmpty {
            score = max(score + 12, 92)
            evidenceReasons.append(FoodTrustReason(
                "Calories and macros matched another database",
                kind: .evidence
            ))
        }

        switch metadata?.reviewStatus {
        case .userEdited:
            score += 10
            evidenceReasons.append(FoodTrustReason("Nutrition edited by you", kind: .evidence))
        case .userConfirmed:
            score += 6
            evidenceReasons.append(FoodTrustReason("Serving selected by you", kind: .evidence))
        case .notRequired, .unreviewed, nil:
            break
        }

        if isEstimated {
            score -= wasReviewed ? 4 : 16
            cautionReasons.append(FoodTrustReason("Estimated food, not a label match", kind: .caution))
        }

        if !hasComparableServing {
            score -= 7
            cautionReasons.append(FoodTrustReason(
                "Serving weight is unavailable for comparison",
                kind: .caution
            ))
        }

        if requiresCorrection {
            score = min(score, 34)
            correctionReasons.append(FoodTrustReason(
                "Nutrition checks found a value to fix",
                kind: .correction
            ))
        } else if !findings.isEmpty {
            score -= 8
            cautionReasons.append(FoodTrustReason(
                "One nutrition detail deserves a quick look",
                kind: .caution
            ))
        }

        // Excellent is reserved for current, independently corroborated database nutrition.
        if verifiedSources.isEmpty {
            score = min(score, 89)
        }
        if isEstimated || sourceKey == "community_barcode" {
            score = min(score, 74)
        }
        if !hasComparableServing || !findings.isEmpty {
            score = min(score, 89)
        }

        let clampedScore = min(max(score, 0), 99)
        let orderedReasons = (correctionReasons + cautionReasons + evidenceReasons).uniqued()
        return evaluation(
            score: clampedScore,
            reasonDetails: Array(orderedReasons.prefix(5)),
            requiresCorrection: requiresCorrection,
            isEstimated: isEstimated,
            isReviewedEstimate: isEstimated && wasReviewed,
            isReviewed: wasReviewed,
            hasComparableServing: hasComparableServing
        )
    }

    private static func baseScore(for sourceKey: String) -> Int {
        switch sourceKey {
        case "usda": return 86
        case "fatsecret": return 74
        case "open_food_facts": return 68
        case "custom_barcode": return 82
        case "manual": return 68
        case "planned", "recent": return 82
        case "community_barcode": return 68
        case "chain_builder": return 66
        case "ai_estimate": return 58
        default: return 55
        }
    }

    private static func baseReasons(
        for sourceKey: String,
        descriptor: FoodSourceDescriptor,
        metadata: FoodSourceMetadata?
    ) -> [String] {
        switch sourceKey {
        case "usda":
            return ["USDA sourced nutrition"]
        case "fatsecret":
            return ["Packaged-food database match"]
        case "open_food_facts":
            return ["Public packaged-food database match"]
        case "custom_barcode":
            return ["Saved from your own food library"]
        case "community_barcode":
            return ["At least three private corrections reached consensus"]
        case "manual":
            return ["User-entered food"]
        case "planned":
            return ["Built from your recipes or meal plan"]
        case "recent":
            return ["Reused from your own history"]
        case "ai_estimate":
            return ["Maia estimate"]
        case "chain_builder":
            return ["Restaurant catalog estimate"]
        default:
            let sourceName = metadata?.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return [sourceName?.isEmpty == false ? sourceName! : descriptor.title]
        }
    }

    private static func trustedSourceKey(
        descriptor: FoodSourceDescriptor,
        metadata: FoodSourceMetadata?
    ) -> String {
        guard let metadata else { return descriptor.sourceKey }
        return FoodSourceClassifier.descriptor(for: metadata).sourceKey
    }

    private static func evaluation(
        score: Int,
        reasonDetails: [FoodTrustReason],
        requiresCorrection: Bool,
        isEstimated: Bool,
        isReviewedEstimate: Bool,
        isReviewed: Bool,
        hasComparableServing: Bool
    ) -> FoodTrustEvaluation {
        switch score {
        case 90...:
            return FoodTrustEvaluation(
                score: score,
                level: .excellent,
                label: "Excellent trust",
                summary: "Independent databases agree on calories and macros, with no nutrition warnings found.",
                reasonDetails: reasonDetails,
                requiresCorrection: false
            )
        case 75..<90:
            return FoodTrustEvaluation(
                score: score,
                level: .strong,
                label: "Strong trust",
                summary: "The source and nutrition checks look reliable. Confirm the serving you ate.",
                reasonDetails: reasonDetails,
                requiresCorrection: false
            )
        case 55..<75:
            let label: String
            if isReviewedEstimate {
                label = "Reviewed estimate"
            } else if isEstimated {
                label = "Review estimate"
            } else if isReviewed {
                label = "Reviewed entry"
            } else {
                label = hasComparableServing ? "Review entry" : "Review serving"
            }
            let summary: String
            if isReviewedEstimate {
                summary = hasComparableServing
                    ? "This remains an estimate, but you reviewed its serving or nutrition. A package or database match is still stronger."
                    : "You reviewed this estimate, but its serving weight is still unavailable for an independent comparison."
            } else if isEstimated {
                summary = "This is an estimate. Review the serving and nutrition before relying on it."
            } else if isReviewed {
                summary = hasComparableServing
                    ? "You reviewed this entry. It is still supported by a single source rather than an independent match."
                    : "You reviewed this entry, but its serving weight is still unavailable for an independent comparison."
            } else {
                summary = "This entry is usable, but one or more trust checks deserve a look."
            }

            let action: String?
            if isReviewedEstimate {
                action = hasComparableServing ? nil : "Improve estimate"
            } else if isReviewed {
                action = hasComparableServing ? nil : "Improve entry"
            } else {
                action = isEstimated ? "Review estimate" : "Review food"
            }
            return FoodTrustEvaluation(
                score: score,
                level: .review,
                label: label,
                summary: summary,
                reasonDetails: reasonDetails,
                action: action,
                requiresCorrection: false
            )
        default:
            if !requiresCorrection {
                let label: String
                if isReviewedEstimate {
                    label = "Reviewed estimate"
                } else if isEstimated {
                    label = "Review estimate"
                } else if isReviewed {
                    label = "Reviewed entry"
                } else {
                    label = "Low confidence"
                }

                let summary: String
                if isReviewedEstimate {
                    summary = "You reviewed this estimate, but its serving weight is still unavailable for an independent comparison."
                } else if isEstimated {
                    summary = "This estimate needs your review before it should guide your totals."
                } else if isReviewed {
                    summary = "You reviewed this entry, but the available source or serving evidence remains limited."
                } else {
                    summary = "The available evidence is limited. Review the serving and nutrition before logging."
                }
                return FoodTrustEvaluation(
                    score: score,
                    level: .low,
                    label: label,
                    summary: summary,
                    reasonDetails: reasonDetails,
                    action: isReviewedEstimate
                        ? "Improve estimate"
                        : (isReviewed ? "Improve entry" : (isEstimated ? "Review estimate" : "Review food")),
                    requiresCorrection: false
                )
            }
            return FoodTrustEvaluation(
                score: score,
                level: .low,
                label: "Needs correction",
                summary: "Review the highlighted nutrition values before using this entry in your totals.",
                reasonDetails: reasonDetails,
                action: "Fix data",
                requiresCorrection: true
            )
        }
    }

    private init(
        score: Int,
        level: Level,
        label: String,
        summary: String,
        reasonDetails: [FoodTrustReason],
        action: String? = nil,
        requiresCorrection: Bool
    ) {
        self.score = score
        self.level = level
        self.label = label
        self.summary = summary
        self.reasonDetails = reasonDetails
        self.action = action
        self.requiresCorrection = requiresCorrection
    }
}

public enum FoodSourceType: String, Codable, Sendable {
    case usda
    case fatSecret
    case openFoodFacts
    case aiImage
    case aiMenu
    case aiText
    case aiChat
    case manual
    case custom
    case chainBuilder
    case recipe
    case mealPlan
    case recent
    case unknown
}

public enum FoodConfidenceLevel: String, Codable, Sendable {
    case verified
    case databaseMatch
    case estimated
    case needsReview
    case userVerified
}

public enum FoodReviewStatus: String, Codable, Sendable {
    case notRequired
    case unreviewed
    case userConfirmed
    case userEdited
}

public struct FoodNutritionSnapshot: Codable, Hashable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fats: Double
    public var servingSize: String
    public var servingWeight: Double

    public init(
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        servingSize: String,
        servingWeight: Double
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.servingSize = servingSize
        self.servingWeight = servingWeight
    }
}

public struct FoodSourceMetadata: Codable, Hashable, Sendable {
    public var sourceType: FoodSourceType
    public var confidence: FoodConfidenceLevel
    public var reviewStatus: FoodReviewStatus
    public var sourceName: String?
    public var sourceID: String?
    public var barcode: String?
    public var matchedFoodID: String?
    public var createdAt: Date?
    public var notes: String?
    public var originalEstimate: FoodNutritionSnapshot?
    public var userCorrection: FoodNutritionSnapshot?
    /// Independent databases whose entries agreed with this one at lookup time
    /// (see FoodSourceAgreement). Optional so previously stored metadata decodes unchanged.
    public var crossVerifiedBy: [String]?

    public init(
        sourceType: FoodSourceType,
        confidence: FoodConfidenceLevel,
        reviewStatus: FoodReviewStatus,
        sourceName: String? = nil,
        sourceID: String? = nil,
        barcode: String? = nil,
        matchedFoodID: String? = nil,
        createdAt: Date? = Date(),
        notes: String? = nil,
        originalEstimate: FoodNutritionSnapshot? = nil,
        userCorrection: FoodNutritionSnapshot? = nil,
        crossVerifiedBy: [String]? = nil
    ) {
        self.sourceType = sourceType
        self.confidence = confidence
        self.reviewStatus = reviewStatus
        self.sourceName = sourceName
        self.sourceID = sourceID
        self.barcode = barcode
        self.matchedFoodID = matchedFoodID
        self.createdAt = createdAt
        self.notes = notes
        self.originalEstimate = originalEstimate
        self.userCorrection = userCorrection
        self.crossVerifiedBy = crossVerifiedBy
    }

    public static func database(
        _ sourceType: FoodSourceType,
        sourceName: String,
        sourceID: String?,
        barcode: String? = nil,
        matchedFoodID: String? = nil
    ) -> FoodSourceMetadata {
        FoodSourceMetadata(
            sourceType: sourceType,
            confidence: sourceType == .usda ? .verified : .databaseMatch,
            reviewStatus: .notRequired,
            sourceName: sourceName,
            sourceID: sourceID,
            barcode: barcode,
            matchedFoodID: matchedFoodID ?? sourceID
        )
    }

    public static func aiEstimate(
        _ sourceType: FoodSourceType,
        sourceName: String,
        notes: String? = nil,
        originalEstimate: FoodNutritionSnapshot? = nil
    ) -> FoodSourceMetadata {
        FoodSourceMetadata(
            sourceType: sourceType,
            confidence: .estimated,
            reviewStatus: .unreviewed,
            sourceName: sourceName,
            notes: notes,
            originalEstimate: originalEstimate
        )
    }

    public static func userEntered(sourceName: String = "MyFitPlate") -> FoodSourceMetadata {
        FoodSourceMetadata(
            sourceType: .manual,
            confidence: .userVerified,
            reviewStatus: .userConfirmed,
            sourceName: sourceName
        )
    }
}

public enum FoodSourceClassifier {
    public static func descriptor(
        for source: String,
        foodID: String? = nil,
        metadata: FoodSourceMetadata? = nil
    ) -> FoodSourceDescriptor {
        if let metadata {
            return descriptor(for: metadata)
        }

        let normalizedSource = source.lowercased()

        if normalizedSource.contains("ai") ||
            normalizedSource.contains("image") ||
            normalizedSource.contains("menu") ||
            normalizedSource.contains("pantry_vision") {
            return FoodSourceDescriptor(
                sourceKey: "ai_estimate",
                title: "AI Estimate",
                detail: "Review the serving and macros before relying on this entry.",
                confidence: "Needs Review",
                systemImage: "sparkles",
                isEstimated: true
            )
        }

        if normalizedSource.contains("usda") || foodID?.hasPrefix("usda_") == true {
            return FoodSourceDescriptor(
                sourceKey: "usda",
                title: "USDA",
                detail: "Matched from USDA FoodData Central.",
                confidence: "High Trust",
                systemImage: "checkmark.seal.fill"
            )
        }

        if normalizedSource.contains("open_food_facts") || foodID?.hasPrefix("off_") == true {
            return FoodSourceDescriptor(
                sourceKey: "open_food_facts",
                title: "Open Food Facts",
                detail: "Matched from a public packaged-food database.",
                confidence: "Review Serving",
                systemImage: "barcode.viewfinder"
            )
        }

        if normalizedSource.contains("barcode") ||
            normalizedSource.contains("fatsecret") ||
            foodID?.allSatisfy(\.isNumber) == true {
            return FoodSourceDescriptor(
                sourceKey: "fatsecret",
                title: "Food Database",
                detail: "Matched from a packaged-food database.",
                confidence: "Database Match",
                systemImage: "checkmark.circle.fill"
            )
        }

        if normalizedSource.contains("quick_log") || normalizedSource.contains("recent") {
            return FoodSourceDescriptor(
                sourceKey: "recent",
                title: "Recent Log",
                detail: "Reused from your food history.",
                confidence: "User History",
                systemImage: "clock.arrow.circlepath"
            )
        }

        if normalizedSource.contains("recipe") || normalizedSource.contains("meal_plan") {
            return FoodSourceDescriptor(
                sourceKey: "planned",
                title: "Planned Food",
                detail: "Built from your recipes or meal plan.",
                confidence: "User Plan",
                systemImage: "list.clipboard.fill"
            )
        }

        if normalizedSource.contains("manual") || normalizedSource.contains("custom") {
            return FoodSourceDescriptor(
                sourceKey: "manual",
                title: "Custom Entry",
                detail: "Entered or saved by you.",
                confidence: "Personal Entry",
                systemImage: "person.crop.circle.badge.checkmark"
            )
        }

        return FoodSourceDescriptor(
            sourceKey: "unknown",
            title: "Food Entry",
            detail: "Review serving details before logging.",
            confidence: "Review",
            systemImage: "info.circle.fill"
        )
    }

    public static func descriptor(for metadata: FoodSourceMetadata) -> FoodSourceDescriptor {
        switch metadata.sourceType {
        case .usda:
            return trustedDatabaseDescriptor(
                sourceKey: "usda",
                title: "USDA",
                detail: sourceDetail(
                    metadata,
                    defaultDetail: "Matched from USDA FoodData Central."
                ),
                confidence: confidenceText(for: metadata),
                systemImage: "checkmark.seal.fill"
            )

        case .fatSecret:
            return trustedDatabaseDescriptor(
                sourceKey: "fatsecret",
                title: "Food Database",
                detail: sourceDetail(
                    metadata,
                    defaultDetail: "Matched from a packaged-food database."
                ),
                confidence: confidenceText(for: metadata),
                systemImage: "checkmark.circle.fill"
            )

        case .openFoodFacts:
            return trustedDatabaseDescriptor(
                sourceKey: "open_food_facts",
                title: "Open Food Facts",
                detail: sourceDetail(
                    metadata,
                    defaultDetail: "Matched from a public packaged-food database."
                ),
                confidence: confidenceText(for: metadata),
                systemImage: "barcode.viewfinder"
            )

        case .aiImage, .aiMenu, .aiText, .aiChat:
            return aiDescriptor(for: metadata)

        case .manual, .custom:
            if CommunityBarcodeRules.isCommunityMatch(metadata) {
                return FoodSourceDescriptor(
                    sourceKey: "community_barcode",
                    title: "Community Match",
                    detail: sourceDetail(
                        metadata,
                        defaultDetail: "At least three private corrections agreed on this nutrition. Confirm it against the package."
                    ),
                    confidence: "Community Consensus",
                    systemImage: "person.2.fill"
                )
            }

            if metadata.barcode?.isEmpty == false {
                return FoodSourceDescriptor(
                    sourceKey: "custom_barcode",
                    title: "My Foods Match",
                    detail: sourceDetail(
                        metadata,
                        defaultDetail: "Matched from a food you saved for this barcode."
                    ),
                    confidence: confidenceText(for: metadata),
                    systemImage: "barcode.viewfinder"
                )
            }

            return FoodSourceDescriptor(
                sourceKey: "manual",
                title: "Custom Entry",
                detail: sourceDetail(metadata, defaultDetail: "Entered or saved by you."),
                confidence: confidenceText(for: metadata),
                systemImage: "person.crop.circle.badge.checkmark"
            )

        case .chainBuilder:
            return FoodSourceDescriptor(
                sourceKey: "chain_builder",
                title: "Chain Builder",
                detail: sourceDetail(
                    metadata,
                    defaultDetail: "Built from the MyFitPlate chain catalog. Review portions before logging."
                ),
                confidence: confidenceText(for: metadata),
                systemImage: "takeoutbag.and.cup.and.straw.fill",
                isEstimated: metadata.confidence == .estimated
            )

        case .recipe, .mealPlan:
            return FoodSourceDescriptor(
                sourceKey: "planned",
                title: "Planned Food",
                detail: sourceDetail(
                    metadata,
                    defaultDetail: metadata.confidence == .estimated
                        ? "Estimated for your meal plan. Review portions before logging."
                        : "Built from your recipes or meal plan."
                ),
                confidence: confidenceText(for: metadata),
                systemImage: "list.clipboard.fill",
                isEstimated: metadata.confidence == .estimated
            )

        case .recent:
            return FoodSourceDescriptor(
                sourceKey: "recent",
                title: "Recent Log",
                detail: "Reused from your food history.",
                confidence: confidenceText(for: metadata),
                systemImage: "clock.arrow.circlepath"
            )

        case .unknown:
            return descriptor(for: "unknown")
        }
    }

    public static func descriptor(forFoodID foodID: String) -> FoodSourceDescriptor? {
        if foodID.hasPrefix("usda_") {
            return descriptor(for: "usda", foodID: foodID)
        }

        if foodID.hasPrefix("off_") {
            return descriptor(for: "open_food_facts", foodID: foodID)
        }

        if !foodID.isEmpty && foodID.allSatisfy(\.isNumber) {
            return descriptor(for: "fatsecret", foodID: foodID)
        }

        return nil
    }

    private static func trustedDatabaseDescriptor(
        sourceKey: String,
        title: String,
        detail: String,
        confidence: String,
        systemImage: String
    ) -> FoodSourceDescriptor {
        FoodSourceDescriptor(
            sourceKey: sourceKey,
            title: title,
            detail: detail,
            confidence: confidence,
            systemImage: systemImage
        )
    }

    private static func aiDescriptor(for metadata: FoodSourceMetadata) -> FoodSourceDescriptor {
        let title: String
        let detail: String
        switch metadata.sourceType {
        case .aiMenu:
            title = "Menu Estimate"
            detail = "Estimated from a menu photo. Restaurant portions vary."
        case .aiText, .aiChat:
            title = "Text Estimate"
            detail = "Estimated from your description. Sauces, oils, and shared portions may vary."
        default:
            title = "AI Estimate"
            detail = "Estimated from a photo. Review the serving and macros before relying on this entry."
        }

        return FoodSourceDescriptor(
            sourceKey: "ai_estimate",
            title: title,
            detail: sourceDetail(metadata, defaultDetail: detail),
            confidence: confidenceText(for: metadata),
            systemImage: "sparkles",
            isEstimated: true
        )
    }

    private static func sourceDetail(
        _: FoodSourceMetadata,
        defaultDetail: String
    ) -> String {
        defaultDetail
    }

    private static func confidenceText(for metadata: FoodSourceMetadata) -> String {
        switch metadata.reviewStatus {
        case .userEdited:
            return "Edited by You"
        case .userConfirmed, .notRequired, .unreviewed:
            break
        }

        // Two independent databases agreeing beats either database's solo confidence.
        if metadata.hasIndependentCrossVerification {
            return "Cross-Verified"
        }

        if metadata.reviewStatus == .userConfirmed {
            return metadata.confidence == .estimated ? "Reviewed by You" : "Serving Reviewed"
        }

        switch metadata.confidence {
        case .verified:
            return "High Trust"
        case .databaseMatch:
            return "Database Match"
        case .estimated, .needsReview:
            return "Needs Review"
        case .userVerified:
            return "Personal Entry"
        }
    }
}

public extension FoodItem {
    var nutritionSnapshot: FoodNutritionSnapshot {
        FoodNutritionSnapshot(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            servingSize: servingSize,
            servingWeight: servingWeight
        )
    }

    func withSourceMetadata(_ metadata: FoodSourceMetadata?) -> FoodItem {
        var item = self
        item.sourceMetadata = metadata
        return item
    }

    func savedAsCustomFood(
        sourceName: String = "My Foods",
        barcode: String? = nil,
        originalItem: FoodItem? = nil
    ) -> FoodItem {
        var metadata = sourceMetadata ?? .userEntered(sourceName: sourceName)
        let normalizedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode ?? metadata.barcode ?? "")
        let originalSnapshot = originalItem?.nutritionSnapshot ?? metadata.originalEstimate

        metadata.sourceType = .custom
        metadata.confidence = .userVerified
        metadata.reviewStatus = originalSnapshot == nil || originalSnapshot == nutritionSnapshot ? .userConfirmed : .userEdited
        metadata.sourceName = sourceName
        metadata.sourceID = id
        metadata.matchedFoodID = metadata.matchedFoodID ?? originalItem?.id ?? id
        metadata.barcode = normalizedBarcode.isEmpty ? nil : normalizedBarcode
        metadata.crossVerifiedBy = nil

        if metadata.reviewStatus == .userEdited {
            metadata.originalEstimate = metadata.originalEstimate ?? originalSnapshot
            metadata.userCorrection = nutritionSnapshot
            metadata.notes = metadata.notes ?? "User edited nutrition before saving to My Foods."
        }

        return withSourceMetadata(metadata)
    }

    func withDatabaseSource(
        _ sourceType: FoodSourceType,
        sourceName: String,
        sourceID: String? = nil,
        barcode: String? = nil
    ) -> FoodItem {
        withSourceMetadata(
            .database(
                sourceType,
                sourceName: sourceName,
                sourceID: sourceID ?? id,
                barcode: barcode,
                matchedFoodID: id
            )
        )
    }

    func withAIEstimateSource(_ sourceType: FoodSourceType, sourceName: String) -> FoodItem {
        withSourceMetadata(
            .aiEstimate(
                sourceType,
                sourceName: sourceName,
                originalEstimate: nutritionSnapshot
            )
        )
    }

    func markedUserConfirmed(
        sourceType fallbackSourceType: FoodSourceType? = nil,
        originalItem: FoodItem? = nil
    ) -> FoodItem {
        withReviewStatus(
            .userConfirmed,
            fallbackSourceType: fallbackSourceType,
            originalItem: originalItem
        )
    }

    func markedUserEdited(sourceType fallbackSourceType: FoodSourceType? = nil) -> FoodItem {
        withReviewStatus(.userEdited, fallbackSourceType: fallbackSourceType)
    }

    func markedUserEdited(
        sourceType fallbackSourceType: FoodSourceType? = nil,
        originalItem: FoodItem
    ) -> FoodItem {
        withReviewStatus(
            .userEdited,
            fallbackSourceType: fallbackSourceType,
            originalItem: originalItem
        )
    }

    private func withReviewStatus(
        _ reviewStatus: FoodReviewStatus,
        fallbackSourceType: FoodSourceType?,
        originalItem: FoodItem? = nil
    ) -> FoodItem {
        var metadata = sourceMetadata ?? FoodSourceMetadata(
            sourceType: fallbackSourceType ?? .manual,
            confidence: fallbackSourceType?.isAISource == true ? .estimated : .userVerified,
            reviewStatus: reviewStatus,
            sourceID: id,
            matchedFoodID: id
        )
        if let fallbackSourceType, metadata.sourceType == .unknown {
            metadata.sourceType = fallbackSourceType
        }
        metadata.reviewStatus = reviewStatus
        if metadata.crossVerifiedBy?.isEmpty == false {
            let preservesEvidence = originalItem.map {
                FoodSourceAgreement.preservesAgreementEvidence(self, $0)
            } ?? false
            if !preservesEvidence && (reviewStatus == .userEdited || originalItem != nil) {
                metadata.crossVerifiedBy = nil
            }
        }
        if reviewStatus == .userEdited {
            metadata.originalEstimate = metadata.originalEstimate ?? originalItem?.nutritionSnapshot
            metadata.userCorrection = nutritionSnapshot
            metadata.notes = metadata.notes ?? "User edited nutrition before logging."
        }
        return withSourceMetadata(metadata)
    }
}

private extension FoodSourceType {
    var isAISource: Bool {
        switch self {
        case .aiImage, .aiMenu, .aiText, .aiChat:
            return true
        default:
            return false
        }
    }
}

public struct BarcodeFoodLookupResult: Sendable {
    public let item: FoodItem
    public let source: String
    public let scannedBarcode: String
    public let matchedBarcode: String
    public let candidateCount: Int

    public init(
        item: FoodItem,
        source: String,
        scannedBarcode: String? = nil,
        matchedBarcode: String? = nil,
        candidateCount: Int = 1
    ) {
        self.item = item
        self.source = source
        let scanned = BarcodeCorrectionRules.normalizedBarcode(scannedBarcode ?? item.sourceMetadata?.barcode ?? "")
        let matched = BarcodeCorrectionRules.normalizedBarcode(matchedBarcode ?? scanned)
        self.scannedBarcode = scanned
        self.matchedBarcode = matched
        self.candidateCount = max(candidateCount, 1)
    }

    public var usedRelatedBarcode: Bool {
        !scannedBarcode.isEmpty && !matchedBarcode.isEmpty && scannedBarcode != matchedBarcode
    }
}

public struct BarcodeLookupOutcome: Equatable, Sendable {
    public static let eventName = ProductAnalytics.Event.barcodeLookupOutcome.rawValue

    public let result: String
    public let source: String
    public let scannedLength: Int
    public let matchedLength: Int
    public let candidateCount: Int
    public let usedRelatedBarcode: Bool
    public let crossVerifiedCount: Int
    public let trustScore: Int?
    public let trustLevel: String?
    public let durationMilliseconds: Int
    public let durationBucket: String

    public var analyticsParameters: [String: Any] {
        var params: [String: Any] = [
            "result": result,
            "source": source,
            "scanned_length": scannedLength,
            "matched_length": matchedLength,
            "candidate_count": candidateCount,
            "used_related_barcode": usedRelatedBarcode,
            "cross_verified_count": crossVerifiedCount,
            "trust_model_version": String(FoodTrustEvaluation.modelVersion),
            "duration_ms": durationMilliseconds,
            "duration_bucket": durationBucket
        ]
        if let trustScore {
            params["trust_score"] = trustScore
        }
        if let trustLevel {
            params["trust_level"] = trustLevel
        }
        return params
    }

    public static func success(
        _ lookupResult: BarcodeFoodLookupResult,
        durationMilliseconds: Int = 0
    ) -> BarcodeLookupOutcome {
        let descriptor = FoodSourceClassifier.descriptor(
            for: lookupResult.source,
            foodID: lookupResult.item.id,
            metadata: lookupResult.item.sourceMetadata
        )
        let evaluation = FoodTrustEvaluation.evaluate(
            item: lookupResult.item,
            descriptor: descriptor,
            metadata: lookupResult.item.sourceMetadata
        )

        return BarcodeLookupOutcome(
            result: "hit",
            source: lookupResult.source,
            scannedLength: lookupResult.scannedBarcode.count,
            matchedLength: lookupResult.matchedBarcode.count,
            candidateCount: lookupResult.candidateCount,
            usedRelatedBarcode: lookupResult.usedRelatedBarcode,
            crossVerifiedCount: lookupResult.item.sourceMetadata?.validatedCrossVerifiedBy.count ?? 0,
            trustScore: evaluation.score,
            trustLevel: evaluation.level.rawValue,
            durationMilliseconds: max(durationMilliseconds, 0),
            durationBucket: ProductAnalytics.durationBucket(milliseconds: durationMilliseconds)
        )
    }

    public static func miss(barcode: String, durationMilliseconds: Int = 0) -> BarcodeLookupOutcome {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        return BarcodeLookupOutcome(
            result: "miss",
            source: "none",
            scannedLength: normalized.count,
            matchedLength: 0,
            candidateCount: BarcodeCorrectionRules.lookupCandidates(for: normalized).count,
            usedRelatedBarcode: false,
            crossVerifiedCount: 0,
            trustScore: nil,
            trustLevel: nil,
            durationMilliseconds: max(durationMilliseconds, 0),
            durationBucket: ProductAnalytics.durationBucket(milliseconds: durationMilliseconds)
        )
    }
}

public struct BarcodeRecoveryOutcome: Equatable, Sendable {
    public static let eventName = ProductAnalytics.Event.barcodeMissRecovery.rawValue

    public let action: String
    public let scannedLength: Int
    public let candidateCount: Int
    public let trustScore: Int?
    public let trustLevel: String?

    public var analyticsParameters: [String: Any] {
        var params: [String: Any] = [
            "action": action,
            "scanned_length": scannedLength,
            "candidate_count": candidateCount,
            "trust_model_version": String(FoodTrustEvaluation.modelVersion)
        ]
        if let trustScore {
            params["trust_score"] = trustScore
        }
        if let trustLevel {
            params["trust_level"] = trustLevel
        }
        return params
    }

    public static func selected(action: String, barcode: String?) -> BarcodeRecoveryOutcome {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode ?? "")
        return BarcodeRecoveryOutcome(
            action: action,
            scannedLength: normalized.count,
            candidateCount: normalized.isEmpty ? 0 : BarcodeCorrectionRules.lookupCandidates(for: normalized).count,
            trustScore: nil,
            trustLevel: nil
        )
    }

    public static func manualFoodCreated(_ item: FoodItem) -> BarcodeRecoveryOutcome {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(item.sourceMetadata?.barcode ?? "")
        let descriptor = FoodSourceClassifier.descriptor(
            for: "manual_barcode_create",
            foodID: item.id,
            metadata: item.sourceMetadata
        )
        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        return BarcodeRecoveryOutcome(
            action: "manual_food_created",
            scannedLength: normalized.count,
            candidateCount: normalized.isEmpty ? 0 : BarcodeCorrectionRules.lookupCandidates(for: normalized).count,
            trustScore: evaluation.score,
            trustLevel: evaluation.level.rawValue
        )
    }
}

public enum BarcodeCorrectionRules {
    private static let supportedGTINLengths = [8, 12, 13, 14]

    public static func normalizedBarcode(_ barcode: String) -> String {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.compactMap(\.wholeNumberValue).map(String.init).joined()
        return digits.isEmpty ? trimmed : digits
    }

    /// Validates the GS1 modulo-10 check digit for GTIN-8, GTIN-12, GTIN-13, and GTIN-14.
    public static func isValidGTIN(_ barcode: String) -> Bool {
        let normalized = normalizedBarcode(barcode)
        guard supportedGTINLengths.contains(normalized.count),
              normalized.allSatisfy(\.isNumber),
              let checkDigit = normalized.last?.wholeNumberValue else {
            return false
        }

        let payload = normalized.dropLast().reversed()
        let weightedSum = payload.enumerated().reduce(into: 0) { sum, pair in
            guard let digit = pair.element.wholeNumberValue else { return }
            sum += digit * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - weightedSum % 10) % 10 == checkDigit
    }

    public static func lookupCandidates(for barcode: String) -> [String] {
        let normalized = normalizedBarcode(barcode)
        guard !normalized.isEmpty else { return [] }
        guard normalized.allSatisfy(\.isNumber) else { return [normalized] }
        guard isValidGTIN(normalized) else { return [normalized] }

        var candidates = [normalized]
        let canonical = String(repeating: "0", count: 14 - normalized.count) + normalized
        let alternateLengths: [Int]
        switch normalized.count {
        case 8:
            alternateLengths = [12, 13, 14]
        case 12:
            alternateLengths = [13, 14, 8]
        case 13:
            alternateLengths = [12, 14, 8]
        case 14:
            alternateLengths = [13, 12, 8]
        default:
            return candidates
        }

        for length in alternateLengths {
            let prefixCount = canonical.count - length
            guard canonical.prefix(prefixCount).allSatisfy({ $0 == "0" }) else { continue }
            let candidate = String(canonical.suffix(length))
            if isValidGTIN(candidate) {
                candidates.append(candidate)
            }
        }
        return candidates.uniqued()
    }

    public static func bestCorrectedFood(in foods: [FoodItem], barcode: String) -> FoodItem? {
        let candidates = lookupCandidates(for: barcode)
        guard !candidates.isEmpty else { return nil }

        return foods
            .filter { food in
                guard let barcode = food.sourceMetadata?.barcode else { return false }
                return candidates.contains(normalizedBarcode(barcode))
            }
            .sorted { lhs, rhs in
                let lhsScore = correctionScore(for: lhs, candidates: candidates)
                let rhsScore = correctionScore(for: rhs, candidates: candidates)
                return lhsScore > rhsScore
            }
            .first
            .map { correctedFood(from: $0, barcode: candidates[0]) }
    }

    public static func matches(_ food: FoodItem, barcode: String) -> Bool {
        guard let foodBarcode = food.sourceMetadata?.barcode else { return false }
        return lookupCandidates(for: barcode).contains(normalizedBarcode(foodBarcode))
    }

    public static func correctedFood(from food: FoodItem, barcode: String) -> FoodItem {
        food.savedAsCustomFood(barcode: barcode, originalItem: nil)
    }

    private static func correctionScore(for food: FoodItem) -> Int {
        switch food.sourceMetadata?.reviewStatus {
        case .userEdited:
            return 4
        case .userConfirmed:
            return 3
        case .notRequired:
            return 2
        case .unreviewed:
            return 1
        case nil:
            return 0
        }
    }

    private static func correctionScore(for food: FoodItem, candidates: [String]) -> Int {
        let barcode = normalizedBarcode(food.sourceMetadata?.barcode ?? "")
        let candidateBonus = max(0, candidates.count - (candidates.firstIndex(of: barcode) ?? candidates.count))
        return correctionScore(for: food) * 10 + candidateBonus
    }
}

public protocol BarcodeCorrectionStoreProtocol: Sendable {
    func correctedFood(for barcode: String) async -> FoodItem?
}

public struct CustomFoodBarcodeCorrectionStore: BarcodeCorrectionStoreProtocol {
    public init() {}

    public func correctedFood(for barcode: String) async -> FoodItem? {
        let dependencies = await MainActor.run { () -> (userID: String?, repository: NutritionRepositoryProtocol?) in
            let authService: AuthServiceProtocol? = DIContainer.shared.authService
            let nutritionRepository: NutritionRepositoryProtocol? = DIContainer.shared.nutritionRepository
            return (authService?.currentUserID, nutritionRepository)
        }

        guard let userID = dependencies.userID, !userID.isEmpty, let repository = dependencies.repository else {
            return nil
        }

        do {
            let customFoods = try await repository.fetchCustomFoods(userID: userID)
            return BarcodeCorrectionRules.bestCorrectedFood(in: customFoods, barcode: barcode)
        } catch {
            AppLog.data.error("Failed to fetch barcode corrections: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

public final class BarcodeFoodLookupService {
    private struct ProviderMatches {
        let fatSecret: FoodItem?
        let usda: FoodItem?
        let openFoodFacts: FoodItem?
    }

    private let fatSecretService: FatSecretFoodAPIService
    private let usdaService: USDAFoodAPIService
    private let openFoodFactsService: OpenFoodFactsAPIService
    private let correctionStore: BarcodeCorrectionStoreProtocol?

    public init(
        fatSecretService: FatSecretFoodAPIService = FatSecretFoodAPIService(),
        usdaService: USDAFoodAPIService = USDAFoodAPIService(),
        openFoodFactsService: OpenFoodFactsAPIService = OpenFoodFactsAPIService(),
        correctionStore: BarcodeCorrectionStoreProtocol? = CustomFoodBarcodeCorrectionStore()
    ) {
        self.fatSecretService = fatSecretService
        self.usdaService = usdaService
        self.openFoodFactsService = openFoodFactsService
        self.correctionStore = correctionStore
    }

    public func lookup(_ barcode: String) async -> BarcodeFoodLookupResult? {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let result = await lookupResult(barcode)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let durationMilliseconds = max(0, Int((elapsed * 1_000).rounded()))
        let outcome = result.map {
            BarcodeLookupOutcome.success($0, durationMilliseconds: durationMilliseconds)
        } ?? BarcodeLookupOutcome.miss(
            barcode: barcode,
            durationMilliseconds: durationMilliseconds
        )
        await MainActor.run {
            DIContainer.shared.analyticsManager?.barcodeLookupOutcome(outcome)
        }
        return result
    }

    private func lookupResult(_ barcode: String) async -> BarcodeFoodLookupResult? {
        let trimmedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard !trimmedBarcode.isEmpty else { return nil }
        let barcodeCandidates = BarcodeCorrectionRules.lookupCandidates(for: trimmedBarcode)

        if let item = await correctionStore?.correctedFood(for: trimmedBarcode) {
            return BarcodeFoodLookupResult(
                item: item,
                source: "custom_barcode",
                scannedBarcode: trimmedBarcode,
                matchedBarcode: item.sourceMetadata?.barcode ?? trimmedBarcode,
                candidateCount: barcodeCandidates.count
            )
        }

        // Query all established providers concurrently for each exact/zero-padded-equivalent
        // GTIN. This avoids exhausting every FatSecret variant before accepting an exact USDA
        // or Open Food Facts hit, while preserving provider preference for the same identifier.
        for candidate in barcodeCandidates {
            let matches = await providerMatches(for: candidate)

            if let item = matches.fatSecret {
                let primary = databaseSourcedItem(
                    item,
                    sourceType: .fatSecret,
                    sourceName: "FatSecret",
                    scannedBarcode: trimmedBarcode,
                    matchedBarcode: candidate
                )
                let confirmedBy: [String]
                if BarcodeCorrectionRules.isValidGTIN(candidate) {
                    confirmedBy = FoodSourceAgreement.agreeingSourceNames(
                        primary: primary,
                        candidates: [
                            ("USDA", matches.usda),
                            ("Open Food Facts", matches.openFoodFacts)
                        ]
                    )
                } else {
                    confirmedBy = []
                }
                let enriched = FoodMicronutrientEnrichment.enrichExactProduct(
                    primary: primary,
                    with: [matches.usda, matches.openFoodFacts]
                )
                return BarcodeFoodLookupResult(
                    item: enriched.withCrossVerification(confirmedBy),
                    source: "barcode_result",
                    scannedBarcode: trimmedBarcode,
                    matchedBarcode: candidate,
                    candidateCount: barcodeCandidates.count
                )
            }

            if let item = matches.usda {
                let primary = databaseSourcedItem(
                    item,
                    sourceType: .usda,
                    sourceName: "USDA FoodData Central",
                    scannedBarcode: trimmedBarcode,
                    matchedBarcode: candidate
                )
                let confirmedBy: [String]
                if BarcodeCorrectionRules.isValidGTIN(candidate) {
                    confirmedBy = FoodSourceAgreement.agreeingSourceNames(
                        primary: primary,
                        candidates: [("Open Food Facts", matches.openFoodFacts)]
                    )
                } else {
                    confirmedBy = []
                }
                let enriched = FoodMicronutrientEnrichment.enrichExactProduct(
                    primary: primary,
                    with: [matches.openFoodFacts]
                )
                return BarcodeFoodLookupResult(
                    item: enriched.withCrossVerification(confirmedBy),
                    source: "usda_barcode",
                    scannedBarcode: trimmedBarcode,
                    matchedBarcode: candidate,
                    candidateCount: barcodeCandidates.count
                )
            }

            if let item = matches.openFoodFacts {
                return BarcodeFoodLookupResult(
                    item: databaseSourcedItem(
                        item,
                        sourceType: .openFoodFacts,
                        sourceName: "Open Food Facts",
                        scannedBarcode: trimmedBarcode,
                        matchedBarcode: candidate
                    ),
                    source: "open_food_facts_barcode",
                    scannedBarcode: trimmedBarcode,
                    matchedBarcode: candidate,
                    candidateCount: barcodeCandidates.count
                )
            }
        }

        // A single community submission is useful recovery evidence, but it is not stronger
        // than an established food database. Keep it as the final fallback after external misses.
        for candidate in barcodeCandidates {
            if let item = await lookupCommunityCorrection(candidate) {
                return BarcodeFoodLookupResult(
                    item: item,
                    source: "community_barcode",
                    scannedBarcode: trimmedBarcode,
                    matchedBarcode: candidate,
                    candidateCount: barcodeCandidates.count
                )
            }
        }

        return nil
    }

    private func providerMatches(for barcode: String) async -> ProviderMatches {
        async let fatSecret = lookupFatSecret(barcode)
        async let usda = usdaService.lookupBarcode(barcode)
        async let openFoodFacts = lookupOpenFoodFacts(barcode)
        return await ProviderMatches(
            fatSecret: fatSecret,
            usda: usda,
            openFoodFacts: openFoodFacts
        )
    }

    private func databaseSourcedItem(
        _ item: FoodItem,
        sourceType: FoodSourceType,
        sourceName: String,
        scannedBarcode: String,
        matchedBarcode: String
    ) -> FoodItem {
        var metadata = FoodSourceMetadata.database(
            sourceType,
            sourceName: sourceName,
            sourceID: item.id,
            barcode: scannedBarcode,
            matchedFoodID: item.id
        )
        if item.sourceMetadata?.sourceType == sourceType,
           let sourceConfidence = item.sourceMetadata?.confidence {
            metadata.confidence = sourceConfidence
        }
        if scannedBarcode != matchedBarcode {
            metadata.notes = "Matched using related barcode \(matchedBarcode)."
        }
        return item.withSourceMetadata(metadata)
    }

    private func lookupCommunityCorrection(_ barcode: String) async -> FoodItem? {
        let dependencies = await MainActor.run { () -> (enabled: Bool, store: CommunityBarcodeStoreProtocol?) in
            let flags: FeatureFlagServiceProtocol? = DIContainer.shared.featureFlagService
            return (
                flags?.boolValue(for: .communityBarcodeCorrections) ?? false,
                DIContainer.shared.communityBarcodeStore
            )
        }
        guard dependencies.enabled, let store = dependencies.store else { return nil }
        return await store.communityFood(for: barcode)
    }

    private func lookupFatSecret(_ barcode: String) async -> FoodItem? {
        await withCheckedContinuation { continuation in
            fatSecretService.fetchFoodByBarcode(barcode: barcode) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    private func lookupOpenFoodFacts(_ barcode: String) async -> FoodItem? {
        await withCheckedContinuation { continuation in
            openFoodFactsService.fetchFoodItem(barcode: barcode) { result in
                guard let item = try? result.get() else {
                    continuation.resume(returning: nil)
                    return
                }
                let returnedBarcode = BarcodeCorrectionRules.normalizedBarcode(
                    item.sourceMetadata?.barcode ?? item.id.replacingOccurrences(of: "off_", with: "")
                )
                let isMatchingProduct = BarcodeCorrectionRules.lookupCandidates(for: barcode)
                    .contains(returnedBarcode)
                continuation.resume(returning: isMatchingProduct ? item : nil)
            }
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
