import Foundation

public enum ChainIngredientControlStyle: Hashable, Sendable {
    case portion
    case stepper(unit: String)
    case fixed
}

public struct ChainIngredient: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let servingDescription: String
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let fiber: Double
    public let sodium: Double?
    public let controlStyle: ChainIngredientControlStyle

    public init(
        id: String,
        name: String,
        servingDescription: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        sodium: Double? = nil,
        controlStyle: ChainIngredientControlStyle = .portion
    ) {
        self.id = id
        self.name = name
        self.servingDescription = servingDescription
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sodium = sodium
        self.controlStyle = controlStyle
    }

    public var maximumCount: Int {
        switch controlStyle {
        case .portion, .fixed:
            return 1
        case .stepper(let unit):
            switch unit.lowercased() {
            case "slices":
                return 12
            case "scoops":
                return 6
            case "cups":
                return 4
            case "packets", "pumps", "spoons":
                return 12
            default:
                return 10
            }
        }
    }
}

public struct ChainCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let ingredients: [ChainIngredient]

    public init(id: String, title: String, ingredients: [ChainIngredient]) {
        self.id = id
        self.title = title
        self.ingredients = ingredients
    }
}

public struct ChainRestaurant: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let iconName: String
    public let brandColorHex: String
    public let categories: [ChainCategory]

    public init(
        id: String,
        name: String,
        subtitle: String,
        iconName: String,
        brandColorHex: String,
        categories: [ChainCategory]
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.iconName = iconName
        self.brandColorHex = brandColorHex
        self.categories = categories
    }

    public var brandForegroundUsesDarkText: Bool {
        let hex = brandColorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return false }
        let components = [
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        ].map { component in
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
        let contrastWithBlack = (luminance + 0.05) / 0.05
        let contrastWithWhite = 1.05 / (luminance + 0.05)
        return contrastWithBlack >= contrastWithWhite
    }
}

public enum ChainMealPortion: Double, CaseIterable, Identifiable, Sendable {
    case light = 0.5
    case regular = 1.0
    case double = 2.0

    public var id: Double { rawValue }

    public var title: String {
        switch self {
        case .light: return "Light (0.5x)"
        case .regular: return "Regular"
        case .double: return "Double (2x)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .light: return "0.5x"
        case .regular: return "1x"
        case .double: return "2x"
        }
    }
}

public struct ChainSelectionItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let ingredient: ChainIngredient
    public var portion: ChainMealPortion
    public var count: Int

    public init(
        id: String,
        ingredient: ChainIngredient,
        portion: ChainMealPortion = .regular,
        count: Int = 1
    ) {
        self.id = id
        self.ingredient = ingredient
        self.portion = portion
        self.count = count
    }

    public var totalMultiplier: Double {
        switch ingredient.controlStyle {
        case .portion:
            return portion.rawValue
        case .stepper, .fixed:
            return Double(count)
        }
    }

    public var calories: Double { ingredient.calories * totalMultiplier }
    public var protein: Double { ingredient.protein * totalMultiplier }
    public var carbs: Double { ingredient.carbs * totalMultiplier }
    public var fat: Double { ingredient.fat * totalMultiplier }
    public var fiber: Double { ingredient.fiber * totalMultiplier }
    public var sodium: Double? { ingredient.sodium.map { $0 * totalMultiplier } }
}

public struct ChainMealNutritionTotals: Hashable, Sendable {
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let fiber: Double
    public let sodium: Double?

    public init(
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        sodium: Double?
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sodium = sodium
    }
}

public extension ChainRestaurant {
    var ingredientCount: Int {
        categories.reduce(0) { $0 + $1.ingredients.count }
    }

    func orderedSelections(from selections: [String: ChainSelectionItem]) -> [ChainSelectionItem] {
        categories.flatMap(\.ingredients).compactMap { selections[$0.id] }
    }

    func nutritionTotals(for selections: [String: ChainSelectionItem]) -> ChainMealNutritionTotals {
        let orderedItems = orderedSelections(from: selections)
        let knownSodiumValues = orderedItems.compactMap(\.sodium)

        return ChainMealNutritionTotals(
            calories: orderedItems.reduce(0) { $0 + $1.calories },
            protein: orderedItems.reduce(0) { $0 + $1.protein },
            carbs: orderedItems.reduce(0) { $0 + $1.carbs },
            fat: orderedItems.reduce(0) { $0 + $1.fat },
            fiber: orderedItems.reduce(0) { $0 + $1.fiber },
            sodium: knownSodiumValues.isEmpty ? nil : knownSodiumValues.reduce(0, +)
        )
    }

    func ingredientSummary(for selections: [String: ChainSelectionItem]) -> String {
        orderedSelections(from: selections).map { item in
            switch item.ingredient.controlStyle {
            case .portion:
                return "\(item.ingredient.name) (\(item.portion.title))"
            case .stepper(let unit):
                return "\(item.ingredient.name) (\(item.count) \(unit))"
            case .fixed:
                return item.ingredient.name
            }
        }.joined(separator: ", ")
    }

    func catalogSourceID(catalogVersion: String = ChainRestaurantCatalog.catalogVersion) -> String {
        "\(id):\(catalogVersion)"
    }

    func customMealFoodItem(
        from selections: [String: ChainSelectionItem],
        id: String = UUID().uuidString,
        catalogVersion: String = ChainRestaurantCatalog.catalogVersion,
        lastUpdatedDate: String = ChainRestaurantCatalog.lastUpdatedDate
    ) -> FoodItem {
        let orderedItems = orderedSelections(from: selections)
        let totals = nutritionTotals(for: selections)
        let summary = ingredientSummary(for: selections)
        let sourceID = catalogSourceID(catalogVersion: catalogVersion)

        return FoodItem(
            id: id,
            name: "\(name) Custom Meal",
            calories: totals.calories,
            protein: totals.protein,
            carbs: totals.carbs,
            fats: totals.fat,
            fiber: totals.fiber,
            servingSize: "\(orderedItems.count) \(orderedItems.count == 1 ? "item" : "items")",
            servingWeight: 0,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .chainBuilder,
                confidence: .estimated,
                reviewStatus: .unreviewed,
                sourceName: "\(name) Builder",
                sourceID: sourceID,
                matchedFoodID: sourceID,
                notes: "Catalog \(catalogVersion) (\(lastUpdatedDate)): \(summary)",
                originalEstimate: FoodNutritionSnapshot(
                    calories: totals.calories,
                    protein: totals.protein,
                    carbs: totals.carbs,
                    fats: totals.fat,
                    servingSize: "\(orderedItems.count) \(orderedItems.count == 1 ? "item" : "items")",
                    servingWeight: 0
                )
            ),
            sodium: totals.sodium
        )
    }
}

public struct ChainRestaurantCatalog {
    public static let catalogVersion: String = "2026.07.V1"
    public static let lastUpdatedDate: String = "July 2026"

    public static let allChains: [ChainRestaurant] = [
        chipotle,
        sweetgreen,
        cava,
        chickFilA,
        tacoBell,
        mcdonalds,
        inNOut,
        panera,
        burgerKing,
        popeyes,
        pandaExpress,
        qdoba,
        shakeShack,
        subway,
        starbucks,
        dunkin,
        jerseyMikes,
        jimmyJohns,
        firehouseSubs,
        wingstop,
        culvers,
        wendys,
        tropicalSmoothie,
        dominos,
        fiveGuys
    ]

