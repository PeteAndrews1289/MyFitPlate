import Foundation

public struct BuffetPersonalCatalog: Codable, Equatable {
    public var hiddenIDs: [String] = []
    public var restaurantRecents: [String: [String]] = [:]
    public var customFavorites: [AYCECatalogItem] = []
    public var customFavoriteRestaurants: [String: String]?
    public init() {}
    public static func restaurantKey(_ name: String?) -> String? {
        guard let text = name?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public mutating func record(_ item: AYCECatalogItem, restaurant: String?) {
        guard let key = Self.restaurantKey(restaurant) else { return }
        var ids = restaurantRecents[key] ?? []; ids.removeAll { $0 == item.id }; ids.insert(item.id, at: 0)
        restaurantRecents[key] = Array(ids.prefix(30))
    }
}

public final class BuffetPersonalCatalogStore {
    private let drafts: EditorDraftStore
    private let userID: String
    public init(userID: String, drafts: EditorDraftStore = EditorDraftStore()) { self.userID = userID; self.drafts = drafts }
    public func load() throws -> BuffetPersonalCatalog {
        try drafts.load(BuffetPersonalCatalog.self, userID: userID, scope: "buffet-personal-catalog")?.value ?? BuffetPersonalCatalog()
    }
    public func save(_ next: BuffetPersonalCatalog, replacing old: BuffetPersonalCatalog) throws {
        guard try load() == old, next.customFavorites.count <= 100 else { throw CocoaError(.fileWriteFileExists) }
        try drafts.save(next, userID: userID, scope: "buffet-personal-catalog")
    }
}
