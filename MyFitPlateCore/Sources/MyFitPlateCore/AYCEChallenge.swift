import Foundation

/// "Beat the buffet": during an all-you-can-eat session the user logs what they eat and
/// watches the à-la-carte value climb past what they paid. Prices are typical US menu
/// estimates from a curated catalog — always presented as estimates, never as fact
/// (same honesty rules as the food-data trust layer).
public enum AYCECuisine: String, Codable, CaseIterable, Sendable {
    case sushi
    case kbbq
    case hotpot

    public var displayName: String {
        switch self {
        case .sushi: return "Sushi"
        case .kbbq: return "Korean BBQ"
        case .hotpot: return "Hot pot"
        }
    }

    public var emoji: String {
        switch self {
        case .sushi: return "🍣"
        case .kbbq: return "🥩"
        case .hotpot: return "🍲"
        }
    }
}

/// One orderable thing from the catalog: per-unit nutrition plus what it typically costs
/// à la carte and what the ingredients run at home.
public struct AYCECatalogItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let cuisine: AYCECuisine
    public let name: String
    public let emoji: String
    /// "piece", "roll (6 pc)", "plate", "serving", "bowl" — shown after the count.
    public let unit: String
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    /// Typical US à-la-carte menu price per unit.
    public let restaurantPrice: Double
    /// Approximate grocery cost per unit to make it yourself.
    public let homeCost: Double

    public init(
        id: String, cuisine: AYCECuisine, name: String, emoji: String, unit: String,
        calories: Double, protein: Double, carbs: Double, fats: Double,
        restaurantPrice: Double, homeCost: Double
    ) {
        self.id = id
        self.cuisine = cuisine
        self.name = name
        self.emoji = emoji
        self.unit = unit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.restaurantPrice = restaurantPrice
        self.homeCost = homeCost
    }
}

/// A logged line in a session: a catalog item (or a custom/photo-estimated one) times a count.
public struct AYCESessionEntry: Codable, Identifiable, Equatable {
    public let id: String
    public var item: AYCECatalogItem
    public var count: Int

    public init(id: String = UUID().uuidString, item: AYCECatalogItem, count: Int) {
        self.id = id
        self.item = item
        self.count = count
    }

    public var restaurantValue: Double { item.restaurantPrice * Double(count) }
    public var homeValue: Double { item.homeCost * Double(count) }
    public var calories: Double { item.calories * Double(count) }
}

public struct AYCESession: Codable, Identifiable, Equatable {
    public let id: String
    public var cuisine: AYCECuisine
    /// What the user is paying for the buffet.
    public var buffetPrice: Double
    public var startedAt: Date
    public var entries: [AYCESessionEntry]

    public init(
        id: String = UUID().uuidString,
        cuisine: AYCECuisine,
        buffetPrice: Double,
        startedAt: Date = Date(),
        entries: [AYCESessionEntry] = []
    ) {
        self.id = id
        self.cuisine = cuisine
        self.buffetPrice = buffetPrice
        self.startedAt = startedAt
        self.entries = entries
    }
}

public enum AYCERules {

    public struct Totals: Equatable {
        public let restaurantValue: Double
        public let homeCost: Double
        public let calories: Double
        public let protein: Double
        public let carbs: Double
        public let fats: Double
        public let itemCount: Int
    }

    public static func totals(for session: AYCESession) -> Totals {
        Totals(
            restaurantValue: session.entries.reduce(0) { $0 + $1.restaurantValue },
            homeCost: session.entries.reduce(0) { $0 + $1.homeValue },
            calories: session.entries.reduce(0) { $0 + $1.calories },
            protein: session.entries.reduce(0) { $0 + $1.item.protein * Double($1.count) },
            carbs: session.entries.reduce(0) { $0 + $1.item.carbs * Double($1.count) },
            fats: session.entries.reduce(0) { $0 + $1.item.fats * Double($1.count) },
            itemCount: session.entries.reduce(0) { $0 + $1.count }
        )
    }

    /// Fraction of the buffet price eaten back, uncapped (1.4 = 140% of what you paid).
    public static func breakEvenProgress(session: AYCESession) -> Double {
        guard session.buffetPrice > 0 else { return 0 }
        return totals(for: session).restaurantValue / session.buffetPrice
    }

    /// Dollars of à-la-carte value beyond the buffet price; negative while still behind.
    public static func beatByAmount(session: AYCESession) -> Double {
        totals(for: session).restaurantValue - session.buffetPrice
    }

    /// The live status line. DESIGN.md §5: sentence case, no exclamation marks —
    /// the number does the celebrating.
    public static func statusLine(session: AYCESession) -> String {
        let delta = beatByAmount(session: session)
        if delta >= 0 {
            return "You beat the spot by \(money(delta))"
        }
        let progress = breakEvenProgress(session: session)
        if progress >= 0.85 {
            return "\(money(-delta)) from breaking even — so close"
        }
        return "\(money(-delta)) to break even"
    }

    /// The end-of-session verdict headline.
    public static func verdictHeadline(session: AYCESession) -> String {
        let delta = beatByAmount(session: session)
        if delta >= 0 {
            return "You beat the spot by \(money(delta))"
        }
        return "The spot won this round by \(money(-delta))"
    }

    /// The secondary honesty line: what this meal would have cost from the grocery store.
    public static func homeCostLine(session: AYCESession) -> String {
        "Cooking this at home: about \(money(totals(for: session).homeCost))"
    }

    public static func money(_ amount: Double) -> String {
        String(format: "$%.2f", max(0, amount))
    }

    /// Bridges a session entry into the daily food log. The whole count collapses into one
    /// FoodItem line ("Salmon nigiri ×4") so the diary stays readable.
    public static func foodItem(from entry: AYCESessionEntry) -> FoodItem {
        let count = Double(entry.count)
        let name = entry.count > 1 ? "\(entry.item.name) ×\(entry.count)" : entry.item.name
        return FoodItem(
            id: "ayce_\(entry.id)",
            name: name,
            calories: entry.item.calories * count,
            protein: entry.item.protein * count,
            carbs: entry.item.carbs * count,
            fats: entry.item.fats * count,
            servingSize: "\(entry.count) \(entry.item.unit)",
            sourceMetadata: .userEntered(sourceName: "Beat the buffet")
        )
    }

    /// The diary meal name a session logs under.
    public static func mealName(for cuisine: AYCECuisine) -> String {
        "All-you-can-eat \(cuisine.displayName)"
    }
}
