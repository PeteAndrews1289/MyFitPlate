import XCTest
@testable import MyFitPlateCore

final class ChainMealBuilderCatalogTests: XCTestCase {
    func testBrandForegroundChoosesReadableTextForLightAndDarkColors() {
        XCTAssertTrue(ChainRestaurantCatalog.mcdonalds.brandForegroundUsesDarkText)
        XCTAssertTrue(ChainRestaurantCatalog.inNOut.brandForegroundUsesDarkText)
        XCTAssertFalse(ChainRestaurantCatalog.jerseyMikes.brandForegroundUsesDarkText)
    }

    func testCatalogHasExpectedShapeAndUniqueIngredientIDs() {
        let chains = ChainRestaurantCatalog.allChains
        XCTAssertGreaterThanOrEqual(chains.count, 25)
        XCTAssertEqual(Set(chains.map(\.id)).count, chains.count)

        let ingredients = chains.flatMap { chain in
            chain.categories.flatMap(\.ingredients)
        }
        XCTAssertEqual(Set(ingredients.map(\.id)).count, ingredients.count)

        for chain in chains {
            XCTAssertFalse(chain.name.isEmpty)
            XCTAssertTrue(chain.brandColorHex.hasPrefix("#"))
            XCTAssertFalse(chain.categories.isEmpty, "\(chain.name) needs at least one category")
            XCTAssertEqual(chain.ingredientCount, chain.categories.flatMap(\.ingredients).count)

            for category in chain.categories {
                XCTAssertFalse(category.ingredients.isEmpty, "\(chain.name) / \(category.title) is empty")
            }
        }
    }

    func testCatalogMacrosStayWithinReasonableCalorieBounds() {
        let ingredients = ChainRestaurantCatalog.allChains.flatMap { chain in
            chain.categories.flatMap(\.ingredients)
        }

        let offenders = ingredients.filter { ingredient in
            let macroCalories = ingredient.protein * 4 + ingredient.carbs * 4 + ingredient.fat * 9
            let delta = abs(macroCalories - ingredient.calories)
            return delta > 120 && delta / max(ingredient.calories, 1) > 0.25
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Macro-derived calories drifted too far for: \(offenders.map(\.id).joined(separator: ", "))"
        )
    }

    func testIngredientSummaryUsesCatalogOrderNotDictionaryOrder() {
        let chain = ChainRestaurantCatalog.chipotle
        let whiteRice = chain.categories[0].ingredients[0]
        let chicken = chain.categories[2].ingredients[0]
        let selections = [
            chicken.id: ChainSelectionItem(id: chicken.id, ingredient: chicken),
            whiteRice.id: ChainSelectionItem(id: whiteRice.id, ingredient: whiteRice)
        ]

        let summary = chain.ingredientSummary(for: selections)

        XCTAssertTrue(summary.hasPrefix("Cilantro-Lime White Rice"))
        XCTAssertTrue(summary.contains("Adobo Chicken"))
    }

    func testCustomMealFactoryCarriesHonestReviewMetadataAndProvenance() {
        let chain = ChainRestaurantCatalog.chipotle
        let whiteRice = chain.categories[0].ingredients[0]
        let chicken = chain.categories[2].ingredients[0]
        let selections = [
            whiteRice.id: ChainSelectionItem(id: whiteRice.id, ingredient: whiteRice),
            chicken.id: ChainSelectionItem(id: chicken.id, ingredient: chicken)
        ]

        let item = chain.customMealFoodItem(from: selections, id: "chain-test")

        XCTAssertEqual(item.name, "Chipotle Custom Meal")
        XCTAssertEqual(item.calories, 390, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(item.sodium), 660, accuracy: 0.001)
        XCTAssertEqual(item.sourceMetadata?.sourceType, .chainBuilder)
        XCTAssertEqual(item.sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(item.sourceMetadata?.reviewStatus, .unreviewed)
        XCTAssertEqual(item.sourceMetadata?.sourceName, "Chipotle Builder")
        XCTAssertEqual(item.sourceMetadata?.sourceID, "chipotle:\(ChainRestaurantCatalog.catalogVersion)")
        XCTAssertEqual(item.sourceMetadata?.matchedFoodID, item.sourceMetadata?.sourceID)
        XCTAssertTrue(item.sourceMetadata?.notes?.contains(ChainRestaurantCatalog.catalogVersion) == true)

        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)
        XCTAssertEqual(descriptor.sourceKey, "chain_builder")
        XCTAssertEqual(descriptor.confidence, "Needs Review")

        let confirmed = item.markedUserConfirmed(sourceType: .chainBuilder)
        XCTAssertEqual(confirmed.sourceMetadata?.sourceType, .chainBuilder)
        XCTAssertEqual(confirmed.sourceMetadata?.reviewStatus, .userConfirmed)
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: confirmed.sourceMetadata!).confidence, "User Reviewed")
    }

    func testUnknownSodiumStaysNilInsteadOfBecomingZero() {
        let chain = ChainRestaurantCatalog.sweetgreen
        let kale = chain.categories[0].ingredients[0]
        let selections = [
            kale.id: ChainSelectionItem(id: kale.id, ingredient: kale)
        ]

        XCTAssertNil(chain.nutritionTotals(for: selections).sodium)
        XCTAssertNil(chain.customMealFoodItem(from: selections).sodium)
    }

    func testStepperControlsExposeReasonableMaximumCounts() throws {
        let dominosSlice = try XCTUnwrap(
            ChainRestaurantCatalog.dominos.categories
                .flatMap(\.ingredients)
                .first { $0.id == "dom_ht_pepperoni" }
        )
        let smoothieBoost = try XCTUnwrap(
            ChainRestaurantCatalog.tropicalSmoothie.categories
                .flatMap(\.ingredients)
                .first { $0.id == "tsc_whey_scoop" }
        )
        let fixedBurger = try XCTUnwrap(
            ChainRestaurantCatalog.fiveGuys.categories
                .flatMap(\.ingredients)
                .first { $0.id == "fg_cheeseburger" }
        )

        XCTAssertEqual(dominosSlice.maximumCount, 12)
        XCTAssertEqual(smoothieBoost.maximumCount, 6)
        XCTAssertEqual(fixedBurger.maximumCount, 1)
    }
}
