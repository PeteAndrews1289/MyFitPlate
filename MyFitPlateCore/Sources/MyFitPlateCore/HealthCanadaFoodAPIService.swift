import Foundation

public final class HealthCanadaFoodAPIService {
    private let cloudFunctionService: CloudFunctionServiceProtocol?

    public init(cloudFunctionService: CloudFunctionServiceProtocol? = nil) {
        self.cloudFunctionService = cloudFunctionService
    }

    public func searchFoods(query: String, limit: Int = 12) async -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard await isFeatureEnabled() else { return [] }
        guard let service = await resolvedCloudFunctionService() else { return [] }

        do {
            let payload = try await service.callFunction(
                "healthCanadaFoodSearch",
                with: ["query": trimmed, "limit": min(max(limit, 1), 20)]
            )
            let data = try Self.jsonData(from: payload)
            return try HealthCanadaFoodParser.foodItems(from: data)
        } catch {
            AppLog.data.error("Health Canada food search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func jsonData(from payload: Any?) throws -> Data {
        guard let payload, !(payload is NSNull), JSONSerialization.isValidJSONObject(payload) else {
            throw APIError.noData
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func resolvedCloudFunctionService() async -> CloudFunctionServiceProtocol? {
        if let cloudFunctionService {
            return cloudFunctionService
        }
        return await MainActor.run { DIContainer.shared.cloudFunctionService }
    }

    private func isFeatureEnabled() async -> Bool {
        await MainActor.run {
            DIContainer.shared.featureFlagService?.boolValue(for: .healthCanadaFoodSearch)
                ?? FeatureFlag.healthCanadaFoodSearch.defaultValue
        }
    }
}

public enum HealthCanadaFoodParser {
    public static func foodItems(from data: Data, observedAt: Date = Date()) throws -> [FoodItem] {
        try JSONDecoder()
            .decode([HealthCanadaFoodRecord].self, from: data)
            .map { foodItem(from: $0, observedAt: observedAt) }
    }

    private static func foodItem(from record: HealthCanadaFoodRecord, observedAt: Date) -> FoodItem {
        let nutrient = record.nutrients
        let item = FoodItem(
            id: record.id,
            name: record.name,
            calories: nutrient["calories"] ?? 0,
            protein: nutrient["protein"] ?? 0,
            carbs: nutrient["carbs"] ?? 0,
            fats: nutrient["fat"] ?? 0,
            saturatedFat: nutrient["saturatedFat"],
            polyunsaturatedFat: nutrient["polyunsaturatedFat"],
            monounsaturatedFat: nutrient["monounsaturatedFat"],
            fiber: nutrient["fiber"],
            servingSize: record.servingSize,
            servingWeight: record.servingWeight,
            calcium: nutrient["calcium"],
            iron: nutrient["iron"],
            potassium: nutrient["potassium"],
            sodium: nutrient["sodium"],
            vitaminA: nutrient["vitaminA"],
            vitaminC: nutrient["vitaminC"],
            vitaminD: nutrient["vitaminD"],
            vitaminB12: nutrient["vitaminB12"],
            folate: nutrient["folate"],
            magnesium: nutrient["magnesium"],
            phosphorus: nutrient["phosphorus"],
            zinc: nutrient["zinc"],
            copper: nutrient["copper"],
            manganese: nutrient["manganese"],
            selenium: nutrient["selenium"],
            vitaminB1: nutrient["vitaminB1"],
            vitaminB2: nutrient["vitaminB2"],
            vitaminB3: nutrient["vitaminB3"],
            vitaminB5: nutrient["vitaminB5"],
            vitaminB6: nutrient["vitaminB6"],
            vitaminE: nutrient["vitaminE"],
            vitaminK: nutrient["vitaminK"]
        )

        var metadata = FoodSourceMetadata.database(
            .healthCanadaCNF,
            sourceName: "Health Canada CNF",
            sourceID: record.id,
            evidenceLineage: .governmentCompilation,
            sourceUpdatedAt: fullDate(record.datasetRelease)
        )
        metadata.confidence = .databaseMatch
        metadata.sourceObservedAt = observedAt
        metadata.notes = [
            record.foodSourceSummary,
            "Canadian Nutrient File release \(record.datasetRelease)",
            "Food record last revised \(record.recordUpdatedAt)"
        ].joined(separator: ". ") + "."
        return item.withSourceMetadata(metadata)
    }

    private static func fullDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }
}

private struct HealthCanadaFoodRecord: Decodable {
    let id: String
    let name: String
    let servingSize: String
    let servingWeight: Double
    let nutrients: [String: Double]
    let datasetRelease: String
    let recordUpdatedAt: String
    let foodSourceCode: Int
    let foodSourceSummary: String
    let micronutrientCount: Int
}