    // MARK: - Chipotle
    public static let chipotle = ChainRestaurant(
        id: "chipotle",
        name: "Chipotle",
        subtitle: "Burrito Bowls, Salads & Burritos",
        iconName: "takeoutbag.and.cup.and.straw.fill",
        brandColorHex: "#AD2118",
        categories: [
            ChainCategory(id: "chipotle_base", title: "Bases & Grains", ingredients: [
                ChainIngredient(id: "c_white_rice", name: "Cilantro-Lime White Rice", servingDescription: "1 scoop (113g)", calories: 210, protein: 4, carbs: 40, fat: 4, fiber: 1, sodium: 350),
                ChainIngredient(id: "c_brown_rice", name: "Cilantro-Lime Brown Rice", servingDescription: "1 scoop (113g)", calories: 210, protein: 4, carbs: 39, fat: 6, fiber: 2, sodium: 190),
                ChainIngredient(id: "c_romaine", name: "Romaine Lettuce Base", servingDescription: "1 bowl base", calories: 5, protein: 1, carbs: 1, fat: 0, fiber: 1, sodium: 0),
                ChainIngredient(id: "c_tortilla", name: "Flour Tortilla (Burrito)", servingDescription: "1 tortilla", calories: 320, protein: 8, carbs: 50, fat: 9, fiber: 3, sodium: 600)
            ]),
            ChainCategory(id: "chipotle_beans", title: "Beans", ingredients: [
                ChainIngredient(id: "c_black_beans", name: "Black Beans", servingDescription: "1 scoop (130g)", calories: 130, protein: 8, carbs: 22, fat: 1.5, fiber: 7, sodium: 210),
                ChainIngredient(id: "c_pinto_beans", name: "Pinto Beans", servingDescription: "1 scoop (130g)", calories: 130, protein: 8, carbs: 21, fat: 1.5, fiber: 7, sodium: 210)
            ]),
            ChainCategory(id: "chipotle_protein", title: "Proteins", ingredients: [
                ChainIngredient(id: "c_chicken", name: "Adobo Chicken", servingDescription: "1 scoop (113g)", calories: 180, protein: 32, carbs: 0, fat: 7, fiber: 0, sodium: 310),
                ChainIngredient(id: "c_al_pastor", name: "Chicken Al Pastor", servingDescription: "1 scoop (113g)", calories: 210, protein: 30, carbs: 5, fat: 8, fiber: 0, sodium: 390),
                ChainIngredient(id: "c_steak", name: "Grilled Steak", servingDescription: "1 scoop (113g)", calories: 150, protein: 21, carbs: 1, fat: 6, fiber: 0, sodium: 330),
                ChainIngredient(id: "c_barbacoa", name: "Barbacoa Beef", servingDescription: "1 scoop (113g)", calories: 170, protein: 24, carbs: 2, fat: 7, fiber: 1, sodium: 530),
                ChainIngredient(id: "c_carnitas", name: "Braised Carnitas", servingDescription: "1 scoop (113g)", calories: 210, protein: 23, carbs: 0, fat: 12, fiber: 0, sodium: 450),
                ChainIngredient(id: "c_sofritas", name: "Sofritas Tofu", servingDescription: "1 scoop (113g)", calories: 150, protein: 8, carbs: 9, fat: 10, fiber: 3, sodium: 560)
            ]),
            ChainCategory(id: "chipotle_salsas", title: "Salsas & Veggies", ingredients: [
                ChainIngredient(id: "c_fajita", name: "Fajita Veggies", servingDescription: "1 scoop (57g)", calories: 20, protein: 1, carbs: 4, fat: 0, fiber: 1, sodium: 150),
                ChainIngredient(id: "c_pico", name: "Fresh Tomato Salsa (Pico)", servingDescription: "1 scoop (99g)", calories: 25, protein: 1, carbs: 4, fat: 0, fiber: 1, sodium: 550),
                ChainIngredient(id: "c_corn", name: "Roasted Chili-Corn Salsa", servingDescription: "1 scoop (99g)", calories: 80, protein: 3, carbs: 16, fat: 1.5, fiber: 2, sodium: 330),
                ChainIngredient(id: "c_green", name: "Tomatillo-Green Chili Salsa", servingDescription: "1 scoop (57g)", calories: 15, protein: 0, carbs: 4, fat: 0, fiber: 0, sodium: 260),
                ChainIngredient(id: "c_red", name: "Tomatillo-Red Chili Salsa", servingDescription: "1 scoop (57g)", calories: 30, protein: 0, carbs: 4, fat: 0, fiber: 1, sodium: 500)
            ]),
            ChainCategory(id: "chipotle_toppings", title: "Toppings & Fats", ingredients: [
                ChainIngredient(id: "c_guac", name: "Guacamole", servingDescription: "1 scoop (113g)", calories: 230, protein: 2, carbs: 8, fat: 22, fiber: 6, sodium: 370),
                ChainIngredient(id: "c_cheese", name: "Monterey Jack Cheese", servingDescription: "1 pinch (28g)", calories: 110, protein: 6, carbs: 1, fat: 8, fiber: 0, sodium: 190),
                ChainIngredient(id: "c_sourcream", name: "Sour Cream", servingDescription: "1 scoop (57g)", calories: 110, protein: 2, carbs: 2, fat: 9, fiber: 0, sodium: 30),
                ChainIngredient(id: "c_queso", name: "Queso Blanco", servingDescription: "1 scoop (57g)", calories: 120, protein: 5, carbs: 4, fat: 9, fiber: 0, sodium: 330),
                ChainIngredient(id: "c_vinaigrette", name: "Chipotle Honey Vinaigrette", servingDescription: "1 cup (2 fl oz)", calories: 220, protein: 1, carbs: 18, fat: 16, fiber: 0, sodium: 850)
            ])
        ]
    )

    // MARK: - Sweetgreen
    public static let sweetgreen = ChainRestaurant(
        id: "sweetgreen",
        name: "Sweetgreen",
        subtitle: "Warm Bowls & Custom Salads",
        iconName: "leaf.fill",
        brandColorHex: "#1C4E37",
        categories: [
            ChainCategory(id: "sg_base", title: "Bases", ingredients: [
                ChainIngredient(id: "sg_kale", name: "Shredded Kale", servingDescription: "1 base", calories: 40, protein: 3, carbs: 7, fat: 0.5, fiber: 2),
                ChainIngredient(id: "sg_quinoa", name: "Warm Quinoa", servingDescription: "1 scoop", calories: 150, protein: 5, carbs: 27, fat: 2.5, fiber: 3),
                ChainIngredient(id: "sg_wildrice", name: "Wild Rice", servingDescription: "1 scoop", calories: 150, protein: 4, carbs: 30, fat: 1.5, fiber: 2)
            ]),
            ChainCategory(id: "sg_protein", title: "Proteins", ingredients: [
                ChainIngredient(id: "sg_chicken", name: "Roasted Chicken", servingDescription: "1 serving", calories: 160, protein: 24, carbs: 0, fat: 7),
                ChainIngredient(id: "sg_blackened", name: "Blackened Chicken", servingDescription: "1 serving", calories: 190, protein: 26, carbs: 1, fat: 9),
                ChainIngredient(id: "sg_tofu", name: "Roasted Tofu", servingDescription: "1 serving", calories: 120, protein: 10, carbs: 4, fat: 7)
            ]),
            ChainCategory(id: "sg_toppings", title: "Toppings & Cheese", ingredients: [
                ChainIngredient(id: "sg_avocado", name: "Avocado Half", servingDescription: "1/2 avocado", calories: 120, protein: 1, carbs: 6, fat: 11, fiber: 5),
                ChainIngredient(id: "sg_sweetpot", name: "Roasted Sweet Potatoes", servingDescription: "1 scoop", calories: 90, protein: 1, carbs: 20, fat: 0.5, fiber: 3),
                ChainIngredient(id: "sg_goat", name: "Goat Cheese", servingDescription: "1 scoop", calories: 80, protein: 5, carbs: 1, fat: 6)
            ]),
            ChainCategory(id: "sg_dressing", title: "Dressings", ingredients: [
                ChainIngredient(id: "sg_balsamic", name: "Balsamic Vinaigrette", servingDescription: "2 oz", calories: 140, protein: 0, carbs: 3, fat: 14),
                ChainIngredient(id: "sg_goddess", name: "Green Goddess Dressing", servingDescription: "2 oz", calories: 120, protein: 1, carbs: 2, fat: 12)
            ])
        ]
    )

    // MARK: - Cava
    public static let cava = ChainRestaurant(
        id: "cava",
        name: "Cava",
        subtitle: "Mediterranean Grain Bowls & Pitas",
        iconName: "flame.fill",
        brandColorHex: "#D96C32",
        categories: [
            ChainCategory(id: "cava_base", title: "Grains & Greens", ingredients: [
                ChainIngredient(id: "cv_saffron_rice", name: "Saffron Basmati Rice", servingDescription: "1 scoop", calories: 170, protein: 3, carbs: 35, fat: 2),
                ChainIngredient(id: "cv_greens", name: "SuperGreens Mix", servingDescription: "1 bowl", calories: 25, protein: 2, carbs: 4, fat: 0)
            ]),
            ChainCategory(id: "cava_dips", title: "Dips & Spreads", ingredients: [
                ChainIngredient(id: "cv_tzatziki", name: "Tzatziki", servingDescription: "1 scoop", calories: 30, protein: 1, carbs: 2, fat: 2),
                ChainIngredient(id: "cv_hummus", name: "Traditional Hummus", servingDescription: "1 scoop", calories: 45, protein: 2, carbs: 5, fat: 2.5),
                ChainIngredient(id: "cv_crazy_feta", name: "Crazy Feta", servingDescription: "1 scoop", calories: 70, protein: 2, carbs: 1, fat: 6)
            ]),
            ChainCategory(id: "cava_protein", title: "Proteins", ingredients: [
                ChainIngredient(id: "cv_chicken", name: "Grilled Chicken", servingDescription: "1 scoop", calories: 190, protein: 25, carbs: 1, fat: 9),
                ChainIngredient(id: "cv_harissa_chick", name: "Harissa Honey Chicken", servingDescription: "1 scoop", calories: 240, protein: 24, carbs: 11, fat: 11),
                ChainIngredient(id: "cv_lamb", name: "Braised Lamb", servingDescription: "1 scoop", calories: 230, protein: 18, carbs: 1, fat: 16)
            ]),
            ChainCategory(id: "cava_dressings", title: "Dressings & Pita", ingredients: [
                ChainIngredient(id: "cv_garlic_dress", name: "Garlic Dressing", servingDescription: "1 splash", calories: 160, protein: 0, carbs: 1, fat: 18),
                ChainIngredient(id: "cv_hot_harissa", name: "Hot Harissa Vinaigrette", servingDescription: "1 splash", calories: 120, protein: 0, carbs: 4, fat: 11),
                ChainIngredient(id: "cv_pita", name: "Warm Pita Side", servingDescription: "1 round", calories: 200, protein: 7, carbs: 38, fat: 2)
            ])
        ]
    )

