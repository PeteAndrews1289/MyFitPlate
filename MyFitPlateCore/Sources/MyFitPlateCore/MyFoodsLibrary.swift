import CryptoKit
import Foundation

public enum MyFoodsLibraryFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case barcodeCorrections
    case manual
    case recipes
    case recent
    case needsReview
}

public enum MyFoodsLibrarySort: String, CaseIterable, Hashable, Sendable {
    case name
    case lastUsed
    case trust
}

public struct MyFoodsLibraryEntry: Identifiable, Sendable {
    public let item: FoodItem
    public let lastUsedAt: Date?
    public let descriptor: FoodSourceDescriptor
    public let trust: FoodTrustEvaluation

    public var id: String { item.id }

    public var hasBarcodeAssociation: Bool {
        !(BarcodeCorrectionRules.normalizedBarcode(item.sourceMetadata?.barcode ?? "").isEmpty)
    }

    public var isRecipe: Bool {
        item.sourceMetadata?.sourceType == .recipe ||
            item.sourceMetadata?.originSourceType == .recipe
    }

    public var isManual: Bool {
        guard !hasBarcodeAssociation, !isRecipe else { return false }
        let sourceType = item.sourceMetadata?.originSourceType ?? item.sourceMetadata?.sourceType
        switch sourceType {
        case .manual, .custom, .unknown, nil:
            return true
        default:
            return false
        }
    }

    public var needsReview: Bool {
        if trust.action != nil || trust.requiresCorrection { return true }
        if item.sourceMetadata?.reviewStatus == .unreviewed { return true }
        switch item.sourceMetadata?.confidence {
        case .estimated, .needsReview:
            return true
        default:
            return false
        }
    }
}

public struct MyFoodsDuplicateGroup: Identifiable, Sendable {
    public let keeper: MyFoodsLibraryEntry
    public let duplicates: [MyFoodsLibraryEntry]

    public var id: String { keeper.id }
    public var itemCount: Int { duplicates.count + 1 }
}

public enum MyFoodsLibraryRules {
    public static func isValidSavedSnapshot(_ food: FoodItem) -> Bool {
        guard !food.id.isEmpty, !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [food.calories, food.protein, food.carbs, food.fats, food.servingWeight].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        let optionalValues = [food.saturatedFat, food.polyunsaturatedFat, food.monounsaturatedFat]
            + MicronutrientKey.allCases.map { food.micronutrientValue(for: $0) }
        return optionalValues.compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
            && (try? JSONEncoder().encode(food)) != nil
    }

