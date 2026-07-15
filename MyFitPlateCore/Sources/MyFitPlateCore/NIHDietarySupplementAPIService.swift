import Foundation

public final class NIHDietarySupplementAPIService {
    private let cloudFunctionService: CloudFunctionServiceProtocol?

    public init(cloudFunctionService: CloudFunctionServiceProtocol? = nil) {
        self.cloudFunctionService = cloudFunctionService
    }

    public func searchSupplements(query: String, limit: Int = 6) async -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard await isFeatureEnabled() else { return [] }
        guard let service = await resolvedCloudFunctionService() else { return [] }

        do {
            let payload = try await service.callFunction(
                "nihSupplementSearch",
                with: ["query": trimmed, "limit": min(max(limit, 1), 8)]
            )
            let data = try Self.jsonData(from: payload)
            return try NIHDietarySupplementParser.foodItems(from: data)
        } catch {
            AppLog.data.error("NIH supplement search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func lookupBarcode(_ barcode: String) async -> FoodItem? {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard (8...14).contains(normalized.count) else { return nil }
        guard await isFeatureEnabled() else { return nil }
        guard let service = await resolvedCloudFunctionService() else { return nil }

        do {
            let payload = try await service.callFunction(
                "nihSupplementBarcodeLookup",
                with: ["barcode": normalized]
            )
            guard let payload, !(payload is NSNull) else { return nil }
            let data = try Self.jsonData(from: payload)
            return try NIHDietarySupplementParser.foodItem(from: data)
        } catch {
            AppLog.data.error("NIH supplement barcode lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
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
            DIContainer.shared.featureFlagService?.boolValue(for: .nihSupplementLabels)
                ?? FeatureFlag.nihSupplementLabels.defaultValue
        }
    }
}

public enum NIHDietarySupplementParser {
    public static func foodItems(from data: Data, observedAt: Date = Date()) throws -> [FoodItem] {
        try JSONDecoder()
            .decode([NIHDietarySupplementRecord].self, from: data)
            .map { foodItem(from: $0, observedAt: observedAt) }
    }

    public static func foodItem(from data: Data, observedAt: Date = Date()) throws -> FoodItem {
        foodItem(
            from: try JSONDecoder().decode(NIHDietarySupplementRecord.self, from: data),
            observedAt: observedAt
        )
    }

    private static func foodItem(
        from record: NIHDietarySupplementRecord,
        observedAt: Date
    ) -> FoodItem {
        let nutrient = record.nutrients
        let item = FoodItem(
            id: record.id,
            name: record.name,
            calories: nutrient["calories"] ?? 0,
            protein: nutrient["protein"] ?? 0,
            carbs: nutrient["carbs"] ?? 0,
            fats: nutrient["fat"] ?? 0,
            fiber: nutrient["fiber"],
            servingSize: record.servingSize,
            servingWeight: 0,
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
            vitaminK: nutrient["vitaminK"],
            // Nutrition is reported per complete label serving (for example, 2 capsules).
            // FoodDetail's quantity is a multiplier of that base serving, not a capsule count.
            quantityValue: 1,
            servingUnit: "serving"
        )

        var metadata = FoodSourceMetadata.database(
            .nihDSLD,
            sourceName: "NIH DSLD",
            sourceID: record.id,
            barcode: record.barcode,
            evidenceLineage: .manufacturerLabel
        )
        metadata.confidence = .databaseMatch
        metadata.sourceObservedAt = observedAt
        var notes = ["Current manufacturer supplement label record; not laboratory verification"]
        notes.append("Label serving: \(record.quantityValue.formatted()) \(record.servingUnit)")
        if let productType = record.productType, !productType.isEmpty {
            notes.append(productType)
        }
        if let entryDate = record.entryDate, !entryDate.isEmpty {
            notes.append("Entered in NIH DSLD \(entryDate)")
        }
        metadata.notes = notes.joined(separator: ". ") + "."
        return item.withSourceMetadata(metadata)
    }
}

private struct NIHDietarySupplementRecord: Decodable {
    let id: String
    let name: String
    let servingSize: String
    let quantityValue: Double
    let servingUnit: String
    let barcode: String?
    let entryDate: String?
    let productType: String?
    let micronutrientCount: Int
    let nutrients: [String: Double]
}