    // MARK: - Panda Express
    public static let pandaExpress = ChainRestaurant(
        id: "panda_express",
        name: "Panda Express",
        subtitle: "Bowls & Wok Plates",
        iconName: "bowl.fill",
        brandColorHex: "#C41230",
        categories: [
            ChainCategory(id: "pe_side", title: "Bases & Sides", ingredients: [
                ChainIngredient(id: "pe_supergreens", name: "Super Greens", servingDescription: "1 side (145g)", calories: 90, protein: 6, carbs: 10, fat: 3, fiber: 5),
                ChainIngredient(id: "pe_chowmein", name: "Chow Mein Noodles", servingDescription: "1 side (266g)", calories: 510, protein: 13, carbs: 80, fat: 20, fiber: 6),
                ChainIngredient(id: "pe_friedrice", name: "Fried Rice", servingDescription: "1 side (264g)", calories: 520, protein: 11, carbs: 85, fat: 16, fiber: 2),
                ChainIngredient(id: "pe_whiterice", name: "White Steamed Rice", servingDescription: "1 side (232g)", calories: 380, protein: 7, carbs: 86, fat: 0, fiber: 0)
            ]),
            ChainCategory(id: "pe_entree", title: "Entrees & Proteins", ingredients: [
                ChainIngredient(id: "pe_teriyaki", name: "Grilled Teriyaki Chicken", servingDescription: "1 entree (170g)", calories: 300, protein: 36, carbs: 8, fat: 13),
                ChainIngredient(id: "pe_broccolibeef", name: "Broccoli Beef", servingDescription: "1 entree (153g)", calories: 150, protein: 9, carbs: 13, fat: 7, fiber: 2),
                ChainIngredient(id: "pe_orangechick", name: "The Original Orange Chicken", servingDescription: "1 entree (162g)", calories: 490, protein: 25, carbs: 51, fat: 23),
                ChainIngredient(id: "pe_kungpao", name: "Kung Pao Chicken", servingDescription: "1 entree (160g)", calories: 290, protein: 16, carbs: 14, fat: 19, fiber: 2),
                ChainIngredient(id: "pe_shrimp", name: "Honey Walnut Shrimp", servingDescription: "1 entree (105g)", calories: 360, protein: 13, carbs: 35, fat: 19),
                ChainIngredient(id: "pe_beijingbeef", name: "Beijing Beef", servingDescription: "1 entree (153g)", calories: 470, protein: 14, carbs: 48, fat: 26),
                ChainIngredient(id: "pe_stringbeanchick", name: "String Bean Chicken Breast", servingDescription: "1 entree (159g)", calories: 210, protein: 12, carbs: 13, fat: 12, fiber: 4)
            ])
        ]
    )

    // MARK: - Qdoba
    public static let qdoba = ChainRestaurant(
        id: "qdoba",
        name: "Qdoba",
        subtitle: "Burrito Bowls & Free Queso/Guac",
        iconName: "fork.knife",
        brandColorHex: "#F26522",
        categories: [
            ChainCategory(id: "qd_base", title: "Bases & Beans", ingredients: [
                ChainIngredient(id: "qd_whiterice", name: "Cilantro Lime White Rice", servingDescription: "1 scoop", calories: 210, protein: 4, carbs: 41, fat: 3.5, fiber: 1),
                ChainIngredient(id: "qd_brownrice", name: "Cilantro Lime Brown Rice", servingDescription: "1 scoop", calories: 190, protein: 4, carbs: 38, fat: 3, fiber: 3),
                ChainIngredient(id: "qd_blackbeans", name: "Black Beans", servingDescription: "1 scoop", calories: 130, protein: 8, carbs: 22, fat: 1.5, fiber: 7)
            ]),
            ChainCategory(id: "qd_protein", title: "Proteins", ingredients: [
                ChainIngredient(id: "qd_chicken", name: "Grilled Adobo Chicken", servingDescription: "1 scoop", calories: 180, protein: 26, carbs: 2, fat: 7),
                ChainIngredient(id: "qd_steak", name: "Grilled Steak", servingDescription: "1 scoop", calories: 160, protein: 20, carbs: 2, fat: 8),
                ChainIngredient(id: "qd_pork", name: "Pulled Pork", servingDescription: "1 scoop", calories: 170, protein: 18, carbs: 3, fat: 9)
            ]),
            ChainCategory(id: "qd_queso_guac", title: "Free Queso & Guacamole", ingredients: [
                ChainIngredient(id: "qd_3cheese", name: "3-Cheese Queso", servingDescription: "1 scoop", calories: 120, protein: 5, carbs: 4, fat: 9),
                ChainIngredient(id: "qd_guac", name: "Hand-Smashed Guacamole", servingDescription: "1 scoop", calories: 130, protein: 2, carbs: 5, fat: 12, fiber: 4)
            ])
        ]
    )

    // MARK: - Shake Shack
    public static let shakeShack = ChainRestaurant(
        id: "shake_shack",
        name: "Shake Shack",
        subtitle: "Custom Burgers & Lettuce Wraps",
        iconName: "star.fill",
        brandColorHex: "#549D39",
        categories: [
            ChainCategory(id: "ss_wrap", title: "Bun or Wrap", ingredients: [
                ChainIngredient(id: "ss_potato_bun", name: "Potato Bun", servingDescription: "1 bun", calories: 180, protein: 6, carbs: 31, fat: 3.5),
                ChainIngredient(id: "ss_lettuce_wrap", name: "Lettuce Wrap (No Bun)", servingDescription: "Wrap", calories: 10, protein: 1, carbs: 2, fat: 0)
            ]),
            ChainCategory(id: "ss_patties", title: "Patties & Chicken", ingredients: [
                ChainIngredient(id: "ss_single_beef", name: "Single Shack Beef Patty", servingDescription: "1 patty", calories: 260, protein: 19, carbs: 0, fat: 20),
                ChainIngredient(id: "ss_double_beef", name: "Double Shack Beef Patties", servingDescription: "2 patties", calories: 520, protein: 38, carbs: 0, fat: 40),
                ChainIngredient(id: "ss_chicken_breast", name: "Crispy Chicken Shack Breast", servingDescription: "1 breast", calories: 290, protein: 28, carbs: 12, fat: 14)
            ]),
            ChainCategory(id: "ss_toppings", title: "Cheese & Sauce", ingredients: [
                ChainIngredient(id: "ss_cheese", name: "American Cheese Slice", servingDescription: "1 slice", calories: 70, protein: 4, carbs: 1, fat: 6),
                ChainIngredient(id: "ss_shacksauce", name: "ShackSauce", servingDescription: "1 spread", calories: 60, protein: 0, carbs: 1, fat: 6)
            ])
        ]
    )

    // MARK: - Subway
    public static let subway = ChainRestaurant(
        id: "subway",
        name: "Subway",
        subtitle: "Custom Subs & Protein Bowls",
        iconName: "bag.fill",
        brandColorHex: "#008C15",
        categories: [
            ChainCategory(id: "sub_bread", title: "Bread or Bowl", ingredients: [
                ChainIngredient(id: "sb_italian_6", name: "6\" Artisan Italian Bread", servingDescription: "6 inch", calories: 200, protein: 7, carbs: 37, fat: 2.5, fiber: 1),
                ChainIngredient(id: "sb_bowl", name: "No Bread (Protein Bowl Base)", servingDescription: "Bowl", calories: 20, protein: 1, carbs: 4, fat: 0)
            ]),
            ChainCategory(id: "sub_protein", title: "Proteins", ingredients: [
                ChainIngredient(id: "sb_rotisserie", name: "Rotisserie-Style Chicken", servingDescription: "Standard portion", calories: 140, protein: 23, carbs: 1, fat: 5),
                ChainIngredient(id: "sb_turkey", name: "Oven-Roasted Turkey", servingDescription: "Standard portion", calories: 100, protein: 18, carbs: 2, fat: 1.5)
            ]),
            ChainCategory(id: "sub_cheese", title: "Cheese & Sauce", ingredients: [
                ChainIngredient(id: "sb_provolone", name: "Provolone Cheese", servingDescription: "2 slices", calories: 50, protein: 4, carbs: 0, fat: 4),
                ChainIngredient(id: "sb_chipotle", name: "Baja Chipotle Sauce", servingDescription: "1 drizzle", calories: 100, protein: 0, carbs: 1, fat: 11)
            ])
        ]
    )

