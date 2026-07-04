import Foundation

/// The all-you-can-eat canon: what people actually order at sushi, KBBQ, and hot-pot
/// buffets, with per-unit nutrition, a typical US à-la-carte menu price, and the rough
/// grocery cost to make it at home. Prices are 2026 casual-dining ballparks — the UI
/// must always present them as estimates.
public enum AYCECatalog {

    public static func items(for cuisine: AYCECuisine) -> [AYCECatalogItem] {
        all.filter { $0.cuisine == cuisine }
    }

    public static func item(id: String) -> AYCECatalogItem? {
        all.first { $0.id == id }
    }

    public static let all: [AYCECatalogItem] = sushi + kbbq + hotpot

    // MARK: Sushi (per piece unless noted)

    static let sushi: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_salmon_nigiri", cuisine: .sushi, name: "Salmon nigiri", emoji: "🍣", unit: "piece",
                        calories: 60, protein: 3.5, carbs: 9, fats: 1.5, restaurantPrice: 3.25, homeCost: 0.95),
        AYCECatalogItem(id: "sushi_tuna_nigiri", cuisine: .sushi, name: "Tuna nigiri", emoji: "🍣", unit: "piece",
                        calories: 55, protein: 4.5, carbs: 9, fats: 0.5, restaurantPrice: 3.75, homeCost: 1.25),
        AYCECatalogItem(id: "sushi_yellowtail_nigiri", cuisine: .sushi, name: "Yellowtail nigiri", emoji: "🍣", unit: "piece",
                        calories: 60, protein: 4, carbs: 9, fats: 1.5, restaurantPrice: 3.95, homeCost: 1.40),
        AYCECatalogItem(id: "sushi_eel_nigiri", cuisine: .sushi, name: "Eel nigiri", emoji: "🍣", unit: "piece",
                        calories: 75, protein: 3.5, carbs: 10, fats: 2.5, restaurantPrice: 3.95, homeCost: 1.35),
        AYCECatalogItem(id: "sushi_shrimp_nigiri", cuisine: .sushi, name: "Shrimp nigiri", emoji: "🍤", unit: "piece",
                        calories: 50, protein: 3.5, carbs: 9, fats: 0.3, restaurantPrice: 2.95, homeCost: 0.80),
        AYCECatalogItem(id: "sushi_tamago_nigiri", cuisine: .sushi, name: "Tamago nigiri", emoji: "🍣", unit: "piece",
                        calories: 65, protein: 3, carbs: 10, fats: 1.5, restaurantPrice: 2.50, homeCost: 0.55),
        AYCECatalogItem(id: "sushi_salmon_sashimi", cuisine: .sushi, name: "Salmon sashimi", emoji: "🐟", unit: "slice",
                        calories: 40, protein: 5, carbs: 0, fats: 2, restaurantPrice: 2.75, homeCost: 0.85),
        AYCECatalogItem(id: "sushi_tuna_sashimi", cuisine: .sushi, name: "Tuna sashimi", emoji: "🐟", unit: "slice",
                        calories: 30, protein: 6, carbs: 0, fats: 0.3, restaurantPrice: 3.25, homeCost: 1.10),
        AYCECatalogItem(id: "sushi_california_roll", cuisine: .sushi, name: "California roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 250, protein: 8, carbs: 38, fats: 7, restaurantPrice: 7.50, homeCost: 2.20),
        AYCECatalogItem(id: "sushi_spicy_tuna_roll", cuisine: .sushi, name: "Spicy tuna roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 290, protein: 12, carbs: 36, fats: 10, restaurantPrice: 8.50, homeCost: 2.60),
        AYCECatalogItem(id: "sushi_tempura_roll", cuisine: .sushi, name: "Shrimp tempura roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 380, protein: 11, carbs: 46, fats: 16, restaurantPrice: 9.50, homeCost: 2.80),
        AYCECatalogItem(id: "sushi_gyoza", cuisine: .sushi, name: "Gyoza", emoji: "🥟", unit: "piece",
                        calories: 65, protein: 2.5, carbs: 7, fats: 3, restaurantPrice: 1.60, homeCost: 0.45),
        AYCECatalogItem(id: "sushi_edamame", cuisine: .sushi, name: "Edamame", emoji: "🫛", unit: "bowl",
                        calories: 120, protein: 11, carbs: 10, fats: 5, restaurantPrice: 5.00, homeCost: 1.20),
        AYCECatalogItem(id: "sushi_miso_soup", cuisine: .sushi, name: "Miso soup", emoji: "🥣", unit: "bowl",
                        calories: 60, protein: 4, carbs: 7, fats: 2, restaurantPrice: 3.50, homeCost: 0.60),
        AYCECatalogItem(id: "sushi_seaweed_salad", cuisine: .sushi, name: "Seaweed salad", emoji: "🥗", unit: "serving",
                        calories: 70, protein: 1.5, carbs: 10, fats: 3, restaurantPrice: 5.50, homeCost: 1.50)
    ]

    // MARK: Korean BBQ (per grilled serving, ~110 g cooked, unless noted)

    static let kbbq: [AYCECatalogItem] = [
        AYCECatalogItem(id: "kbbq_pork_belly", cuisine: .kbbq, name: "Pork belly", emoji: "🥓", unit: "serving",
                        calories: 440, protein: 18, carbs: 1, fats: 40, restaurantPrice: 13.95, homeCost: 3.20),
        AYCECatalogItem(id: "kbbq_bulgogi", cuisine: .kbbq, name: "Beef bulgogi", emoji: "🥩", unit: "serving",
                        calories: 310, protein: 26, carbs: 12, fats: 17, restaurantPrice: 14.95, homeCost: 3.80),
        AYCECatalogItem(id: "kbbq_galbi", cuisine: .kbbq, name: "Galbi short rib", emoji: "🍖", unit: "serving",
                        calories: 400, protein: 24, carbs: 10, fats: 28, restaurantPrice: 18.95, homeCost: 6.50),
        AYCECatalogItem(id: "kbbq_brisket", cuisine: .kbbq, name: "Brisket slices", emoji: "🥩", unit: "serving",
                        calories: 350, protein: 25, carbs: 0, fats: 27, restaurantPrice: 15.95, homeCost: 4.20),
        AYCECatalogItem(id: "kbbq_spicy_pork", cuisine: .kbbq, name: "Spicy pork", emoji: "🌶️", unit: "serving",
                        calories: 330, protein: 22, carbs: 9, fats: 22, restaurantPrice: 13.95, homeCost: 3.30),
        AYCECatalogItem(id: "kbbq_chicken_bulgogi", cuisine: .kbbq, name: "Chicken bulgogi", emoji: "🍗", unit: "serving",
                        calories: 250, protein: 28, carbs: 10, fats: 10, restaurantPrice: 12.95, homeCost: 2.80),
        AYCECatalogItem(id: "kbbq_steamed_egg", cuisine: .kbbq, name: "Steamed egg", emoji: "🍳", unit: "bowl",
                        calories: 140, protein: 11, carbs: 2, fats: 9, restaurantPrice: 6.00, homeCost: 1.00),
        AYCECatalogItem(id: "kbbq_banchan", cuisine: .kbbq, name: "Banchan refill", emoji: "🥬", unit: "set",
                        calories: 40, protein: 2, carbs: 6, fats: 1, restaurantPrice: 4.00, homeCost: 0.90),
        AYCECatalogItem(id: "kbbq_rice", cuisine: .kbbq, name: "Steamed rice", emoji: "🍚", unit: "bowl",
                        calories: 210, protein: 4, carbs: 45, fats: 0.5, restaurantPrice: 3.00, homeCost: 0.40),
        AYCECatalogItem(id: "kbbq_lettuce_wraps", cuisine: .kbbq, name: "Lettuce wrap set", emoji: "🥬", unit: "set",
                        calories: 25, protein: 1.5, carbs: 4, fats: 0.3, restaurantPrice: 4.50, homeCost: 1.10),
        AYCECatalogItem(id: "kbbq_japchae", cuisine: .kbbq, name: "Japchae", emoji: "🍜", unit: "side",
                        calories: 190, protein: 4, carbs: 33, fats: 5, restaurantPrice: 6.50, homeCost: 1.60)
    ]

    // MARK: Hot pot (per plate/serving)

    static let hotpot: [AYCECatalogItem] = [
        AYCECatalogItem(id: "hotpot_lamb", cuisine: .hotpot, name: "Lamb slices", emoji: "🍖", unit: "plate",
                        calories: 290, protein: 24, carbs: 0, fats: 21, restaurantPrice: 11.95, homeCost: 4.00),
        AYCECatalogItem(id: "hotpot_beef", cuisine: .hotpot, name: "Beef slices", emoji: "🥩", unit: "plate",
                        calories: 310, protein: 25, carbs: 0, fats: 23, restaurantPrice: 12.95, homeCost: 4.50),
        AYCECatalogItem(id: "hotpot_fatty_beef", cuisine: .hotpot, name: "Fatty beef ribeye", emoji: "🥩", unit: "plate",
                        calories: 380, protein: 22, carbs: 0, fats: 32, restaurantPrice: 14.95, homeCost: 5.50),
        AYCECatalogItem(id: "hotpot_fish_balls", cuisine: .hotpot, name: "Fish balls", emoji: "🍥", unit: "6 pieces",
                        calories: 160, protein: 12, carbs: 14, fats: 5, restaurantPrice: 6.95, homeCost: 2.10),
        AYCECatalogItem(id: "hotpot_shrimp", cuisine: .hotpot, name: "Shrimp", emoji: "🍤", unit: "6 pieces",
                        calories: 90, protein: 18, carbs: 1, fats: 1.5, restaurantPrice: 9.95, homeCost: 3.60),
        AYCECatalogItem(id: "hotpot_tofu", cuisine: .hotpot, name: "Firm tofu", emoji: "🧊", unit: "plate",
                        calories: 140, protein: 15, carbs: 4, fats: 8, restaurantPrice: 4.95, homeCost: 1.00),
        AYCECatalogItem(id: "hotpot_napa", cuisine: .hotpot, name: "Napa cabbage", emoji: "🥬", unit: "plate",
                        calories: 30, protein: 2, carbs: 5, fats: 0.3, restaurantPrice: 4.50, homeCost: 0.90),
        AYCECatalogItem(id: "hotpot_mushrooms", cuisine: .hotpot, name: "Mushroom medley", emoji: "🍄", unit: "plate",
                        calories: 45, protein: 4, carbs: 7, fats: 0.5, restaurantPrice: 6.50, homeCost: 1.80),
        AYCECatalogItem(id: "hotpot_udon", cuisine: .hotpot, name: "Udon noodles", emoji: "🍜", unit: "serving",
                        calories: 220, protein: 7, carbs: 44, fats: 1, restaurantPrice: 4.50, homeCost: 0.70),
        AYCECatalogItem(id: "hotpot_dumplings", cuisine: .hotpot, name: "Dumplings", emoji: "🥟", unit: "6 pieces",
                        calories: 300, protein: 12, carbs: 34, fats: 13, restaurantPrice: 7.50, homeCost: 2.20),
        AYCECatalogItem(id: "hotpot_sauce_bowl", cuisine: .hotpot, name: "Sauce bar bowl", emoji: "🥣", unit: "bowl",
                        calories: 150, protein: 3, carbs: 6, fats: 13, restaurantPrice: 1.50, homeCost: 0.50)
    ]
}
