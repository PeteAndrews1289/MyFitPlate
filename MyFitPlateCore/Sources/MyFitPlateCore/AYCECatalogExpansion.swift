import Foundation

// Generic estimates for the stated portion; these are not chain-specific nutrition labels.
// Menu coverage was reviewed against Kura Sushi and GEN Korean BBQ in October 2026.
// See the buffet audit notes in docs/elite-quality-plan-2026-10-20.md for sourcing and limits.
extension AYCECatalog {

    static let extraSushiFish: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_albacore_nigiri", cuisine: .sushi, name: "Albacore nigiri", emoji: "🍣", unit: "piece",
                        calories: 55, protein: 4, carbs: 8, fats: 1, restaurantPrice: 3.5, homeCost: 1),
        AYCECatalogItem(id: "sushi_mackerel_nigiri", cuisine: .sushi, name: "Mackerel nigiri", emoji: "🍣", unit: "piece",
                        calories: 70, protein: 4, carbs: 8, fats: 2.5, restaurantPrice: 3.25, homeCost: 0.9),
        AYCECatalogItem(id: "sushi_squid_nigiri", cuisine: .sushi, name: "Squid nigiri", emoji: "🦑", unit: "piece",
                        calories: 50, protein: 4, carbs: 8, fats: 0.3, restaurantPrice: 3.25, homeCost: 0.85),
        AYCECatalogItem(id: "sushi_surf_clam_nigiri", cuisine: .sushi, name: "Surf clam nigiri", emoji: "🍣", unit: "piece",
                        calories: 50, protein: 4, carbs: 8, fats: 0.4, restaurantPrice: 3.5, homeCost: 1),
        AYCECatalogItem(id: "sushi_crab_nigiri", cuisine: .sushi, name: "Snow crab nigiri", emoji: "🦀", unit: "piece",
                        calories: 50, protein: 4, carbs: 8, fats: 0.4, restaurantPrice: 4.5, homeCost: 1.5),
        AYCECatalogItem(id: "sushi_sweet_shrimp_nigiri", cuisine: .sushi, name: "Sweet shrimp nigiri", emoji: "🍤", unit: "piece",
                        calories: 50, protein: 4, carbs: 8, fats: 0.3, restaurantPrice: 4, homeCost: 1.3),
        AYCECatalogItem(id: "sushi_whitefish_nigiri", cuisine: .sushi, name: "Whitefish nigiri", emoji: "🍣", unit: "piece",
                        calories: 55, protein: 4, carbs: 8, fats: 0.8, restaurantPrice: 3.5, homeCost: 1),
        AYCECatalogItem(id: "sushi_salmon_belly_nigiri", cuisine: .sushi, name: "Salmon belly nigiri", emoji: "🍣", unit: "piece",
                        calories: 85, protein: 4, carbs: 8, fats: 4, restaurantPrice: 4, homeCost: 1.3),
        AYCECatalogItem(id: "sushi_seared_salmon_nigiri", cuisine: .sushi, name: "Seared salmon with mayo nigiri", emoji: "🍣", unit: "piece",
                        calories: 90, protein: 4, carbs: 9, fats: 4.5, restaurantPrice: 4, homeCost: 1.2),
        AYCECatalogItem(id: "sushi_uni_gunkan", cuisine: .sushi, name: "Sea urchin gunkan", emoji: "🍣", unit: "piece",
                        calories: 55, protein: 3, carbs: 8, fats: 1, restaurantPrice: 6, homeCost: 2.5),
        AYCECatalogItem(id: "sushi_tobiko_gunkan", cuisine: .sushi, name: "Flying fish roe gunkan", emoji: "🍣", unit: "piece",
                        calories: 60, protein: 4, carbs: 8, fats: 1.5, restaurantPrice: 3.75, homeCost: 1.1),
        AYCECatalogItem(id: "sushi_negitoro_gunkan", cuisine: .sushi, name: "Minced tuna belly gunkan", emoji: "🍣", unit: "piece",
                        calories: 75, protein: 4, carbs: 8, fats: 3, restaurantPrice: 4.5, homeCost: 1.5),
        AYCECatalogItem(id: "sushi_yellowtail_sashimi", cuisine: .sushi, name: "Yellowtail sashimi", emoji: "🐟", unit: "slice (25 g)",
                        calories: 40, protein: 5, carbs: 0, fats: 2, restaurantPrice: 3.5, homeCost: 1.2),
        AYCECatalogItem(id: "sushi_albacore_sashimi", cuisine: .sushi, name: "Albacore sashimi", emoji: "🐟", unit: "slice (25 g)",
                        calories: 35, protein: 6, carbs: 0, fats: 1, restaurantPrice: 3.25, homeCost: 1),
        AYCECatalogItem(id: "sushi_scallop_sashimi", cuisine: .sushi, name: "Scallop sashimi", emoji: "🍣", unit: "piece (25 g)",
                        calories: 25, protein: 4, carbs: 1, fats: 0.2, restaurantPrice: 3.95, homeCost: 1.3),
        AYCECatalogItem(id: "sushi_salmon_belly_sashimi", cuisine: .sushi, name: "Salmon belly sashimi", emoji: "🐟", unit: "slice (25 g)",
                        calories: 65, protein: 5, carbs: 0, fats: 5, restaurantPrice: 3.75, homeCost: 1.3)
    ]

    static let extraSushiRolls: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_spicy_salmon_roll", cuisine: .sushi, name: "Spicy salmon roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 300, protein: 11, carbs: 36, fats: 12, restaurantPrice: 8.5, homeCost: 2.5, piecesPerUnit: 6),
        AYCECatalogItem(id: "sushi_spicy_crab_roll", cuisine: .sushi, name: "Spicy crab roll", emoji: "🦀", unit: "roll (6 pc)",
                        calories: 300, protein: 8, carbs: 40, fats: 12, restaurantPrice: 8, homeCost: 2, piecesPerUnit: 6),
        AYCECatalogItem(id: "sushi_spicy_scallop_roll", cuisine: .sushi, name: "Spicy scallop roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 290, protein: 11, carbs: 35, fats: 12, restaurantPrice: 9.5, homeCost: 3, piecesPerUnit: 6),
        AYCECatalogItem(id: "sushi_oshinko_roll", cuisine: .sushi, name: "Pickled radish roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 150, protein: 3, carbs: 32, fats: 1, restaurantPrice: 5.5, homeCost: 0.9, piecesPerUnit: 6),
        AYCECatalogItem(id: "sushi_asparagus_roll", cuisine: .sushi, name: "Asparagus roll", emoji: "🍱", unit: "roll (6 pc)",
                        calories: 150, protein: 4, carbs: 31, fats: 1, restaurantPrice: 6, homeCost: 1.2, piecesPerUnit: 6)
    ]

    static let extraSushiHandRolls: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_spicy_tuna_hand_roll", cuisine: .sushi, name: "Spicy tuna hand roll", emoji: "🍱", unit: "hand roll",
                        calories: 180, protein: 9, carbs: 22, fats: 6, restaurantPrice: 5.5, homeCost: 1.7),
        AYCECatalogItem(id: "sushi_california_hand_roll", cuisine: .sushi, name: "California hand roll", emoji: "🦀", unit: "hand roll",
                        calories: 170, protein: 5, carbs: 24, fats: 6, restaurantPrice: 5, homeCost: 1.4),
        AYCECatalogItem(id: "sushi_eel_hand_roll", cuisine: .sushi, name: "Eel hand roll", emoji: "🍱", unit: "hand roll",
                        calories: 210, protein: 8, carbs: 26, fats: 8, restaurantPrice: 6, homeCost: 1.8),
        AYCECatalogItem(id: "sushi_salmon_skin_hand_roll", cuisine: .sushi, name: "Salmon skin hand roll", emoji: "🍱", unit: "hand roll",
                        calories: 190, protein: 7, carbs: 23, fats: 8, restaurantPrice: 5.5, homeCost: 1.5),
        AYCECatalogItem(id: "sushi_spicy_scallop_hand_roll", cuisine: .sushi, name: "Spicy scallop hand roll", emoji: "🍱", unit: "hand roll",
                        calories: 190, protein: 8, carbs: 22, fats: 8, restaurantPrice: 6, homeCost: 1.8),
        AYCECatalogItem(id: "sushi_vegetable_hand_roll", cuisine: .sushi, name: "Vegetable hand roll", emoji: "🥑", unit: "hand roll",
                        calories: 130, protein: 2, carbs: 23, fats: 4, restaurantPrice: 4.5, homeCost: 1)
    ]

    static let extraSushiSides: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_agedashi_tofu", cuisine: .sushi, name: "Agedashi tofu", emoji: "🍲", unit: "side (150 g)",
                        calories: 210, protein: 9, carbs: 18, fats: 11, restaurantPrice: 6.5, homeCost: 1.4),
        AYCECatalogItem(id: "sushi_chicken_karaage", cuisine: .sushi, name: "Chicken karaage", emoji: "🍗", unit: "side (100 g)",
                        calories: 280, protein: 20, carbs: 14, fats: 16, restaurantPrice: 7.5, homeCost: 2),
        AYCECatalogItem(id: "sushi_takoyaki", cuisine: .sushi, name: "Takoyaki", emoji: "🐙", unit: "piece",
                        calories: 55, protein: 2, carbs: 7, fats: 2, restaurantPrice: 1.5, homeCost: 0.4),
        AYCECatalogItem(id: "sushi_cucumber_salad", cuisine: .sushi, name: "Cucumber sunomono", emoji: "🥒", unit: "side (100 g)",
                        calories: 40, protein: 1, carbs: 8, fats: 0.5, restaurantPrice: 4.5, homeCost: 0.8),
        AYCECatalogItem(id: "sushi_green_tea_ice_cream", cuisine: .sushi, name: "Green tea ice cream", emoji: "🍨", unit: "scoop (65 g)",
                        calories: 140, protein: 2, carbs: 18, fats: 7, restaurantPrice: 3.5, homeCost: 0.8)
    ]

    static let sushiSauces: [AYCECatalogItem] = [
        AYCECatalogItem(id: "sushi_spicy_mayo", cuisine: .sushi, name: "Spicy mayo", emoji: "🥣", unit: "tbsp (15 g)",
                        calories: 100, protein: 0, carbs: 1, fats: 11, restaurantPrice: 0.75, homeCost: 0.2),
        AYCECatalogItem(id: "sushi_eel_sauce", cuisine: .sushi, name: "Eel sauce", emoji: "🥣", unit: "tbsp (15 g)",
                        calories: 35, protein: 0, carbs: 9, fats: 0, restaurantPrice: 0.5, homeCost: 0.15),
        AYCECatalogItem(id: "sushi_soy_sauce", cuisine: .sushi, name: "Soy sauce", emoji: "🥣", unit: "tbsp (15 ml)",
                        calories: 10, protein: 1, carbs: 1, fats: 0, restaurantPrice: 0.25, homeCost: 0.05)
    ]

    static let extraKBBQBeef: [AYCECatalogItem] = [
        AYCECatalogItem(id: "kbbq_ribeye", cuisine: .kbbq, name: "Ribeye steak", emoji: "🥩", unit: "serving (110 g cooked)",
                        calories: 330, protein: 28, carbs: 0, fats: 24, restaurantPrice: 19, homeCost: 6, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_skirt_steak", cuisine: .kbbq, name: "Skirt steak", emoji: "🥩", unit: "serving (110 g cooked)",
                        calories: 290, protein: 30, carbs: 0, fats: 19, restaurantPrice: 17, homeCost: 5, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_beef_belly", cuisine: .kbbq, name: "Beef belly", emoji: "🥩", unit: "serving (110 g cooked)",
                        calories: 420, protein: 20, carbs: 0, fats: 38, restaurantPrice: 16, homeCost: 4, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_spicy_beef_belly", cuisine: .kbbq, name: "Spicy marinated beef belly", emoji: "🥩", unit: "serving (110 g cooked)",
                        calories: 440, protein: 19, carbs: 9, fats: 37, restaurantPrice: 17, homeCost: 4.2, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_boneless_short_rib", cuisine: .kbbq, name: "Boneless short rib", emoji: "🥩", unit: "serving (110 g cooked)",
                        calories: 390, protein: 25, carbs: 0, fats: 32, restaurantPrice: 20, homeCost: 6.5, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_daechang", cuisine: .kbbq, name: "Marinated large intestine", emoji: "🥩", unit: "serving (110 g cooked)",
                        calories: 390, protein: 13, carbs: 12, fats: 32, restaurantPrice: 16, homeCost: 3.5, cookedGramsPerUnit: 110)
    ]

    static let extraKBBQPork: [AYCECatalogItem] = [
        AYCECatalogItem(id: "kbbq_garlic_pork_belly", cuisine: .kbbq, name: "Garlic pork belly", emoji: "🥓", unit: "serving (110 g cooked)",
                        calories: 460, protein: 18, carbs: 5, fats: 41, restaurantPrice: 15, homeCost: 3.4, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_spicy_pork_belly", cuisine: .kbbq, name: "Spicy pork belly", emoji: "🥓", unit: "serving (110 g cooked)",
                        calories: 460, protein: 18, carbs: 9, fats: 39, restaurantPrice: 15, homeCost: 3.4, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_pork_collar", cuisine: .kbbq, name: "Pork collar", emoji: "🥩", unit: "serving (110 g cooked)",
                        calories: 320, protein: 26, carbs: 0, fats: 24, restaurantPrice: 14, homeCost: 3, cookedGramsPerUnit: 110)
    ]

    static let extraKBBQChickenAndSeafood: [AYCECatalogItem] = [
        AYCECatalogItem(id: "kbbq_garlic_chicken", cuisine: .kbbq, name: "Garlic chicken thigh", emoji: "🍗", unit: "serving (110 g cooked)",
                        calories: 260, protein: 27, carbs: 8, fats: 13, restaurantPrice: 13, homeCost: 2.8, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_spicy_chicken", cuisine: .kbbq, name: "Spicy chicken thigh", emoji: "🍗", unit: "serving (110 g cooked)",
                        calories: 270, protein: 27, carbs: 10, fats: 14, restaurantPrice: 13, homeCost: 2.8, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_grilled_shrimp", cuisine: .kbbq, name: "Grilled shrimp", emoji: "🍤", unit: "serving (110 g cooked)",
                        calories: 130, protein: 25, carbs: 1, fats: 3, restaurantPrice: 14, homeCost: 4, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_garlic_squid", cuisine: .kbbq, name: "Garlic squid", emoji: "🦑", unit: "serving (110 g cooked)",
                        calories: 180, protein: 22, carbs: 8, fats: 7, restaurantPrice: 14, homeCost: 3.5, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_spicy_octopus", cuisine: .kbbq, name: "Spicy baby octopus", emoji: "🐙", unit: "serving (110 g cooked)",
                        calories: 190, protein: 25, carbs: 11, fats: 5, restaurantPrice: 15, homeCost: 4, cookedGramsPerUnit: 110),
        AYCECatalogItem(id: "kbbq_grilled_salmon", cuisine: .kbbq, name: "Grilled salmon", emoji: "🐟", unit: "serving (110 g cooked)",
                        calories: 230, protein: 25, carbs: 0, fats: 14, restaurantPrice: 16, homeCost: 4.5, cookedGramsPerUnit: 110)
    ]

    static let extraKBBQBanchan: [AYCECatalogItem] = [
        AYCECatalogItem(id: "kbbq_kimchi", cuisine: .kbbq, name: "Napa cabbage kimchi", emoji: "🥬", unit: "side (50 g)",
                        calories: 20, protein: 1, carbs: 3, fats: 0.5, restaurantPrice: 1, homeCost: 0.25),
        AYCECatalogItem(id: "kbbq_cucumber_kimchi", cuisine: .kbbq, name: "Cucumber kimchi", emoji: "🥒", unit: "side (50 g)",
                        calories: 25, protein: 1, carbs: 4, fats: 0.5, restaurantPrice: 1, homeCost: 0.25),
        AYCECatalogItem(id: "kbbq_bean_sprouts", cuisine: .kbbq, name: "Seasoned bean sprouts", emoji: "🌱", unit: "side (50 g)",
                        calories: 40, protein: 2, carbs: 3, fats: 2, restaurantPrice: 1.25, homeCost: 0.3),
        AYCECatalogItem(id: "kbbq_spinach", cuisine: .kbbq, name: "Seasoned spinach", emoji: "🥬", unit: "side (50 g)",
                        calories: 45, protein: 2, carbs: 3, fats: 3, restaurantPrice: 1.25, homeCost: 0.3),
        AYCECatalogItem(id: "kbbq_pickled_radish", cuisine: .kbbq, name: "Pickled radish wraps", emoji: "🥬", unit: "side (50 g)",
                        calories: 20, protein: 0, carbs: 5, fats: 0, restaurantPrice: 1, homeCost: 0.25),
        AYCECatalogItem(id: "kbbq_potato_salad", cuisine: .kbbq, name: "Korean potato salad", emoji: "🥔", unit: "side (75 g)",
                        calories: 130, protein: 2, carbs: 16, fats: 7, restaurantPrice: 2, homeCost: 0.5),
        AYCECatalogItem(id: "kbbq_grilled_mushrooms", cuisine: .kbbq, name: "Grilled mushrooms", emoji: "🍄", unit: "side (75 g)",
                        calories: 45, protein: 2, carbs: 4, fats: 2, restaurantPrice: 3, homeCost: 0.8),
        AYCECatalogItem(id: "kbbq_grilled_tofu", cuisine: .kbbq, name: "Grilled tofu", emoji: "🍲", unit: "side (100 g)",
                        calories: 140, protein: 14, carbs: 3, fats: 8, restaurantPrice: 4, homeCost: 1)
    ]

    static let extraKBBQSides: [AYCECatalogItem] = [
        AYCECatalogItem(id: "kbbq_fried_chicken", cuisine: .kbbq, name: "Korean fried chicken", emoji: "🍗", unit: "side (100 g)",
                        calories: 310, protein: 19, carbs: 22, fats: 16, restaurantPrice: 8, homeCost: 2),
        AYCECatalogItem(id: "kbbq_kimchi_pancake", cuisine: .kbbq, name: "Kimchi pancake", emoji: "🥞", unit: "small pancake (100 g)",
                        calories: 230, protein: 5, carbs: 31, fats: 10, restaurantPrice: 7, homeCost: 1.3),
        AYCECatalogItem(id: "kbbq_tteokbokki", cuisine: .kbbq, name: "Spicy rice cakes", emoji: "🍚", unit: "side (150 g)",
                        calories: 280, protein: 5, carbs: 57, fats: 3, restaurantPrice: 7, homeCost: 1.2)
    ]

    static let kbbqSauces: [AYCECatalogItem] = [
        AYCECatalogItem(id: "kbbq_ssamjang", cuisine: .kbbq, name: "Ssamjang dipping paste", emoji: "🥣", unit: "tbsp (20 g)",
                        calories: 40, protein: 2, carbs: 6, fats: 1, restaurantPrice: 1, homeCost: 0.25),
        AYCECatalogItem(id: "kbbq_sesame_oil", cuisine: .kbbq, name: "Sesame oil with salt", emoji: "🥣", unit: "tsp (5 ml)",
                        calories: 40, protein: 0, carbs: 0, fats: 4.5, restaurantPrice: 0.5, homeCost: 0.15),
        AYCECatalogItem(id: "kbbq_gochujang", cuisine: .kbbq, name: "Gochujang", emoji: "🥣", unit: "tbsp (20 g)",
                        calories: 40, protein: 1, carbs: 9, fats: 0, restaurantPrice: 1, homeCost: 0.25),
        AYCECatalogItem(id: "kbbq_soy_garlic_sauce", cuisine: .kbbq, name: "Soy garlic dipping sauce", emoji: "🥣", unit: "tbsp (15 ml)",
                        calories: 25, protein: 1, carbs: 5, fats: 0, restaurantPrice: 0.75, homeCost: 0.15)
    ]

    static let kbbqBeef = kbbqOriginal.filter { ["kbbq_bulgogi", "kbbq_galbi", "kbbq_brisket", "kbbq_beef_tongue"].contains($0.id) } + extraKBBQBeef
    static let kbbqPork = kbbqOriginal.filter { ["kbbq_pork_belly", "kbbq_pork_jowl", "kbbq_spicy_pork"].contains($0.id) } + extraKBBQPork
    static let kbbqChickenAndSeafood = kbbqOriginal.filter { $0.id == "kbbq_chicken_bulgogi" } + extraKBBQChickenAndSeafood
    static let kbbqBanchan = kbbqOriginal.filter { ["kbbq_banchan", "kbbq_lettuce_wraps"].contains($0.id) } + extraKBBQBanchan
    static let kbbqSides = kbbqOriginal.filter { !["kbbq_bulgogi", "kbbq_galbi", "kbbq_brisket", "kbbq_beef_tongue", "kbbq_pork_belly", "kbbq_pork_jowl", "kbbq_spicy_pork", "kbbq_chicken_bulgogi", "kbbq_banchan", "kbbq_lettuce_wraps"].contains($0.id) } + extraKBBQSides
    static let kbbq = kbbqBeef + kbbqPork + kbbqChickenAndSeafood + kbbqBanchan + kbbqSides + kbbqSauces

    static let searchAliases: [String: [String]] = [
        "kbbq_pork_belly": ["samgyeopsal", "samgyupsal", "samgyubsal"],
        "kbbq_garlic_pork_belly": ["garlic samgyeopsal", "garlic samgyubsal"],
        "kbbq_spicy_pork_belly": ["spicy samgyeopsal", "spicy samgyubsal"],
        "kbbq_brisket": ["chadol", "chadolbaegi"],
        "kbbq_galbi": ["kalbi", "LA galbi", "yangnyeom galbi", "bone in"],
        "kbbq_boneless_short_rib": ["galbi", "kalbi"],
        "kbbq_pork_jowl": ["hangjeongsal", "hangjungsal", "pork cheek"],
        "kbbq_pork_collar": ["moksal", "pork neck"],
        "kbbq_beef_belly": ["woo samgyeop", "woo beasal", "short plate"],
        "kbbq_beef_tongue": ["gyutan", "usul"],
        "kbbq_spicy_pork": ["dwaeji bulgogi", "jeyuk bokkeum"],
        "kbbq_daechang": ["daechang", "offal"],
        "kbbq_spicy_octopus": ["jukkumi", "jjukkumi"],
        "kbbq_steamed_egg": ["gyeran jjim", "gyeranjjim"],
        "kbbq_soft_tofu_stew": ["sundubu", "soondubu", "jjigae"],
        "kbbq_kimchi_stew": ["kimchi jjigae"],
        "kbbq_naengmyeon": ["naengmyeon", "naengmyun"],
        "kbbq_pajeon": ["haemul pajeon"],
        "kbbq_bean_sprouts": ["kongnamul", "sukju namul"],
        "kbbq_spinach": ["sigeumchi namul"],
        "kbbq_pickled_radish": ["ssam mu", "ssammu"],
        "kbbq_potato_salad": ["gamja salad"],
        "kbbq_tteokbokki": ["ddukbokki", "topokki"],
        "sushi_salmon_nigiri": ["sake"],
        "sushi_tuna_nigiri": ["maguro"],
        "sushi_yellowtail_nigiri": ["hamachi"],
        "sushi_yellowtail_sashimi": ["hamachi"],
        "sushi_eel_nigiri": ["unagi"],
        "sushi_mackerel_nigiri": ["saba"],
        "sushi_squid_nigiri": ["ika"],
        "sushi_surf_clam_nigiri": ["hokkigai"],
        "sushi_sweet_shrimp_nigiri": ["amaebi"],
        "sushi_scallop_nigiri": ["hotate"],
        "sushi_tako_nigiri": ["tako"],
        "sushi_tamago_nigiri": ["egg omelet"],
        "sushi_ikura_gunkan": ["salmon roe"],
        "sushi_uni_gunkan": ["uni"],
        "sushi_tobiko_gunkan": ["tobiko"],
        "sushi_negitoro_gunkan": ["negitoro"],
        "sushi_seared_salmon_nigiri": ["aburi"],
        "sushi_oshinko_roll": ["oshinko", "takuan"],
        "sushi_negihama_roll": ["negihama", "hamachi"],
        "sushi_spicy_mayo": ["sriracha mayo"]
    ]
}