    // MARK: - Starbucks
    public static let starbucks = ChainRestaurant(
        id: "starbucks",
        name: "Starbucks",
        subtitle: "Tall/Grande/Venti Coffee & Specialty Drinks",
        iconName: "cup.and.saucer.fill",
        brandColorHex: "#00704A",
        categories: [
            ChainCategory(id: "sbx_sizes", title: "Drink Base & Size (Tall / Grande / Venti)", ingredients: [
                ChainIngredient(id: "sbx_tall_black", name: "Tall Iced/Hot Coffee Base (12 oz)", servingDescription: "Tall black", calories: 5, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "sbx_grande_black", name: "Grande Iced/Hot Coffee Base (16 oz)", servingDescription: "Grande black", calories: 5, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "sbx_venti_black", name: "Venti Iced Coffee Base (24 oz)", servingDescription: "Venti black", calories: 10, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "sbx_trenta_black", name: "Trenta Iced Coffee Base (30 oz)", servingDescription: "Trenta black", calories: 15, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "sbx_americano", name: "Caffè Americano Base (Grande)", servingDescription: "Grande (Espresso + Water)", calories: 15, protein: 1, carbs: 2, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "sbx_shaken_esp", name: "Iced Shaken Espresso Base (Grande)", servingDescription: "Grande espresso base", calories: 35, protein: 1, carbs: 4, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "sbx_matcha", name: "Matcha Tea Concentrate Base (Grande)", servingDescription: "Grande base", calories: 120, protein: 2, carbs: 28, fat: 0, controlStyle: .fixed)
            ]),
            ChainCategory(id: "sbx_milk", title: "Milk & Dairy Choice", ingredients: [
                ChainIngredient(id: "sbx_oatmilk", name: "Oatmilk Portion", servingDescription: "Standard portion", calories: 80, protein: 1, carbs: 14, fat: 3, controlStyle: .portion),
                ChainIngredient(id: "sbx_almondmilk", name: "Almondmilk Portion", servingDescription: "Standard portion", calories: 40, protein: 1, carbs: 3, fat: 2.5, controlStyle: .portion),
                ChainIngredient(id: "sbx_wholemilk", name: "Whole Milk Portion", servingDescription: "Standard portion", calories: 110, protein: 6, carbs: 9, fat: 6, controlStyle: .portion),
                ChainIngredient(id: "sbx_nonfat", name: "Nonfat / Skim Milk Portion", servingDescription: "Standard portion", calories: 60, protein: 6, carbs: 9, fat: 0, controlStyle: .portion),
                ChainIngredient(id: "sbx_breve", name: "Half & Half (Breve Splash)", servingDescription: "Splash (2 oz)", calories: 80, protein: 2, carbs: 2, fat: 7, controlStyle: .portion)
            ]),
            ChainCategory(id: "sbx_syrups_foams", title: "Syrups (1 Pump = 20 Cal) & Cold Foams", ingredients: [
                ChainIngredient(id: "sbx_vs_foam", name: "Vanilla Sweet Cream Cold Foam", servingDescription: "1 topping scoop", calories: 100, protein: 1, carbs: 11, fat: 6, controlStyle: .portion),
                ChainIngredient(id: "sbx_vanilla_pump", name: "Vanilla Syrup (Per Pump)", servingDescription: "1 pump = 20 cal (Tall=3, Gr=4, Vt=6)", calories: 20, protein: 0, carbs: 5, fat: 0, controlStyle: .stepper(unit: "pumps")),
                ChainIngredient(id: "sbx_sf_vanilla", name: "Sugar-Free Vanilla Syrup (Per Pump)", servingDescription: "1 pump = 0 cal", calories: 0, protein: 0, carbs: 0, fat: 0, controlStyle: .stepper(unit: "pumps")),
                ChainIngredient(id: "sbx_bs_pump", name: "Brown Sugar Syrup (Per Pump)", servingDescription: "1 pump = 10 cal", calories: 10, protein: 0, carbs: 3, fat: 0, controlStyle: .stepper(unit: "pumps")),
                ChainIngredient(id: "sbx_caramel_driz", name: "Caramel Drizzle", servingDescription: "Standard drizzle", calories: 15, protein: 0, carbs: 3, fat: 0, controlStyle: .portion)
            ]),
            ChainCategory(id: "sbx_eggbites", title: "Egg Bites & Wraps", ingredients: [
                ChainIngredient(id: "sbx_bacon_gruyere", name: "Bacon & Gruyère Egg Bites", servingDescription: "2 bites (130g)", calories: 300, protein: 19, carbs: 9, fat: 20),
                ChainIngredient(id: "sbx_eggwhite_pepper", name: "Egg White & Roasted Red Pepper Bites", servingDescription: "2 bites (130g)", calories: 170, protein: 12, carbs: 11, fat: 8),
                ChainIngredient(id: "sbx_spinach_wrap", name: "Spinach, Feta & Egg White Wrap", servingDescription: "1 wrap (290g)", calories: 290, protein: 20, carbs: 34, fat: 8, fiber: 3)
            ]),
            ChainCategory(id: "sbx_oats", title: "Warm Oatmeal & Toppings", ingredients: [
                ChainIngredient(id: "sbx_oatmeal_base", name: "Rolled & Steel-Cut Oatmeal Base", servingDescription: "1 bowl", calories: 160, protein: 5, carbs: 28, fat: 2.5, fiber: 4),
                ChainIngredient(id: "sbx_nut_medley", name: "Mixed Nut & Seed Topping", servingDescription: "1 pack", calories: 100, protein: 3, carbs: 2, fat: 9)
            ])
        ]
    )

    // MARK: - Dunkin'
    public static let dunkin = ChainRestaurant(
        id: "dunkin",
        name: "Dunkin'",
        subtitle: "Small/Med/Lrg/XL Coffee, Refreshers & Breakfast",
        iconName: "mug.fill",
        brandColorHex: "#FF671F",
        categories: [
            ChainCategory(id: "dd_sizes", title: "Drink Base & Size (S / M / L / XL)", ingredients: [
                ChainIngredient(id: "dd_small_iced", name: "Small Iced Coffee Base (16 oz)", servingDescription: "Small black", calories: 5, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "dd_med_iced", name: "Medium Iced Coffee Base (24 oz)", servingDescription: "Medium black", calories: 10, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "dd_lrg_iced", name: "Large Iced Coffee Base (32 oz)", servingDescription: "Large black", calories: 15, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "dd_xl_hot", name: "Extra Large Hot Coffee Base (20 oz)", servingDescription: "XL black", calories: 10, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "dd_cold_brew_med", name: "Cold Brew Coffee Base (Medium)", servingDescription: "Medium black", calories: 10, protein: 0, carbs: 0, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "dd_refresher_s", name: "Strawberry Dragonfruit Refresher Base (Medium)", servingDescription: "Medium w/ Green Tea", calories: 130, protein: 0, carbs: 29, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "dd_matcha_med", name: "Iced Matcha Latte Base (Medium)", servingDescription: "Medium base", calories: 250, protein: 9, carbs: 34, fat: 8, controlStyle: .fixed),
                ChainIngredient(id: "dd_chai_med", name: "Iced Chai Latte Base (Medium)", servingDescription: "Medium chai + milk", calories: 290, protein: 8, carbs: 43, fat: 9, controlStyle: .fixed)
            ]),
            ChainCategory(id: "dd_cream_dairy", title: "Cream & Dairy (1 Pump = 30 Cal • Med=3, Lrg=4)", ingredients: [
                ChainIngredient(id: "dd_cream_pump", name: "Light Cream (Per Pump / Dispense)", servingDescription: "1 pump = 30 cal (S=2, M=3, L=4, XL=5)", calories: 30, protein: 0.5, carbs: 1, fat: 3, controlStyle: .stepper(unit: "pumps")),
                ChainIngredient(id: "dd_whole_pump", name: "Whole Milk (Per Pour / Dispense)", servingDescription: "1 pour = 15 cal (S=2, M=3, L=4, XL=5)", calories: 15, protein: 1, carbs: 1, fat: 1, controlStyle: .stepper(unit: "pours")),
                ChainIngredient(id: "dd_oat_pump", name: "Oatmilk (Per Pour / Dispense)", servingDescription: "1 pour = 15 cal (S=2, M=3, L=4, XL=5)", calories: 15, protein: 0.5, carbs: 2, fat: 0.5, controlStyle: .stepper(unit: "pours")),
                ChainIngredient(id: "dd_almond_pump", name: "Almondmilk (Per Pour / Dispense)", servingDescription: "1 pour = 10 cal (S=2, M=3, L=4, XL=5)", calories: 10, protein: 0.5, carbs: 0.5, fat: 0.8, controlStyle: .stepper(unit: "pours")),
                ChainIngredient(id: "dd_skim_pump", name: "Skim Milk (Per Pour / Dispense)", servingDescription: "1 pour = 10 cal (S=2, M=3, L=4, XL=5)", calories: 10, protein: 1, carbs: 1.5, fat: 0, controlStyle: .stepper(unit: "pours"))
            ]),
            ChainCategory(id: "dd_sugar", title: "Sugar & Sweeteners (1 Spoon = 25 Cal • Med=3, Lrg=4)", ingredients: [
                ChainIngredient(id: "dd_sugar_spoon", name: "Granulated Sugar (Per Spoon / Dispense)", servingDescription: "1 spoon = 25 cal (S=2, M=3, L=4, XL=5)", calories: 25, protein: 0, carbs: 6, fat: 0, controlStyle: .stepper(unit: "spoons")),
                ChainIngredient(id: "dd_liquid_sugar", name: "Liquid Cane Sugar (Per Pump)", servingDescription: "1 pump = 25 cal (S=2, M=3, L=4, XL=5)", calories: 25, protein: 0, carbs: 6.5, fat: 0, controlStyle: .stepper(unit: "pumps"))
            ]),
            ChainCategory(id: "dd_swirls", title: "Sweetened Swirls (1 Pump = 50 Cal • Med=3, Lrg=4)", ingredients: [
                ChainIngredient(id: "dd_caramel_pump", name: "Caramel Flavor Swirl (Per Pump)", servingDescription: "1 pump = 50 cal (S=2, M=3, L=4, XL=5)", calories: 50, protein: 0, carbs: 12, fat: 0, controlStyle: .stepper(unit: "pumps")),
                ChainIngredient(id: "dd_mocha_pump", name: "Mocha Flavor Swirl (Per Pump)", servingDescription: "1 pump = 50 cal (S=2, M=3, L=4, XL=5)", calories: 50, protein: 0.5, carbs: 12, fat: 0.5, controlStyle: .stepper(unit: "pumps")),
                ChainIngredient(id: "dd_fv_pump", name: "French Vanilla Swirl (Per Pump)", servingDescription: "1 pump = 50 cal (S=2, M=3, L=4, XL=5)", calories: 50, protein: 0, carbs: 12, fat: 0, controlStyle: .stepper(unit: "pumps")),
                ChainIngredient(id: "dd_bp_pump", name: "Butter Pecan Swirl (Per Pump)", servingDescription: "1 pump = 50 cal (S=2, M=3, L=4, XL=5)", calories: 50, protein: 0, carbs: 12, fat: 0.5, controlStyle: .stepper(unit: "pumps"))
            ]),
            ChainCategory(id: "dd_unsweet_shots", title: "Unsweetened Flavor Shots (0 Cal / 0 Sugar)", ingredients: [
                ChainIngredient(id: "dd_shot_fv", name: "French Vanilla Flavor Shot (Unsweetened)", servingDescription: "Standard shot", calories: 0, protein: 0, carbs: 0, fat: 0),
                ChainIngredient(id: "dd_shot_almond", name: "Toasted Almond Flavor Shot (Unsweetened)", servingDescription: "Standard shot", calories: 0, protein: 0, carbs: 0, fat: 0),
                ChainIngredient(id: "dd_shot_hazelnut", name: "Hazelnut Flavor Shot (Unsweetened)", servingDescription: "Standard shot", calories: 0, protein: 0, carbs: 0, fat: 0),
                ChainIngredient(id: "dd_shot_blueberry", name: "Blueberry Flavor Shot (Unsweetened)", servingDescription: "Standard shot", calories: 0, protein: 0, carbs: 0, fat: 0),
                ChainIngredient(id: "dd_shot_coconut", name: "Coconut Flavor Shot (Unsweetened)", servingDescription: "Standard shot", calories: 0, protein: 0, carbs: 0, fat: 0)
            ]),
            ChainCategory(id: "dd_foams_toppings", title: "Foams & Toppings", ingredients: [
                ChainIngredient(id: "dd_cold_foam", name: "Sweet Cold Foam Topping", servingDescription: "Standard layer", calories: 80, protein: 1, carbs: 10, fat: 4.5),
                ChainIngredient(id: "dd_whipped_cream", name: "Whipped Cream Topping", servingDescription: "Standard dollop", calories: 70, protein: 0, carbs: 1, fat: 6)
            ]),
            ChainCategory(id: "dd_breakfast", title: "Breakfast Sandwiches & Wraps", ingredients: [
                ChainIngredient(id: "dd_wakeup_egg", name: "Egg & Cheese Wake-Up Wrap", servingDescription: "1 wrap", calories: 180, protein: 10, carbs: 14, fat: 10),
                ChainIngredient(id: "dd_wakeup_turkey", name: "Turkey Sausage Wake-Up Wrap", servingDescription: "1 wrap", calories: 240, protein: 15, carbs: 15, fat: 13),
                ChainIngredient(id: "dd_sourdough", name: "Sourdough Breakfast Sandwich", servingDescription: "1 sandwich", calories: 530, protein: 24, carbs: 50, fat: 26)
            ])
        ]
    )

