import Foundation

public enum AYCERepeatRules {
    /// Positive additions since the last round marker; removals are never repeated.
    public static func currentRound(_ session: AYCESession) -> [AYCESessionEntry] {
        session.entries.compactMap { entry in
            let baseline = session.roundBaseline?.first { $0.id == entry.id }?.count ?? 0
            let amount = entry.count - baseline
            guard AYCEPortionRules.isValid(amount) else { return nil }
            return AYCESessionEntry(id: entry.id, item: entry.item, count: amount)
        }
    }
    public static func finishingRound(_ session: AYCESession) -> AYCESession? {
        guard session.endedAt == nil, session.submittedAt == nil else { return nil }
        let entries = currentRound(session)
        guard !entries.isEmpty else { return nil }
        var result = session
        result.lastRound = entries
        result.roundBaseline = session.entries
        return result
    }
    public static func repeatingLastRound(_ session: AYCESession) -> AYCESession? {
        guard session.endedAt == nil, session.submittedAt == nil, currentRound(session).isEmpty,
              let entries = session.lastRound, !entries.isEmpty else { return nil }
        var result = session
        for entry in entries {
            guard entry.item.cuisine == session.cuisine, AYCEPortionRules.isValid(entry.count) else { return nil }
            if let index = result.entries.firstIndex(where: { $0.item.id == entry.item.id }) {
                guard result.entries[index].item == entry.item else { return nil }
                let amount = result.entries[index].count + entry.count
                guard AYCEPortionRules.isValid(amount) else { return nil }
                result.entries[index].count = amount
            } else { result.entries.append(AYCESessionEntry(item: entry.item, count: entry.count)) }
        }
        result.roundBaseline = result.entries
        return result
    }
}

/// Device-local preferences are scoped to the signed-in account. Restaurant cuts
/// alter the piece conversion only: a roll cut into six still has one roll's nutrition.
@MainActor
public final class AYCEPreferences {
    private struct Values: Codable {
        var favorites: Set<String> = []
        var cuts: [String: Int] = [:]
    }
    private let defaults: UserDefaults
    private let key: String?
    public init(userID: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = AccountScopedStorageKey.make(prefix: "aycePreferences", userID: userID)
    }
    private var values: Values {
        guard let key, let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Values.self, from: data) else { return Values() }
        return value
    }
    private func save(_ values: Values) {
        guard let key, let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: key)
    }
    public func isFavorite(_ id: String) -> Bool { values.favorites.contains(id) }
    public func toggleFavorite(_ id: String) {
        var next = values
        if !next.favorites.insert(id).inserted { next.favorites.remove(id) }
        save(next)
    }
    public func rememberCut(_ pieces: Int, for item: AYCECatalogItem, restaurant: String) {
        guard (2...24).contains(pieces), (item.piecesPerUnit ?? 0) > 1, let key = cutKey(item, restaurant) else { return }
        var next = values
        next.cuts[key] = pieces
        save(next)
    }
    public func resolve(_ item: AYCECatalogItem, restaurant: String?) -> AYCECatalogItem {
        guard let restaurant, let key = cutKey(item, restaurant), let pieces = values.cuts[key] else { return item }
        return AYCEPortionRules.changingCut(of: item, pieces: pieces) ?? item
    }
    private func cutKey(_ item: AYCECatalogItem, _ restaurant: String) -> String? {
        let restaurant = restaurant.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return restaurant.isEmpty ? nil : "\(item.cuisine.rawValue)|\(restaurant)|\(item.id)"
    }
}

public extension AYCEPortionRules {
    static func changingCut(of item: AYCECatalogItem, pieces: Int) -> AYCECatalogItem? {
        guard (item.piecesPerUnit ?? 0) > 1, (2...24).contains(pieces) else { return nil }
        return AYCECatalogItem(id: item.id, cuisine: item.cuisine, name: item.name, emoji: item.emoji,
                               unit: "roll (\(pieces) pc)", calories: item.calories, protein: item.protein,
                               carbs: item.carbs, fats: item.fats, restaurantPrice: item.restaurantPrice,
                               homeCost: item.homeCost, isAIEstimated: item.isAIEstimated,
                               isLocallyPriced: item.isLocallyPriced, piecesPerUnit: pieces,
                               cookedGramsPerUnit: item.cookedGramsPerUnit, catalogMatch: item.catalogMatch)
    }
    static func personalShare(quantity: Double, diners: Int) -> Double? {
        guard (1...20).contains(diners), quantity.isFinite, quantity > 0 else { return nil }
        let personal = quantity / Double(diners)
        return isValid(personal) ? personal : nil
    }
}
