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
        let values: [UInt64?]

        init(item: FoodItem) {
            name = Self.normalized(item.name)
            serving = Self.normalized(item.servingSize)
            servingUnit = Self.normalized(item.servingUnit ?? "")
            barcode = BarcodeCorrectionRules.normalizedBarcode(item.sourceMetadata?.barcode ?? "")
            sourceCategory = (
                item.sourceMetadata?.originSourceType ?? item.sourceMetadata?.sourceType
            )?.rawValue ?? "unknown"
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
