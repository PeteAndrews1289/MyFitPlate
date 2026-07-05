import Foundation

/// "Beat the buffet": during an all-you-can-eat session the user logs what they eat and
/// watches the à-la-carte value climb past what they paid. Prices are typical US menu
/// estimates from a curated catalog — always presented as estimates, never as fact
/// (same honesty rules as the food-data trust layer).
public enum AYCECuisine: String, Codable, CaseIterable, Sendable {
    case sushi
    case kbbq
    case hotpot
    case chinese
    case dimSum
    case indian

    public var displayName: String {
        switch self {
        case .sushi: return "Sushi"
        case .kbbq: return "Korean BBQ"
        case .hotpot: return "Hot pot"
        case .chinese: return "Chinese buffet"
        case .dimSum: return "Dim sum"
        case .indian: return "Indian buffet"
        }
    }

    public var emoji: String {
        switch self {
        case .sushi: return "🍣"
        case .kbbq: return "🥩"
        case .hotpot: return "🍲"
        case .chinese: return "🥡"
        case .dimSum: return "🥟"
        case .indian: return "🍛"
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
    /// True for plate-scanned items whose nutrition and prices came from the AI —
    /// they carry AI-estimate source metadata into the diary instead of user-entered.
    public let isAIEstimated: Bool

    public init(
        id: String, cuisine: AYCECuisine, name: String, emoji: String, unit: String,
        calories: Double, protein: Double, carbs: Double, fats: Double,
        restaurantPrice: Double, homeCost: Double, isAIEstimated: Bool = false
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
        self.isAIEstimated = isAIEstimated
    }

    private enum CodingKeys: String, CodingKey {
        case id, cuisine, name, emoji, unit, calories, protein, carbs, fats, restaurantPrice, homeCost, isAIEstimated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cuisine = try container.decode(AYCECuisine.self, forKey: .cuisine)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        unit = try container.decode(String.self, forKey: .unit)
        calories = try container.decode(Double.self, forKey: .calories)
        protein = try container.decode(Double.self, forKey: .protein)
        carbs = try container.decode(Double.self, forKey: .carbs)
        fats = try container.decode(Double.self, forKey: .fats)
        restaurantPrice = try container.decode(Double.self, forKey: .restaurantPrice)
        homeCost = try container.decode(Double.self, forKey: .homeCost)
        // Absent in drafts persisted before this field existed.
        isAIEstimated = try container.decodeIfPresent(Bool.self, forKey: .isAIEstimated) ?? false
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
    /// AYCECityIndex slug scaling curated prices to the local market; nil = US average.
    /// Optional, so drafts persisted before city support still decode.
    public var citySlug: String?

    public init(
        id: String = UUID().uuidString,
        cuisine: AYCECuisine,
        buffetPrice: Double,
        startedAt: Date = Date(),
        entries: [AYCESessionEntry] = [],
        citySlug: String? = nil
    ) {
        self.id = id
        self.cuisine = cuisine
        self.buffetPrice = buffetPrice
        self.startedAt = startedAt
        self.entries = entries
        self.citySlug = citySlug
    }

    public var city: AYCECity { AYCECityIndex.city(slug: citySlug) }
}

public enum AYCERules {

    public struct Totals: Equatable {
        public let restaurantValue: Double
        public let homeCost: Double
        /// What the ingredients likely cost the restaurant itself (wholesale).
        public let restaurantFoodCost: Double
        public let calories: Double
        public let protein: Double
        public let carbs: Double
        public let fats: Double
        public let itemCount: Int
    }

    /// Restaurants buy wholesale — their ingredient cost runs below your grocery cost for
    /// the same portion, bounded so it never exceeds a plausible share of the menu price.
    public static func restaurantFoodCost(homeCost: Double, menuPrice: Double) -> Double {
        max(0.15, min(homeCost * 0.7, menuPrice * 0.45))
    }

    /// The menu price a single unit displays and sums at, in this session's city.
    /// AI-scanned items were priced FOR the city already and pass through untouched;
    /// curated catalog items scale by the city's multipliers.
    public static func unitPrices(for item: AYCECatalogItem, in session: AYCESession) -> (restaurant: Double, home: Double) {
        guard !item.isAIEstimated else {
            return (item.restaurantPrice, item.homeCost)
        }
        let city = session.city
        return (item.restaurantPrice * city.restaurantMultiplier, item.homeCost * city.homeMultiplier)
    }

    public static func totals(for session: AYCESession) -> Totals {
        var restaurantValue = 0.0
        var homeCost = 0.0
        var foodCost = 0.0
        var calories = 0.0
        var protein = 0.0
        var carbs = 0.0
        var fats = 0.0
        var itemCount = 0

        for entry in session.entries {
            let unit = unitPrices(for: entry.item, in: session)
            let count = Double(entry.count)
            restaurantValue += unit.restaurant * count
            homeCost += unit.home * count
            foodCost += restaurantFoodCost(homeCost: unit.home, menuPrice: unit.restaurant) * count
            calories += entry.item.calories * count
            protein += entry.item.protein * count
            carbs += entry.item.carbs * count
            fats += entry.item.fats * count
            itemCount += entry.count
        }

        return Totals(
            restaurantValue: restaurantValue,
            homeCost: homeCost,
            restaurantFoodCost: foodCost,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            itemCount: itemCount
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

    /// The gloat line: what the restaurant likely spent on the ingredients it fed you.
    public static func ingredientCostLine(session: AYCESession) -> String {
        "Their ingredients: about \(money(totals(for: session).restaurantFoodCost))"
    }

    // MARK: The second game — beating the kitchen itself

    /// Dollars of the restaurant's OWN ingredient spend beyond what the user paid.
    /// Menu-value break-even is the warm-up; this is the real trophy: the kitchen
    /// spent more feeding you than you handed them.
    public static func kitchenDelta(session: AYCESession) -> Double {
        totals(for: session).restaurantFoodCost - session.buffetPrice
    }

    public static func hasBeatenKitchen(session: AYCESession) -> Bool {
        session.buffetPrice > 0 && kitchenDelta(session: session) >= 0
    }

    /// Live-ticker second line tracking the kitchen's spend on this table.
    public static func kitchenLine(session: AYCESession) -> String {
        let spent = totals(for: session).restaurantFoodCost
        if hasBeatenKitchen(session: session) {
            return "Their kitchen has spent \(money(spent)) on you — they're losing money"
        }
        return "Their kitchen has spent about \(money(spent)) on you"
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
            sourceMetadata: entry.item.isAIEstimated
                ? .aiEstimate(.aiImage, sourceName: "Beat the buffet")
                : .userEntered(sourceName: "Beat the buffet")
        )
    }

    /// The diary meal name a session logs under.
    public static func mealName(for cuisine: AYCECuisine) -> String {
        "All-you-can-eat \(cuisine.displayName)"
    }
}
