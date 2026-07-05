import Foundation

/// The all-you-can-eat canon across six cuisines: what people actually order, with
/// per-unit nutrition, a typical US mid-range à-la-carte price, and the rough grocery
/// cost to make it at home. Prices are 2026 national-baseline ballparks (city multipliers
/// apply downstream) — the UI must always present them as estimates.
///
/// Adding items: the contract tests are the spec — restaurantPrice > homeCost on every
/// row, and macros must reconcile with calories via Atwater (4/4/9) within 15%.
public enum AYCECatalog {

    public static func items(for cuisine: AYCECuisine) -> [AYCECatalogItem] {
        all.filter { $0.cuisine == cuisine }
    }

    public static func item(id: String) -> AYCECatalogItem? {
        all.first { $0.id == id }
    }

    public static let all: [AYCECatalogItem] = sushi + kbbq + hotpot + chinese + dimSum + indian

    /// A titled slice of a cuisine's menu, for section headers in long grids.
    public struct MenuSection: Identifiable {
        public let title: String
        public let items: [AYCECatalogItem]
        public var id: String { title }
    }

    /// Sushi is big enough to need grouping; other cuisines render as one untitled section.
    public static func sections(for cuisine: AYCECuisine) -> [MenuSection] {
        switch cuisine {
        case .sushi:
            return [
                MenuSection(title: "Nigiri & sashimi", items: sushiNigiriAndSashimi),
                MenuSection(title: "Rolls", items: sushiRolls),
                MenuSection(title: "Small plates & dessert", items: sushiSides)
            ]
        default:
            return [MenuSection(title: "", items: items(for: cuisine))]
        }
    }

    // MARK: Sushi (per piece unless noted)

    static let sushi: [AYCECatalogItem] = sushiNigiriAndSashimi + sushiRolls + sushiSides

    static let sushiNigiriAndSashimi: [AYCECatalogItem] = [
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
        AYCECatalogItem(id: "sushi_tako_nigiri", cuisine: .sushi, name: "Octopus nigiri", emoji: "🐙", unit: "piece",
                        calories: 50, protein: 4, carbs: 8, fats: 0.3, restaurantPrice: 3.50, homeCost: 1.10),
        AYCECatalogItem(id: "sushi_scallop_nigiri", cuisine: .sushi, name: "Scallop nigiri", emoji: "🍣", unit: "piece",
                        calories: 58, protein: 4, carbs: 9, fats: 0.8, restaurantPrice: 3.95, homeCost: 1.30),
        AYCECatalogItem(id: "sushi_tamago_nigiri", cuisine: .sushi, name: "Tamago nigiri", emoji: "🍣", unit: "piece",
                        calories: 65, protein: 3, carbs: 10, fats: 1.5, restaurantPrice: 2.50, homeCost: 0.55),
        AYCECatalogItem(id: "sushi_inari", cuisine: .sushi, name: "Inari", emoji: "🍣", unit: "piece",
                        calories: 80, protein: 2.5, carbs: 14, fats: 1.5, restaurantPrice: 2.00, homeCost: 0.40),
        AYCECatalogItem(id: "sushi_ikura_gunkan", cuisine: .sushi, name: "Ikura gunkan", emoji: "🍣", unit: "piece",
                        calories: 70, protein: 4, carbs: 9, fats: 2, restaurantPrice: 4.50, homeCost: 1.60),
        AYCECatalogItem(id: "sushi_salmon_sashimi", cuisine: .sushi, name: "Salmon sashimi", emoji: "🐟", unit: "slice",
                        calories: 40, protein: 5, carbs: 0, fats: 2, restaurantPrice: 2.75, homeCost: 0.85),
        AYCECatalogItem(id: "sushi_tuna_sashimi", cuisine: .sushi, name: "Tuna sashimi", emoji: "🐟", unit: "slice",
                        calories: 30, protein: 6, carbs: 0, fats: 0.3, restaurantPrice: 3.25, homeCost: 1.10)
    ]

