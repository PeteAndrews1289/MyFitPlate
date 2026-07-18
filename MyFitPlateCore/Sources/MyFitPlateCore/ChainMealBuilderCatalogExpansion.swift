import Foundation

extension ChainRestaurantCatalog {
    static func expandingMenu(_ chain: ChainRestaurant) -> ChainRestaurant {
        guard let supplemental = supplementalCategories[chain.id], !supplemental.isEmpty else {
            return chain
        }

        return ChainRestaurant(
            id: chain.id,
            name: chain.name,
            subtitle: chain.subtitle,
            iconName: chain.iconName,
            brandColorHex: chain.brandColorHex,
            categories: chain.categories + supplemental
        )
    }

    public static func officialNutritionURL(for chainID: String) -> URL? {
        guard let source = officialNutritionSources[chainID] else { return nil }
        return URL(string: source)
    }

    private static let officialNutritionSources: [String: String] = [
        "chipotle": "https://www.chipotle.com/nutrition-calculator",
        "sweetgreen": "https://www.sweetgreen.com/menu",
        "cava": "https://cava.com/nutrition",
        "chick_fil_a": "https://www.chick-fil-a.com/nutrition-allergens",
        "taco_bell": "https://www.tacobell.com/nutrition/calculator",
        "mcdonalds": "https://www.mcdonalds.com/us/en-us/about-our-food/nutrition-calculator.html",
        "in_n_out": "https://www.in-n-out.com/menu/nutrition-info",
        "panera": "https://www.panerabread.com/en-us/menu/nutrition.html",
        "burger_king": "https://www.bk.com/nutrition-explorer",
        "popeyes": "https://www.popeyes.com/nutritional-information",
        "panda_express": "https://www.pandaexpress.com/nutritioninformation",
        "qdoba": "https://www.qdoba.com/nutrition-allergens",
        "shake_shack": "https://shakeshack.com/nutrition-allergens",
        "subway": "https://www.subway.com/en-us/menunutrition1/nutrition",
        "starbucks": "https://www.starbucks.com/menu",
        "dunkin": "https://www.dunkindonuts.com/en/menu/nutrition",
        "jersey_mikes": "https://www.jerseymikes.com/menu/nutrition",
        "jimmy_johns": "https://www.jimmyjohns.com/menu",
        "firehouse_subs": "https://www.firehousesubs.com/nutritional-information",
        "wingstop": "https://www.wingstop.com/nutrition",
        "culvers": "https://www.culvers.com/menu-and-nutrition/nutrition-and-allergen-guide",
        "wendys": "https://www.wendys.com/en-us/nutrition-and-health",
        "tropical_smoothie": "https://www.tropicalsmoothiecafe.com/nutrition",
        "dominos": "https://www.dominos.com/en/pages/content/nutritional/nutrition",
        "five_guys": "https://www.fiveguys.com/our-food/"
    ]