    // MARK: - Jersey Mike's
    public static let jerseyMikes = ChainRestaurant(
        id: "jersey_mikes",
        name: "Jersey Mike's",
        subtitle: "Subs & Sub-In-A-Tub Bowls",
        iconName: "takeoutbag.and.cup.and.straw.fill",
        brandColorHex: "#002C5F",
        categories: [
            ChainCategory(id: "jm_base", title: "Bread or Tub", ingredients: [
                ChainIngredient(id: "jm_regular_bread", name: "Regular White Sub Bread", servingDescription: "Regular roll", calories: 280, protein: 9, carbs: 54, fat: 3),
                ChainIngredient(id: "jm_tub", name: "Sub in a Tub (Lettuce Bowl Base)", servingDescription: "Bowl", calories: 30, protein: 1, carbs: 5, fat: 0, fiber: 2)
            ]),
            ChainCategory(id: "jm_protein", title: "Proteins", ingredients: [
                ChainIngredient(id: "jm_roastbeef", name: "Roast Beef", servingDescription: "Regular portion", calories: 160, protein: 26, carbs: 1, fat: 6),
                ChainIngredient(id: "jm_turkey", name: "Turkey Breast", servingDescription: "Regular portion", calories: 110, protein: 22, carbs: 2, fat: 1.5),
                ChainIngredient(id: "jm_philly_chicken", name: "Big Kahuna Chicken Philly Meat", servingDescription: "Regular portion", calories: 240, protein: 32, carbs: 6, fat: 9)
            ]),
            ChainCategory(id: "jm_cheese_style", title: "Cheese & Mike's Way", ingredients: [
                ChainIngredient(id: "jm_provolone", name: "Provolone Cheese", servingDescription: "3 slices", calories: 110, protein: 8, carbs: 1, fat: 8),
                ChainIngredient(id: "jm_mikes_way", name: "Olive Oil & Red Wine Vinegar Blend", servingDescription: "Standard splash", calories: 220, protein: 0, carbs: 1, fat: 24)
            ])
        ]
    )

    // MARK: - Wingstop
    public static let wingstop = ChainRestaurant(
        id: "wingstop",
        name: "Wingstop",
        subtitle: "Wings, Tenders & Dips",
        iconName: "flame.fill",
        brandColorHex: "#004B23",
        categories: [
            ChainCategory(id: "ws_wings", title: "Wings & Tenders", ingredients: [
                ChainIngredient(id: "ws_classic_wings", name: "Classic Wings (Plain)", servingDescription: "5 wings", calories: 400, protein: 35, carbs: 0, fat: 28),
                ChainIngredient(id: "ws_boneless", name: "Boneless Wings (Plain)", servingDescription: "5 wings", calories: 360, protein: 25, carbs: 20, fat: 20),
                ChainIngredient(id: "ws_tenders", name: "Crispy Chicken Tenders", servingDescription: "3 tenders", calories: 390, protein: 33, carbs: 18, fat: 21)
            ]),
            ChainCategory(id: "ws_flavors", title: "Flavors & Glazes", ingredients: [
                ChainIngredient(id: "ws_lemon_pepper", name: "Lemon Pepper Dry Rub", servingDescription: "5 wings coating", calories: 15, protein: 0, carbs: 1, fat: 1),
                ChainIngredient(id: "ws_garlic_parm", name: "Garlic Parmesan Sauce", servingDescription: "5 wings coating", calories: 130, protein: 1, carbs: 2, fat: 13),
                ChainIngredient(id: "ws_hot", name: "Original Hot Sauce", servingDescription: "5 wings coating", calories: 30, protein: 0, carbs: 2, fat: 2)
            ]),
            ChainCategory(id: "ws_dips", title: "Dips & Veggie Sides", ingredients: [
                ChainIngredient(id: "ws_ranch", name: "House-Made Ranch Cup", servingDescription: "1 cup (1.5 oz)", calories: 200, protein: 1, carbs: 2, fat: 21),
                ChainIngredient(id: "ws_veggies", name: "Celery & Carrot Sticks", servingDescription: "Standard side", calories: 15, protein: 1, carbs: 3, fat: 0, fiber: 2)
            ])
        ]
    )