    /// A new provider copy uses a repeatable identity, so an ambiguous accepted save
    /// can be retried after relaunch. Existing personal IDs are always reused instead.
    public static func savedCopyID(for food: FoodItem) -> String {
        if food.sourceMetadata?.sourceType == .custom {
            return food.sourceMetadata?.sourceID.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? food.id
        }
        let metadata = food.sourceMetadata
        let source = metadata?.originSourceType ?? metadata?.sourceType ?? .unknown
        let originalID = [metadata?.matchedFoodID, metadata?.sourceID, food.id].compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? food.id
        let version = metadata?.sourceUpdatedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "unversioned"
        let digest = SHA256.hash(data: Data("\(source.rawValue)|\(originalID)|\(version)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "custom_copy_\(digest)"
    }

    /// Display names are not product identity. A star/unsave action must target this exact
    /// personal record or a saved copy with matching source lineage.
    public static func savedCopy(of food: FoodItem, in items: [FoodItem]) -> FoodItem? {
        if !food.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let exact = items.first(where: {
               guard $0.id == food.id else { return false }
               guard let incoming = food.sourceMetadata, let saved = $0.sourceMetadata else { return true }
               let incomingSource = incoming.originSourceType ?? incoming.sourceType
               let savedSource = saved.originSourceType ?? saved.sourceType
               if incoming.sourceType != .custom, incoming.sourceType != .manual, incomingSource != .unknown,
                  let originalID = saved.matchedFoodID, !originalID.isEmpty,
                  ![food.id, incoming.sourceID, incoming.matchedFoodID].compactMap({ $0 }).contains(originalID) { return false }
               return incomingSource == savedSource || incomingSource == .unknown || savedSource == .unknown
                   || ([FoodSourceType.manual, .custom].contains(incomingSource) && [.manual, .custom].contains(savedSource))
           }) { return exact }
        guard let metadata = food.sourceMetadata else { return nil }
        let source = metadata.originSourceType ?? metadata.sourceType
        let sourceIDs = Set([food.id, metadata.sourceID, metadata.matchedFoodID].compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return items.first {
            guard let saved = $0.sourceMetadata, let originalID = saved.matchedFoodID,
                  !originalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  saved.sourceUpdatedAt == metadata.sourceUpdatedAt,
                  (saved.originSourceType ?? saved.sourceType) == source else { return false }
            return sourceIDs.contains(originalID)
        }
    }

    public static func entries(
        savedFoods: [FoodItem],
        recentFoods: [FoodItem]
    ) -> [MyFoodsLibraryEntry] {
        savedFoods.map { item in
            let descriptor = FoodSourceClassifier.descriptor(
                for: "custom_food",
                foodID: item.id,
                metadata: item.sourceMetadata
            )
            return MyFoodsLibraryEntry(
                item: item,
                lastUsedAt: lastUsedDate(for: item, recentFoods: recentFoods),
                descriptor: descriptor,
                trust: FoodTrustEvaluation.evaluate(
                    item: item,
                    descriptor: descriptor,
                    metadata: item.sourceMetadata
                )
            )
        }
    }

    public static func visibleEntries(
        _ entries: [MyFoodsLibraryEntry],
        query: String,
        filter: MyFoodsLibraryFilter,
        sort: MyFoodsLibrarySort
    ) -> [MyFoodsLibraryEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = entries.filter { entry in
            let matchesQuery = trimmedQuery.isEmpty ||
                entry.item.name.localizedCaseInsensitiveContains(trimmedQuery) ||
                entry.item.servingSize.localizedCaseInsensitiveContains(trimmedQuery)
            guard matchesQuery else { return false }

            switch filter {
            case .all:
                return true
            case .barcodeCorrections:
                return entry.hasBarcodeAssociation
            case .manual:
                return entry.isManual
            case .recipes:
                return entry.isRecipe
            case .recent:
                return entry.lastUsedAt != nil
            case .needsReview:
                return entry.needsReview
            }
        }

        return filtered.sorted { lhs, rhs in
            switch sort {
            case .name:
                let comparison = lhs.item.name.localizedStandardCompare(rhs.item.name)
                return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
            case .lastUsed:
                switch (lhs.lastUsedAt, rhs.lastUsedAt) {
                case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return stableNameOrder(lhs, rhs)
                }
            case .trust:
                if lhs.trust.score != rhs.trust.score {
                    return lhs.trust.score > rhs.trust.score
                }
                return stableNameOrder(lhs, rhs)
            }
        }
    }

    public static func duplicateGroups(
        from entries: [MyFoodsLibraryEntry]
    ) -> [MyFoodsDuplicateGroup] {
        Dictionary(grouping: entries, by: { DuplicateSignature(item: $0.item) })
            .values
            .filter { $0.count > 1 }
            .compactMap { candidates in
                let ordered = candidates.sorted(by: preferredKeeper)
                guard let keeper = ordered.first else { return nil }
                return MyFoodsDuplicateGroup(
                    keeper: keeper,
                    duplicates: Array(ordered.dropFirst())
                )
            }
            .sorted {
                $0.keeper.item.name.localizedStandardCompare($1.keeper.item.name) == .orderedAscending
            }
    }

    public static func reviewGroups(from entries: [MyFoodsLibraryEntry]) -> [MyFoodsDuplicateGroup] {
        Dictionary(grouping: entries, by: { $0.item.name.folding(options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")).split(whereSeparator: \.isWhitespace).joined(separator: " ") })
            .values.filter { $0.count > 1 }.compactMap { candidates in
                let ordered = candidates.sorted(by: preferredKeeper)
                guard let keeper = ordered.first else { return nil }
                return MyFoodsDuplicateGroup(keeper: keeper, duplicates: Array(ordered.dropFirst()))
            }.sorted { $0.keeper.item.name.localizedStandardCompare($1.keeper.item.name) == .orderedAscending }
    }

    public static func areExactDuplicates(_ foods: [FoodItem]) -> Bool {
        guard let first = foods.first, foods.count >= 2 else { return false }
        let signature = DuplicateSignature(item: first)
        return foods.dropFirst().allSatisfy { DuplicateSignature(item: $0) == signature }
    }

    public static func removingBarcodeAssociation(from item: FoodItem) -> FoodItem {
        guard var metadata = item.sourceMetadata else { return item }
        metadata.barcode = nil
        return item.withSourceMetadata(metadata)
    }

    private static func lastUsedDate(
        for savedFood: FoodItem,
        recentFoods: [FoodItem]
    ) -> Date? {
        recentFoods.compactMap { recent -> Date? in
            let metadata = recent.sourceMetadata
            let referencesSavedFood = recent.id == savedFood.id ||
                metadata?.sourceID == savedFood.id ||
                metadata?.matchedFoodID == savedFood.id
            return referencesSavedFood ? recent.timestamp : nil
        }
        .max()
    }

    private static func preferredKeeper(
        _ lhs: MyFoodsLibraryEntry,
        _ rhs: MyFoodsLibraryEntry
    ) -> Bool {
        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.trust.score != rhs.trust.score {
                return lhs.trust.score > rhs.trust.score
            }
            return lhs.id < rhs.id
        }
    }

    private static func stableNameOrder(
        _ lhs: MyFoodsLibraryEntry,
        _ rhs: MyFoodsLibraryEntry
    ) -> Bool {
        let comparison = lhs.item.name.localizedStandardCompare(rhs.item.name)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }

    private struct DuplicateSignature: Hashable {
        let name: String
        let serving: String
        let servingUnit: String
        let barcode: String
        let sourceCategory: String
        let brand: String
        let lineage: String?
        let values: [UInt64?]

        init(item: FoodItem) {
            name = Self.normalized(item.name)
            serving = Self.normalized(item.servingSize)
            servingUnit = Self.normalized(item.servingUnit ?? "")
            barcode = BarcodeCorrectionRules.normalizedBarcode(item.sourceMetadata?.barcode ?? "")
            sourceCategory = (
                item.sourceMetadata?.originSourceType ?? item.sourceMetadata?.sourceType
            )?.rawValue ?? "unknown"
            brand = Self.normalized(item.sourceMetadata?.brandName ?? "")
            var source = RecipePortionRules.revisionIngredient(item).sourceMetadata
            if source?.sourceType == .custom {
                source?.sourceID = nil
                if source?.originSourceType == nil || source?.originSourceType == .custom || source?.originSourceType == .manual,
                   source?.matchedFoodID == item.id { source?.matchedFoodID = nil }
            }
            lineage = try? PlanFingerprint.make(source)
            values = [
                item.calories, item.protein, item.carbs, item.fats, item.saturatedFat,
                item.polyunsaturatedFat, item.monounsaturatedFat, item.fiber,
                item.servingWeight, item.calcium, item.iron, item.potassium, item.sodium,
                item.vitaminA, item.vitaminC, item.vitaminD, item.vitaminB12, item.folate,
                item.magnesium, item.phosphorus, item.zinc, item.copper, item.manganese,
                item.selenium, item.vitaminB1, item.vitaminB2, item.vitaminB3,
                item.vitaminB5, item.vitaminB6, item.vitaminE, item.vitaminK,
                item.quantityValue
            ].map(Self.bits)
        }

        private static func normalized(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
        }

        private static func bits(_ value: Double?) -> UInt64? {
            guard let value else { return nil }
            return value == 0 ? 0 : value.bitPattern
        }
    }
}