    private static let supplementalCategories: [String: [ChainCategory]] = [
        "sweetgreen": [
            menuCategory("sg_signatures", "Signature Bowls & Salads", [
                menu("sg_harvest_bowl", "Harvest Bowl", 740, 32, 60, 41),
                menu("sg_crispy_rice_bowl", "Crispy Rice Bowl", 640, 28, 61, 30),
                menu("sg_chicken_pesto_parm", "Chicken Pesto Parm", 525, 35, 38, 23),
                menu("sg_chicken_avocado_ranch", "Chicken Avocado Ranch", 715, 23, 59, 42)
            ])
        ],
        "cava": [
            menuCategory("cava_signatures", "Signature Bowls & Salads", [
                menu("cv_chicken_rice_bowl", "Chicken + Rice Bowl", 700, 35, 78, 27),
                menu("cv_harissa_avocado_bowl", "Harissa Avocado Bowl", 830, 34, 81, 42),
                menu("cv_steak_harissa_bowl", "Steak + Harissa Bowl", 620, 36, 54, 29),
                menu("cv_greek_salad", "Greek Salad", 580, 30, 38, 34)
            ])
        ],
        "panda_express": [
            menuCategory("pe_more_menu", "More Entrees & Appetizers", [
                menu("pe_mushroom_chicken", "Mushroom Chicken", 220, 13, 10, 14),
                menu("pe_wok_fired_shrimp", "Wok-Fired Shrimp", 190, 17, 19, 5),
                menu("pe_chicken_egg_roll", "Chicken Egg Roll", 200, 6, 20, 10),
                menu("pe_chicken_potstickers", "Chicken Potstickers (3)", 160, 6, 20, 6)
            ])
        ],
        "qdoba": [
            menuCategory("qd_more_ingredients", "More Ingredients", [
                menu("qd_pinto_beans", "Pinto Beans", 130, 8, 22, 1.5),
                menu("qd_fajita_veggies", "Fajita Veggies", 35, 1, 6, 1),
                menu("qd_pico", "Pico de Gallo", 20, 1, 4, 0),
                menu("qd_corn_salsa", "Chile Corn Salsa", 60, 2, 12, 1),
                menu("qd_shredded_cheese", "Shredded Cheese", 110, 7, 1, 9),
                menu("qd_sour_cream", "Sour Cream", 90, 1, 2, 9),
                menu("qd_burrito_tortilla", "Flour Tortilla", 300, 8, 50, 8)
            ])
        ],
        "shake_shack": [
            menuCategory("ss_popular_menu", "Popular Menu Items", [
                menu("ss_shackburger_single", "Single ShackBurger", 500, 29, 26, 30),
                menu("ss_shackburger_double", "Double ShackBurger", 760, 51, 27, 48),
                menu("ss_smokeshack_single", "Single SmokeShack", 570, 36, 28, 35),
                menu("ss_shroom_burger", "'Shroom Burger", 510, 18, 49, 27),
                menu("ss_shack_stack", "Shack Stack", 770, 40, 50, 45),
                menu("ss_hamburger_single", "Single Hamburger", 370, 25, 24, 18),
                menu("ss_cheeseburger_single", "Single Cheeseburger", 440, 29, 25, 24),
                menu("ss_fries_regular", "Crinkle Cut Fries", 470, 6, 63, 22)
            ])
        ],
        "subway": [
            menuCategory("sub_popular_six_inch", "Popular 6-Inch Subs", [
                menu("sub_turkey_6", "Oven-Roasted Turkey", 280, 20, 40, 4),
                menu("sub_black_forest_ham_6", "Black Forest Ham", 280, 18, 42, 4),
                menu("sub_tuna_6", "Tuna", 510, 20, 40, 28),
                menu("sub_steak_cheese_6", "Steak & Cheese", 370, 26, 45, 10),
                menu("sub_meatball_6", "Meatball Marinara", 460, 20, 55, 18),
                menu("sub_veggie_delite_6", "Veggie Delite", 200, 8, 39, 2),
                menu("sub_italian_bmt_6", "Italian B.M.T.", 410, 21, 46, 16),
                menu("sub_chicken_teriyaki_6", "Sweet Onion Chicken Teriyaki", 340, 25, 54, 3),
                menu("sub_all_american_club_6", "All-American Club", 540, 27, 45, 28)
            ])
        ],
        "jersey_mikes": [
            menuCategory("jm_popular_regular", "Popular Regular Subs", [
                menu("jm_7_turkey_provolone", "#7 Turkey & Provolone", 780, 46, 58, 40),
                menu("jm_13_original_italian", "#13 Original Italian", 930, 47, 62, 55),
                menu("jm_8_club_sub", "#8 Club Sub", 1_110, 66, 61, 67),
                menu("jm_17_philly", "#17 Mike's Famous Philly", 700, 48, 56, 32),
                menu("jm_43_chipotle_steak", "#43 Chipotle Cheese Steak", 980, 53, 68, 55),
                menu("jm_56_big_kahuna_chicken", "#56 Big Kahuna Chicken", 770, 55, 58, 35),
                menu("jm_3_ham_provolone", "#3 Ham & Provolone", 810, 47, 59, 43),
                menu("jm_14_veggie", "#14 The Veggie", 930, 34, 68, 58)
            ])
        ],
        "wingstop": [
            menuCategory("ws_more_flavors", "More Flavors", [
                menu("ws_cajun", "Cajun Seasoning", 5, 0, 1, 0, serving: "Flavor for 5 wings"),
                menu("ws_mango_habanero", "Mango Habanero", 70, 0, 18, 0, serving: "Flavor for 5 wings"),
                menu("ws_hickory_bbq", "Hickory Smoked BBQ", 50, 0, 13, 0, serving: "Flavor for 5 wings"),
                menu("ws_hawaiian", "Hawaiian", 35, 0, 9, 0, serving: "Flavor for 5 wings"),
                menu("ws_louisiana_rub", "Louisiana Rub", 60, 0, 2, 6, serving: "Flavor for 5 wings"),
                menu("ws_mild", "Mild Sauce", 90, 0, 2, 9, serving: "Flavor for 5 wings"),
                menu("ws_spicy_korean_q", "Spicy Korean Q", 70, 0, 18, 0, serving: "Flavor for 5 wings")
            ])
        ],
        "chick_fil_a": [
            menuCategory("cfa_more_entrees", "More Entrees", [
                menu("cfa_original_sandwich", "Chick-fil-A Chicken Sandwich", 420, 29, 41, 18),
                menu("cfa_chick_n_strips_3", "Chick-n-Strips (3 Ct)", 310, 29, 16, 14),
                menu("cfa_market_salad", "Market Salad with Grilled Filet", 320, 28, 26, 12)
            ])
        ],
        "taco_bell": [
            menuCategory("tb_popular_menu", "Popular Menu Items", [
                menu("tb_crunchwrap_supreme", "Crunchwrap Supreme", 530, 16, 71, 21),
                menu("tb_cheesy_gordita_crunch", "Cheesy Gordita Crunch", 490, 20, 41, 28),
                menu("tb_chicken_quesadilla", "Chicken Quesadilla", 520, 27, 41, 26),
                menu("tb_bean_burrito", "Bean Burrito", 360, 13, 54, 10),
                menu("tb_mexican_pizza", "Mexican Pizza", 540, 19, 49, 29),
                menu("tb_nachos_bellgrande", "Nachos BellGrande", 730, 16, 82, 38)
            ])
        ],
        "in_n_out": [
            menuCategory("ino_more_menu", "More Burgers, Fries & Shakes", [
                menu("ino_hamburger", "Hamburger with Onion", 360, 16, 39, 16),
                menu("ino_hamburger_protein", "Hamburger Protein Style", 200, 13, 11, 14),
                menu("ino_3x3", "3x3 Burger", 860, 52, 39, 54),
                menu("ino_4x4", "4x4 Burger", 1_050, 68, 39, 70),
                menu("ino_animal_fries", "Animal Style Fries", 750, 15, 71, 45),
                menu("ino_vanilla_shake", "Vanilla Shake", 590, 10, 72, 30),
                menu("ino_chocolate_shake", "Chocolate Shake", 610, 10, 84, 29),
                menu("ino_strawberry_shake", "Strawberry Shake", 590, 10, 81, 27)
            ])
        ],
        "panera": [
            menuCategory("panera_popular_menu", "Popular Menu Items", [
                menu("pan_bacon_turkey_bravo", "Bacon Turkey Bravo (Whole)", 900, 54, 80, 40),
                menu("pan_frontega_chicken", "Frontega Chicken (Whole)", 850, 44, 82, 38),
                menu("pan_chipotle_avocado_melt", "Chipotle Chicken Avocado Melt", 920, 43, 85, 45),
                menu("pan_garden_caprese", "Toasted Garden Caprese", 890, 31, 100, 41),
                menu("pan_caesar_chicken", "Caesar Salad with Chicken", 550, 37, 24, 34),
                menu("pan_green_goddess_cobb", "Green Goddess Cobb with Chicken", 510, 40, 28, 27),
                menu("pan_mac_cheese_bowl", "Mac & Cheese (Bowl)", 960, 31, 92, 52),
                menu("pan_tomato_soup_bowl", "Creamy Tomato Soup (Bowl)", 370, 6, 42, 20),
                menu("pan_asiago_bagel", "Asiago Cheese Bagel", 310, 12, 47, 7),
                menu("pan_yogurt_berries", "Greek Yogurt with Mixed Berries", 250, 16, 47, 2)
            ])
        ],
        "culvers": [
            menuCategory("cul_popular_menu", "Popular Menu Items", [
                menu("cul_original_single", "Original ButterBurger Single", 390, 20, 38, 18),
                menu("cul_deluxe_single", "ButterBurger Deluxe Single", 570, 26, 42, 33),
                menu("cul_bacon_deluxe_single", "Bacon Deluxe Single", 610, 31, 43, 34),
                menu("cul_mushroom_swiss_single", "Mushroom & Swiss Single", 500, 26, 40, 27),
                menu("cul_grilled_chicken", "Grilled Chicken Sandwich", 390, 41, 40, 7),
                menu("cul_cod_sandwich", "North Atlantic Cod Sandwich", 600, 25, 51, 33),
                menu("cul_crinkle_fries_regular", "Crinkle Cut Fries (Regular)", 360, 5, 53, 14),
                menu("cul_mashed_gravy_regular", "Mashed Potatoes & Gravy (Regular)", 130, 3, 20, 4),
                menu("cul_chili_regular", "George's Chili (Regular)", 300, 20, 26, 13),
                menu("cul_vanilla_dish", "Vanilla Frozen Custard Dish", 310, 6, 31, 18)
            ])
        ],
        "wendys": [
            menuCategory("wen_popular_menu", "Popular Menu Items", [
                menu("wen_baconator", "Baconator", 960, 57, 36, 66),
                menu("wen_son_baconator", "Son of Baconator", 630, 32, 37, 40),
                menu("wen_jr_bacon_cheeseburger", "Jr. Bacon Cheeseburger", 370, 18, 26, 22),
                menu("wen_pretzel_baconator", "Pretzel Baconator", 1_050, 61, 43, 72),
                menu("wen_crispy_chicken", "Crispy Chicken Sandwich", 330, 14, 33, 15),
                menu("wen_nuggets_10", "Crispy Chicken Nuggets (10 Pc)", 450, 25, 22, 31),
                menu("wen_fries_medium", "Natural-Cut Fries (Medium)", 350, 5, 47, 15),
                menu("wen_chili_large", "Chili (Large)", 340, 22, 31, 15),
                menu("wen_taco_salad", "Taco Salad", 690, 30, 68, 34),
                menu("wen_vanilla_frosty_small", "Vanilla Frosty (Small)", 340, 10, 58, 8)
            ])
        ],
        "mcdonalds": [
            menuCategory("mcd_more_menu", "More Menu Items", [
                menu("mcd_filet_o_fish", "Filet-O-Fish", 380, 16, 39, 18),
                menu("mcd_double_cheeseburger", "Double Cheeseburger", 450, 24, 34, 24),
                menu("mcd_hamburger", "Hamburger", 250, 13, 31, 9),
                menu("mcd_mccrispy", "McCrispy", 470, 26, 46, 20),
                menu("mcd_vanilla_cone", "Vanilla Cone", 200, 5, 33, 5)
            ])
        ],
        "burger_king": [
            menuCategory("bk_more_menu", "More Menu Items", [
                menu("bk_bacon_king", "Bacon King", 1_200, 66, 50, 81),
                menu("bk_double_whopper", "Double Whopper", 920, 48, 50, 59),
                menu("bk_bacon_cheeseburger", "Bacon Cheeseburger", 340, 17, 28, 18),
                menu("bk_royal_crispy", "Royal Crispy Chicken", 600, 31, 54, 29),
                menu("bk_spicy_royal_crispy", "Spicy Royal Crispy Chicken", 760, 31, 57, 45),
                menu("bk_big_fish", "Big Fish Sandwich", 570, 19, 58, 29),
                menu("bk_nuggets_8", "Chicken Nuggets (8 Pc)", 350, 16, 22, 22),
                menu("bk_hash_browns_small", "Hash Browns (Small)", 250, 2, 24, 16)
            ])
        ],
        "popeyes": [
            menuCategory("pop_more_menu", "More Chicken, Sides & Desserts", [
                menu("pop_chicken_2pc", "Signature Chicken (2 Pc)", 610, 47, 18, 39),
                menu("pop_tenders_5pc", "Handcrafted Tenders (5 Pc)", 740, 63, 48, 32),
                menu("pop_wings_6pc", "Signature Wings (6 Pc)", 680, 40, 40, 40),
                menu("pop_mashed_gravy_regular", "Mashed Potatoes with Gravy", 110, 3, 18, 3),
                menu("pop_biscuit", "Buttermilk Biscuit", 210, 4, 20, 13),
                menu("pop_coleslaw_regular", "Coleslaw (Regular)", 140, 1, 14, 9),
                menu("pop_apple_pie", "Cinnamon Apple Pie", 320, 3, 46, 14)
            ])
        ],
        "tropical_smoothie": [
            menuCategory("tsc_more_menu", "More Smoothies & Food", [
                menu("tsc_island_green", "Island Green Smoothie", 410, 3, 102, 0),
                menu("tsc_bahama_mama", "Bahama Mama Smoothie", 510, 4, 117, 4),
                menu("tsc_peanut_paradise", "Peanut Paradise Smoothie", 710, 30, 105, 20),
                menu("tsc_mango_magic", "Mango Magic Smoothie", 430, 3, 104, 1),
                menu("tsc_acai_berry_boost", "Acai Berry Boost Smoothie", 540, 4, 128, 2),
                menu("tsc_buffalo_chicken_wrap", "Buffalo Chicken Wrap", 510, 32, 50, 20),
                menu("tsc_chicken_pesto_flatbread", "Chicken Pesto Flatbread", 430, 28, 43, 16),
                menu("tsc_supergreen_caesar", "Supergreen Caesar Chicken Salad", 750, 40, 43, 47)
            ])
        ],
        "jimmy_johns": [
            menuCategory("jj_popular_regular", "Popular Regular Sandwiches", [
                menu("jj_5_vito", "#5 Vito", 580, 24, 55, 30),
                menu("jj_6_veggie", "#6 The Veggie", 670, 28, 67, 34),
                menu("jj_7_spicy_east_coast", "#7 Spicy East Coast Italian", 850, 42, 58, 50),
                menu("jj_10_hunters_club", "#10 Hunters Club", 830, 48, 58, 45),
                menu("jj_11_country_club", "#11 Country Club", 800, 42, 60, 43),
                menu("jj_12_beach_club", "#12 Beach Club", 810, 35, 59, 48),
                menu("jj_14_bootlegger", "#14 Bootlegger Club", 680, 38, 57, 33),
                menu("jj_16_club_lulu", "#16 Club Lulu", 690, 36, 57, 35)
            ])
        ],
        "firehouse_subs": [
            menuCategory("fh_popular_medium", "Popular Medium Subs & Sides", [
                menu("fh_italian_medium", "Italian", 940, 45, 57, 59),
                menu("fh_engineer_medium", "Engineer", 700, 38, 59, 35),
                menu("fh_meatball_medium", "Firehouse Meatball", 910, 42, 74, 50),
                menu("fh_turkey_bacon_ranch", "Turkey Bacon Ranch", 830, 52, 60, 43),
                menu("fh_new_york_steamer", "New York Steamer", 750, 47, 56, 37),
                menu("fh_firehouse_hero", "Firehouse Hero", 850, 53, 58, 45),
                menu("fh_jamaican_jerk_turkey", "Jamaican Jerk Turkey", 720, 39, 62, 35),
                menu("fh_sweet_spicy_meatball", "Sweet & Spicy Meatball", 960, 43, 85, 50),
                menu("fh_veggie_medium", "Veggie", 720, 25, 66, 40),
                menu("fh_tuna_medium", "Tuna", 910, 38, 62, 57),
                menu("fh_chicken_salad", "Chopped Salad with Chicken", 270, 30, 18, 9),
                menu("fh_chili_cup", "Firehouse Chili (Cup)", 300, 17, 30, 12)
            ])
        ],
        "dominos": [
            menuCategory("dom_more_menu", "More Pizza, Chicken & Sides", [
                menu("dom_pan_pepperoni", "Pan Pepperoni Slice", 310, 12, 28, 17),
                menu("dom_brooklyn_pepperoni", "Brooklyn Pepperoni Slice", 300, 14, 31, 13),
                menu("dom_pacific_veggie", "Pacific Veggie Slice", 260, 11, 31, 10),
                menu("dom_buffalo_chicken", "Buffalo Chicken Slice", 280, 13, 30, 12),
                menu("dom_extravaganzza", "ExtravaganZZa Slice", 290, 13, 30, 13),
                menu("dom_stuffed_cheesy_bread", "Stuffed Cheesy Bread (1/8)", 150, 6, 17, 7),
                menu("dom_parmesan_bites_4", "Parmesan Bread Bites (4)", 220, 5, 27, 10),
                menu("dom_boneless_chicken_8", "Boneless Chicken (8 Pc)", 440, 26, 36, 22),
                menu("dom_chicken_alfredo", "Chicken Alfredo Pasta", 690, 30, 70, 32),
                menu("dom_lava_cakes_2", "Chocolate Lava Crunch Cakes (2)", 700, 9, 86, 36)
            ])
        ],
        "five_guys": [
            menuCategory("fg_more_menu", "More Burgers, Dogs, Fries & Shakes", [
                menu("fg_hamburger", "Hamburger (2 Patties)", 840, 43, 39, 55),
                menu("fg_little_hamburger", "Little Hamburger", 540, 24, 39, 26),
                menu("fg_bacon_burger", "Bacon Burger", 920, 48, 39, 62),
                menu("fg_hot_dog", "Hot Dog", 520, 18, 40, 32),
                menu("fg_cheese_dog", "Cheese Dog", 590, 22, 41, 36),
                menu("fg_bacon_cheese_dog", "Bacon Cheese Dog", 670, 28, 42, 43),
                menu("fg_regular_fries", "Regular Fries", 950, 14, 131, 41),
                menu("fg_little_cajun_fries", "Little Cajun Fries", 530, 8, 72, 23),
                menu("fg_milkshake_base", "Five Guys Milkshake", 670, 13, 84, 32)
            ])
        ]
    ]

    private static func menuCategory(
        _ id: String,
        _ title: String,
        _ ingredients: [ChainIngredient]
    ) -> ChainCategory {
        ChainCategory(id: id, title: title, ingredients: ingredients)
    }

    // Numeric order is calories, protein, carbohydrates, fat, then optional fiber and sodium.
    private static func menu(
        _ id: String,
        _ name: String,
        _ calories: Double,
        _ protein: Double,
        _ carbs: Double,
        _ fat: Double,
        _ fiber: Double = 0,
        _ sodium: Double? = nil,
        serving: String = "1 menu item"
    ) -> ChainIngredient {
        ChainIngredient(
            id: id,
            name: name,
            servingDescription: serving,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sodium: sodium,
            controlStyle: .fixed
        )
    }
}
