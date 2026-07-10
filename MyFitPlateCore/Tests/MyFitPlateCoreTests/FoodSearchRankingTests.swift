import XCTest
@testable import MyFitPlateCore

final class FoodSearchRankingTests: XCTestCase {
    func testTrustedLocalMatchesPreferSavedUserEditedFoods() {
        let saved = FoodItem(
            id: "saved",
            name: "Greek Yogurt Bowl",
            calories: 320,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userEdited,
                sourceName: "My Foods"
            )
        )
        let recent = FoodItem(
            id: "recent",
            name: "Plain Greek Yogurt",
            calories: 160,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .recent,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "Recent"
            )
        )

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "greek yogurt",
            savedFoods: [saved],
            recentFoods: [recent]
        )

        XCTAssertEqual(matches.map(\.id), ["saved", "recent"])
    }

    func testTrustedLocalMatchesDeduplicateSavedAndRecentFoods() {
        let food = FoodItem(id: "same", name: "Protein Bar", calories: 210)

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "protein",
            savedFoods: [food],
            recentFoods: [food]
        )

        XCTAssertEqual(matches.map(\.id), ["same"])
    }

    func testTrustedLocalMatchesFindBarcodeCorrectionsByDigits() {
        let food = FoodItem(
            id: "barcode-food",
            name: "Saved Cereal",
            calories: 180,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: "00 123456"
            )
        )

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "123456",
            savedFoods: [food],
            recentFoods: []
        )

        XCTAssertEqual(matches.first?.id, "barcode-food")
    }

    func testTrustedLocalMatchesIgnoreUnrelatedFoods() {
        let food = FoodItem(id: "banana", name: "Banana", calories: 105)

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "chicken",
            savedFoods: [food],
            recentFoods: []
        )

        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - Search-source merging

    func testMergedResultsAppendDistinctUSDAAfterFatSecret() {
        let fatSecret = [
            FoodItem(id: "111", name: "Chicken Breast", calories: 165),
            FoodItem(id: "222", name: "Brand X Chicken Strips", calories: 210)
        ]
        let usda = [
            FoodItem(id: "usda_1", name: "Chicken Breast", calories: 165),
            FoodItem(id: "usda_2", name: "Chicken Thigh", calories: 209)
        ]

        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: fatSecret, usda: usda)

        XCTAssertEqual(merged.map(\.id), ["111", "222", "usda_2"], "Name collisions defer to FatSecret; distinct USDA appends")
    }

    func testMergedResultsCapUSDAAdditions() {
        let usda = (0..<20).map { FoodItem(id: "usda_\($0)", name: "Food \($0)", calories: 100) }
        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: [], usda: usda, usdaLimit: 8)
        XCTAssertEqual(merged.count, 8)
    }

    func testMergedResultsIncludeOpenFoodFacts() {
        let fatSecret = [FoodItem(id: "fs_1", name: "Chicken Breast", calories: 165)]
        let usda = [FoodItem(id: "usda_1", name: "Chicken Thigh", calories: 209)]
        let off = [
            FoodItem(id: "off_1", name: "Chicken Breast", calories: 160), // duplicate name ignored
            FoodItem(id: "off_2", name: "Skyr Yogurt", calories: 120)
        ]

        let merged = FoodSearchRanking.mergedSearchResults(
            fatSecret: fatSecret,
            usda: usda,
            openFoodFacts: off
        )
        XCTAssertEqual(merged.map(\.id), ["fs_1", "usda_1", "off_2"])
    }

    func testRankedRemoteMatchesPreferPlainQueryBeforeIngredientMatches() {
        let foods = [
            FoodItem(id: "1", name: "Croissants, Apple", calories: 260),
            FoodItem(id: "2", name: "Apples, Raw, With Skin", calories: 52),
            FoodItem(id: "3", name: "Strudel, Apple", calories: 310)
        ]

        let ranked = FoodSearchRanking.rankedRemoteMatches(query: "apple", foods: foods)

        XCTAssertEqual(ranked.first?.id, "2")
    }

    // MARK: - Quick-log hydration

    private var fatSecretPreview: FoodItem {
        // What mapSearchResultToFoodItem produces: numeric id, macros from the description
        // string, no micronutrients.
        FoodItem(id: "12345", name: "Oatmeal", calories: 150, protein: 5, carbs: 27, fats: 3, servingSize: "1 cup")
    }

    func testNeedsHydrationOnlyForMicrolessFatSecretIDs() {
        XCTAssertTrue(FoodSearchRanking.needsNutritionHydration(fatSecretPreview))

        var withMicros = fatSecretPreview
        withMicros.potassium = 140
        XCTAssertFalse(FoodSearchRanking.needsNutritionHydration(withMicros))

        let usdaItem = FoodItem(id: "usda_999", name: "Oats", calories: 150)
        XCTAssertFalse(FoodSearchRanking.needsNutritionHydration(usdaItem), "USDA ids never hydrate via FatSecret")

        let customItem = FoodItem(id: UUID().uuidString, name: "My Oats", calories: 150)
        XCTAssertFalse(FoodSearchRanking.needsNutritionHydration(customItem))
    }

    func testHydratedQuickLogPrefersServingMatchingThePreview() {
        let base = FoodItem(id: "12345", name: "Oatmeal", calories: 379, protein: 13, carbs: 67, fats: 6.5,
                            servingSize: "100 g", servingWeight: 100, potassium: 429, sodium: 2)
        let cupServing = ServingSizeOption(
            description: "1 cup", servingWeightGrams: 40,
            calories: 150, protein: 5.2, carbs: 27, fats: 2.6,
            potassium: 172, sodium: 1
        )
        let hundredGrams = ServingSizeOption(
            description: "100 g", servingWeightGrams: 100,
            calories: 379, protein: 13, carbs: 67, fats: 6.5,
            potassium: 429, sodium: 2
        )

        let hydrated = FoodSearchRanking.hydratedQuickLogItem(
            preview: fatSecretPreview,
            detailBase: base,
            availableServings: [hundredGrams, cupServing]
        )

        XCTAssertEqual(hydrated.servingSize, "1 cup", "The serving the search row previewed wins")
        XCTAssertEqual(hydrated.calories, 150, accuracy: 0.001)
        XCTAssertEqual(hydrated.potassium ?? 0, 172, accuracy: 0.001, "Micros ride along at the matched serving")
    }

    func testHydratedQuickLogFallsBackToDetailBase() {
        let base = FoodItem(id: "12345", name: "Oatmeal", calories: 379, servingSize: "100 g",
                            servingWeight: 100, potassium: 429)
        var preview = fatSecretPreview
        preview.servingSize = "Tap to see details"

        let hydrated = FoodSearchRanking.hydratedQuickLogItem(
            preview: preview,
            detailBase: base,
            availableServings: []
        )

        XCTAssertEqual(hydrated.servingSize, "100 g")
        XCTAssertEqual(hydrated.potassium ?? 0, 429, accuracy: 0.001)
    }
}