    // MARK: - Chick-fil-A
    public static let chickFilA = ChainRestaurant(
        id: "chick_fil_a",
        name: "Chick-fil-A",
        subtitle: "Chicken Sandwiches, Nuggets & Sauces",
        iconName: "bird.fill",
        brandColorHex: "#E51636",
        categories: [
            ChainCategory(id: "cfa_entrees", title: "Entrees & Nuggets", ingredients: [
                ChainIngredient(id: "cfa_grilled_nuggets_8", name: "Grilled Nuggets (8 Ct)", servingDescription: "8 pieces", calories: 130, protein: 25, carbs: 1, fat: 3, controlStyle: .fixed),
                ChainIngredient(id: "cfa_grilled_nuggets_12", name: "Grilled Nuggets (12 Ct)", servingDescription: "12 pieces", calories: 200, protein: 38, carbs: 2, fat: 4.5, controlStyle: .fixed),
                ChainIngredient(id: "cfa_nuggets_8", name: "Chick-fil-A Nuggets (8 Ct)", servingDescription: "8 pieces", calories: 250, protein: 27, carbs: 11, fat: 11, controlStyle: .fixed),
                ChainIngredient(id: "cfa_grilled_sandwich", name: "Grilled Chicken Sandwich", servingDescription: "1 sandwich", calories: 390, protein: 29, carbs: 44, fat: 12, controlStyle: .fixed),
                ChainIngredient(id: "cfa_spicy_sandwich", name: "Spicy Chicken Sandwich", servingDescription: "1 sandwich", calories: 450, protein: 28, carbs: 45, fat: 19, controlStyle: .fixed)
            ]),
            ChainCategory(id: "cfa_sides", title: "Sides & Salads", ingredients: [
                ChainIngredient(id: "cfa_waffle_fries_m", name: "Waffle Potato Fries (Medium)", servingDescription: "1 order", calories: 420, protein: 5, carbs: 45, fat: 24, controlStyle: .portion),
                ChainIngredient(id: "cfa_kale_crunch", name: "Kale Crunch Side", servingDescription: "Standard side", calories: 120, protein: 3, carbs: 8, fat: 9, controlStyle: .portion),
                ChainIngredient(id: "cfa_mac_cheese", name: "Mac & Cheese (Medium)", servingDescription: "1 order", calories: 450, protein: 20, carbs: 30, fat: 29, controlStyle: .portion)
            ]),
            ChainCategory(id: "cfa_sauces", title: "Sauces & Dressings (Per Packet)", ingredients: [
                ChainIngredient(id: "cfa_sauce_pkt", name: "Chick-fil-A Sauce Packet", servingDescription: "1 packet", calories: 140, protein: 0, carbs: 7, fat: 13, controlStyle: .stepper(unit: "packets")),
                ChainIngredient(id: "cfa_poly_pkt", name: "Polynesian Sauce Packet", servingDescription: "1 packet", calories: 110, protein: 0, carbs: 14, fat: 6, controlStyle: .stepper(unit: "packets")),
                ChainIngredient(id: "cfa_ranch_pkt", name: "Garden Herb Ranch Packet", servingDescription: "1 packet", calories: 140, protein: 1, carbs: 1, fat: 15, controlStyle: .stepper(unit: "packets")),
                ChainIngredient(id: "cfa_buffalo_pkt", name: "Zesty Buffalo Sauce Packet", servingDescription: "1 packet", calories: 25, protein: 0, carbs: 1, fat: 2.5, controlStyle: .stepper(unit: "packets"))
            ])
        ]
    )

    // MARK: - Taco Bell
    public static let tacoBell = ChainRestaurant(
        id: "taco_bell",
        name: "Taco Bell",
        subtitle: "Power Bowls, Burritos, Tacos & Extras",
        iconName: "bell.fill",
        brandColorHex: "#702082",
        categories: [
            ChainCategory(id: "tb_bases", title: "Power Bowls & Tacos", ingredients: [
                ChainIngredient(id: "tb_power_bowl_chk", name: "Power Menu Bowl - Chicken Base", servingDescription: "1 bowl", calories: 460, protein: 27, carbs: 41, fat: 21, controlStyle: .fixed),
                ChainIngredient(id: "tb_power_bowl_stk", name: "Power Menu Bowl - Steak Base", servingDescription: "1 bowl", calories: 480, protein: 26, carbs: 42, fat: 23, controlStyle: .fixed),
                ChainIngredient(id: "tb_crunchy_taco", name: "Crunchy Taco", servingDescription: "1 taco", calories: 170, protein: 8, carbs: 13, fat: 10, controlStyle: .stepper(unit: "tacos")),
                ChainIngredient(id: "tb_soft_taco", name: "Soft Taco", servingDescription: "1 taco", calories: 180, protein: 9, carbs: 18, fat: 9, controlStyle: .stepper(unit: "tacos"))
            ]),
            ChainCategory(id: "tb_mods", title: "Custom Add-Ins & Extras", ingredients: [
                ChainIngredient(id: "tb_extra_beef", name: "Seasoned Beef Portion", servingDescription: "Standard portion", calories: 70, protein: 5, carbs: 3, fat: 4.5, controlStyle: .portion),
                ChainIngredient(id: "tb_extra_chicken", name: "Grilled Chicken Portion", servingDescription: "Standard portion", calories: 50, protein: 9, carbs: 0, fat: 1.5, controlStyle: .portion),
                ChainIngredient(id: "tb_black_beans", name: "Black Beans Portion", servingDescription: "Standard scoop", calories: 50, protein: 3, carbs: 8, fat: 1, controlStyle: .portion),
                ChainIngredient(id: "tb_nacho_cheese", name: "Nacho Cheese Sauce", servingDescription: "Standard side", calories: 60, protein: 1, carbs: 4, fat: 4.5, controlStyle: .portion),
                ChainIngredient(id: "tb_guac", name: "Guacamole Portion", servingDescription: "Standard scoop", calories: 70, protein: 1, carbs: 3, fat: 6, controlStyle: .portion)
            ])
        ]
    )

    // MARK: - In-N-Out Burger
    public static let inNOut = ChainRestaurant(
        id: "in_n_out",
        name: "In-N-Out",
        subtitle: "Burgers, Protein Style Wraps & Fries",
        iconName: "leaf.fill",
        brandColorHex: "#FFCB05",
        categories: [
            ChainCategory(id: "ino_burgers", title: "Burgers & Wraps", ingredients: [
                ChainIngredient(id: "ino_dbl_dbl", name: "Double-Double (w/ Onion)", servingDescription: "1 burger", calories: 670, protein: 37, carbs: 39, fat: 41, controlStyle: .fixed),
                ChainIngredient(id: "ino_dbl_dbl_protein", name: "Double-Double Protein Style (Lettuce Wrap)", servingDescription: "1 lettuce wrap", calories: 520, protein: 33, carbs: 11, fat: 39, controlStyle: .fixed),
                ChainIngredient(id: "ino_cheeseburger", name: "Cheeseburger (w/ Onion)", servingDescription: "1 burger", calories: 480, protein: 22, carbs: 39, fat: 27, controlStyle: .fixed),
                ChainIngredient(id: "ino_cheeseburger_protein", name: "Cheeseburger Protein Style", servingDescription: "1 lettuce wrap", calories: 330, protein: 18, carbs: 11, fat: 25, controlStyle: .fixed)
            ]),
            ChainCategory(id: "ino_mods", title: "Custom Add-Ons & Fries", ingredients: [
                ChainIngredient(id: "ino_animal_style", name: "Animal Style Burger Modification", servingDescription: "Mustard cook, pickles, extra spread", calories: 80, protein: 1, carbs: 3, fat: 7, controlStyle: .fixed),
                ChainIngredient(id: "ino_spread_pkt", name: "In-N-Out Spread Packet", servingDescription: "1 packet", calories: 80, protein: 0, carbs: 3, fat: 7, controlStyle: .stepper(unit: "packets")),
                ChainIngredient(id: "ino_fries", name: "French Fries", servingDescription: "1 order", calories: 395, protein: 7, carbs: 54, fat: 18, controlStyle: .portion)
            ])
        ]
    )

    // MARK: - Panera Bread
    public static let panera = ChainRestaurant(
        id: "panera",
        name: "Panera Bread",
        subtitle: "Warm Bowls, Salads, Soups & Sandwiches",
        iconName: "cup.and.saucer.fill",
        brandColorHex: "#3E5B36",
        categories: [
            ChainCategory(id: "pan_bowls", title: "Warm Bowls & Salads", ingredients: [
                ChainIngredient(id: "pan_med_chicken_bowl", name: "Mediterranean Warm Bowl with Chicken", servingDescription: "1 bowl", calories: 630, protein: 32, carbs: 64, fat: 27, controlStyle: .fixed),
                ChainIngredient(id: "pan_fuji_salad", name: "Fuji Apple Chicken Salad (Full)", servingDescription: "1 salad", calories: 560, protein: 30, carbs: 36, fat: 34, controlStyle: .fixed),
                ChainIngredient(id: "pan_broc_cheddar", name: "Broccoli Cheddar Soup (Bowl)", servingDescription: "1 bowl", calories: 360, protein: 14, carbs: 30, fat: 21, controlStyle: .fixed)
            ]),
            ChainCategory(id: "pan_sides", title: "Included Pick Sides", ingredients: [
                ChainIngredient(id: "pan_apple", name: "Fresh Apple Side", servingDescription: "1 apple", calories: 80, protein: 0, carbs: 22, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "pan_baguette", name: "French Baguette Side", servingDescription: "1 piece", calories: 180, protein: 6, carbs: 36, fat: 1, controlStyle: .fixed)
            ])
        ]
    )

    // MARK: - Culver's
    public static let culvers = ChainRestaurant(
        id: "culvers",
        name: "Culver's",
        subtitle: "ButterBurgers, Custard & Curds",
        iconName: "star.fill",
        brandColorHex: "#00539F",
        categories: [
            ChainCategory(id: "cul_burgers", title: "ButterBurgers & Entrees", ingredients: [
                ChainIngredient(id: "cul_single_cheese", name: "ButterBurger Cheese Single", servingDescription: "1 burger", calories: 460, protein: 23, carbs: 39, fat: 23, controlStyle: .fixed),
                ChainIngredient(id: "cul_double_cheese", name: "ButterBurger Cheese Double", servingDescription: "1 burger", calories: 650, protein: 39, carbs: 39, fat: 38, controlStyle: .fixed),
                ChainIngredient(id: "cul_tenders_4", name: "Crispy Chicken Tenders (4 Pc)", servingDescription: "4 tenders", calories: 540, protein: 44, carbs: 24, fat: 28, controlStyle: .fixed)
            ]),
            ChainCategory(id: "cul_sides", title: "Sides & Custard", ingredients: [
                ChainIngredient(id: "cul_curds_m", name: "Wisconsin Cheese Curds (Medium)", servingDescription: "1 order", calories: 510, protein: 20, carbs: 45, fat: 28, controlStyle: .portion),
                ChainIngredient(id: "cul_custard_vanilla", name: "Vanilla Frozen Custard (1 Scoop)", servingDescription: "1 dish", calories: 300, protein: 5, carbs: 31, fat: 17, controlStyle: .stepper(unit: "scoops"))
            ])
        ]
    )

