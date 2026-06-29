import Foundation

public enum SmartSuggestionBuilder {
    public static func uniqueRecentFoods(from items: [FoodItem], limit: Int = 5) -> [FoodItem] {
        var uniqueItems: [FoodItem] = []
        var seenNames = Set<String>()

        for item in items {
            let lowerName = item.name.lowercased()
            guard !seenNames.contains(lowerName) else { continue }

            seenNames.insert(lowerName)
            uniqueItems.append(item)

            if uniqueItems.count == limit {
                break
            }
        }

        return uniqueItems
    }
}
