import XCTest
@testable import MyFitPlateCore

final class AYCEChallengeTests: XCTestCase {

    private func entry(_ id: String, count: Int) -> AYCESessionEntry {
        guard let item = AYCECatalog.item(id: id) else {
            XCTFail("Missing catalog item \(id)")
            return AYCESessionEntry(item: AYCECatalog.all[0], count: count)
        }
        return AYCESessionEntry(item: item, count: count)
    }

    private func sushiSession(buffetPrice: Double, entries: [AYCESessionEntry]) -> AYCESession {
        AYCESession(cuisine: .sushi, buffetPrice: buffetPrice, entries: entries)
    }

    // MARK: Session math

    func testTotalsAccumulateAcrossCountsAndItems() {
        let session = sushiSession(buffetPrice: 32.99, entries: [
            entry("sushi_salmon_nigiri", count: 4),   // 4 × $3.25 = $13.00, 240 cal
            entry("sushi_california_roll", count: 1), // $7.50, 250 cal
            entry("sushi_miso_soup", count: 1)        // $3.50, 60 cal
        ])

        let totals = AYCERules.totals(for: session)
        XCTAssertEqual(totals.restaurantValue, 24.00, accuracy: 0.001)
        XCTAssertEqual(totals.homeCost, 4 * 0.95 + 2.20 + 0.60, accuracy: 0.001)
        XCTAssertEqual(totals.calories, 4 * 60 + 250 + 60, accuracy: 0.001)
        XCTAssertEqual(totals.itemCount, 6)
    }

    func testEmptySessionIsAllZeros() {
        let session = sushiSession(buffetPrice: 30, entries: [])
        let totals = AYCERules.totals(for: session)
        XCTAssertEqual(totals.restaurantValue, 0)
        XCTAssertEqual(totals.calories, 0)
        XCTAssertEqual(AYCERules.breakEvenProgress(session: session), 0)
    }

    func testBeatByAndProgressAroundTheBreakEvenPoint() {
        var session = sushiSession(buffetPrice: 20, entries: [entry("sushi_california_roll", count: 2)]) // $15
        XCTAssertEqual(AYCERules.beatByAmount(session: session), -5, accuracy: 0.001)
        XCTAssertEqual(AYCERules.breakEvenProgress(session: session), 0.75, accuracy: 0.001)

        session.entries.append(entry("sushi_miso_soup", count: 2)) // +$7 → $22
        XCTAssertEqual(AYCERules.beatByAmount(session: session), 2, accuracy: 0.001)
        XCTAssertEqual(AYCERules.breakEvenProgress(session: session), 1.1, accuracy: 0.001)
    }

    func testZeroBuffetPriceDoesNotDivide() {
        let session = sushiSession(buffetPrice: 0, entries: [entry("sushi_gyoza", count: 3)])
        XCTAssertEqual(AYCERules.breakEvenProgress(session: session), 0)
    }

    // MARK: Copy tiers (DESIGN.md 5: sentence case, no exclamation marks)

    func testStatusLineTiers() {
        let behind = sushiSession(buffetPrice: 40, entries: [entry("sushi_california_roll", count: 1)]) // $7.50 of $40
        XCTAssertEqual(AYCERules.statusLine(session: behind), "$32.50 to break even")

        let close = sushiSession(buffetPrice: 20, entries: [entry("sushi_spicy_tuna_roll", count: 2)]) // $17 of $20 = 85%
        XCTAssertEqual(AYCERules.statusLine(session: close), "$3.00 from breaking even — so close")

        let ahead = sushiSession(buffetPrice: 20, entries: [entry("sushi_spicy_tuna_roll", count: 3)]) // $25.50
        XCTAssertEqual(AYCERules.statusLine(session: ahead), "You beat the spot by $5.50")
    }

    func testVerdictAndHomeCostLines() {
        let ahead = sushiSession(buffetPrice: 20, entries: [entry("sushi_spicy_tuna_roll", count: 3)])
        XCTAssertEqual(AYCERules.verdictHeadline(session: ahead), "You beat the spot by $5.50")

        let behind = sushiSession(buffetPrice: 50, entries: [entry("sushi_miso_soup", count: 1)])
        XCTAssertEqual(AYCERules.verdictHeadline(session: behind), "The spot won this round by $46.50")

        XCTAssertEqual(AYCERules.homeCostLine(session: ahead), "Cooking this at home: about $7.80")

        for line in [AYCERules.statusLine(session: ahead), AYCERules.verdictHeadline(session: behind)] {
            XCTAssertFalse(line.contains("!"), "System copy never uses exclamation marks")
        }
    }

