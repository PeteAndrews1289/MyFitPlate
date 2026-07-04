import Foundation

/// Pricing for plate-scanned items that aren't in the curated catalog. The AI supplies
/// typical US à-la-carte and grocery estimates; everything it says passes through the
/// same kind of sanity clamps we apply to external food data — an estimate that breaks
/// the feature's premise (restaurant > home) gets corrected, not displayed.
public enum AYCEPricingRules {

    public static func prompt(for itemNames: [String], cuisine: AYCECuisine, city: AYCECity = AYCECityIndex.national) -> String {
        let list = itemNames.map { "- \($0)" }.joined(separator: "\n")
        let market = city.slug == AYCECityIndex.national.slug
            ? "in a typical US city"
            : "in \(city.name)"
        return """
        You estimate restaurant menu prices. The user is at an all-you-can-eat \(cuisine.displayName) restaurant \(market) and ate these items:

        \(list)

        For each item, estimate:
        1. "restaurantPrice": the à-la-carte menu price for one serving at a typical MID-RANGE neighborhood restaurant \(market), in dollars. Use median local spots as the reference — never premium, fine-dining, or tourist-district restaurants.
        2. "homeCost": approximate grocery-ingredient cost to make one serving at home \(market), in dollars. Always lower than restaurantPrice.

        Respond with ONLY a valid JSON object: {"items": [{"name": "...", "restaurantPrice": 0.0, "homeCost": 0.0}]}
        Use the exact item names given.
        """
    }

    public struct PricedItem: Equatable {
        public let name: String
        public let restaurantPrice: Double
        public let homeCost: Double
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let name: String
            let restaurantPrice: Double?
            let homeCost: Double?
        }
        let items: [Item]
    }

    /// Decodes the AI response (fences tolerated) and clamps every price into sanity.
    public static func decodePrices(from raw: String) throws -> [PricedItem] {
        let payload = InsightsRules.extractJSONPayload(raw)
        let response = try JSONDecoder().decode(Response.self, from: Data(payload.utf8))
        return response.items.compactMap { item in
            guard !item.name.isEmpty else { return nil }
            let clamped = clampedPrices(
                restaurant: item.restaurantPrice ?? 0,
                home: item.homeCost ?? 0
            )
            return PricedItem(name: item.name, restaurantPrice: clamped.restaurant, homeCost: clamped.home)
        }
    }

    /// Restaurant lands in $0.75–$75 per serving; home cost stays positive and strictly
    /// below the restaurant price (the premise of the whole feature).
    public static func clampedPrices(restaurant: Double, home: Double) -> (restaurant: Double, home: Double) {
        let safeRestaurant = min(max(restaurant.isFinite ? restaurant : 0, 0.75), 75)
        var safeHome = home.isFinite ? home : 0
        if safeHome <= 0 { safeHome = safeRestaurant * 0.3 }
        safeHome = min(safeHome, safeRestaurant * 0.9)
        safeHome = max(safeHome, 0.25)
        return (safeRestaurant, min(safeHome, safeRestaurant * 0.9))
    }

    /// When the AI can't be reached, price from calories instead of blocking the log:
    /// roughly $1.60 per 100 cal with a $2 floor — crude, visibly an estimate, never zero.
    public static func heuristicPrices(calories: Double) -> (restaurant: Double, home: Double) {
        let restaurant = max(2.0, (calories / 100) * 1.6)
        return clampedPrices(restaurant: restaurant, home: restaurant * 0.3)
    }

    public static func catalogItem(
        name: String,
        cuisine: AYCECuisine,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        restaurantPrice: Double,
        homeCost: Double
    ) -> AYCECatalogItem {
        AYCECatalogItem(
            id: "custom_\(UUID().uuidString)",
            cuisine: cuisine,
            name: name,
            emoji: emoji(for: name),
            unit: "serving",
            calories: max(0, calories),
            protein: max(0, protein),
            carbs: max(0, carbs),
            fats: max(0, fats),
            restaurantPrice: restaurantPrice,
            homeCost: homeCost,
            isAIEstimated: true
        )
    }

    static func emoji(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("roll") || lowered.contains("sushi") || lowered.contains("nigiri") { return "🍣" }
        if lowered.contains("soup") || lowered.contains("broth") { return "🥣" }
        if lowered.contains("noodle") || lowered.contains("udon") || lowered.contains("ramen") { return "🍜" }
        if lowered.contains("dumpling") || lowered.contains("gyoza") { return "🥟" }
        if lowered.contains("shrimp") || lowered.contains("prawn") { return "🍤" }
        if lowered.contains("beef") || lowered.contains("pork") || lowered.contains("rib") { return "🥩" }
        if lowered.contains("chicken") { return "🍗" }
        if lowered.contains("rice") { return "🍚" }
        return "🍽️"
    }
}

/// One text request prices a whole scanned plate. Failure never blocks logging — the
/// heuristic fallback prices step in and the error is logged.
public final class AYCEPriceService {

    public init() {}

    public func pricedCatalogItems(for foods: [FoodItem], cuisine: AYCECuisine, city: AYCECity = AYCECityIndex.national) async -> [AYCECatalogItem] {
        guard !foods.isEmpty else { return [] }

        var pricesByName: [String: AYCEPricingRules.PricedItem] = [:]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: [["role": "user", "content": AYCEPricingRules.prompt(for: foods.map(\.name), cuisine: cuisine, city: city)]],
            model: "gpt-4o-mini",
            temperature: 0.2,
            responseFormat: ["type": "json_object"]
        )

        switch result {
        case .success(let raw):
            do {
                for priced in try AYCEPricingRules.decodePrices(from: raw) {
                    pricesByName[priced.name.lowercased()] = priced
                }
            } catch {
                AppLog.ai.error("AYCE price decode failed, using heuristics: \(error.localizedDescription, privacy: .public)")
            }
        case .failure(let error):
            AppLog.ai.error("AYCE price request failed, using heuristics: \(error.localizedDescription, privacy: .public)")
        }

        return foods.map { food in
            let prices: (restaurant: Double, home: Double)
            if let matched = pricesByName[food.name.lowercased()] {
                prices = (matched.restaurantPrice, matched.homeCost)
            } else {
                // Heuristic fallback is national-baseline; scale it here because scanned
                // items bypass the city multiplier downstream (they're city-native).
                let base = AYCEPricingRules.heuristicPrices(calories: food.calories)
                prices = AYCEPricingRules.clampedPrices(
                    restaurant: base.restaurant * city.restaurantMultiplier,
                    home: base.home * city.homeMultiplier
                )
            }
            return AYCEPricingRules.catalogItem(
                name: food.name,
                cuisine: cuisine,
                calories: food.calories,
                protein: food.protein,
                carbs: food.carbs,
                fats: food.fats,
                restaurantPrice: prices.restaurant,
                homeCost: prices.home
            )
        }
    }
}