    // MARK: - Wendy's
    public static let wendys = ChainRestaurant(
        id: "wendys",
        name: "Wendy's",
        subtitle: "Burgers, Chicken, Salads & Frosty",
        iconName: "flame.fill",
        brandColorHex: "#E2231A",
        categories: [
            ChainCategory(id: "wen_entrees", title: "Burgers & Salads", ingredients: [
                ChainIngredient(id: "wen_daves_single", name: "Dave's Single", servingDescription: "1 burger", calories: 590, protein: 33, carbs: 39, fat: 37, controlStyle: .fixed),
                ChainIngredient(id: "wen_spicy_nuggets_10", name: "Spicy Chicken Nuggets (10 Pc)", servingDescription: "10 pieces", calories: 470, protein: 25, carbs: 22, fat: 31, controlStyle: .fixed),
                ChainIngredient(id: "wen_apple_pecan", name: "Apple Pecan Salad (w/ Chicken)", servingDescription: "Full salad", calories: 450, protein: 32, carbs: 42, fat: 18, controlStyle: .fixed)
            ]),
            ChainCategory(id: "wen_sides", title: "Sides & Frosty", ingredients: [
                ChainIngredient(id: "wen_frosty_choc_s", name: "Classic Chocolate Frosty (Small)", servingDescription: "Small cup", calories: 350, protein: 9, carbs: 58, fat: 9, controlStyle: .fixed),
                ChainIngredient(id: "wen_baked_potato", name: "Sour Cream & Chive Baked Potato", servingDescription: "1 potato", calories: 310, protein: 7, carbs: 63, fat: 3, controlStyle: .fixed)
            ])
        ]
    )

    // MARK: - McDonald's
    public static let mcdonalds = ChainRestaurant(
        id: "mcdonalds",
        name: "McDonald's",
        subtitle: "Burgers, Nuggets, Breakfast & Fries",
        iconName: "star.fill",
        brandColorHex: "#FFC72C",
        categories: [
            ChainCategory(id: "mcd_entrees", title: "Burgers & Chicken", ingredients: [
                ChainIngredient(id: "mcd_big_mac", name: "Big Mac", servingDescription: "1 burger", calories: 590, protein: 25, carbs: 46, fat: 34, controlStyle: .fixed),
                ChainIngredient(id: "mcd_quarter_pounder", name: "Quarter Pounder with Cheese", servingDescription: "1 burger", calories: 520, protein: 30, carbs: 42, fat: 26, controlStyle: .fixed),
                ChainIngredient(id: "mcd_mcchicken", name: "McChicken", servingDescription: "1 sandwich", calories: 400, protein: 14, carbs: 39, fat: 21, controlStyle: .fixed),
                ChainIngredient(id: "mcd_nuggets_10", name: "Chicken McNuggets (10 Pc)", servingDescription: "10 pieces", calories: 410, protein: 23, carbs: 26, fat: 24, controlStyle: .fixed)
            ]),
            ChainCategory(id: "mcd_breakfast_sides", title: "Breakfast & Fries", ingredients: [
                ChainIngredient(id: "mcd_egg_mcmuffin", name: "Egg McMuffin", servingDescription: "1 sandwich", calories: 310, protein: 17, carbs: 30, fat: 13, controlStyle: .fixed),
                ChainIngredient(id: "mcd_hash_brown", name: "Hash Browns", servingDescription: "1 piece", calories: 140, protein: 2, carbs: 18, fat: 8, controlStyle: .fixed),
                ChainIngredient(id: "mcd_fries_m", name: "World Famous Fries (Medium)", servingDescription: "1 order", calories: 320, protein: 4, carbs: 43, fat: 15, controlStyle: .portion)
            ]),
            ChainCategory(id: "mcd_sauces", title: "Sauces (Per Packet)", ingredients: [
                ChainIngredient(id: "mcd_bbq_pkt", name: "Tangy Barbeque Sauce Packet", servingDescription: "1 packet", calories: 45, protein: 0, carbs: 11, fat: 0, controlStyle: .stepper(unit: "packets")),
                ChainIngredient(id: "mcd_sweet_sour_pkt", name: "Sweet and Sour Sauce Packet", servingDescription: "1 packet", calories: 50, protein: 0, carbs: 11, fat: 0, controlStyle: .stepper(unit: "packets")),
                ChainIngredient(id: "mcd_buffalo_pkt", name: "Spicy Buffalo Sauce Packet", servingDescription: "1 packet", calories: 30, protein: 0, carbs: 1, fat: 3, controlStyle: .stepper(unit: "packets"))
            ])
        ]
    )

    // MARK: - Burger King
    public static let burgerKing = ChainRestaurant(
        id: "burger_king",
        name: "Burger King",
        subtitle: "Flame-Grilled Whoppers & Chicken",
        iconName: "flame.fill",
        brandColorHex: "#D62300",
        categories: [
            ChainCategory(id: "bk_burgers", title: "Flame-Grilled Burgers", ingredients: [
                ChainIngredient(id: "bk_whopper", name: "Whopper", servingDescription: "1 burger", calories: 670, protein: 29, carbs: 51, fat: 39, controlStyle: .fixed),
                ChainIngredient(id: "bk_whopper_jr", name: "Whopper Jr.", servingDescription: "1 burger", calories: 330, protein: 15, carbs: 30, fat: 18, controlStyle: .fixed),
                ChainIngredient(id: "bk_impossible_whopper", name: "Impossible Whopper", servingDescription: "1 burger", calories: 630, protein: 25, carbs: 58, fat: 34, controlStyle: .fixed)
            ]),
            ChainCategory(id: "bk_chicken_sides", title: "Chicken & Sides", ingredients: [
                ChainIngredient(id: "bk_orig_chicken", name: "Original Chicken Sandwich", servingDescription: "1 sandwich", calories: 680, protein: 28, carbs: 61, fat: 36, controlStyle: .fixed),
                ChainIngredient(id: "bk_chicken_fries_9", name: "Chicken Fries (9 Pc)", servingDescription: "9 pieces", calories: 280, protein: 13, carbs: 20, fat: 17, controlStyle: .fixed),
                ChainIngredient(id: "bk_fries_m", name: "French Fries (Medium)", servingDescription: "1 order", calories: 380, protein: 4, carbs: 53, fat: 17, controlStyle: .portion),
                ChainIngredient(id: "bk_onion_rings_m", name: "Onion Rings (Medium)", servingDescription: "1 order", calories: 410, protein: 5, carbs: 53, fat: 20, controlStyle: .portion)
            ])
        ]
    )

    // MARK: - Popeyes
    public static let popeyes = ChainRestaurant(
        id: "popeyes",
        name: "Popeyes",
        subtitle: "Louisiana Kitchen Sandwiches & Tenders",
        iconName: "bird.fill",
        brandColorHex: "#F26522",
        categories: [
            ChainCategory(id: "pop_entrees", title: "Sandwiches & Handcrafted Tenders", ingredients: [
                ChainIngredient(id: "pop_classic_sandwich", name: "Classic Chicken Sandwich", servingDescription: "1 sandwich", calories: 700, protein: 28, carbs: 50, fat: 42, controlStyle: .fixed),
                ChainIngredient(id: "pop_spicy_sandwich", name: "Spicy Chicken Sandwich", servingDescription: "1 sandwich", calories: 700, protein: 28, carbs: 50, fat: 42, controlStyle: .fixed),
                ChainIngredient(id: "pop_tenders_3", name: "Handcrafted Chicken Tenders (3 Pc)", servingDescription: "3 tenders", calories: 380, protein: 35, carbs: 20, fat: 18, controlStyle: .fixed)
            ]),
            ChainCategory(id: "pop_sides", title: "Famous Sides", ingredients: [
                ChainIngredient(id: "pop_red_beans_r", name: "Red Beans & Rice (Regular)", servingDescription: "1 side", calories: 250, protein: 8, carbs: 38, fat: 8, fiber: 6, controlStyle: .portion),
                ChainIngredient(id: "pop_cajun_fries_r", name: "Cajun Fries (Regular)", servingDescription: "1 side", calories: 260, protein: 4, carbs: 33, fat: 12, controlStyle: .portion),
                ChainIngredient(id: "pop_mac_cheese_r", name: "Homestyle Mac & Cheese (Regular)", servingDescription: "1 side", calories: 280, protein: 10, carbs: 23, fat: 17, controlStyle: .portion)
            ]),
            ChainCategory(id: "pop_sauces", title: "Signature Sauces", ingredients: [
                ChainIngredient(id: "pop_ranch_pkt", name: "Blackened Ranch Packet", servingDescription: "1 packet", calories: 120, protein: 1, carbs: 2, fat: 12, controlStyle: .stepper(unit: "packets")),
                ChainIngredient(id: "pop_sweet_heat_pkt", name: "Sweet Heat Sauce Packet", servingDescription: "1 packet", calories: 70, protein: 0, carbs: 18, fat: 0, controlStyle: .stepper(unit: "packets"))
            ])
        ]
    )

