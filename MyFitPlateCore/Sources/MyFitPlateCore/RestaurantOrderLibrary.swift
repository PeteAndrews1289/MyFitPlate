import Foundation

/// Packaged, offline estimates. Source publication dates are deliberately not inferred
/// from the date the app's package was assembled.
public struct RestaurantCatalogEvidence: Codable, Equatable {
    public let version: String
    public let assembledLabel: String
    public let market: String
    public let publicationDate: Date?
    public let sourceURL: URL?
    public let limitations: String
    public init(chainID: String) {
        version = ChainRestaurantCatalog.catalogVersion
        assembledLabel = ChainRestaurantCatalog.lastUpdatedDate
        market = "US reference menu"
        publicationDate = nil
        sourceURL = ChainRestaurantCatalog.officialNutritionURL(for: chainID)
        limitations = "Offline reference estimates, not a live menu. Publication date and local availability are unverified. Portion sizes, recipes and limited-time items may differ."
    }
}

public struct SavedRestaurantOrder: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var chainID: String
    public var chainName: String
    public var catalogVersion: String
    public var components: [ChainSelectionItem]
    public var mealName: String
    public var savedAt: Date
    public init(id: UUID = UUID(), name: String, chain: ChainRestaurant,
                components: [ChainSelectionItem], mealName: String, savedAt: Date = Date()) {
        self.id = id; self.name = name; chainID = chain.id; chainName = chain.name
        catalogVersion = ChainRestaurantCatalog.catalogVersion
        self.components = components; self.mealName = mealName; self.savedAt = savedAt
    }
    public func catalogChanges(in chain: ChainRestaurant) -> [String] {
        let current = Dictionary(uniqueKeysWithValues: chain.categories.flatMap(\.ingredients).map { ($0.id, $0) })
        return components.compactMap { component in
            guard let now = current[component.id] else { return "\(component.ingredient.name): no longer in this package" }
            return now == component.ingredient ? nil : "\(component.ingredient.name): nutrition or portion changed"
        }
    }
    public func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
              (1...80).contains(components.count), Set(components.map(\.id)).count == components.count,
              components.allSatisfy({ $0.totalMultiplier.isFinite && $0.totalMultiplier > 0 &&
                  (1...$0.ingredient.maximumCount).contains($0.count) &&
                  [$0.calories, $0.protein, $0.carbs, $0.fat].allSatisfy { $0.isFinite && $0 >= 0 } }) else {
            throw CocoaError(.coderInvalidValue)
        }
        return self
    }
}

public struct RestaurantOrderWorkspace: Codable, Equatable {
    public var orders: [SavedRestaurantOrder] = []
    public var draft: SavedRestaurantOrder?
    public var favoriteChainIDs: [String] = []
    public var recentChainIDs: [String] = []
    public init() {}
}

/// A device-local workspace. CAS protects another open editor and unreadable drafts.
public final class RestaurantOrderStore {
    private let drafts: EditorDraftStore
    public let userID: String
    public let scope = "restaurant-order-workspace"
    public init(userID: String, drafts: EditorDraftStore = EditorDraftStore()) { self.userID = userID; self.drafts = drafts }
    public func load() throws -> RestaurantOrderWorkspace {
        try drafts.load(RestaurantOrderWorkspace.self, userID: userID, scope: scope)?.value ?? RestaurantOrderWorkspace()
    }
    public func save(_ value: RestaurantOrderWorkspace, replacing original: RestaurantOrderWorkspace) throws {
        guard try load() == original, value.orders.count <= 100 else { throw CocoaError(.fileWriteFileExists) }
        for order in value.orders { _ = try order.validated() }
        if let draft = value.draft { _ = try draft.validated() }
        try drafts.save(value, userID: userID, scope: scope)
    }
}

/// Deterministic distributable representation of the built-in package. A future package
/// is installed only after validating the complete candidate; callers retain the old
/// package on failure and saved orders remain pinned to their own component snapshots.
public struct RestaurantCatalogPackage: Codable, Equatable {
    public struct Item: Codable, Equatable {
        public var chainID: String
        public var categoryID: String
        public var ingredient: ChainIngredient
        public var evidence: RestaurantCatalogEvidence
    }
    public var version: String
    public var items: [Item]
    public static func bundled() -> Self {
        Self(version: ChainRestaurantCatalog.catalogVersion, items: ChainRestaurantCatalog.allChains.flatMap { chain in
            chain.categories.flatMap { category in category.ingredients.map {
                Item(chainID: chain.id, categoryID: category.id, ingredient: $0, evidence: RestaurantCatalogEvidence(chainID: chain.id))
            } }
        })
    }
    public func validate() throws {
        guard !version.isEmpty, !items.isEmpty, Set(items.map { "\($0.chainID)|\($0.ingredient.id)" }).count == items.count,
              items.allSatisfy({ !$0.ingredient.name.isEmpty && !$0.ingredient.servingDescription.isEmpty &&
                  !$0.evidence.market.isEmpty && $0.evidence.version == version && $0.evidence.sourceURL != nil &&
                  [$0.ingredient.calories, $0.ingredient.protein, $0.ingredient.carbs, $0.ingredient.fat, $0.ingredient.fiber].allSatisfy { $0.isFinite && $0 >= 0 } &&
                  $0.ingredient.sodium.map { $0.isFinite && $0 >= 0 } != false }) else { throw CocoaError(.coderInvalidValue) }
    }
    public func replacing(with candidate: Self) throws -> Self { try candidate.validate(); return candidate }
}