    func testKitchenLineTracksRestaurantIngredientSpendAsTheHarderGame() {
        let behindKitchen = sushiSession(buffetPrice: 30, entries: [entry("sushi_salmon_nigiri", count: 4)])
        XCTAssertEqual(AYCERules.kitchenDelta(session: behindKitchen), 0.95 * 0.7 * 4 - 30, accuracy: 0.001)
        XCTAssertFalse(AYCERules.hasBeatenKitchen(session: behindKitchen))
        XCTAssertEqual(AYCERules.kitchenLine(session: behindKitchen), "Their kitchen has spent about $2.66 on you")

        let kitchenLoss = sushiSession(buffetPrice: 20, entries: [entry("sushi_spicy_tuna_roll", count: 12)])
        XCTAssertTrue(AYCERules.hasBeatenKitchen(session: kitchenLoss))
        XCTAssertEqual(
            AYCERules.kitchenLine(session: kitchenLoss),
            "Their kitchen has spent $21.84 on you — they're losing money"
        )
    }

    // MARK: Daily-log bridge

    func testFoodItemBridgeMultipliesByCountAndLabelsTheLine() {
        let bridged = AYCERules.foodItem(from: entry("sushi_salmon_nigiri", count: 4))
        XCTAssertEqual(bridged.name, "Salmon nigiri ×4")
        XCTAssertEqual(bridged.calories, 240, accuracy: 0.001)
        XCTAssertEqual(bridged.protein, 14, accuracy: 0.001)
        XCTAssertEqual(bridged.servingSize, "4 piece")
        XCTAssertEqual(bridged.sourceMetadata?.sourceName, "Beat the buffet")

        let single = AYCERules.foodItem(from: entry("sushi_miso_soup", count: 1))
        XCTAssertEqual(single.name, "Miso soup", "No ×1 noise on single items")
    }

    func testMealNamesReadNaturally() {
        XCTAssertEqual(AYCERules.mealName(for: .sushi), "All-you-can-eat Sushi")
        XCTAssertEqual(AYCERules.mealName(for: .kbbq), "All-you-can-eat Korean BBQ")
        XCTAssertEqual(AYCERules.mealName(for: .hotpot), "All-you-can-eat Hot pot")
        XCTAssertEqual(AYCERules.mealName(for: .chinese), "All-you-can-eat Chinese buffet")
        XCTAssertEqual(AYCERules.mealName(for: .dimSum), "All-you-can-eat Dim sum")
        XCTAssertEqual(AYCERules.mealName(for: .indian), "All-you-can-eat Indian buffet")
    }

    // MARK: Catalog sanity — the data IS the feature

    func testEveryCuisineHasARealMenu() {
        for cuisine in AYCECuisine.allCases {
            XCTAssertGreaterThanOrEqual(AYCECatalog.items(for: cuisine).count, 12, "\(cuisine) menu is too thin")
        }
    }

    func testExpandedCatalogIsLargeEnoughToFeelLikeARealBuffetLibrary() {
        XCTAssertGreaterThanOrEqual(AYCECatalog.all.count, 100)
    }

    func testMenuSectionsPartitionEachCuisineExactly() {
        for cuisine in AYCECuisine.allCases {
            let sectioned = AYCECatalog.sections(for: cuisine).flatMap(\.items)
            XCTAssertEqual(sectioned.map(\.id), AYCECatalog.items(for: cuisine).map(\.id),
                           "\(cuisine): sections must cover the whole menu in order — no drops, no dupes")
        }
    }

    func testSushiRollLibraryIsDeep() {
        let rolls = AYCECatalog.sections(for: .sushi).first { $0.title == "Rolls" }
        XCTAssertGreaterThanOrEqual(rolls?.items.count ?? 0, 25, "Rolls are the heart of a sushi AYCE")
        XCTAssertGreaterThanOrEqual(AYCECatalog.items(for: .sushi).count, 45)
    }

    func testCatalogIDsAreUnique() {
        let ids = AYCECatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testRestaurantAlwaysChargesMoreThanTheGroceryStore() {
        for item in AYCECatalog.all {
            XCTAssertGreaterThan(item.restaurantPrice, item.homeCost,
                                 "\(item.name): the feature's premise is à-la-carte > home cost")
            XCTAssertGreaterThan(item.homeCost, 0, "\(item.name) home cost must be positive")
        }
    }

    func testCatalogNutritionReconcilesWithAtwater() {
        for item in AYCECatalog.all {
            let implied = item.protein * 4 + item.carbs * 4 + item.fats * 9
            let tolerance = max(15, item.calories * 0.15)
            XCTAssertEqual(implied, item.calories, accuracy: tolerance,
                           "\(item.name): macros imply \(implied) cal but item claims \(item.calories)")
        }
    }
}