    // MARK: - Tropical Smoothie Cafe
    public static let tropicalSmoothie = ChainRestaurant(
        id: "tropical_smoothie",
        name: "Tropical Smoothie Cafe",
        subtitle: "Smoothies, Flatbreads & Protein Boosts",
        iconName: "cup.and.straw.fill",
        brandColorHex: "#009B77",
        categories: [
            ChainCategory(id: "tsc_smoothies", title: "Smoothies & Flatbreads", ingredients: [
                ChainIngredient(id: "tsc_sunrise_sunset", name: "Sunrise Sunset Smoothie", servingDescription: "24 oz", calories: 400, protein: 2, carbs: 98, fat: 0, controlStyle: .fixed),
                ChainIngredient(id: "tsc_detox_green", name: "Detox Island Green Smoothie", servingDescription: "24 oz", calories: 290, protein: 4, carbs: 68, fat: 1, controlStyle: .fixed),
                ChainIngredient(id: "tsc_avocolada", name: "Avocolada Smoothie", servingDescription: "24 oz", calories: 580, protein: 6, carbs: 96, fat: 21, controlStyle: .fixed),
                ChainIngredient(id: "tsc_chipotle_chicken", name: "Chipotle Chicken Club Flatbread", servingDescription: "1 flatbread", calories: 520, protein: 28, carbs: 46, fat: 24, controlStyle: .fixed)
            ]),
            ChainCategory(id: "tsc_boosts", title: "Protein & Supplement Boosts", ingredients: [
                ChainIngredient(id: "tsc_whey_scoop", name: "Whey Protein Powder Scoop", servingDescription: "1 scoop", calories: 90, protein: 15, carbs: 4, fat: 1, controlStyle: .stepper(unit: "scoops")),
                ChainIngredient(id: "tsc_pea_scoop", name: "Pea Protein Powder Scoop", servingDescription: "1 scoop", calories: 80, protein: 15, carbs: 3, fat: 1.5, controlStyle: .stepper(unit: "scoops")),
                ChainIngredient(id: "tsc_pb_scoop", name: "Natural Peanut Butter Scoop", servingDescription: "1 scoop", calories: 180, protein: 8, carbs: 6, fat: 15, controlStyle: .stepper(unit: "scoops"))
            ])
        ]
    )

    // MARK: - Jimmy John's
    public static let jimmyJohns = ChainRestaurant(
        id: "jimmy_johns",
        name: "Jimmy John's",
        subtitle: "Freaky Fast Subs & Lettuce Unwiches",
        iconName: "bag.fill",
        brandColorHex: "#D11F2E",
        categories: [
            ChainCategory(id: "jj_subs", title: "Subs & Unwiches", ingredients: [
                ChainIngredient(id: "jj_turkey_tom", name: "#4 Turkey Tom (Regular 8\")", servingDescription: "1 sub", calories: 480, protein: 24, carbs: 54, fat: 19, controlStyle: .fixed),
                ChainIngredient(id: "jj_turkey_tom_unwich", name: "#4 Turkey Tom Unwich (Lettuce Wrap)", servingDescription: "1 unwich", calories: 70, protein: 13, carbs: 3, fat: 1, controlStyle: .fixed),
                ChainIngredient(id: "jj_pepe", name: "#1 The Pepe (Ham & Provolone)", servingDescription: "1 sub", calories: 600, protein: 28, carbs: 54, fat: 29, controlStyle: .fixed),
                ChainIngredient(id: "jj_inc", name: "#9 Italian Night Club", servingDescription: "1 sub", calories: 930, protein: 44, carbs: 57, fat: 58, controlStyle: .fixed)
            ]),
            ChainCategory(id: "jj_mods", title: "Condiments & Extras", ingredients: [
                ChainIngredient(id: "jj_jimmy_mustard", name: "Jimmy Mustard", servingDescription: "Standard portion", calories: 10, protein: 1, carbs: 1, fat: 0, controlStyle: .portion),
                ChainIngredient(id: "jj_peppers", name: "Jimmy Peppers (Hot)", servingDescription: "Standard portion", calories: 5, protein: 0, carbs: 1, fat: 0, controlStyle: .portion),
                ChainIngredient(id: "jj_avo_spread", name: "Avocado Spread", servingDescription: "Standard portion", calories: 70, protein: 1, carbs: 3, fat: 6, controlStyle: .portion)
            ])
        ]
    )

    // MARK: - Firehouse Subs
    public static let firehouseSubs = ChainRestaurant(
        id: "firehouse_subs",
        name: "Firehouse Subs",
        subtitle: "Hot Specialty Subs & Salads",
        iconName: "flame.fill",
        brandColorHex: "#B8111A",
        categories: [
            ChainCategory(id: "fhs_subs", title: "Hot Specialty Subs (Medium)", ingredients: [
                ChainIngredient(id: "fhs_hook_ladder", name: "Hook & Ladder (Turkey & Ham)", servingDescription: "Medium sub", calories: 720, protein: 44, carbs: 58, fat: 34, controlStyle: .fixed),
                ChainIngredient(id: "fhs_club_on_sub", name: "Club on a Sub", servingDescription: "Medium sub", calories: 780, protein: 48, carbs: 58, fat: 40, controlStyle: .fixed),
                ChainIngredient(id: "fhs_brisket", name: "Smokehouse Beef & Cheddar Brisket", servingDescription: "Medium sub", calories: 890, protein: 47, carbs: 57, fat: 53, controlStyle: .fixed)
            ])
        ]
    )

    // MARK: - Domino's Pizza
    public static let dominos = ChainRestaurant(
        id: "dominos",
        name: "Domino's Pizza",
        subtitle: "Custom Pizza Slices & Dips",
        iconName: "chart.pie.fill",
        brandColorHex: "#006491",
        categories: [
            ChainCategory(id: "dom_slices", title: "Pizza Slices (Per Slice - 1/8 Large)", ingredients: [
                ChainIngredient(id: "dom_ht_pepperoni", name: "Hand Tossed Pepperoni Slice", servingDescription: "1 slice", calories: 300, protein: 12, carbs: 35, fat: 12, controlStyle: .stepper(unit: "slices")),
                ChainIngredient(id: "dom_ht_cheese", name: "Hand Tossed Cheese Slice", servingDescription: "1 slice", calories: 290, protein: 12, carbs: 35, fat: 11, controlStyle: .stepper(unit: "slices")),
                ChainIngredient(id: "dom_thin_pepp", name: "Thin Crust Pepperoni Slice", servingDescription: "1 slice", calories: 210, protein: 9, carbs: 15, fat: 13, controlStyle: .stepper(unit: "slices"))
            ]),
            ChainCategory(id: "dom_extras", title: "Dips & Specialty Chicken", ingredients: [
                ChainIngredient(id: "dom_garlic_dip", name: "Garlic Dipping Sauce Cup", servingDescription: "1 cup", calories: 250, protein: 0, carbs: 0, fat: 28, controlStyle: .stepper(unit: "cups")),
                ChainIngredient(id: "dom_spec_chicken", name: "Specialty Chicken - Classic Hot Buffalo", servingDescription: "4 pieces", calories: 170, protein: 11, carbs: 6, fat: 11, controlStyle: .portion)
            ])
        ]
    )

    // MARK: - Five Guys
    public static let fiveGuys = ChainRestaurant(
        id: "five_guys",
        name: "Five Guys",
        subtitle: "Handcrafted Burgers, Dogs & Fries",
        iconName: "star.fill",
        brandColorHex: "#D1121C",
        categories: [
            ChainCategory(id: "fg_burgers", title: "Burgers", ingredients: [
                ChainIngredient(id: "fg_cheeseburger", name: "Cheeseburger (2 Patties)", servingDescription: "1 burger", calories: 840, protein: 47, carbs: 39, fat: 55, controlStyle: .fixed),
                ChainIngredient(id: "fg_little_cheeseburger", name: "Little Cheeseburger (1 Patty)", servingDescription: "1 burger", calories: 610, protein: 30, carbs: 39, fat: 36, controlStyle: .fixed),
                ChainIngredient(id: "fg_bacon_cheeseburger", name: "Bacon Cheeseburger", servingDescription: "1 burger", calories: 920, protein: 51, carbs: 40, fat: 62, controlStyle: .fixed)
            ]),
            ChainCategory(id: "fg_toppings_fries", title: "Toppings & Peanut Oil Fries", ingredients: [
                ChainIngredient(id: "fg_mushrooms", name: "Grilled Mushrooms", servingDescription: "Free topping", calories: 5, protein: 1, carbs: 1, fat: 0, controlStyle: .portion),
                ChainIngredient(id: "fg_onions", name: "Grilled Onions", servingDescription: "Free topping", calories: 10, protein: 0, carbs: 2, fat: 0, controlStyle: .portion),
                ChainIngredient(id: "fg_little_fries", name: "Little Fries", servingDescription: "1 order", calories: 530, protein: 8, carbs: 72, fat: 23, controlStyle: .portion)
            ])
        ]
    )
}
