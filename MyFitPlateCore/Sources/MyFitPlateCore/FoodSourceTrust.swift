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
        userCorrection: FoodNutritionSnapshot? = nil
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
                confidence: "User Verified",
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
                detail: reviewAwareDetail(
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
                detail: reviewAwareDetail(
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
                detail: reviewAwareDetail(
                    metadata,
                    defaultDetail: "Matched from a public packaged-food database."
                ),
                confidence: confidenceText(for: metadata),
                systemImage: "barcode.viewfinder"
            )

        case .aiImage, .aiMenu, .aiText, .aiChat:
            return aiDescriptor(for: metadata)

        case .manual, .custom:
            if metadata.barcode?.isEmpty == false {
                return FoodSourceDescriptor(
                    sourceKey: "custom_barcode",
                    title: "My Foods Match",
                    detail: reviewAwareDetail(
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
                detail: "Entered or saved by you.",
                confidence: confidenceText(for: metadata),
                systemImage: "person.crop.circle.badge.checkmark"
            )

        case .recipe, .mealPlan:
            return FoodSourceDescriptor(
                sourceKey: "planned",
                title: "Planned Food",
                detail: "Built from your recipes or meal plan.",
                confidence: confidenceText(for: metadata),
                systemImage: "list.clipboard.fill"
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
            detail: reviewAwareDetail(metadata, defaultDetail: detail),
            confidence: confidenceText(for: metadata),
            systemImage: "sparkles",
            isEstimated: true
        )
    }

    private static func reviewAwareDetail(_ metadata: FoodSourceMetadata, defaultDetail: String) -> String {
        switch metadata.reviewStatus {
        case .userEdited:
            return "\(defaultDetail) Edited by you."
        case .userConfirmed:
            return "\(defaultDetail) Reviewed by you."
        case .notRequired, .unreviewed:
            return defaultDetail
        }
    }

    private static func confidenceText(for metadata: FoodSourceMetadata) -> String {
        switch metadata.reviewStatus {
        case .userEdited:
            return "User Edited"
        case .userConfirmed:
            return metadata.confidence == .estimated ? "User Reviewed" : "User Verified"
        case .notRequired, .unreviewed:
            break
        }

        switch metadata.confidence {
        case .verified:
            return "High Trust"
        case .databaseMatch:
            return "Database Match"
        case .estimated, .needsReview:
            return "Needs Review"
        case .userVerified:
            return "User Verified"
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

    func markedUserConfirmed(sourceType fallbackSourceType: FoodSourceType? = nil) -> FoodItem {
        withReviewStatus(.userConfirmed, fallbackSourceType: fallbackSourceType)
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

    public init(item: FoodItem, source: String) {
        self.item = item
        self.source = source
    }
}

public enum BarcodeCorrectionRules {
    public static func normalizedBarcode(_ barcode: String) -> String {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        return digits.isEmpty ? trimmed : String(digits)
    }

    public static func bestCorrectedFood(in foods: [FoodItem], barcode: String) -> FoodItem? {
        let normalized = normalizedBarcode(barcode)
        guard !normalized.isEmpty else { return nil }

        return foods
            .filter { matches($0, barcode: normalized) }
            .sorted { correctionScore(for: $0) > correctionScore(for: $1) }
            .first
            .map { correctedFood(from: $0, barcode: normalized) }
    }

    public static func matches(_ food: FoodItem, barcode: String) -> Bool {
        guard let foodBarcode = food.sourceMetadata?.barcode else { return false }
        return normalizedBarcode(foodBarcode) == normalizedBarcode(barcode)
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
        let trimmedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard !trimmedBarcode.isEmpty else { return nil }

        if let item = await correctionStore?.correctedFood(for: trimmedBarcode) {
            return BarcodeFoodLookupResult(
                item: item,
                source: "custom_barcode"
            )
        }

        if let item = await lookupFatSecret(trimmedBarcode) {
            return BarcodeFoodLookupResult(
                item: item.withDatabaseSource(
                    .fatSecret,
                    sourceName: "FatSecret",
                    barcode: trimmedBarcode
                ),
                source: "barcode_result"
            )
        }

        if let item = await usdaService.lookupBarcode(trimmedBarcode) {
            return BarcodeFoodLookupResult(
                item: item.withDatabaseSource(
                    .usda,
                    sourceName: "USDA FoodData Central",
                    barcode: trimmedBarcode
                ),
                source: "usda_barcode"
            )
        }

        if let item = await lookupOpenFoodFacts(trimmedBarcode) {
            return BarcodeFoodLookupResult(
                item: item.withDatabaseSource(
                    .openFoodFacts,
                    sourceName: "Open Food Facts",
                    barcode: trimmedBarcode
                ),
                source: "open_food_facts_barcode"
            )
        }

        return nil
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
                continuation.resume(returning: try? result.get())
            }
        }
    }
}