    static let sushiRolls: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_california_roll", cuisine: .sushi, name: "California roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 250, protein: 8, carbs: 38, fats: 7, restaurantPrice: 7.50, homeCost: 2.20),
        AYCECatalogItem(id: "sushi_spicy_tuna_roll", cuisine: .sushi, name: "Spicy tuna roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 290, protein: 12, carbs: 36, fats: 10, restaurantPrice: 8.50, homeCost: 2.60),
        AYCECatalogItem(id: "sushi_tempura_roll", cuisine: .sushi, name: "Shrimp tempura roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 380, protein: 11, carbs: 46, fats: 16, restaurantPrice: 9.50, homeCost: 2.80),
        AYCECatalogItem(id: "sushi_tuna_roll", cuisine: .sushi, name: "Tuna roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 190, protein: 9, carbs: 27, fats: 4.5, restaurantPrice: 6.50, homeCost: 2.00),
        AYCECatalogItem(id: "sushi_salmon_roll", cuisine: .sushi, name: "Salmon roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 210, protein: 9, carbs: 28, fats: 6.5, restaurantPrice: 6.50, homeCost: 1.90),
        AYCECatalogItem(id: "sushi_philadelphia_roll", cuisine: .sushi, name: "Philadelphia roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 300, protein: 11, carbs: 33, fats: 13, restaurantPrice: 8.95, homeCost: 2.40),
        AYCECatalogItem(id: "sushi_rainbow_roll", cuisine: .sushi, name: "Rainbow roll", emoji: "🍱", unit: "roll (8 pc)",
                        calories: 350, protein: 18, carbs: 40, fats: 12, restaurantPrice: 12.95, homeCost: 3.80),
        AYCECatalogItem(id: "sushi_dragon_roll", cuisine: .sushi, name: "Dragon roll", emoji: "🍱", unit: "roll (8 pc)",
                        calories: 420, protein: 14, carbs: 52, fats: 16, restaurantPrice: 13.95, homeCost: 3.60),
        AYCECatalogItem(id: "sushi_spider_roll", cuisine: .sushi, name: "Spider roll", emoji: "🦀", unit: "roll (5 pc)",
                        calories: 320, protein: 12, carbs: 34, fats: 15, restaurantPrice: 11.95, homeCost: 3.40),
        AYCECatalogItem(id: "sushi_caterpillar_roll", cuisine: .sushi, name: "Caterpillar roll", emoji: "🍱", unit: "roll (8 pc)",
                        calories: 400, protein: 12, carbs: 48, fats: 17, restaurantPrice: 12.95, homeCost: 3.40),
        AYCECatalogItem(id: "sushi_volcano_roll", cuisine: .sushi, name: "Volcano roll", emoji: "🌋", unit: "roll (8 pc)",
                        calories: 480, protein: 16, carbs: 46, fats: 26, restaurantPrice: 12.95, homeCost: 3.20),
        AYCECatalogItem(id: "sushi_crunchy_roll", cuisine: .sushi, name: "Crunchy roll", emoji: "🍱", unit: "roll (8 pc)",
                        calories: 420, protein: 12, carbs: 52, fats: 17, restaurantPrice: 10.95, homeCost: 2.90),
        AYCECatalogItem(id: "sushi_dynamite_roll", cuisine: .sushi, name: "Dynamite roll", emoji: "🧨", unit: "roll (8 pc)",
                        calories: 430, protein: 14, carbs: 44, fats: 21, restaurantPrice: 11.95, homeCost: 3.00),
        AYCECatalogItem(id: "sushi_vegas_roll", cuisine: .sushi, name: "Vegas roll", emoji: "🍱", unit: "roll (8 pc)",
                        calories: 460, protein: 15, carbs: 42, fats: 26, restaurantPrice: 12.50, homeCost: 3.10),
        AYCECatalogItem(id: "sushi_alaska_roll", cuisine: .sushi, name: "Alaska roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 240, protein: 10, carbs: 30, fats: 8.5, restaurantPrice: 7.95, homeCost: 2.30),
        AYCECatalogItem(id: "sushi_boston_roll", cuisine: .sushi, name: "Boston roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 230, protein: 9, carbs: 30, fats: 8, restaurantPrice: 7.50, homeCost: 2.10),
        AYCECatalogItem(id: "sushi_spicy_yellowtail_roll", cuisine: .sushi, name: "Spicy yellowtail roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 280, protein: 11, carbs: 34, fats: 10.5, restaurantPrice: 8.95, homeCost: 2.70),
        AYCECatalogItem(id: "sushi_negihama_roll", cuisine: .sushi, name: "Yellowtail scallion roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 220, protein: 11, carbs: 28, fats: 6.5, restaurantPrice: 7.95, homeCost: 2.50),
        AYCECatalogItem(id: "sushi_salmon_avocado_roll", cuisine: .sushi, name: "Salmon avocado roll", emoji: "🥑", unit: "roll (6 pc)",
                        calories: 260, protein: 9, carbs: 30, fats: 11, restaurantPrice: 7.95, homeCost: 2.30),
        AYCECatalogItem(id: "sushi_tuna_avocado_roll", cuisine: .sushi, name: "Tuna avocado roll", emoji: "🥑", unit: "roll (6 pc)",
                        calories: 250, protein: 10, carbs: 30, fats: 9.5, restaurantPrice: 8.50, homeCost: 2.60),
        AYCECatalogItem(id: "sushi_eel_avocado_roll", cuisine: .sushi, name: "Eel avocado roll", emoji: "🥑", unit: "roll (6 pc)",
                        calories: 290, protein: 9, carbs: 34, fats: 12.5, restaurantPrice: 8.95, homeCost: 2.60),
        AYCECatalogItem(id: "sushi_eel_cucumber_roll", cuisine: .sushi, name: "Eel cucumber roll", emoji: "🥒", unit: "roll (6 pc)",
                        calories: 250, protein: 9, carbs: 34, fats: 8, restaurantPrice: 8.50, homeCost: 2.40),
        AYCECatalogItem(id: "sushi_cucumber_roll", cuisine: .sushi, name: "Cucumber roll", emoji: "🥒", unit: "roll (6 pc)",
                        calories: 130, protein: 2.5, carbs: 27, fats: 0.8, restaurantPrice: 4.50, homeCost: 1.00),
        AYCECatalogItem(id: "sushi_avocado_roll", cuisine: .sushi, name: "Avocado roll", emoji: "🥑", unit: "roll (6 pc)",
                        calories: 180, protein: 2.5, carbs: 28, fats: 6.5, restaurantPrice: 5.50, homeCost: 1.20),
        AYCECatalogItem(id: "sushi_sweet_potato_roll", cuisine: .sushi, name: "Sweet potato tempura roll", emoji: "🍠", unit: "roll (6 pc)",
                        calories: 260, protein: 3, carbs: 44, fats: 7.5, restaurantPrice: 7.50, homeCost: 1.60),
        AYCECatalogItem(id: "sushi_veggie_roll", cuisine: .sushi, name: "Veggie roll", emoji: "🥗", unit: "roll (6 pc)",
                        calories: 170, protein: 3, carbs: 32, fats: 3, restaurantPrice: 6.50, homeCost: 1.40),
        AYCECatalogItem(id: "sushi_futomaki", cuisine: .sushi, name: "Futomaki", emoji: "🍱", unit: "roll (5 pc)",
                        calories: 280, protein: 7, carbs: 48, fats: 6, restaurantPrice: 8.50, homeCost: 1.90),
        AYCECatalogItem(id: "sushi_salmon_skin_roll", cuisine: .sushi, name: "Salmon skin roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 250, protein: 8, carbs: 30, fats: 10.5, restaurantPrice: 7.50, homeCost: 1.80),
        AYCECatalogItem(id: "sushi_spicy_salmon_hand_roll", cuisine: .sushi, name: "Spicy salmon hand roll", emoji: "🍱", unit: "hand roll",
                        calories: 190, protein: 8, carbs: 22, fats: 7.5, restaurantPrice: 5.50, homeCost: 1.60)
    ]

    static let sushiSides: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_shrimp_tempura_piece", cuisine: .sushi, name: "Shrimp tempura", emoji: "🍤", unit: "piece",
                        calories: 75, protein: 3, carbs: 7, fats: 4, restaurantPrice: 2.25, homeCost: 0.50),
        AYCECatalogItem(id: "sushi_gyoza", cuisine: .sushi, name: "Gyoza", emoji: "🥟", unit: "piece",
                        calories: 65, protein: 2.5, carbs: 7, fats: 3, restaurantPrice: 1.60, homeCost: 0.45),
        AYCECatalogItem(id: "sushi_edamame", cuisine: .sushi, name: "Edamame", emoji: "🫛", unit: "bowl",
                        calories: 120, protein: 11, carbs: 10, fats: 5, restaurantPrice: 5.00, homeCost: 1.20),
        AYCECatalogItem(id: "sushi_miso_soup", cuisine: .sushi, name: "Miso soup", emoji: "🥣", unit: "bowl",
                        calories: 60, protein: 4, carbs: 7, fats: 2, restaurantPrice: 3.50, homeCost: 0.60),
        AYCECatalogItem(id: "sushi_seaweed_salad", cuisine: .sushi, name: "Seaweed salad", emoji: "🥗", unit: "serving",
                        calories: 70, protein: 1.5, carbs: 10, fats: 3, restaurantPrice: 5.50, homeCost: 1.50),
        AYCECatalogItem(id: "sushi_chicken_teriyaki", cuisine: .sushi, name: "Chicken teriyaki", emoji: "🍗", unit: "plate",
                        calories: 350, protein: 30, carbs: 26, fats: 13, restaurantPrice: 12.95, homeCost: 2.80),
        AYCECatalogItem(id: "sushi_mochi_ice_cream", cuisine: .sushi, name: "Mochi ice cream", emoji: "🍡", unit: "piece",
                        calories: 110, protein: 1.5, carbs: 18, fats: 3.5, restaurantPrice: 2.50, homeCost: 0.60)
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
        AYCECatalogItem(id: "kbbq_beef_tongue", cuisine: .kbbq, name: "Beef tongue", emoji: "🥩", unit: "serving",
                        calories: 320, protein: 18, carbs: 1, fats: 27, restaurantPrice: 16.95, homeCost: 5.20),
        AYCECatalogItem(id: "kbbq_pork_jowl", cuisine: .kbbq, name: "Pork jowl", emoji: "🥓", unit: "serving",
                        calories: 380, protein: 16, carbs: 0.5, fats: 35, restaurantPrice: 14.95, homeCost: 3.60),
        AYCECatalogItem(id: "kbbq_spicy_pork", cuisine: .kbbq, name: "Spicy pork", emoji: "🌶️", unit: "serving",
                        calories: 330, protein: 22, carbs: 9, fats: 22, restaurantPrice: 13.95, homeCost: 3.30),
        AYCECatalogItem(id: "kbbq_chicken_bulgogi", cuisine: .kbbq, name: "Chicken bulgogi", emoji: "🍗", unit: "serving",
                        calories: 250, protein: 28, carbs: 10, fats: 10, restaurantPrice: 12.95, homeCost: 2.80),
        AYCECatalogItem(id: "kbbq_steamed_egg", cuisine: .kbbq, name: "Steamed egg", emoji: "🍳", unit: "bowl",
                        calories: 140, protein: 11, carbs: 2, fats: 9, restaurantPrice: 6.00, homeCost: 1.00),
        AYCECatalogItem(id: "kbbq_corn_cheese", cuisine: .kbbq, name: "Corn cheese", emoji: "🌽", unit: "skillet",
                        calories: 250, protein: 7, carbs: 24, fats: 14, restaurantPrice: 7.95, homeCost: 1.60),
        AYCECatalogItem(id: "kbbq_kimchi_stew", cuisine: .kbbq, name: "Kimchi stew", emoji: "🍲", unit: "bowl",
                        calories: 180, protein: 12, carbs: 11, fats: 9.5, restaurantPrice: 9.95, homeCost: 1.90),
        AYCECatalogItem(id: "kbbq_soft_tofu_stew", cuisine: .kbbq, name: "Soft tofu stew", emoji: "🍲", unit: "bowl",
                        calories: 220, protein: 14, carbs: 9, fats: 14, restaurantPrice: 10.95, homeCost: 2.00),
        AYCECatalogItem(id: "kbbq_naengmyeon", cuisine: .kbbq, name: "Cold noodles", emoji: "🍜", unit: "bowl",
                        calories: 340, protein: 11, carbs: 64, fats: 4, restaurantPrice: 10.95, homeCost: 1.80),
        AYCECatalogItem(id: "kbbq_pajeon", cuisine: .kbbq, name: "Seafood pancake", emoji: "🥞", unit: "pancake",
                        calories: 320, protein: 11, carbs: 34, fats: 15, restaurantPrice: 12.95, homeCost: 2.40),
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
        AYCECatalogItem(id: "hotpot_pork_belly", cuisine: .hotpot, name: "Pork belly slices", emoji: "🥓", unit: "plate",
                        calories: 400, protein: 14, carbs: 0, fats: 38, restaurantPrice: 10.95, homeCost: 3.20),
        AYCECatalogItem(id: "hotpot_chicken", cuisine: .hotpot, name: "Chicken slices", emoji: "🍗", unit: "plate",
                        calories: 180, protein: 24, carbs: 0, fats: 9, restaurantPrice: 8.95, homeCost: 2.60),
        AYCECatalogItem(id: "hotpot_fish_balls", cuisine: .hotpot, name: "Fish balls", emoji: "🍥", unit: "6 pieces",
                        calories: 160, protein: 12, carbs: 14, fats: 5, restaurantPrice: 6.95, homeCost: 2.10),
        AYCECatalogItem(id: "hotpot_shrimp", cuisine: .hotpot, name: "Shrimp", emoji: "🍤", unit: "6 pieces",
                        calories: 90, protein: 18, carbs: 1, fats: 1.5, restaurantPrice: 9.95, homeCost: 3.60),
        AYCECatalogItem(id: "hotpot_crab_sticks", cuisine: .hotpot, name: "Crab sticks", emoji: "🦀", unit: "plate",
                        calories: 90, protein: 7, carbs: 13, fats: 0.5, restaurantPrice: 4.95, homeCost: 1.40),
        AYCECatalogItem(id: "hotpot_quail_eggs", cuisine: .hotpot, name: "Quail eggs", emoji: "🥚", unit: "6 pieces",
                        calories: 85, protein: 7, carbs: 0.5, fats: 6, restaurantPrice: 4.50, homeCost: 1.30),
        AYCECatalogItem(id: "hotpot_wontons", cuisine: .hotpot, name: "Wontons", emoji: "🥟", unit: "6 pieces",
                        calories: 240, protein: 10, carbs: 28, fats: 10, restaurantPrice: 6.95, homeCost: 1.90),
        AYCECatalogItem(id: "hotpot_tofu", cuisine: .hotpot, name: "Firm tofu", emoji: "🧊", unit: "plate",
                        calories: 140, protein: 15, carbs: 4, fats: 8, restaurantPrice: 4.95, homeCost: 1.00),
        AYCECatalogItem(id: "hotpot_tofu_puffs", cuisine: .hotpot, name: "Tofu puffs", emoji: "🧊", unit: "plate",
                        calories: 130, protein: 8, carbs: 4, fats: 9.5, restaurantPrice: 4.50, homeCost: 0.90),
        AYCECatalogItem(id: "hotpot_napa", cuisine: .hotpot, name: "Napa cabbage", emoji: "🥬", unit: "plate",
                        calories: 30, protein: 2, carbs: 5, fats: 0.3, restaurantPrice: 4.50, homeCost: 0.90),
        AYCECatalogItem(id: "hotpot_bok_choy", cuisine: .hotpot, name: "Bok choy", emoji: "🥬", unit: "plate",
                        calories: 25, protein: 2, carbs: 4, fats: 0.3, restaurantPrice: 4.25, homeCost: 0.80),
        AYCECatalogItem(id: "hotpot_lotus_root", cuisine: .hotpot, name: "Lotus root", emoji: "🪷", unit: "plate",
                        calories: 60, protein: 1.5, carbs: 13, fats: 0.3, restaurantPrice: 4.95, homeCost: 1.20),
        AYCECatalogItem(id: "hotpot_mushrooms", cuisine: .hotpot, name: "Mushroom medley", emoji: "🍄", unit: "plate",
                        calories: 45, protein: 4, carbs: 7, fats: 0.5, restaurantPrice: 6.50, homeCost: 1.80),
        AYCECatalogItem(id: "hotpot_udon", cuisine: .hotpot, name: "Udon noodles", emoji: "🍜", unit: "serving",
                        calories: 220, protein: 7, carbs: 44, fats: 1, restaurantPrice: 4.50, homeCost: 0.70),
        AYCECatalogItem(id: "hotpot_rice_cakes", cuisine: .hotpot, name: "Rice cakes", emoji: "🍚", unit: "plate",
                        calories: 190, protein: 3, carbs: 42, fats: 1, restaurantPrice: 4.50, homeCost: 0.90),
        AYCECatalogItem(id: "hotpot_dumplings", cuisine: .hotpot, name: "Dumplings", emoji: "🥟", unit: "6 pieces",
                        calories: 300, protein: 12, carbs: 34, fats: 13, restaurantPrice: 7.50, homeCost: 2.20),
        AYCECatalogItem(id: "hotpot_sauce_bowl", cuisine: .hotpot, name: "Sauce bar bowl", emoji: "🥣", unit: "bowl",
                        calories: 150, protein: 3, carbs: 6, fats: 13, restaurantPrice: 1.50, homeCost: 0.50)
    ]

    // MARK: Chinese buffet (per serving/scoop unless noted)

    static let chinese: [AYCECatalogItem] = [
        AYCECatalogItem(id: "cn_general_tso", cuisine: .chinese, name: "General Tso's chicken", emoji: "🍗", unit: "serving",
                        calories: 430, protein: 22, carbs: 38, fats: 21, restaurantPrice: 13.95, homeCost: 3.10),
        AYCECatalogItem(id: "cn_orange_chicken", cuisine: .chinese, name: "Orange chicken", emoji: "🍊", unit: "serving",
                        calories: 420, protein: 20, carbs: 42, fats: 19, restaurantPrice: 13.95, homeCost: 3.00),
        AYCECatalogItem(id: "cn_sesame_chicken", cuisine: .chinese, name: "Sesame chicken", emoji: "🍗", unit: "serving",
                        calories: 440, protein: 21, carbs: 44, fats: 20, restaurantPrice: 13.95, homeCost: 3.10),
        AYCECatalogItem(id: "cn_sweet_sour_pork", cuisine: .chinese, name: "Sweet and sour pork", emoji: "🍍", unit: "serving",
                        calories: 400, protein: 17, carbs: 46, fats: 16, restaurantPrice: 12.95, homeCost: 2.80),
        AYCECatalogItem(id: "cn_beef_broccoli", cuisine: .chinese, name: "Beef and broccoli", emoji: "🥦", unit: "serving",
                        calories: 290, protein: 22, carbs: 14, fats: 16, restaurantPrice: 14.95, homeCost: 3.60),
        AYCECatalogItem(id: "cn_mongolian_beef", cuisine: .chinese, name: "Mongolian beef", emoji: "🥩", unit: "serving",
                        calories: 340, protein: 24, carbs: 22, fats: 17, restaurantPrice: 14.95, homeCost: 3.80),
        AYCECatalogItem(id: "cn_kung_pao", cuisine: .chinese, name: "Kung pao chicken", emoji: "🥜", unit: "serving",
                        calories: 380, protein: 26, carbs: 18, fats: 22, restaurantPrice: 13.95, homeCost: 3.20),
        AYCECatalogItem(id: "cn_honey_walnut_shrimp", cuisine: .chinese, name: "Honey walnut shrimp", emoji: "🍤", unit: "serving",
                        calories: 430, protein: 16, carbs: 30, fats: 28, restaurantPrice: 16.95, homeCost: 4.60),
        AYCECatalogItem(id: "cn_salt_pepper_shrimp", cuisine: .chinese, name: "Salt and pepper shrimp", emoji: "🍤", unit: "serving",
                        calories: 300, protein: 20, carbs: 16, fats: 17, restaurantPrice: 15.95, homeCost: 4.20),
        AYCECatalogItem(id: "cn_mapo_tofu", cuisine: .chinese, name: "Mapo tofu", emoji: "🧊", unit: "serving",
                        calories: 260, protein: 14, carbs: 11, fats: 18, restaurantPrice: 11.95, homeCost: 2.20),
        AYCECatalogItem(id: "cn_green_beans", cuisine: .chinese, name: "Stir-fried green beans", emoji: "🫛", unit: "serving",
                        calories: 120, protein: 3, carbs: 11, fats: 7, restaurantPrice: 7.95, homeCost: 1.30),
        AYCECatalogItem(id: "cn_fried_rice", cuisine: .chinese, name: "Fried rice", emoji: "🍚", unit: "bowl",
                        calories: 330, protein: 8, carbs: 56, fats: 8, restaurantPrice: 8.95, homeCost: 1.20),
        AYCECatalogItem(id: "cn_lo_mein", cuisine: .chinese, name: "Lo mein", emoji: "🍜", unit: "serving",
                        calories: 310, protein: 10, carbs: 52, fats: 7, restaurantPrice: 9.95, homeCost: 1.40),
        AYCECatalogItem(id: "cn_white_rice", cuisine: .chinese, name: "White rice", emoji: "🍚", unit: "bowl",
                        calories: 200, protein: 4, carbs: 44, fats: 0.5, restaurantPrice: 2.50, homeCost: 0.30),
        AYCECatalogItem(id: "cn_egg_roll", cuisine: .chinese, name: "Egg roll", emoji: "🌯", unit: "piece",
                        calories: 170, protein: 4, carbs: 18, fats: 9, restaurantPrice: 2.50, homeCost: 0.55),
        AYCECatalogItem(id: "cn_spring_roll", cuisine: .chinese, name: "Spring roll", emoji: "🌯", unit: "piece",
                        calories: 110, protein: 2, carbs: 14, fats: 5, restaurantPrice: 2.25, homeCost: 0.45),
        AYCECatalogItem(id: "cn_crab_rangoon", cuisine: .chinese, name: "Crab rangoon", emoji: "🦀", unit: "piece",
                        calories: 95, protein: 2, carbs: 8, fats: 6, restaurantPrice: 1.95, homeCost: 0.40),
        AYCECatalogItem(id: "cn_potsticker", cuisine: .chinese, name: "Potsticker", emoji: "🥟", unit: "piece",
                        calories: 70, protein: 3, carbs: 8, fats: 3, restaurantPrice: 1.75, homeCost: 0.45),
        AYCECatalogItem(id: "cn_hot_sour_soup", cuisine: .chinese, name: "Hot and sour soup", emoji: "🥣", unit: "bowl",
                        calories: 95, protein: 6, carbs: 10, fats: 3.5, restaurantPrice: 3.95, homeCost: 0.70),
        AYCECatalogItem(id: "cn_egg_drop_soup", cuisine: .chinese, name: "Egg drop soup", emoji: "🥣", unit: "bowl",
                        calories: 70, protein: 4, carbs: 8, fats: 2.5, restaurantPrice: 3.50, homeCost: 0.50)
    ]

    // MARK: Dim sum (per piece/order as noted)

    static let dimSum: [AYCECatalogItem] = [
        AYCECatalogItem(id: "ds_har_gow", cuisine: .dimSum, name: "Har gow", emoji: "🥟", unit: "piece",
                        calories: 55, protein: 3, carbs: 7, fats: 1.5, restaurantPrice: 1.90, homeCost: 0.55),
        AYCECatalogItem(id: "ds_siu_mai", cuisine: .dimSum, name: "Siu mai", emoji: "🥟", unit: "piece",
                        calories: 60, protein: 3.5, carbs: 5, fats: 3, restaurantPrice: 1.85, homeCost: 0.50),
        AYCECatalogItem(id: "ds_char_siu_bao", cuisine: .dimSum, name: "Char siu bao", emoji: "🥠", unit: "piece",
                        calories: 180, protein: 7, carbs: 30, fats: 4, restaurantPrice: 2.50, homeCost: 0.60),
        AYCECatalogItem(id: "ds_custard_bun", cuisine: .dimSum, name: "Custard bun", emoji: "🥠", unit: "piece",
                        calories: 150, protein: 4, carbs: 24, fats: 4.5, restaurantPrice: 2.10, homeCost: 0.45),
        AYCECatalogItem(id: "ds_cheung_fun", cuisine: .dimSum, name: "Shrimp cheung fun", emoji: "🍥", unit: "plate",
                        calories: 240, protein: 8, carbs: 40, fats: 5.5, restaurantPrice: 6.50, homeCost: 1.40),
        AYCECatalogItem(id: "ds_turnip_cake", cuisine: .dimSum, name: "Turnip cake", emoji: "🍥", unit: "piece",
                        calories: 90, protein: 2, carbs: 12, fats: 4, restaurantPrice: 2.00, homeCost: 0.40),
        AYCECatalogItem(id: "ds_sticky_rice", cuisine: .dimSum, name: "Sticky rice in lotus leaf", emoji: "🍙", unit: "parcel",
                        calories: 330, protein: 11, carbs: 50, fats: 10, restaurantPrice: 6.95, homeCost: 1.50),
        AYCECatalogItem(id: "ds_chicken_feet", cuisine: .dimSum, name: "Chicken feet", emoji: "🍗", unit: "order",
                        calories: 190, protein: 16, carbs: 2, fats: 13, restaurantPrice: 5.95, homeCost: 1.30),
        AYCECatalogItem(id: "ds_spare_ribs", cuisine: .dimSum, name: "Spare ribs in black bean", emoji: "🍖", unit: "order",
                        calories: 240, protein: 14, carbs: 5, fats: 18, restaurantPrice: 6.50, homeCost: 1.80),
        AYCECatalogItem(id: "ds_beef_ball", cuisine: .dimSum, name: "Beef ball", emoji: "🍥", unit: "piece",
                        calories: 85, protein: 6, carbs: 3, fats: 5.5, restaurantPrice: 1.90, homeCost: 0.55),
        AYCECatalogItem(id: "ds_congee", cuisine: .dimSum, name: "Congee", emoji: "🥣", unit: "bowl",
                        calories: 180, protein: 7, carbs: 32, fats: 2.5, restaurantPrice: 5.50, homeCost: 0.80),
        AYCECatalogItem(id: "ds_egg_tart", cuisine: .dimSum, name: "Egg tart", emoji: "🥧", unit: "piece",
                        calories: 175, protein: 4, carbs: 19, fats: 9.5, restaurantPrice: 2.25, homeCost: 0.50),
        AYCECatalogItem(id: "ds_sesame_ball", cuisine: .dimSum, name: "Sesame ball", emoji: "🍡", unit: "piece",
                        calories: 130, protein: 2, carbs: 18, fats: 5.5, restaurantPrice: 1.80, homeCost: 0.35)
    ]

    // MARK: Indian buffet (per serving/piece as noted)

    static let indian: [AYCECatalogItem] = [
        AYCECatalogItem(id: "in_butter_chicken", cuisine: .indian, name: "Butter chicken", emoji: "🍛", unit: "serving",
                        calories: 420, protein: 28, carbs: 12, fats: 29, restaurantPrice: 15.95, homeCost: 3.80),
        AYCECatalogItem(id: "in_tikka_masala", cuisine: .indian, name: "Chicken tikka masala", emoji: "🍛", unit: "serving",
                        calories: 400, protein: 29, carbs: 14, fats: 26, restaurantPrice: 15.95, homeCost: 3.70),
        AYCECatalogItem(id: "in_tandoori_chicken", cuisine: .indian, name: "Tandoori chicken", emoji: "🍗", unit: "leg quarter",
                        calories: 260, protein: 32, carbs: 3, fats: 13, restaurantPrice: 13.95, homeCost: 2.90),
        AYCECatalogItem(id: "in_lamb_curry", cuisine: .indian, name: "Lamb curry", emoji: "🍛", unit: "serving",
                        calories: 380, protein: 27, carbs: 9, fats: 26, restaurantPrice: 17.95, homeCost: 4.80),
        AYCECatalogItem(id: "in_saag_paneer", cuisine: .indian, name: "Saag paneer", emoji: "🥬", unit: "serving",
                        calories: 300, protein: 13, carbs: 11, fats: 23, restaurantPrice: 13.95, homeCost: 2.60),
        AYCECatalogItem(id: "in_chana_masala", cuisine: .indian, name: "Chana masala", emoji: "🍛", unit: "serving",
                        calories: 250, protein: 11, carbs: 38, fats: 6.5, restaurantPrice: 11.95, homeCost: 1.60),
        AYCECatalogItem(id: "in_dal_makhani", cuisine: .indian, name: "Dal makhani", emoji: "🥣", unit: "serving",
                        calories: 280, protein: 12, carbs: 30, fats: 13, restaurantPrice: 11.95, homeCost: 1.50),
        AYCECatalogItem(id: "in_aloo_gobi", cuisine: .indian, name: "Aloo gobi", emoji: "🥔", unit: "serving",
                        calories: 190, protein: 5, carbs: 26, fats: 8, restaurantPrice: 11.95, homeCost: 1.70),
        AYCECatalogItem(id: "in_biryani", cuisine: .indian, name: "Chicken biryani", emoji: "🍚", unit: "serving",
                        calories: 420, protein: 24, carbs: 52, fats: 13, restaurantPrice: 14.95, homeCost: 2.90),
        AYCECatalogItem(id: "in_basmati_rice", cuisine: .indian, name: "Basmati rice", emoji: "🍚", unit: "bowl",
                        calories: 200, protein: 4, carbs: 43, fats: 1.5, restaurantPrice: 3.50, homeCost: 0.40),
        AYCECatalogItem(id: "in_naan", cuisine: .indian, name: "Naan", emoji: "🫓", unit: "piece",
                        calories: 260, protein: 8, carbs: 48, fats: 4.5, restaurantPrice: 3.95, homeCost: 0.50),
        AYCECatalogItem(id: "in_garlic_naan", cuisine: .indian, name: "Garlic naan", emoji: "🫓", unit: "piece",
                        calories: 290, protein: 8, carbs: 48, fats: 8, restaurantPrice: 4.50, homeCost: 0.60),
        AYCECatalogItem(id: "in_samosa", cuisine: .indian, name: "Samosa", emoji: "🥟", unit: "piece",
                        calories: 150, protein: 3, carbs: 17, fats: 8, restaurantPrice: 2.95, homeCost: 0.55),
        AYCECatalogItem(id: "in_pakora", cuisine: .indian, name: "Vegetable pakora", emoji: "🧅", unit: "order",
                        calories: 220, protein: 6, carbs: 22, fats: 12, restaurantPrice: 5.95, homeCost: 1.10),
        AYCECatalogItem(id: "in_raita", cuisine: .indian, name: "Raita", emoji: "🥣", unit: "bowl",
                        calories: 60, protein: 3, carbs: 6, fats: 2.5, restaurantPrice: 2.95, homeCost: 0.60),
        AYCECatalogItem(id: "in_gulab_jamun", cuisine: .indian, name: "Gulab jamun", emoji: "🍡", unit: "piece",
                        calories: 150, protein: 2, carbs: 22, fats: 6, restaurantPrice: 2.50, homeCost: 0.45),
        AYCECatalogItem(id: "in_mango_lassi", cuisine: .indian, name: "Mango lassi", emoji: "🥭", unit: "glass",
                        calories: 220, protein: 6, carbs: 38, fats: 5, restaurantPrice: 4.95, homeCost: 1.10)
    ]
}
