import Foundation

/// Short-lived catalog responses only. Personal foods and log destinations are never stored
/// here; the owner clears this in-memory cache when the signed-in account changes.
public struct FoodSearchResultCache {
    public enum Provider: Int, CaseIterable, Hashable, Sendable {
        case fatSecret, usda, healthCanada, openFoodFacts, supplements

        public static let primary: Set<Provider> = [.fatSecret, .usda, .healthCanada]
    }

    private struct Entry {
        var foods: [FoodItem]
        var fetchedAt: Date
    }

    private var entries: [String: [Provider: Entry]] = [:]
    private var recentKeys: [String] = []
    private let lifetime: TimeInterval
    private let capacity: Int

    public init(lifetime: TimeInterval = 300, capacity: Int = 12) {
        self.lifetime = max(0, lifetime)
        self.capacity = max(0, capacity)
    }

    /// Preserve product qualifiers such as 2%, zero-sugar and punctuation. Only case and
    /// whitespace are equivalent; sharing a cache entry must not widen the requested food.
    public static func queryKey(_ query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public mutating func batches(for query: String, now: Date = Date()) -> [Provider: [FoodItem]] {
        let key = Self.queryKey(query)
        guard let stored = entries[key] else { return [:] }
        let fresh = stored.filter { entry in
            let age = now.timeIntervalSince(entry.value.fetchedAt)
            return age >= 0 && age < lifetime
        }
        if fresh.isEmpty {
            entries.removeValue(forKey: key)
            recentKeys.removeAll { $0 == key }
            return [:]
        }
        entries[key] = fresh
        touch(key)
        return fresh.mapValues(\.foods)
    }

    /// Call only for a successfully completed provider, including its honest empty result.
    /// Failed or cancelled work is not a reusable response.
    public mutating func store(_ foods: [FoodItem], for query: String, provider: Provider, now: Date = Date()) {
        let key = Self.queryKey(query)
        guard capacity > 0, lifetime > 0, !key.isEmpty else { return }
        entries[key, default: [:]][provider] = Entry(foods: foods, fetchedAt: now)
        touch(key)
        while recentKeys.count > capacity {
            entries.removeValue(forKey: recentKeys.removeFirst())
        }
    }

    public mutating func removeAll() {
        entries.removeAll()
        recentKeys.removeAll()
    }

    private mutating func touch(_ key: String) {
        recentKeys.removeAll { $0 == key }
        recentKeys.append(key)
    }
}
