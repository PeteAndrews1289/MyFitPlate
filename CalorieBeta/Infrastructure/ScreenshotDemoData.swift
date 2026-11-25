import Foundation
import MyFitPlateCore
import SwiftUI

enum ScreenshotDemoMode {
    static var isEnabled: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-ui-testing") && arguments.contains("-screenshot-mode")
        #else
        return false
        #endif
    }
}

#if DEBUG
@MainActor
enum ScreenshotDemoData {
    static let userID = "mock_user"
    static let programID = "screenshot_demo_program"

    private struct HistoryTemplate {
        let title: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fats: Double
        let fiber: Double
        let workoutName: String?
    }

    private struct RunTemplate {
        let id: String
        let daysAgo: Int
        let distance: Double
        let seconds: Double
        let heartRate: Double
        let source: Run.Source
    }

    private struct AchievementProgressFixture {
        let statuses: [String: UserAchievementStatus]
        let points: Int
        let level: Int
        let challenges: [Challenge]
    }

    private static let calendar = Calendar.current
    private static var today: Date { calendar.startOfDay(for: Date()) }

    static var requestedScreen: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard ScreenshotDemoMode.isEnabled else { return "home" }

        if let inline = arguments.first(where: { $0.hasPrefix("-screenshot-screen=") }) {
            return canonicalScreenName(String(inline.dropFirst("-screenshot-screen=".count)))
        }
        if let flagIndex = arguments.firstIndex(of: "-screenshot-screen"),
           arguments.indices.contains(flagIndex + 1) {
            return canonicalScreenName(arguments[flagIndex + 1])
        }
        return "home"
    }

    static var wellnessDemoScore: WellnessScore {
        WellnessScore(
            overallScore: 84,
            nutritionScore: 82,
            sleepScore: 86,
            recoveryScore: nil,
            summary: "Your recorded nutrition and sleep are on track.",
            color: AppPalette.brand,
            hasRecoveryReadings: true
        )
    }

    static var wellnessDemoMealScore: MealScore {
        MealScore(
            grade: "B+",
            summary: "Strong protein and calorie consistency with room for more fiber.",
            color: AppPalette.brand,
            calorieScore: 88,
            macroScore: 84,
            qualityScore: 74,
            overallScore: 82,
            personalizedAISummary: "Yesterday supported your goals with a reliable protein base.",
            improvementTips: [
                ImprovementTip(
                    category: "Fiber",
                    advice: "Add fruit, beans, or vegetables to close the remaining fiber gap.",
                    icon: "leaf",
                    color: AppPalette.brand
                ),
                ImprovementTip(
                    category: "Sodium",
                    advice: "Balance the higher-sodium meal with minimally processed foods today.",
                    icon: "drop",
                    color: AppPalette.hydration
                )
            ],
            actualCalories: 2_040,
            goalCalories: 2_100,
            actualProtein: 156,
            goalProtein: 160,
            actualCarbs: 218,
            goalCarbs: 230,
            actualFats: 62,
            goalFats: 60,
            actualFiber: 24,
            goalFiber: 30,
            actualSaturatedFat: 15,
            goalSaturatedFat: 20,
            actualSodium: 2_460,
            goalSodium: 2_300
        )
    }

    static var wellnessDemoSleepReport: EnhancedSleepReport {
        var dailyData: [EnhancedSleepReport.DailySleepStageData] = []
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let timeInBed = (7.7 + Double(offset % 3) * 0.12) * 3_600
            let timeAsleep = (7.1 + Double(offset % 2) * 0.18) * 3_600
            let timeDeep = (1.0 + Double(offset % 2) * 0.12) * 3_600
            let day = EnhancedSleepReport.DailySleepStageData(
                date: date,
                timeInBed: timeInBed,
                timeAsleep: timeAsleep,
                timeCore: 4.2 * 3_600,
                timeDeep: timeDeep,
                timeREM: 1.8 * 3_600,
                timeAwake: 0.45 * 3_600
            )
            dailyData.append(day)
        }

        return EnhancedSleepReport(
            dateRange: "Last 7 nights",
            averageSleepScore: 86,
            averageTimeInBed: 7.9 * 3_600,
            averageTimeAsleep: 7.3 * 3_600,
            averageTimeInCore: 4.2 * 3_600,
            averageTimeInDeep: 1.1 * 3_600,
            averageTimeInREM: 1.8 * 3_600,
            averageTimeAwake: 0.5 * 3_600,
            sleepConsistencyScore: 88,
            sleepConsistencyMessage: "Bedtime and wake time stayed within a consistent range.",
            dailySleepData: dailyData
        )
    }

    static var cycleDemoDay: CycleDay {
        CycleDay(date: today, cycleDayNumber: 17, phase: .luteal)
    }

    static var cycleDemoInsight: AIInsight {
        AIInsight(
            phaseTitle: "Protect Your Baseline",
            phaseDescription: "Energy and appetite can shift during the luteal phase. Treat the pattern as context, then respond to how you actually feel today.",
            trainingFocus: AIInsight.TrainingFocus(
                title: "Keep Quality High",
                description: "Use your planned loads, but leave room to reduce volume if recovery feels lower than usual."
            ),
            hormonalState: "Typical luteal pattern",
            energyLevel: "Moderate",
            nutritionTip: "Keep protein steady and plan a satisfying high-fiber snack before hunger becomes distracting.",
            symptomTip: "Hydration, sleep consistency, and a lighter session can help when symptoms are more noticeable."
        )
    }

    static func canonicalScreenName(_ name: String) -> String {
        switch name.lowercased() {
        case "cpp-trust": return "trust"
        case "cpp-logging": return "food-search"
        case "cpp-dining": return "builder"
        case "cpp-strength": return "train"
        case "cpp-running": return "runs"
        case "cpp-weight": return "reports"
        case "cpp-meal-plan": return "meal-plan"
        default: return name.lowercased()
        }
    }

    static var trustDemoFood: FoodItem {
        discoveryFoods()[0]
    }

    static var sparseTrustDemoFood: FoodItem {
        FoodItem(
            id: "demo-sparse-branded-food",
            name: "Original Protein Bar",
            calories: 210,
            protein: 20,
            carbs: 23,
            fats: 7,
            saturatedFat: 2.5,
            fiber: 0,
            servingSize: "1 bar (60 g)",
            servingWeight: 60,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .fatSecret,
                confidence: .databaseMatch,
                reviewStatus: .unreviewed,
                sourceName: "FatSecret"
            )
        )
    }

    static var correctionTrustDemoFood: FoodItem {
        FoodItem(
            id: "demo-correction-barcode-food",
            name: "Cinnamon Bun Cookies",
            calories: 150,
            protein: 2,
            carbs: 21,
            fats: 7,
            saturatedFat: 10,
            fiber: 0,
            servingSize: "2 cookies (29 g)",
            servingWeight: 29,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: "0044000087579"
            )
        )
    }

    static var trustHubDemoLog: DailyLog {
        nutritionHistory()[0]
    }

    static var manualFoodDemoFood: FoodItem {
        FoodItem(
            id: "demo-manual-power-bowl",
            name: "Chicken Power Bowl",
            calories: 540,
            protein: 46,
            carbs: 58,
            fats: 14,
            saturatedFat: 3.5,
            fiber: 9,
            servingSize: "1 bowl",
            servingWeight: 420,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                originSourceType: .manual,
                confidence: .userVerified,
                reviewStatus: .userEdited,
                sourceName: "My Foods"
            )
        )
    }

    static var aiTextDemoFoods: [FoodItem] {
        [
            FoodItem(
                id: "demo-ai-text-bowl",
                name: "Chicken Burrito Bowl",
                calories: 620,
                protein: 42,
                carbs: 70,
                fats: 20,
                saturatedFat: 5,
                fiber: 13,
                servingSize: "1 bowl",
                servingWeight: 510,
                sourceMetadata: FoodSourceMetadata(
                    sourceType: .aiText,
                    confidence: .needsReview,
                    reviewStatus: .unreviewed,
                    sourceName: "Maia text estimate"
                )
            ),
            FoodItem(
                id: "demo-ai-text-guacamole",
                name: "Guacamole",
                calories: 110,
                protein: 2,
                carbs: 6,
                fats: 10,
                saturatedFat: 1.5,
                fiber: 4,
                servingSize: "1/4 cup",
                servingWeight: 60,
                sourceMetadata: FoodSourceMetadata(
                    sourceType: .aiText,
                    confidence: .needsReview,
                    reviewStatus: .unreviewed,
                    sourceName: "Maia text estimate"
                )
            ),
            FoodItem(
                id: "demo-ai-text-chips",
                name: "Tortilla Chips",
                calories: 140,
                protein: 2,
                carbs: 19,
                fats: 7,
                saturatedFat: 1,
                fiber: 2,
                servingSize: "1 small handful",
                servingWeight: 28,
                sourceMetadata: FoodSourceMetadata(
                    sourceType: .aiText,
                    confidence: .needsReview,
                    reviewStatus: .unreviewed,
                    sourceName: "Maia text estimate"
                )
            )
        ]
    }

    static var myFoodsDemoFoods: [FoodItem] {
        let oats = FoodItem(
            id: "demo-library-oats",
            name: "Power Protein Oats",
            calories: 445,
            protein: 34,
            carbs: 55,
            fats: 11,
            saturatedFat: 2,
            fiber: 9,
            servingSize: "1 bowl",
            servingWeight: 360,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                originSourceType: .manual,
                confidence: .userVerified,
                reviewStatus: .userEdited,
                sourceName: "My Foods"
            )
        )
        var duplicateOats = oats
        duplicateOats.id = "demo-library-oats-copy"

        let shake = FoodItem(
            id: "demo-library-shake",
            name: "Post-Workout Shake",
            calories: 310,
            protein: 42,
            carbs: 29,
            fats: 4,
            saturatedFat: 1,
            fiber: 4,
            servingSize: "20 fl oz",
            servingWeight: 590,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                originSourceType: .manual,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "Personal barcode correction",
                barcode: "0044000087579"
            )
        )

        let recipe = FoodItem(
            id: "demo-library-recipe",
            name: "Weeknight Chicken Bowl",
            calories: 610,
            protein: 51,
            carbs: 68,
            fats: 18,
            saturatedFat: 4,
            fiber: 10,
            servingSize: "1 recipe serving",
            servingWeight: 475,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                originSourceType: .recipe,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Recipes"
            )
        )

        let needsReview = FoodItem(
            id: "demo-library-review",
            name: "Granola Label Scan",
            calories: 260,
            protein: 8,
            carbs: 38,
            fats: 9,
            saturatedFat: 2,
            fiber: 5,
            servingSize: "2/3 cup",
            servingWeight: 62,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                originSourceType: .aiImage,
                confidence: .needsReview,
                reviewStatus: .unreviewed,
                sourceName: "Nutrition label scan"
            )
        )

        return [oats, duplicateOats, shake, recipe, needsReview]
    }

    static var myFoodsDemoRecentFoods: [FoodItem] {
        var oats = myFoodsDemoFoods[0]
        oats.timestamp = Date().addingTimeInterval(-2 * 60 * 60)
        var shake = myFoodsDemoFoods[2]
        shake.timestamp = Date().addingTimeInterval(-24 * 60 * 60)
        return [oats, shake]
    }

    static var recipeDemoRecipes: [Recipe] {
        func ingredient(
            id: String,
            name: String,
            calories: Double,
            protein: Double,
            carbs: Double,
            fats: Double,
            fiber: Double,
            quantity: Double,
            unit: String
        ) -> FoodItem {
            var item = trustedFood(
                id: id,
                name: name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fats: fats,
                fiber: fiber,
                servingSize: "\(quantity.formatted()) \(unit)",
                servingWeight: unit == "g" ? quantity : 0,
                sourceType: .usda,
                sourceName: "USDA FoodData Central"
            )
            item.quantityValue = quantity
            item.servingUnit = unit
            return item
        }

        let chickenBowlIngredients = [
            ingredient(
                id: "demo-recipe-chicken",
                name: "Grilled Chicken Breast",
                calories: 245,
                protein: 46,
                carbs: 0,
                fats: 5,
                fiber: 0,
                quantity: 170,
                unit: "g"
            ),
            ingredient(
                id: "demo-recipe-rice",
                name: "Jasmine Rice",
                calories: 180,
                protein: 4,
                carbs: 40,
                fats: 0.5,
                fiber: 1,
                quantity: 140,
                unit: "g"
            ),
            ingredient(
                id: "demo-recipe-beans",
                name: "Black Beans",
                calories: 90,
                protein: 6,
                carbs: 16,
                fats: 0.5,
                fiber: 6,
                quantity: 85,
                unit: "g"
            ),
            ingredient(
                id: "demo-recipe-salsa",
                name: "Avocado Salsa",
                calories: 95,
                protein: 2,
                carbs: 10,
                fats: 6,
                fiber: 4,
                quantity: 95,
                unit: "g"
            )
        ]

        let oatsIngredients = [
            ingredient(
                id: "demo-recipe-oats",
                name: "Rolled Oats",
                calories: 225,
                protein: 8,
                carbs: 40,
                fats: 4,
                fiber: 6,
                quantity: 60,
                unit: "g"
            ),
            ingredient(
                id: "demo-recipe-yogurt",
                name: "Greek Yogurt",
                calories: 130,
                protein: 23,
                carbs: 9,
                fats: 0,
                fiber: 0,
                quantity: 225,
                unit: "g"
            ),
            ingredient(
                id: "demo-recipe-berries",
                name: "Blueberries",
                calories: 85,
                protein: 1,
                carbs: 21,
                fats: 0.5,
                fiber: 4,
                quantity: 150,
                unit: "g"
            )
        ]

        let salmonIngredients = [
            ingredient(
                id: "demo-recipe-salmon",
                name: "Baked Atlantic Salmon",
                calories: 300,
                protein: 34,
                carbs: 0,
                fats: 18,
                fiber: 0,
                quantity: 145,
                unit: "g"
            ),
            ingredient(
                id: "demo-recipe-quinoa",
                name: "Cooked Quinoa",
                calories: 185,
                protein: 7,
                carbs: 32,
                fats: 3,
                fiber: 4,
                quantity: 155,
                unit: "g"
            ),
            ingredient(
                id: "demo-recipe-vegetables",
                name: "Roasted Mixed Vegetables",
                calories: 120,
                protein: 4,
                carbs: 21,
                fats: 3,
                fiber: 7,
                quantity: 220,
                unit: "g"
            )
        ]

        let recipes = [
            Recipe(
                id: "demo-recipe-chicken-bowl",
                name: "Weeknight Chicken Power Bowl",
                ingredients: [
                    "170 g grilled chicken breast",
                    "140 g cooked jasmine rice",
                    "85 g black beans",
                    "95 g avocado salsa"
                ],
                detailedIngredients: chickenBowlIngredients,
                instructions: [
                    "Warm the rice and black beans together.",
                    "Slice the grilled chicken and arrange it over the rice.",
                    "Finish with avocado salsa and serve."
                ],
                nutrition: Nutrition.total(for: chickenBowlIngredients),
                servings: 1
            ),
            Recipe(
                id: "demo-recipe-oats",
                name: "Blueberry Protein Overnight Oats",
                ingredients: [
                    "60 g rolled oats",
                    "225 g nonfat Greek yogurt",
                    "150 g blueberries"
                ],
                detailedIngredients: oatsIngredients,
                instructions: [
                    "Stir the oats and Greek yogurt together.",
                    "Fold in half of the blueberries and refrigerate overnight.",
                    "Top with the remaining berries before serving."
                ],
                nutrition: Nutrition.total(for: oatsIngredients),
                servings: 1
            ),
            Recipe(
                id: "demo-recipe-salmon",
                name: "Lemon Salmon Quinoa Plate",
                ingredients: [
                    "145 g baked Atlantic salmon",
                    "155 g cooked quinoa",
                    "220 g roasted mixed vegetables"
                ],
                detailedIngredients: salmonIngredients,
                instructions: [
                    "Season the salmon with lemon and bake until just cooked through.",
                    "Warm the quinoa and vegetables.",
                    "Plate together and spoon the pan juices over the salmon."
                ],
                nutrition: Nutrition.total(for: salmonIngredients),
                servings: 1
            )
        ]
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-recipe-quantity") {
            let metadata = FoodSourceMetadata(sourceType: .fatSecret, confidence: .databaseMatch, reviewStatus: .notRequired,
                sourceName: "Synthetic quantity regression reference", sourceID: "qa-quantity-reference", createdAt: today)
            let ingredient = FoodItem(id: "qa-quantity-rice", name: "QA quantity rice", calories: 640, protein: 12, carbs: 144, fats: 0,
                servingSize: "180 g", servingWeight: 180, sourceMetadata: metadata, quantityValue: 180, servingUnit: "g")
            var fixture = Recipe(id: "qa-quantity-recipe", name: "QA quantity batch", ingredients: ["180 g QA quantity rice"],
                detailedIngredients: [ingredient], instructions: ["Cook rice.", "Weigh the cooked batch."],
                nutrition: Nutrition.total(for: [ingredient]), servings: 4, nutritionBasis: .wholeRecipe,
                nutritionOrigin: .ingredients, unresolvedIngredients: [], cookedWeightGrams: 800)
            fixture.revisionID = try? RecipePortionRules.revisionID(for: fixture)
            return [fixture] + recipes
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-constrained-recipes") {
            var bowl = Recipe(id: "wave2-reviewed-bowl", name: "Reviewed bean bowl", ingredients: ["200 g beans", "100 g rice"], instructions: ["Cook rice.", "Mix beans and rice."], nutrition: Nutrition(calories: 500, protein: 40, carbs: 60, fats: 10), servings: 1, nutritionBasis: .perServing)
            bowl.planningProfile = RecipePlanningProfile(prepMinutes: 20, equipment: ["stove"], diet: .vegan, reviewedExclusions: ["peanut"], costPerServing: 2, reviewedAt: today, contentFingerprint: try? RecipePlanningProfile.fingerprint(bowl))
            return [bowl] + recipes
        }
        return ProcessInfo.processInfo.arguments.contains("-ui-testing-recipe-portions") ? [recipePortionFixture] + recipes : recipes
    }

    private static var recipePortionFixture: Recipe {
        var metadata = FoodSourceMetadata.userEntered(sourceName: "QA ingredient label")
        metadata.createdAt = today; metadata.sourceObservedAt = today
        let rice = FoodItem(id: "wave2-rice", name: "Rice", calories: 1_600, protein: 40, carbs: 300, fats: 16,
            servingSize: "400 g", servingWeight: 400, sourceMetadata: metadata, quantityValue: 400, servingUnit: "g")
        var recipe = Recipe(id: "demo-wave2-batch", name: "Four-serving rice batch", ingredients: ["400 g rice"],
            detailedIngredients: [rice], instructions: ["Cook the rice.", "Weigh the finished batch before portioning."],
            nutrition: Nutrition.total(for: [rice]), servings: 4, nutritionBasis: .wholeRecipe,
            nutritionOrigin: .ingredients, unresolvedIngredients: [], cookedWeightGrams: 800)
        recipe.revisionID = try? RecipePortionRules.revisionID(for: recipe)
        return recipe
    }

    static var receiptDemoItems: [PantryItem] {
        [
            PantryItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                name: "Greek Yogurt",
                quantity: 2,
                unit: "tubs",
                category: "Dairy",
                dateAdded: Date(timeIntervalSince1970: 100)
            ),
            PantryItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                name: "Baby Spinach",
                quantity: 1,
                unit: "bag",
                category: "Produce",
                dateAdded: Date(timeIntervalSince1970: 100)
            ),
            PantryItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                name: "Jasmine Rice",
                quantity: 1,
                unit: "bag",
                category: "Grains",
                dateAdded: Date(timeIntervalSince1970: 100)
            )
        ]
    }

    static var mealSuggestionDemo: MealSuggestion {
        MealSuggestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            title: "Lemon Herb Chicken Grain Bowl",
            calories: 615,
            mealName: "Lemon Herb Chicken Grain Bowl",
            protein: 52,
            carbs: 64,
            fats: 17,
            ingredients: [
                "6 oz lemon herb chicken breast",
                "1 cup cooked quinoa",
                "2 cups baby spinach",
                "1/2 cup cherry tomatoes",
                "2 tbsp tzatziki"
            ],
            instructions: """
            1. Season the chicken and cook until it reaches a safe internal temperature.
            2. Warm the quinoa and wilt the spinach.
            3. Add the tomatoes, slice the chicken, and finish with tzatziki.
            """
        )
    }

    static var mealSuggestionDemoPantry: [String] {
        ["Chicken breast", "Quinoa", "Baby spinach", "Greek yogurt"]
    }

    static var mealPrepDemoDays: [MealPlanDay] {
        let chicken = trustedFood(
            id: "meal-prep-chicken",
            name: "Ginger Chicken Rice Bowls",
            calories: 610,
            protein: 51,
            carbs: 72,
            fats: 14,
            fiber: 9,
            servingSize: "1 bowl"
        )
        let salmon = trustedFood(
            id: "meal-prep-salmon",
            name: "Lemon Salmon Quinoa",
            calories: 680,
            protein: 47,
            carbs: 61,
            fats: 27,
            fiber: 8,
            servingSize: "1 plate"
        )
        let oats = trustedFood(
            id: "meal-prep-oats",
            name: "Blueberry Protein Oats",
            calories: 460,
            protein: 34,
            carbs: 58,
            fats: 11,
            fiber: 10,
            servingSize: "1 jar"
        )

        return [
            MealPlanDay(
                id: "meal-prep-day-one",
                date: day(offset: 0),
                meals: [
                    PlannedMeal(
                        id: "meal-prep-chicken-one",
                        mealType: "Lunch",
                        foodItem: chicken,
                        ingredients: [
                            "680 g chicken breast",
                            "2 cup jasmine rice",
                            "3 cup broccoli",
                            "2 tbsp low-sodium soy sauce"
                        ],
                        instructions: """
                        1. Start the rice and divide it between containers.
                        2. Cook the chicken with ginger and soy sauce.
                        3. Steam the broccoli and portion everything together.
                        """
                    ),
                    PlannedMeal(
                        id: "meal-prep-oats-one",
                        mealType: "Breakfast",
                        foodItem: oats,
                        ingredients: [
                            "2 cup rolled oats",
                            "2 cup Greek yogurt",
                            "1 cup blueberries"
                        ],
                        instructions: "Mix the oats and yogurt, then chill overnight."
                    )
                ]
            ),
            MealPlanDay(
                id: "meal-prep-day-two",
                date: day(offset: 1),
                meals: [
                    PlannedMeal(
                        id: "meal-prep-salmon-one",
                        mealType: "Dinner",
                        foodItem: salmon,
                        ingredients: [
                            "450 g Atlantic salmon",
                            "2 cup cooked quinoa",
                            "2 tbsp olive oil",
                            "1 item lemon",
                            "2 cup spinach"
                        ],
                        instructions: """
                        1. Roast the salmon with lemon until safely cooked.
                        2. Warm the quinoa and wilt the spinach.
                        3. Portion the salmon over the quinoa and vegetables.
                        """
                    )
                ]
            )
        ]
    }

    static func reportDemoViewModel(dailyLogService: DailyLogService) -> ReportsViewModel {
        let viewModel = ReportsViewModel(dailyLogService: dailyLogService)
        let values: [(calories: Double, protein: Double, carbs: Double, fat: Double)] = [
            (1_940, 142, 210, 61),
            (2_080, 158, 224, 66),
            (2_160, 164, 238, 68),
            (1_990, 151, 214, 63),
            (2_120, 169, 226, 70),
            (2_240, 171, 249, 72),
            (2_050, 162, 218, 65)
        ]

        for (offset, value) in values.enumerated() {
            let daysAgo = values.count - 1 - offset
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            viewModel.calorieTrend.append(DateValuePoint(date: date, value: value.calories))
            viewModel.proteinTrend.append(DateValuePoint(date: date, value: value.protein))
            viewModel.carbTrend.append(DateValuePoint(date: date, value: value.carbs))
            viewModel.fatTrend.append(DateValuePoint(date: date, value: value.fat))
        }

        viewModel.micronutrientAverages = [
            MicroAverageDataPoint(
                name: "Calcium",
                unit: "mg",
                averageValue: 860,
                goalValue: 1_000,
                reportedDayCount: 6,
                totalDayCount: 7
            ),
            MicroAverageDataPoint(
                name: "Iron",
                unit: "mg",
                averageValue: 16.4,
                goalValue: 18,
                reportedDayCount: 7,
                totalDayCount: 7
            ),
            MicroAverageDataPoint(
                name: "Potassium",
                unit: "mg",
                averageValue: 3_180,
                goalValue: 3_500,
                reportedDayCount: 5,
                totalDayCount: 7
            ),
            MicroAverageDataPoint(
                name: "Sodium",
                unit: "mg",
                averageValue: 2_410,
                goalValue: 2_300,
                reportedDayCount: 7,
                totalDayCount: 7
            ),
            MicroAverageDataPoint(
                name: "Fiber",
                unit: "g",
                averageValue: 27.2,
                goalValue: 30,
                reportedDayCount: 7,
                totalDayCount: 7
            )
        ]
        return viewModel
    }

    static var insightsDemo: [UserInsight] {
        [
            UserInsight(
                title: "Protein Stayed Reliable",
                message: "You reached at least 90% of your protein target on six of seven logged days, including both training days.",
                category: .macroBalance,
                priority: 90,
                sourceData: "6 of 7 logged days at or above 90% of the current protein target."
            ),
            UserInsight(
                title: "Fiber Improved Late in the Week",
                message: "Fiber intake moved closer to target after beans, berries, and vegetables appeared more often in the diary.",
                category: .fiberIntake,
                priority: 72,
                sourceData: "Four-day average: 29 g. First three logged days: 21 g."
            ),
            UserInsight(
                title: "Recovery Meals Followed Training",
                message: "Both demanding sessions were followed by logged protein and carbohydrate within the recovery window.",
                category: .postWorkout,
                priority: 64,
                sourceData: "2 of 2 eligible training sessions had a matching recovery meal."
            ),
            UserInsight(
                title: "Hydration Was Less Consistent",
                message: "Water logging fell below your usual pattern on the weekend. This may reflect missing entries rather than lower intake.",
                category: .hydration,
                priority: 48,
                sourceData: "Five weekdays reported water; one of two weekend days reported water."
            )
        ]
    }

    static var ayceLiveSession: AYCESession {
        let nigiri = AYCECatalog.item(id: "sushi_salmon_nigiri") ?? AYCECatalog.all[0]
        let roll = AYCECatalog.item(id: "sushi_california_roll") ?? AYCECatalog.all[0]
        let scanned = AYCEPricingRules.reviewedCatalogItem(
            name: "Dragon Roll",
            unit: "roll",
            cuisine: .sushi,
            calories: 480,
            protein: 18,
            carbs: 62,
            fats: 18,
            restaurantPrice: 13.50,
            homeCost: 4.25
        ) ?? nigiri

        return AYCESession(
            id: "screenshot-ayce-live",
            cuisine: .sushi,
            buffetPrice: 34.99,
            startedAt: Date(timeIntervalSince1970: 1_780_000_000),
            entries: [
                AYCESessionEntry(id: "ayce-live-nigiri", item: nigiri, count: 4),
                AYCESessionEntry(id: "ayce-live-roll", item: roll, count: 1),
                AYCESessionEntry(id: "ayce-live-scan", item: scanned, count: 1)
            ],
            citySlug: "nyc"
        )
    }

    static var ayceSummarySession: AYCESession {
        var session = ayceLiveSession
        if let soup = AYCECatalog.item(id: "sushi_miso_soup") {
            session.entries.append(
                AYCESessionEntry(id: "ayce-summary-soup", item: soup, count: 2)
            )
        }
        return session
    }

    static var pantryRecipeDrafts: [Recipe] {
        recipeDemoRecipes.prefix(2).map { recipe in
            var draft = recipe
            draft.id = nil
            return draft
        }
    }

    static var runningDemoRuns: [Run] {
        let runs: [RunTemplate] = [
            RunTemplate(
                id: "demo-run-10k",
                daysAgo: 1,
                distance: 10_000,
                seconds: 2_948,
                heartRate: 157,
                source: .imported(appName: "Apple Watch")
            ),
            RunTemplate(
                id: "demo-run-5k",
                daysAgo: 3,
                distance: 5_000,
                seconds: 1_414,
                heartRate: 163,
                source: .recorded
            ),
            RunTemplate(
                id: "demo-run-easy",
                daysAgo: 5,
                distance: 8_050,
                seconds: 2_736,
                heartRate: 143,
                source: .imported(appName: "Garmin Connect")
            ),
            RunTemplate(
                id: "demo-run-long",
                daysAgo: 9,
                distance: 16_100,
                seconds: 5_640,
                heartRate: 149,
                source: .imported(appName: "Apple Watch")
            )
        ]

        let generated = runs.map { fixture in
            let startDate = calendar.date(byAdding: .day, value: -fixture.daysAgo, to: today) ?? today
            return Run(
                id: fixture.id,
                source: fixture.source,
                startDate: startDate.addingTimeInterval(7 * 60 * 60),
                endDate: startDate.addingTimeInterval((7 * 60 * 60) + fixture.seconds),
                distanceMeters: fixture.distance,
                movingSeconds: fixture.seconds,
                activeCalories: fixture.distance * 0.071,
                averageHeartRate: fixture.heartRate,
                splits: ManualRunEntryRules.splits(
                    distanceMeters: fixture.distance,
                    movingSeconds: fixture.seconds,
                    metric: false
                ),
                hasRoute: true
            )
        }
        if ScreenshotDemoMode.isEnabled,
           ProcessInfo.processInfo.arguments.contains("-ui-testing-run-pacing-fixtures") {
            let start = day(offset: -1).addingTimeInterval(9 * 60 * 60)
            let pacing = Run(id: "demo-run-pacing-tail", source: .recorded, startDate: start,
                             endDate: start.addingTimeInterval(720), distanceMeters: 2_500, movingSeconds: 720,
                             averageHeartRate: 150, splits: [RunSplit(index: 1, distanceMeters: 1_000, seconds: 360),
                                 RunSplit(index: 2, distanceMeters: 1_000, seconds: 300),
                                 RunSplit(index: 3, distanceMeters: 500, seconds: 60)], hasRoute: false,
                             pauseTimeline: RunPauseTimeline(completeness: .complete, intervals: []))
            let manual = Run(id: "demo-run-pacing-manual", source: .recorded, startDate: start.addingTimeInterval(-3_600),
                             endDate: start.addingTimeInterval(-3_600 + 780), distanceMeters: 3_000, movingSeconds: 780,
                             isIndoor: true, splits: ManualRunEntryRules.splits(distanceMeters: 3_000, movingSeconds: 780, metric: true), hasRoute: false)
            return [pacing, manual] + generated
        }
        guard ScreenshotDemoMode.isEnabled,
              ProcessInfo.processInfo.arguments.contains("-ui-testing-run-timing-fixtures") else { return generated }
        let start = day(offset: -1).addingTimeInterval(8 * 60 * 60)
        let timeline = RunPauseTimeline(completeness: .complete, intervals: [
            RunPauseInterval(startDate: start.addingTimeInterval(5 * 60), endDate: start.addingTimeInterval(8 * 60), origin: .explicitPause),
            RunPauseInterval(startDate: start.addingTimeInterval(15 * 60), endDate: start.addingTimeInterval(17 * 60), origin: .recoveryGap)
        ])
        let paused = Run(id: "demo-run-timing-known", source: .recorded, startDate: start,
                         endDate: start.addingTimeInterval(25 * 60), distanceMeters: 5_000, movingSeconds: 20 * 60,
                         averageHeartRate: 150, hasRoute: false, pauseTimeline: timeline)
        let legacyStart = day(offset: -2).addingTimeInterval(8 * 60 * 60)
        let legacy = Run(id: "demo-run-timing-legacy", source: .recorded, startDate: legacyStart,
                         endDate: legacyStart.addingTimeInterval(21 * 60), distanceMeters: 6_000, movingSeconds: 18 * 60,
                         averageHeartRate: 145, hasRoute: false)
        return [paused, legacy] + generated
    }

    static func prepareUserDefaults() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-run-draft") {
            try? RunRecordingDraftStore().remove(userID: userID)
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "cached_user_goals_\(userID)")
        defaults.removeObject(forKey: "chatHistory_\(userID)")
        if let goalCacheKey = AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: userID) {
            defaults.removeObject(forKey: goalCacheKey)
        }
        if let chatCacheKey = AccountScopedStorageKey.make(prefix: "chatHistory", userID: userID) {
            defaults.removeObject(forKey: chatCacheKey)
        }
        defaults.removeObject(forKey: "mealPlanCache")
        if let mealPlanCacheKey = AccountScopedStorageKey.make(prefix: "mealPlanCache", userID: userID) {
            defaults.removeObject(forKey: mealPlanCacheKey)
        }
        if let undoKey = AccountScopedStorageKey.make(prefix: "mealPlanUndo", userID: userID) {
            defaults.removeObject(forKey: undoKey)
        }
        defaults.set(programID, forKey: "activeWorkoutProgramID")
        defaults.set(false, forKey: "activeWorkoutProgramCleared")
        defaults.set(false, forKey: "useMetricBodyUnits")
        let usesCookingFixture = ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-cooking")
            || (ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-cooking-batch") || ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-inventory"))
        let groceryUnits: GroceryUnitSystem = usesCookingFixture ? .metric : .imperial
        defaults.set(groceryUnits.rawValue, forKey: "groceryUnitSystem")
        if let key = AccountScopedStorageKey.make(prefix: "groceryUnitSystem", userID: userID),
           ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-editor-drafts")
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-grocery-design") || defaults.object(forKey: key) == nil {
            defaults.set(groceryUnits.rawValue, forKey: key)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-editor-drafts"),
           let key = AccountScopedStorageKey.make(prefix: "meal-planner-workspace", userID: userID) {
            defaults.set("Plan", forKey: key)
        }
        defaults.set(false, forKey: "hasRequestedAppleHealthAccess")
        let showsFirstSession = ProcessInfo.processInfo.arguments.contains("-ui-testing-first-session")
        defaults.set(!showsFirstSession, forKey: "firstSessionChoiceCompleted")
        defaults.set(showsFirstSession, forKey: "firstSessionChoicePending")
        AIDataConsentStore.shared.revoke(for: userID)
    }

    static func configureRepositories(
        nutrition: MockNutritionRepository,
        workout: MockWorkoutRepository,
        settings: MockSettingsRepository
    ) {
        let logs = requestedScreen == "weekly-checkin-ready" ? weeklyReviewHistory() : nutritionHistory()
        nutrition.mockLogsByDay = logs
        nutrition.mockFetchDailyHistoryResult = .success(logs)
        nutrition.filtersHistoryByRequestedRange = true
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-day-review-persistence") {
            nutrition.persistsDailyLogUpdates = true
            nutrition.seedCommittedDailyLogs(userID: userID, logs: logs)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-day-review-save-failure") {
            nutrition.updateLogSuccess = false
        }
        nutrition.mockRecipes = recipeDemoRecipes
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-recipe-version-history") {
            var original = recipePortionFixture
            original.nutritionOrigin = nil
            original.revisionID = try? RecipePortionRules.revisionID(for: original)
            var edited = original; edited.servings = 8
            edited.revisionID = try? RecipePortionRules.revisionID(for: edited)
            let opening = original, updated = edited
            nutrition.mockRecipes = [opening] + recipeDemoRecipes.filter { $0.id != opening.id }
            // The actual checked-save path creates immutable version records. Repeated
            // fetches replay this fixed receipt without undoing a later reviewed restore.
            nutrition.fetchRecipesHandler = { owner in
                guard owner == "mock_user" else { throw RecipeRevisionError.accountChanged }
                _ = try await nutrition.saveRecipeRevision(userID: owner, expected: opening, updated: updated,
                    operationID: UUID(uuidString: "D9000000-0000-0000-0000-000000000037")!)
                return nutrition.mockRecipes
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-transfer-failure") {
            nutrition.diaryTransferError = CocoaError(.fileWriteUnknown)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-export-failure") {
            nutrition.mockFetchDailyHistoryResult = .failure(CocoaError(.fileReadUnknown))
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-grocery-save-failure") {
            nutrition.groceryMutationError = CocoaError(.fileWriteUnknown)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-receipt-partial"), let itemID = receiptDemoItems.dropFirst().first?.id {
            nutrition.pantryItemErrors[itemID] = CocoaError(.fileWriteUnknown)
        }

        let foods = discoveryFoods()
        nutrition.mockRecommendedFoods = Array(foods.prefix(5))
        nutrition.recentFoodsToReturn = Array(foods.prefix(6))
        nutrition.customFoodsToReturn = [
            trustedFood(
                id: "demo-custom-oats",
                name: "Power Protein Oats",
                calories: 445,
                protein: 34,
                carbs: 55,
                fats: 11,
                fiber: 9,
                servingSize: "1 bowl",
                sourceType: .custom,
                sourceName: "My Foods"
            ).markedUserConfirmed(sourceType: .custom),
            trustedFood(
                id: "demo-custom-shake",
                name: "Post-Workout Shake",
                calories: 310,
                protein: 42,
                carbs: 29,
                fats: 4,
                fiber: 4,
                servingSize: "20 fl oz",
                sourceType: .custom,
                sourceName: "My Foods"
            ).markedUserConfirmed(sourceType: .custom)
        ]

        nutrition.mockPantrySnapshotResult = .success([
            PantryItem(name: "Chicken breast", quantity: 2.5, unit: "lb", category: "Protein"),
            PantryItem(name: "Greek yogurt", quantity: 4, unit: "cups", category: "Dairy"),
            PantryItem(name: "Jasmine rice", quantity: 3, unit: "cups", category: "Grains"),
            PantryItem(name: "Spinach", quantity: 1, unit: "bag", category: "Produce"),
            PantryItem(name: "Blueberries", quantity: 2, unit: "cups", category: "Produce")
        ])

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-inventory") {
            let stockDate = ProcessInfo.processInfo.arguments.contains("-ui-testing-inventory-yesterday-batch") ? day(offset: -1) : today
            var raw = PantryItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!, name: "dry rice", quantity: 1_000, unit: "g", category: "Grains", dateAdded: stockDate)
            raw.quantityVerified = true; raw.preparation = "Raw"; raw.revisionID = "wave2-raw-initial"
            let legacy = PantryItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!, name: "Legacy pantry amount", quantity: 1, unit: "item", dateAdded: today)
            nutrition.mockPantryItemsByID = [raw.id: raw, legacy.id: legacy]
            nutrition.mockPantrySnapshotResult = .success([raw, legacy])
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-inventory-save-failure") {
            nutrition.inventoryFailureBeforeCommit = CocoaError(.fileWriteUnknown)
        }

        let plans = mealPlans()
        nutrition.mockMealPlansByDateString = Dictionary(
            uniqueKeysWithValues: plans.map { (dateString($0.date), $0) }
        )
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-independent-prep"),
           ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-editor-drafts") {
            var checkpoint = MealCookingCheckpoint()
            checkpoint.completedStepIndexes = [0, 1, 2]
            checkpoint.currentStepID = "repeated-sauce-step-0"
            let context = MealCookingCheckpointSession.contextID(days: plans,
                starting: MealPlanEditingRules.week(containing: today).first)
            do {
                try EditorDraftStore().save(checkpoint, userID: userID, scope: "meal-cooking-\(context)")
            } catch { AppLog.app.error("Could not seed synthetic prep checks: \(error.localizedDescription, privacy: .public)") }
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-stock-reservations") {
            let future = day(offset: 14)
            let food = FoodItem(id: "reservation-later-food", name: "Later rice cooking", calories: 400, protein: 25, carbs: 60, fats: 7)
            var meal = PlannedMeal(id: "reservation-later-meal", mealType: "Dinner", foodItem: food, ingredients: ["800 g dry rice"])
            meal.cookingBatch = MealCookingBatch(id: "reservation-later-batch", revisionID: "reservation-later-v1", sourceMealID: meal.id,
                cookingDate: future, name: "Later rice cooking", totalPortions: 1,
                ingredientsPerPortion: meal.plannedIngredients.map(MealCookingIngredient.init), instructions: nil,
                allocations: [.init(mealID: meal.id, date: future, portions: 1)])
            nutrition.mockMealPlansByDateString[dateString(future)] = MealPlanDay(id: dateString(future), date: future, meals: [meal])
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-meal-workspace") {
            let rice = FoodItem(id: "workspace-rice", name: "QA rice", calories: 400, protein: 25, carbs: 50, fats: 10, servingSize: "100 g", servingWeight: 100)
            let egg = FoodItem(id: "workspace-egg", name: "QA egg", calories: 100, protein: 8, carbs: 1, fats: 6, servingSize: "1 egg", servingWeight: 50)
            var composition = SavedMealComposition(id: "workspace-composition", name: "QA composed bowl", components: [rice, egg])
            composition.revisionID = "workspace-composition-initial"; composition.updatedAt = today
            var template = SavedMealWeekTemplate(id: "workspace-week", name: "QA saved week", days: plans)
            template.revisionID = "workspace-week-initial"; template.updatedAt = today
            nutrition.savedMealCompositionsByUserID[userID] = [composition]
            nutrition.savedMealWeekTemplatesByUserID[userID] = [template]
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-workspace-pending"),
               ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-editor-drafts") {
                var changedComposition = composition; changedComposition.name = "QA recovered bowl"; changedComposition.revisionID = "workspace-composition-pending"
                var changedTemplate = template; changedTemplate.name = "QA recovered week"; changedTemplate.revisionID = "workspace-week-pending"
                let compositionReview = PlanningDocumentCheckpoint(proposal: MealCompositionSaveProposal(userID: userID,
                    operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!, expected: composition, updated: changedComposition), submitted: true)
                let weekReview = PlanningDocumentCheckpoint(proposal: MealWeekTemplateSaveProposal(userID: userID,
                    operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!, expected: template, updated: changedTemplate), submitted: true)
                do {
                    try EditorDraftStore().save(compositionReview, userID: userID, scope: "meal-composition-library-save")
                    try EditorDraftStore().save(weekReview, userID: userID, scope: "meal-week-template-save")
                } catch { AppLog.app.error("Could not seed synthetic meal workspace review: \(error.localizedDescription, privacy: .public)") }
            }
        }
        let groceryPlanStart = Calendar.current.startOfDay(for: Date())
        nutrition.mockFetchGroceryListResult = [
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID(),
                name: "Blueberries",
                quantity: 2,
                unit: "pints",
                isCompleted: true,
                category: "Produce",
                source: "mealPlan",
                sourcePlanStart: groceryPlanStart
            ),
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102") ?? UUID(),
                name: "Avocados",
                quantity: 4,
                unit: "item",
                category: "Produce",
                source: "mealPlan",
                sourcePlanStart: groceryPlanStart
            ),
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000103") ?? UUID(),
                name: "Chicken breast",
                quantity: 3,
                unit: "lb",
                category: "Meat & Seafood",
                source: "mealPlan",
                sourcePlanStart: groceryPlanStart
            ),
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000104") ?? UUID(),
                name: "Salmon fillets",
                quantity: 4,
                unit: "fillets",
                category: "Meat & Seafood",
                source: "mealPlan",
                sourcePlanStart: groceryPlanStart
            ),
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000105") ?? UUID(),
                name: "Greek yogurt",
                quantity: 2,
                unit: "tubs",
                isCompleted: true,
                category: "Dairy & Eggs",
                source: "mealPlan",
                sourcePlanStart: groceryPlanStart
            ),
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000106") ?? UUID(),
                name: "Jasmine rice",
                quantity: 2,
                unit: "lb",
                category: "Carbohydrates",
                source: "mealPlan",
                sourcePlanStart: groceryPlanStart
            ),
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000107") ?? UUID(),
                name: "Extra virgin olive oil",
                quantity: 1,
                unit: "bottle",
                category: "Pantry & Oils",
                source: "mealPlan",
                sourcePlanStart: groceryPlanStart
            ),
            GroceryListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000108") ?? UUID(),
                name: "Electrolyte packets",
                quantity: 6,
                unit: "item",
                category: "Misc",
                source: "manual"
            )
        ]

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-grocery-design") {
            do {
                let plan = try groceryDesignPlan(items: nutrition.mockFetchGroceryListResult, starting: groceryPlanStart)
                nutrition.mockMealPlansByDateString = [dateString(plan.date): plan]
            } catch {
                assertionFailure("The synthetic grocery plan must retain its explicit measurements: \(error)")
            }
        }

        let program = strengthProgram()
        if requestedScreen == "week-rescue", ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-editor-drafts") {
            do {
                try EditorDraftStore().remove(userID: userID, scope: "week-rescue-review-\(programID)")
                try EditorDraftStore().remove(userID: userID, scope: "week-rescue-review-\(programID)-history")
            } catch { AppLog.app.error("Could not reset isolated rescue review: \(error.localizedDescription, privacy: .public)") }
        }
        var sessionLogs = workoutLogs(for: program)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-partially-timed-workouts"),
           let index = sessionLogs.firstIndex(where: { $0.date >= day(offset: -6) && $0.date <= Date() }) {
            sessionLogs[index].elapsedSeconds = 45 * 60
        }
        workout.onProgramsSnapshotListenerAdded = { [weak workout] _, update in
            update(.success([workout?.committedBlockPrograms.first(where: { $0.id == program.id }) ?? program]))
            if requestedScreen == "week-rescue" {
                workout?.afterProgramEditCommit = { accepted in update(.success(accepted.map { [$0] } ?? [])) }
            }
        }
        workout.onRoutinesSnapshotListenerAdded = { _, update in
            update(.success(program.routines))
        }
        workout.mockFetchSessionLogsResult = sessionLogs
        workout.mockFetchRecentSessionLogsResult = sessionLogs
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-comparison-workout"), let routine = program.routines.first {
            workout.mockFetchRecentSessionLogsResult = [WorkoutSessionLog(id: "comparison-completed", date: Date(), routineID: routine.id,
                completedExercises: routine.exercises.map { exercise in
                    CompletedExercise(exerciseName: exercise.name, exercise: exercise,
                        sets: exercise.sets.map { set in CompletedSet(reps: set.reps, weight: set.weight, effort: SetEffort(scale: .rpe, value: 7)) })
                })]
        }
        workout.mockFetchHistoryResult = sessionLogs
        workout.mockFetchSessionLogResult = sessionLogs.first.map(Result.success)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-workout-correction"), let summary = workoutSummaryLog {
            workout.mockFetchSessionLogResult = .success(summary)
            if let mirror = summary.generatedDiaryExercise {
                var days = nutrition.mockLogsByDay
                if let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: summary.date) }) {
                    if days[index].exercises == nil { days[index].exercises = [] }
                    days[index].exercises?.append(mirror)
                    nutrition.mockLogsByDay = days
                }
            }
        }
        let seedsLegacyDraft = ProcessInfo.processInfo.arguments.contains("-ui-testing-legacy-program-draft")
        workout.mockSaveProgramResult = seedsLegacyDraft || requestedScreen == "meal-experiments" ? nil : program
        if seedsLegacyDraft, let slot = program.currentProgressIndex,
           let routine = program.routine(forSlot: slot)?.deepCopy(),
           !routine.exercises.isEmpty, !routine.exercises[0].sets.isEmpty {
            routine.exercises[0].sets[0].reps = 8
            routine.exercises[0].sets[0].weight = 135
            routine.exercises[0].sets[0].isCompleted = true
            var draft = WorkoutSessionDraft(routine: routine)
            draft.programContext = nil
            draft.programLinkDecision = nil
            draft.elapsed = 120
            try? WorkoutDraftStore().save(draft, userID: userID)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-active-workout-link-fixture"),
           let slot = program.currentProgressIndex, let routine = program.routine(forSlot: slot)?.deepCopy(),
           let programID = program.id {
            var draft = WorkoutSessionDraft(routine: routine, programContext: .init(programID: programID, slotIndex: slot))
            draft.sessionID = "qa-activity-workout"
            draft.elapsed = 120
            try? WorkoutDraftStore().save(draft, userID: userID)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-active-run-link-fixture"), (try? RunRecordingDraftStore().load(userID: userID)) == nil {
            let now = Date()
            let sample = RunSession(metric: true, timeAccounting: .activeElapsed, id: "qa-activity-run")
            sample.start(at: now.addingTimeInterval(-37))
            sample.pause(at: now)
            if let snapshot = sample.snapshot(at: now) {
                try? RunRecordingDraftStore().save(.init(session: snapshot, updatedAt: now), userID: userID)
            }
        }

        settings.mockFetchUserGoalsResult = goalPayload()
        if ScreenshotDemoMode.isEnabled, ProcessInfo.processInfo.arguments.contains("-ui-testing-meal-constraints") {
            var payload = settings.mockFetchUserGoalsResult ?? [:]
            var goals = payload["goals"] as? [String: Any] ?? [:]
            goals["mealConstraintProfile"] = MealConstraintProfile(revisionID: "ui-test-constraints", hardExclusions: ["sesame"]).fields
            payload["goals"] = goals; settings.mockFetchUserGoalsResult = payload
        }
        settings.mockWeightHistory = requestedScreen == "weekly-checkin-ready" ? weeklyReviewWeights() : weightHistory()
        if requestedScreen == "weekly-checkin-ready", ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-editor-drafts") {
            for scope in ["weekly-target-review-v1", "weekly-target-history-v1", "adaptive-estimate-history-v1", "adaptive-evidence-review-v1"] {
                do { try EditorDraftStore().remove(userID: userID, scope: scope) } catch { AppLog.app.error("Could not reset synthetic weekly review: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    static func configureAchievementRepository(_ repository: MockAchievementRepository) {
        let fixture = achievementProgressFixture(
            definitions: AchievementRules.defaultDefinitions(),
            thresholds: AchievementRules.defaultLevelThresholds
        )

        repository.mockUserProfile = (points: fixture.points, level: fixture.level)
        repository.mockUserStatuses = fixture.statuses.values.sorted {
            $0.achievementID < $1.achievementID
        }
        repository.mockChallenges = fixture.challenges
        repository.mockActiveChallenges = fixture.challenges
    }

    static let gearAcceptanceShoeID = "qa-wave0-lifetime-shoe"

    static var unassignedGearRun: Run {
        gearAcceptanceRun(id: "qa-wave0-unassigned-run", daysAgo: 500, meters: 5_000)
    }

    static var recentGearRuns: [Run] {
        [gearAcceptanceRun(id: "qa-wave0-gear-recent", daysAgo: 1, meters: 5_000)]
    }

    static var lifetimeGearRuns: [Run] {
        recentGearRuns + [gearAcceptanceRun(id: "qa-wave0-gear-old", daysAgo: 500, meters: 45_000)]
    }

    private static func gearAcceptanceRun(id: String, daysAgo: Int, meters: Double) -> Run {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return Run(id: id, source: .recorded, startDate: start,
                   endDate: start.addingTimeInterval(1_800), distanceMeters: meters,
                   movingSeconds: 1_800, activeCalories: nil, averageHeartRate: nil,
                   splits: [], hasRoute: false)
    }

    private static func configureGearAcceptance() {
        guard ["run-detail-unassigned", "shoe-gear-lifetime"].contains(requestedScreen) else { return }
        let store = RunningShoeStore()
        if store.shoe(for: gearAcceptanceShoeID) == nil {
            store.addShoe(RunningShoe(id: gearAcceptanceShoeID, name: "Wave 0 trainer", brand: "QA",
                                     initialMeters: 0, maxMeters: 100_000))
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-gear-assignment") {
            store.tagRun(unassignedGearRun, withShoeID: nil)
        }
        if requestedScreen == "shoe-gear-lifetime" {
            for run in lifetimeGearRuns { store.tagRun(run, withShoeID: gearAcceptanceShoeID) }
        }
    }

    static func configureServices(
        goalSettings: GoalSettings,
        dailyLogService: DailyLogService,
        achievementService: AchievementService,
        healthKitViewModel: HealthKitViewModel,
        cycleTrackingService: CycleTrackingService,
        adaptiveGoalService: AdaptiveGoalService,
        appState: AppState
    ) {
        goalSettings.activateAccount(userID)
        dailyLogService.activateAccount(userID)
        applyGoals(to: goalSettings)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-hydration-preferences") {
            goalSettings.loadHydrationPreferences(userID: userID)
        }
        if requestedScreen == "home-water-tracking" {
            var preferences = HydrationPreferences()
            preferences.unit = .milliliters
            let bottle = WaterContainer(name: "Bottle", amount: 500, unit: .milliliters)
            preferences.containers = [bottle]
            preferences.preferredContainerID = bottle.id
            try? preferences.acceptTarget(nil)
            // The demo goal load also restores owner-scoped preferences asynchronously.
            // Seed that same mock-account source so the real Home projection stays stable.
            try? EditorDraftStore().save(preferences, userID: userID, scope: HydrationPreferences.scope)
            goalSettings.hydrationPreferences = preferences
        }
        configureGearAcceptance()
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-ai-outline"),
           (try? WorkoutAIProposalStore().load(userID: userID)) == nil {
            let movement = RoutineExercise(name: "Push-up", type: .strength, sets: [ExerciseSet(target: "8 reps")], targetSets: 1, targetReps: "8 reps")
            let routine = WorkoutRoutine(id: "qa-ai-outline-day", userID: userID, name: "Floor strength", dateCreated: today, exercises: [movement])
            let program = WorkoutProgram(id: "qa-ai-outline-proposal", userID: userID, name: "Original proposal", dateCreated: today,
                routines: [routine], startDate: today, daysOfWeek: [2], currentProgressIndex: 0)
            let request = WorkoutAIRequestSnapshot(goal: "Strength", daysPerWeek: 1, maximumSessionMinutes: 30,
                experience: "Beginner", equipmentClass: "Bodyweight Only", details: "Synthetic proposal; no provider request",
                gym: nil, movementMappings: [:], startDate: today, weekdays: [2])
            try? WorkoutAIProposalStore().save(WorkoutAIProposal(ownerID: userID, request: request, program: program))
        }
        goalSettings.weightHistory = weightHistory()
        dailyLogService.activelyViewedDate = today
        // A reviewed day must have the same meal and exercise IDs as its repository snapshot.
        let repository = DIContainer.shared.nutritionRepository as? MockNutritionRepository
        let currentLog = repository?.mockLogsByDay.first { calendar.isDate($0.date, inSameDayAs: today) }
        dailyLogService.publishCurrentDailyLog(currentLog ?? nutritionHistory()[0])
        applyAchievementProgress(to: achievementService)

        healthKitViewModel.isAuthorized = false
        healthKitViewModel.lastSyncedAt = Date().addingTimeInterval(-8 * 60)
        healthKitViewModel.todaySteps = 7_420
        healthKitViewModel.todayActiveEnergy = 486
        healthKitViewModel.weeklySteps = [8_340, 6_920, 9_810, 7_540, 11_260, 5_980, 7_420]
        healthKitViewModel.weeklyActiveEnergy = [510, 430, 615, 472, 688, 390, 486]
        healthKitViewModel.weeklyRestingHeartRate = [61, 60, 60, 59, 60, 62, 60]
        healthKitViewModel.weeklyHRV = [48, 52, 55, 51, 58, 46, 54]

        cycleTrackingService.cycleSettings = CycleSettings(typicalCycleLength: 28, typicalPeriodLength: 5)
        cycleTrackingService.cycleDay = cycleDemoDay
        cycleTrackingService.aiInsight = cycleDemoInsight

        if requestedScreen == "weekly-checkin-ready" {
            goalSettings.weightHistory = weeklyReviewWeights()
            if let settings = DIContainer.shared.settingsRepository as? MockSettingsRepository {
                settings.mockFetchUserGoalsResult = goalSettings.makeGoalEditorDraft().payload(updatedAt: Date())
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-weekly-save-failure") {
                    settings.saveUserGoalsError = URLError(.notConnectedToInternet)
                }
            }
            Task { @MainActor in
                await adaptiveGoalService.fetchAndCalculate(userID: userID, goalSettings: goalSettings,
                    dailyLogService: dailyLogService, requireServer: true)
            }
        }

        if requestedScreen == "adaptive-tdee-guardrail" {
            adaptiveGoalService.calculatedTDEE = nil
            adaptiveGoalService.last21DaysCalorieAverage = 6_420
            adaptiveGoalService.weightChangeRatePerDay = 0.02
            adaptiveGoalService.dataConfidence = .low
            adaptiveGoalService.recentWeighInCount = 18
            adaptiveGoalService.recentLogCount = 21
            adaptiveGoalService.recentValidLogCount = 21
            adaptiveGoalService.partialLogCount = 0
            adaptiveGoalService.isEstimateActionable = false
            adaptiveGoalService.tdeeGuardrailMessage = "The result falls outside MyFitPlate's supported TDEE range. Check for missing food entries or unusual weigh-ins before using it."
        }

        switch requestedScreen {
        case "maia": appState.selectedTab = 1
        case "train", "runs", "saved-programs", "program-builder", "routine-builder", "workout-player",
             "program-detail", "workout-history", "workout-summary":
            appState.selectedTab = 2
        case "meal-plan", "pantry-photo-recipes": appState.selectedTab = 3
        case "reports": appState.selectedTab = 4
        default: appState.selectedTab = 0
        }
        appState.isDarkModeEnabled = ProcessInfo.processInfo.arguments.contains("-screenshot-dark-mode")
        appState.isUserLoggedIn = true
    }

    private static func applyAchievementProgress(to service: AchievementService) {
        let fixture = achievementProgressFixture(
            definitions: service.achievementDefinitions,
            thresholds: service.levelThresholds
        )

        service.userStatuses = fixture.statuses
        service.unlockedAchievementsCount = fixture.statuses.values.filter(\.isUnlocked).count
        service.userTotalAchievementPoints = fixture.points
        service.userAchievementLevel = fixture.level
        service.userXp = fixture.points
        service.activeChallenges = fixture.challenges
        service.isLoading = false
    }

    private static func achievementProgressFixture(
        definitions: [AchievementDefinition],
        thresholds: [Int]
    ) -> AchievementProgressFixture {
        var statuses = AchievementRules.mergedStatuses(
            definitions: definitions,
            fetchedStatuses: []
        )

        func updateStatus(
            _ id: String,
            progress: Double,
            unlockedDaysAgo: Int? = nil
        ) {
            guard var status = statuses[id] else { return }
            status.currentProgress = progress
            status.lastProgressUpdate = calendar.date(byAdding: .day, value: -1, to: today)
            if let unlockedDaysAgo {
                status.isUnlocked = true
                status.unlockedDate = calendar.date(byAdding: .day, value: -unlockedDaysAgo, to: today)
            }
            statuses[id] = status
        }

        updateStatus("first_workout", progress: 1, unlockedDaysAgo: 2)
        updateStatus("on_the_weigh", progress: 1, unlockedDaysAgo: 5)
        updateStatus("goal_setter", progress: 1, unlockedDaysAgo: 9)
        updateStatus("first_log", progress: 1, unlockedDaysAgo: 12)
        updateStatus("workout_streak_7", progress: 4)
        updateStatus("apprentice_chef", progress: 6)
        updateStatus("log_streak_7", progress: 5)

        var challenges = AchievementRules.potentialWeeklyChallenges(currentDate: today)
            .filter { ["Workout Warrior", "Protein Power", "Dedicated Dieter"].contains($0.title) }
        for index in challenges.indices {
            challenges[index].id = "demo-challenge-\(index)"
            challenges[index].expiresAt = calendar.date(byAdding: .day, value: 3, to: today) ?? today
            switch challenges[index].title {
            case "Workout Warrior":
                challenges[index].progress = 2
            case "Protein Power":
                challenges[index].progress = 4
                challenges[index].isCompleted = true
            case "Dedicated Dieter":
                challenges[index].progress = 5
            default:
                break
            }
        }

        let points = 780
        return AchievementProgressFixture(
            statuses: statuses,
            points: points,
            level: AchievementRules.level(for: points, thresholds: thresholds),
            challenges: challenges
        )
    }

    private static func applyGoals(to goals: GoalSettings) {
        goals.calorieGoalMethod = .custom
        goals.calories = 2_100
        goals.proteinPercentage = 30.4762
        goals.carbsPercentage = 43.8095
        goals.fatsPercentage = 25.7143
        goals.protein = 160
        goals.carbs = 230
        goals.fats = 60
        goals.weight = 181.2
        goals.height = 180.3
        goals.age = 34
        goals.gender = "Male"
        goals.activityLevel = 1.375
        goals.goal = "Lose Weight"
        goals.targetWeight = 175
        goals.waterGoal = 96
        goals.trainingIntent = "Build Strength"
        goals.reminderStyle = "Gentle"
        goals.maiaTone = "Balanced"
        goals.cookingStyle = "Macro-Focused Prep"
        goals.suggestionProteins = ["Chicken", "Salmon", "Greek Yogurt"]
        goals.suggestionCuisines = ["Mediterranean", "Mexican", "Asian"]
        goals.suggestionCarbs = ["Rice", "Oats", "Potatoes"]
        goals.suggestionVeggies = ["Spinach", "Broccoli", "Bell Peppers"]
    }

    private static func goalPayload() -> [String: Any] {
        [
            "weight": 181.2,
            "height": 180.3,
            "age": 34,
            "gender": "Male",
            "isFirstLogin": false,
            "calorieGoalMethod": CalorieGoalMethod.custom.rawValue,
            "activityLevel": 1.375,
            "goal": "Lose Weight",
            "goals": [
                "calories": 2_100.0,
                "protein": 160.0,
                "carbs": 230.0,
                "fats": 60.0,
                "proteinPercentage": 30.4762,
                "carbsPercentage": 43.8095,
                "fatsPercentage": 25.7143,
                "activityLevel": 1.375,
                "goal": "Lose Weight",
                "targetWeight": 175.0,
                "waterGoal": 96.0,
                "trainingIntent": "Build Strength",
                "reminderStyle": "Gentle",
                "maiaTone": "Balanced",
                "cookingStyle": "Macro-Focused Prep",
                "suggestionProteins": ["Chicken", "Salmon", "Greek Yogurt"],
                "suggestionCuisines": ["Mediterranean", "Mexican", "Asian"],
                "suggestionCarbs": ["Rice", "Oats", "Potatoes"],
                "suggestionVeggies": ["Spinach", "Broccoli", "Bell Peppers"]
            ]
        ]
    }

    private static func weeklyReviewWeights() -> [(id: String, date: Date, weight: Double)] {
        (0..<42).map { index in ("qa-weekly-weight-\(index)", day(offset: -index), 180 + Double(index) * 0.05) }
    }

    private static func weeklyReviewHistory() -> [DailyLog] {
        (0..<42).map { index in
            let date = day(offset: -index)
            let food = FoodItem(id: "qa-weekly-food-\(index)", name: "Complete QA food day", calories: 2_400,
                                protein: 180, carbs: 300, fats: 53)
            var log = DailyLog(id: dateString(date), date: date, meals: [Meal(name: "Meals", foodItems: [food])], exercises: [])
            log.nutritionDayStatus = .complete
            return log
        }
    }

    private static func nutritionHistory() -> [DailyLog] {
        let todayFoods = [
            trustedFood(id: "today-parfait", name: "Greek Yogurt Parfait", calories: 410, protein: 36, carbs: 55, fats: 10, fiber: 8, servingSize: "1 bowl"),
            trustedFood(id: "today-bowl", name: "Grilled Chicken Power Bowl", calories: 620, protein: 55, carbs: 74, fats: 17, fiber: 10, servingSize: "1 bowl"),
            trustedFood(id: "today-snack", name: "Apple & Almond Butter", calories: 280, protein: 7, carbs: 36, fats: 14, fiber: 7, servingSize: "1 plate")
        ]
        let todayLog = DailyLog(
            id: dateString(today),
            date: today,
            meals: [
                Meal(name: "Breakfast", foodItems: [todayFoods[0]]),
                Meal(name: "Lunch", foodItems: [todayFoods[1]]),
                Meal(name: "Snack", foodItems: [todayFoods[2]])
            ],
            waterTracker: WaterTracker(totalOunces: 72, goalOunces: 96, date: today),
            exercises: [LoggedExercise(name: "Upper Body Strength", durationMinutes: 52, caloriesBurned: 320, date: today.addingTimeInterval(12 * 60 * 60), source: "routine")]
        )

        let yesterday = day(offset: -1)
        let yesterdayLog = DailyLog(
            id: dateString(yesterday),
            date: yesterday,
            meals: [
                Meal(name: "Breakfast", foodItems: [trustedFood(id: "yesterday-oats", name: "Protein Overnight Oats", calories: 430, protein: 30, carbs: 58, fats: 11, fiber: 10, servingSize: "1 jar")]),
                Meal(name: "Lunch", foodItems: [trustedFood(id: "yesterday-wrap", name: "Turkey Avocado Wrap", calories: 520, protein: 42, carbs: 52, fats: 19, fiber: 8, servingSize: "1 wrap")]),
                Meal(name: "Dinner", foodItems: [trustedFood(id: "yesterday-salmon", name: "Salmon Rice Bowl", calories: 690, protein: 48, carbs: 72, fats: 28, fiber: 7, servingSize: "1 bowl")]),
                Meal(name: "Snack", foodItems: [trustedFood(id: "yesterday-cottage", name: "Cottage Cheese & Pineapple", calories: 220, protein: 24, carbs: 26, fats: 4, fiber: 2, servingSize: "1 bowl")])
            ],
            waterTracker: WaterTracker(totalOunces: 94, goalOunces: 96, date: yesterday),
            exercises: [LoggedExercise(name: "Lower Body Strength", durationMinutes: 58, caloriesBurned: 365, date: yesterday.addingTimeInterval(18 * 60 * 60), source: "routine")]
        )

        let templates = [
            HistoryTemplate(title: "Mediterranean Day", calories: 2_025, protein: 154, carbs: 224, fats: 71, fiber: 31, workoutName: nil),
            HistoryTemplate(title: "Taco Bowl Day", calories: 1_980, protein: 149, carbs: 218, fats: 70, fiber: 29, workoutName: "Easy Run"),
            HistoryTemplate(title: "High-Protein Prep", calories: 2_110, protein: 163, carbs: 228, fats: 76, fiber: 34, workoutName: "Upper Body Strength"),
            HistoryTemplate(title: "Sushi & Stir-Fry", calories: 2_060, protein: 151, carbs: 236, fats: 69, fiber: 28, workoutName: nil),
            HistoryTemplate(title: "Comfort Food Balance", calories: 1_945, protein: 146, carbs: 211, fats: 71, fiber: 30, workoutName: "Lower Body Strength")
        ]

        let olderLogs = templates.enumerated().map { index, template in
            historyLog(
                offset: -(index + 2),
                title: template.title,
                calories: template.calories,
                protein: template.protein,
                carbs: template.carbs,
                fats: template.fats,
                fiber: template.fiber,
                workoutName: template.workoutName
            )
        }
        // Persisted diary fixtures must keep meal placement and source snapshots
        // through a process restart, just like canonical repository records.
        return ([todayLog, yesterdayLog] + olderLogs).map { value in
            var log = value
            let digits = dateString(log.date).filter(\.isNumber)
            let numericDay = Int(digits) ?? 0
            for index in log.meals.indices {
                let suffix = String(format: "%010d%02d", numericDay, index)
                log.meals[index].id = UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
                for foodIndex in log.meals[index].foodItems.indices {
                    log.meals[index].foodItems[foodIndex].sourceMetadata?.createdAt = calendar.startOfDay(for: log.date)
                    log.meals[index].foodItems[foodIndex].sourceMetadata?.sourceObservedAt = calendar.startOfDay(for: log.date)
                }
            }
            return log
        }
    }

    private static func historyLog(
        offset: Int,
        title: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        fiber: Double,
        workoutName: String?
    ) -> DailyLog {
        let date = day(offset: offset)
        let calorieShares = [0.28, 0.34, 0.38]
        let names = ["\(title) Breakfast", "\(title) Lunch", "\(title) Dinner"]
        let mealNames = ["Breakfast", "Lunch", "Dinner"]
        let foods = calorieShares.enumerated().map { index, share in
            trustedFood(
                id: "demo-\(-offset)-\(index)",
                name: names[index],
                calories: calories * share,
                protein: protein * share,
                carbs: carbs * share,
                fats: fats * share,
                fiber: fiber * share,
                servingSize: "1 serving"
            )
        }
        let exercise = workoutName.map {
            [LoggedExercise(name: $0, durationMinutes: 45, caloriesBurned: 290, date: date.addingTimeInterval(18 * 60 * 60), source: $0.contains("Run") ? "HealthKit" : "routine")]
        }
        return DailyLog(
            id: dateString(date),
            date: date,
            meals: zip(mealNames, foods).map { Meal(name: $0.0, foodItems: [$0.1]) },
            waterTracker: WaterTracker(totalOunces: 80 + Double((-offset * 3) % 16), goalOunces: 96, date: date),
            exercises: exercise
        )
    }

    private static func discoveryFoods() -> [FoodItem] {
        [
            trustedFood(id: "search-chicken", name: "Chicken Breast, Grilled", calories: 187, protein: 35, carbs: 0, fats: 4, fiber: 0, servingSize: "4 oz", servingWeight: 113, sourceType: .usda, sourceName: "USDA FoodData Central"),
            trustedFood(id: "search-yogurt", name: "Greek Yogurt, Nonfat", calories: 130, protein: 23, carbs: 9, fats: 0, fiber: 0, servingSize: "1 cup", sourceType: .usda, sourceName: "USDA FoodData Central"),
            trustedFood(id: "search-rice", name: "Jasmine Rice, Cooked", calories: 205, protein: 4, carbs: 45, fats: 0.4, fiber: 1, servingSize: "1 cup", sourceType: .fatSecret, sourceName: "FatSecret"),
            trustedFood(id: "search-salmon", name: "Atlantic Salmon, Baked", calories: 233, protein: 25, carbs: 0, fats: 14, fiber: 0, servingSize: "4 oz", sourceType: .usda, sourceName: "USDA FoodData Central"),
            trustedFood(id: "search-banana", name: "Banana", calories: 105, protein: 1.3, carbs: 27, fats: 0.4, fiber: 3.1, servingSize: "1 medium", sourceType: .usda, sourceName: "USDA FoodData Central"),
            trustedFood(id: "search-tortilla", name: "Whole Wheat Tortilla", calories: 130, protein: 4, carbs: 22, fats: 3.5, fiber: 4, servingSize: "1 tortilla", sourceType: .openFoodFacts, sourceName: "Open Food Facts")
        ]
    }

    private static func trustedFood(
        id: String,
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        fiber: Double,
        servingSize: String,
        servingWeight: Double = 250,
        sourceType: FoodSourceType = .usda,
        sourceName: String = "USDA FoodData Central"
    ) -> FoodItem {
        FoodItem(
            id: id,
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            saturatedFat: fats * 0.28,
            polyunsaturatedFat: fats * 0.20,
            monounsaturatedFat: fats * 0.42,
            fiber: fiber,
            servingSize: servingSize,
            servingWeight: servingWeight,
            calcium: calories * 0.32,
            iron: calories * 0.006,
            potassium: calories * 1.8,
            sodium: calories * 0.72,
            vitaminA: calories * 0.5,
            vitaminC: calories * 0.04,
            magnesium: calories * 0.18
        )
        .withDatabaseSource(sourceType, sourceName: sourceName, sourceID: id)
        .withCrossVerification(sourceType == .usda ? ["FatSecret"] : ["USDA FoodData Central"])
    }

    /// Keep the grocery-only UI fixture coherent with the actual plan refresh path.
    /// Explicit ingredient snapshots preserve package units instead of guessing their mass.
    static func groceryDesignPlan(items: [GroceryListItem], starting date: Date) throws -> MealPlanDay {
        let ingredients = items.filter { $0.source == "mealPlan" }.map { item in
            FoodItem(id: "grocery-design-\(item.id.uuidString)", name: item.name, calories: 0,
                servingSize: "\(item.quantity.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))) \(item.unit)",
                servingWeight: 0, quantityValue: item.quantity, servingUnit: item.unit)
        }
        let recipe = Recipe(id: "grocery-design-recipe", name: "QA shopping requirements",
            ingredients: ingredients.map { "\($0.servingSize) \($0.name)" }, detailedIngredients: ingredients,
            instructions: [], nutrition: .zero, servings: 1, nutritionBasis: .wholeRecipe,
            nutritionOrigin: .ingredients, unresolvedIngredients: [], ingredientBasis: .wholeRecipe)
        let selection = RecipePortionRules.defaultSelection(for: recipe)
        let meal = PlannedMeal(id: "grocery-design-meal", mealType: "Dinner", recipeID: recipe.id,
            foodItem: try RecipePortionRules.foodItem(for: recipe, selection: selection), ingredients: recipe.ingredients)
        return MealPlanDay(id: dateString(date), date: date, meals: [meal])
    }

    private static func mealPlans() -> [MealPlanDay] {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-planner-blank") { return [] }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-independent-prep") {
            let dates = MealPlanEditingRules.week(containing: today)
            return dates.prefix(2).enumerated().map { offset, date in
                let food = FoodItem(id: "repeated-rice-food", name: "QA repeated rice", calories: 400, protein: 25, carbs: 60, fats: 7)
                var meals = [PlannedMeal(id: "repeated-rice-\(offset)", mealType: "Dinner", foodItem: food,
                    ingredients: ["100 g rice"], instructions: "Rinse rice\nCook rice")]
                if offset == 1 {
                    meals.append(.init(id: "repeated-sauce", mealType: "Sauce", ingredients: ["10 g oil"], instructions: "Mix sauce"))
                }
                return MealPlanDay(id: dateString(date), date: date, meals: meals)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-cooking")
            || (ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-cooking-batch") || ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-inventory")) {
            // The later-day acceptance journey uses yesterday's real plan date so
            // today's leftovers can be eaten without bypassing future-log checks.
            let cookingDate = ProcessInfo.processInfo.arguments.contains("-ui-testing-inventory-yesterday-batch") ? day(offset: -1) : today
            let food = trustedFood(id: "wave2-cooking-rice", name: "Four-portion rice batch",
                calories: 400, protein: 25, carbs: 60, fats: 7, fiber: 3,
                servingSize: "1 portion", sourceType: .mealPlan, sourceName: "Synthetic cooking fixture")
            var dinner = PlannedMeal(id: "wave2-cooking-dinner", mealType: "Dinner", foodItem: food,
                ingredients: ["100 g dry rice"],
                instructions: ProcessInfo.processInfo.arguments.contains("-ui-testing-instruction-times")
                    ? "1. Simmer for 12 minutes.\n2. Rest for 10–15 minutes.\n3. Divide into portions."
                    : "1. Rinse the rice.\n2. Cook the rice with water.\n3. Divide into portions.")
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-cooking-batch") || ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-inventory"),
               var batchMeal = try? MealPlanCookingRules.configuring(dinner, date: cookingDate, cookingPortions: 4) {
                batchMeal.cookingBatch?.id = "wave2-cooking-batch"
                batchMeal.cookingBatch?.revisionID = "wave2-cooking-batch-initial"
                dinner = batchMeal
            }
            return [
                MealPlanDay(id: dateString(cookingDate), date: cookingDate, meals: [dinner]),
                MealPlanDay(id: dateString(calendar.date(byAdding: .day, value: 1, to: cookingDate)!),
                            date: calendar.date(byAdding: .day, value: 1, to: cookingDate)!, meals: [])
            ]
        }
        let mealNames: [[String]] = [
            ["Berry Protein Oats", "Chicken Pesto Grain Bowl", "Miso Salmon with Rice"],
            ["Veggie Egg Scramble", "Turkey Avocado Wrap", "Beef & Broccoli Stir-Fry"],
            ["Greek Yogurt Crunch Bowl", "Mediterranean Chicken Pita", "Shrimp Taco Bowl"],
            ["Banana Protein Pancakes", "Sesame Tuna Rice Bowl", "Herb Chicken & Potatoes"],
            ["Overnight Oats", "Salmon Harvest Salad", "Turkey Meatballs & Pasta"],
            ["Breakfast Burrito Bowl", "Chicken Caesar Wrap", "Teriyaki Beef Bowl"],
            ["Cottage Cheese Toast", "Greek Chicken Bowl", "Lemon Garlic Salmon"]
        ]

        return mealNames.enumerated().map { dayIndex, names in
            let date = day(offset: dayIndex)
            let calories = [475.0, 610.0, 720.0]
            let protein = [35.0, 48.0, 52.0]
            return MealPlanDay(
                id: dateString(date),
                date: date,
                meals: names.enumerated().map { mealIndex, name in
                    let item = trustedFood(
                        id: "plan-\(dayIndex)-\(mealIndex)",
                        name: name,
                        calories: calories[mealIndex],
                        protein: protein[mealIndex],
                        carbs: [55, 68, 76][mealIndex],
                        fats: [14, 19, 25][mealIndex],
                        fiber: [8, 10, 9][mealIndex],
                        servingSize: "1 serving",
                        sourceType: .mealPlan,
                        sourceName: "MyFitPlate Meal Plan"
                    )
                    return PlannedMeal(
                        id: "planned-\(dayIndex)-\(mealIndex)",
                        mealType: ["Breakfast", "Lunch", "Dinner"][mealIndex],
                        foodItem: item,
                        ingredients: ["Lean protein", "Whole grain", "Seasonal produce"],
                        instructions: "Prepare, season to taste, and serve warm."
                    )
                }
            )
        }
    }

    private static func strengthProgram() -> WorkoutProgram {
        if ["week-rescue", "meal-experiments"].contains(requestedScreen) {
            let routine = WorkoutRoutine(id: "adaptive-upper", userID: userID, name: "Upper body", dateCreated: today,
                exercises: ["Dumbbell press", "Dumbbell row", "Lateral raise", "Curl"].map { name in
                    RoutineExercise(id: "adaptive-" + name, name: name,
                        sets: (0..<3).map { index in ExerciseSet(id: "adaptive-\(name)-\(index)", target: "8", reps: 8, weight: 30) }, targetSets: 3)
                })
            return WorkoutProgram(id: programID, userID: userID, name: "Your strength plan", dateCreated: today,
                                  routines: [routine], startDate: today, daysOfWeek: [calendar.component(.weekday, from: today)], currentProgressIndex: 0)
        }

        let completedPHUL = ProcessInfo.processInfo.arguments.contains("-ui-testing-completed-phul")
        let waveTwoPHUL = ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-phul") || completedPHUL
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-migration-review")
        let usesPHUL = ProcessInfo.processInfo.arguments.contains("-ui-testing-legacy-program-draft") || waveTwoPHUL
        var program = WorkoutRules.generatePreBuiltPrograms().first {
            $0.id == (usesPHUL ? "prebuilt_phul" : "prebuilt_dumbbell_hypertrophy_4_day")
        } ?? WorkoutProgram(userID: userID, name: "Dumbbell Strength & Hypertrophy")
        program.id = programID
        program.userID = userID
        program.name = usesPHUL ? "PHUL Power Hypertrophy Upper Lower" : "Dumbbell Strength & Hypertrophy"
        program.dateCreated = day(offset: -21)
        program.startDate = day(offset: -14)
        program.currentProgressIndex = 5
        program.routines.forEach { $0.userID = userID }
        if waveTwoPHUL {
            // A separate disposable fixture exercises the finished-block navigation
            // without completing or changing any real workout or active program.
            program.currentProgressIndex = completedPHUL ? program.totalSlots : 39
            program.skippedIndices = [2, 9, 20]
            for (routineIndex, routine) in program.routines.enumerated() {
                routine.dateCreated = program.dateCreated
                routine.exercises = routine.exercises.enumerated().map { exerciseIndex, original in
                    var exercise = original
                    exercise.id = "wave2-exercise-\(routineIndex)-\(exerciseIndex)"
                    exercise.sets = exercise.sets.enumerated().map { setIndex, originalSet in
                        var set = originalSet
                        set.id = "wave2-set-\(routineIndex)-\(exerciseIndex)-\(setIndex)"
                        return set
                    }
                    return exercise
                }
            }
        }
        return program
    }

    static var questionFood: FoodItem {
        var food = FoodItem(id: "question-rice", name: "Rice bowl", calories: 600, protein: 30, carbs: 80, fats: 18,
                 servingSize: "300 g", servingWeight: 300).withAIEstimateSource(.aiImage, sourceName: "Maia Vision fixture")
        food.sourceMetadata?.portionAnchors = [.init(unit: .package, gramsPerUnit: 450,
            sourceID: "qa-package-label", sourceName: "QA package label")]
        return food
    }

    static var questionReview: MealPhotoReviewContext {
        MealPhotoReviewContext(overallConfidence: 0.7, analysisNotes: "The portion is estimated from the photo.",
            clarificationQuestions: [], groundedItemCount: 0,
            itemReviews: ["question-rice": MealPhotoItemReview(itemID: "question-rice", confidence: 0.7,
                portionLowGrams: 200, portionHighGrams: 450, requiresConfirmation: true,
                clarificationQuestion: nil, hiddenIngredientRisks: ["Cooking oil"], referenceSourceName: nil)])
    }

    static var workoutBuilderProgram: WorkoutProgram {
        strengthProgram()
    }

    static var routineBuilderRoutine: WorkoutRoutine {
        let routine = strengthProgram().routines.first ?? WorkoutRoutine(
            userID: userID,
            name: "Upper Strength",
            dateCreated: today
        )
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-wave2-interval"),
           let copy = routine.deepCopy() {
            // A focused mixed-workout fixture avoids scrolling through unrelated
            // catalog work while retaining real set controls and draft recovery.
            copy.exercises = Array(copy.exercises.prefix(1))
            return copy
        }
        return routine
    }

    static var programDetailProgram: WorkoutProgram {
        strengthProgram()
    }

    static var workoutHistoryLogs: [WorkoutSessionLog] {
        workoutLogs(for: strengthProgram()).sorted { $0.date > $1.date }
    }

    static var workoutSummaryLog: WorkoutSessionLog? {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-workout-correction") {
            return workoutCorrectionFixture
        }
        return workoutHistoryLogs.first
    }

    private static let workoutCorrectionFixture: WorkoutSessionLog? = {
        guard var log = workoutHistoryLogs.first else { return nil }
        log.id = "qa-wave0-workout-correction"
        log.elapsedSeconds = 600
        log.projectionBodyWeightPounds = 180
        log.generatedDiaryExercise = WorkoutDiaryProjectionRules.make(log: log, name: "Fixture strength session", elapsed: 600, weightPounds: 180)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-workout-correction") {
            let store = WorkoutCorrectionStore()
            while var pending = try? store.pending(sessionID: "qa-wave0-workout-correction", userID: userID) {
                pending.abandonedAt = Date()
                do { try store.save(pending) } catch { break }
            }
        }
        return log
    }()

    private static var retainedFastingFixture: FastingManager?

    static func fastingFixtureManager() -> FastingManager {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-fasting-no-projection") else { return .shared }
        if let retainedFastingFixture { return retainedFastingFixture }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyFitPlate/qa-fixtures/fasting")
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-fasting") {
            try? FileManager.default.removeItem(at: directory)
        }
        let unavailable = ProcessInfo.processInfo.arguments.contains("-ui-testing-fasting-storage-failure")
        let manager = FastingManager(store: FastingSessionStore(directory: unavailable ? nil : directory), projectsActivities: false)
        retainedFastingFixture = manager
        return manager
    }

    static func barcodeFixtureBatch() -> RapidBarcodeBatchSession {
        let batch = RapidBarcodeBatchSession(userID: userID, date: day(offset: -1), mealName: "Dinner")
        if batch.checkpoint.entries.isEmpty {
            for code in ["000000000001", "000000000002", "000000000003", "000000000001"] { _ = batch.append(code) }
        }
        return batch
    }

    static func barcodeFixtureLookup(_ code: String) async -> FoodItem? {
        guard code != "000000000003" else { return nil }
        return FoodItem(id: "fixture-\(code)", name: code.hasSuffix("1") ? "Fixture oats" : "Fixture yogurt",
            calories: 180, protein: 15, carbs: 21, fats: 4, servingSize: "1 portion", servingWeight: 150)
    }

    static var muscleRecoveryEstimates: [MuscleRecoveryEstimate] {
        let asOf = today.addingTimeInterval(20 * 60 * 60)
        let fixtures: [(RecoveryMuscleGroup, Double?, Int?)] = [
            (.chest, 12, 12),
            (.back, 35, 10),
            (.legs, 50, 8),
            (.arms, 70, 6),
            (.core, nil, nil),
            (.shoulders, 28, 8)
        ]

        return fixtures.map { group, hoursAgo, sets in
            MuscleRecoveryRules.estimate(
                group: group,
                lastTrained: hoursAgo.map { asOf.addingTimeInterval(-$0 * 3_600) },
                sets: sets,
                sleepScore: 84,
                asOf: asOf
            )
        }
    }

    private static func workoutLogs(for program: WorkoutProgram) -> [WorkoutSessionLog] {
        guard !program.routines.isEmpty else { return [] }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-long-term-trend") {
            return program.routines.flatMap { routine in
                [1, 8, 15, 22].map { days in
                    WorkoutSessionLog(id: "trend-\(routine.id)-\(days)", date: day(offset: -days), routineID: routine.id,
                        completedExercises: routine.exercises.map { exercise in
                            CompletedExercise(exerciseName: exercise.name, exercise: exercise,
                                sets: exercise.sets.map { set in
                                    CompletedSet(reps: ProgressionRules.repRange(set.target ?? exercise.targetReps)?.lowerBound ?? 8,
                                                 weight: 100, setType: set.resolvedSetType, effort: SetEffort(scale: .rpe, value: 9))
                                })
                        })
                }
            }
        }

        var logs: [WorkoutSessionLog] = []
        logs.reserveCapacity(5)

        for index in 0..<5 {
            let routine = program.routines[index % program.routines.count]
            let date = day(offset: -12 + index * 2).addingTimeInterval(18 * 60 * 60)

            var completedExercises: [CompletedExercise] = []
            completedExercises.reserveCapacity(routine.exercises.count)

            for exercise in routine.exercises {
                let setCount = max(3, exercise.targetSets)
                var completedSets: [CompletedSet] = []
                completedSets.reserveCapacity(setCount)

                for setIndex in 0..<setCount {
                    completedSets.append(
                        CompletedSet(
                            reps: max(6, 12 - setIndex),
                            weight: 30 + Double(index * 2 + setIndex * 5),
                            setType: .normal,
                            effort: SetEffort(scale: .rpe, value: 7.5 + Double(setIndex) * 0.5)
                        )
                    )
                }

                completedExercises.append(
                    CompletedExercise(
                        exerciseName: exercise.name,
                        exercise: exercise,
                        sets: completedSets
                    )
                )
            }

            logs.append(
                WorkoutSessionLog(
                    id: "demo-session-\(index)",
                    date: date,
                    routineID: routine.id,
                    completedExercises: completedExercises
                )
            )
        }

        return logs
    }

    private static func weightHistory() -> [(id: String, date: Date, weight: Double)] {
        (0..<30).map { index in
            let progress = Double(index) / 29
            let oscillation = sin(Double(index) * 0.85) * 0.22
            return (
                id: "demo-weight-\(index)",
                date: day(offset: index - 29),
                weight: 184.2 - 3.0 * progress + oscillation
            )
        }
    }

    private static func day(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
#endif
