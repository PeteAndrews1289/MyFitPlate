import XCTest
@testable import MyFitPlateCore

final class AYCEPortionTests: XCTestCase {
    func testIngredientEstimatesStayBoundedForSmallSaucePortions() {
        for item in AYCECatalog.all {
            let cost = AYCERules.restaurantFoodCost(homeCost: item.homeCost, menuPrice: item.restaurantPrice)
            XCTAssertLessThanOrEqual(cost, item.homeCost, item.name)
            XCTAssertLessThanOrEqual(cost, item.restaurantPrice * 0.45, item.name)
            XCTAssertGreaterThanOrEqual(cost, 0)
        }
        XCTAssertEqual(AYCERules.restaurantFoodCost(homeCost: .nan, menuPrice: 1), 0)
    }

    func testExtremeManualNutritionCannotOverflowDisplayCalculations() {
        XCTAssertNil(AYCEPricingRules.reviewedCatalogItem(name: "Invalid", unit: "plate", cuisine: .sushi,
                                                          calories: 1e100, protein: 2, carbs: 2, fats: 2,
                                                          restaurantPrice: 10, homeCost: 2))
        let scanned = AYCEPricingRules.catalogItem(name: "Invalid", cuisine: .sushi, calories: 1e100,
                                                  protein: 1e100, carbs: 1e100, fats: 1e100,
                                                  restaurantPrice: 10, homeCost: 2)
        XCTAssertLessThanOrEqual(scanned.calories, 10_000)
        XCTAssertLessThanOrEqual(scanned.protein, 2_000)
    }
    func testSharedRollScalesAllNutritionAndRegionalValue() throws {
        let roll = try XCTUnwrap(AYCECatalog.item(id: "sushi_rainbow_roll"))
        let quantity = try XCTUnwrap(AYCEPortionRules.quantity(pieces: 3, item: roll))
        XCTAssertEqual(quantity, 0.375)
        let entry = AYCESessionEntry(id: "shared-roll", item: roll, count: quantity)
        let session = AYCESession(cuisine: .sushi, buffetPrice: 35, entries: [entry], citySlug: "nyc")
        let totals = AYCERules.totals(for: session)
        XCTAssertEqual(totals.calories, roll.calories * 3 / 8, accuracy: 0.0001)
        XCTAssertEqual(totals.protein, roll.protein * 3 / 8, accuracy: 0.0001)
        XCTAssertEqual(totals.restaurantValue, roll.restaurantPrice * 1.3 * 3 / 8, accuracy: 0.0001)
        XCTAssertEqual(totals.homeCost, AYCERules.unitPrices(for: roll, in: session).home * quantity, accuracy: 0.0001)
        let food = AYCERules.foodItem(from: entry)
        XCTAssertEqual(food.id, "ayce_shared-roll")
        XCTAssertEqual(food.calories, totals.calories)
        XCTAssertTrue(food.servingSize.hasPrefix("3 pieces"))
        XCTAssertEqual(food.sourceMetadata?.confidence, .estimated)
    }

    func testCookedMeatWeightScalesRatherThanCountingTheSharedTray() throws {
        let meat = try XCTUnwrap(AYCECatalog.item(id: "kbbq_brisket"))
        let quantity = try XCTUnwrap(AYCEPortionRules.quantity(cookedGrams: 165, item: meat))
        XCTAssertEqual(quantity, 1.5)
        let food = AYCERules.foodItem(from: AYCESessionEntry(item: meat, count: quantity))
        XCTAssertEqual(food.calories, 525)
        XCTAssertTrue(food.servingSize.contains("165 g cooked"))
    }

    func testWeightedSauceAndSideLabelsKeepTheCatalogWeightPerUnit() throws {
        let sauce = try XCTUnwrap(AYCECatalog.item(id: "kbbq_ssamjang"))
        let halfSauce = AYCERules.foodItem(from: AYCESessionEntry(item: sauce, count: 0.5))
        XCTAssertEqual(halfSauce.calories, 20)
        XCTAssertEqual(halfSauce.servingSize, "0.5 × 1 tbsp (20 g)")
        XCTAssertEqual(AYCEPortionRules.servingDescription(item: sauce, quantity: 1), "1 tbsp (20 g)")

        let side = try XCTUnwrap(AYCECatalog.item(id: "kbbq_cucumber_kimchi"))
        let doubleSide = AYCERules.foodItem(from: AYCESessionEntry(item: side, count: 2))
        XCTAssertEqual(doubleSide.calories, 50)
        XCTAssertEqual(doubleSide.servingSize, "2 × 1 side (50 g)")

        let sashimi = try XCTUnwrap(AYCECatalog.item(id: "sushi_yellowtail_sashimi"))
        XCTAssertEqual(AYCEPortionRules.servingDescription(item: sashimi, quantity: 3), "3 × 1 slice (25 g)")
    }

    func testInvalidPortionsAndUnsupportedConversionsAreRejected() throws {
        let item = try XCTUnwrap(AYCECatalog.item(id: "sushi_salmon_nigiri"))
        for value in [0, -1, .nan, .infinity, 101] { XCTAssertFalse(AYCEPortionRules.isValid(value)) }
        XCTAssertTrue(AYCEPortionRules.isValid(0, allowsZero: true))
        XCTAssertTrue(AYCEPortionRules.isValid(0.125))
        XCTAssertNil(AYCEPortionRules.quantity(pieces: 2, item: item))
        XCTAssertNil(AYCEPortionRules.quantity(cookedGrams: 100, item: item))
        let roll = try XCTUnwrap(AYCECatalog.item(id: "sushi_california_roll"))
        XCTAssertNil(AYCEPortionRules.quantity(pieces: -3, item: roll))
        XCTAssertNil(AYCEPortionRules.quantity(pieces: .infinity, item: roll))
        XCTAssertNil(AYCEPortionRules.quantity(pieces: 601, item: roll))
    }

    func testOlderIntegerCountDraftDecodesWithoutNewFields() throws {
        let session = AYCESession(cuisine: .kbbq, buffetPrice: 30,
                                  entries: [AYCESessionEntry(item: AYCECatalog.all[0], count: 3)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        object.removeValue(forKey: "endedAt")
        object.removeValue(forKey: "submittedAt")
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0]["count"] = 3
        var item = try XCTUnwrap(entries[0]["item"] as? [String: Any])
        for key in ["piecesPerUnit", "cookedGramsPerUnit", "isAIEstimated", "isLocallyPriced"] { item.removeValue(forKey: key) }
        entries[0]["item"] = item
        object["entries"] = entries
        let restored = try JSONDecoder().decode(AYCESession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.entries[0].count, 3)
        XCTAssertNil(restored.endedAt)
        XCTAssertNil(restored.submittedAt)
        XCTAssertNil(restored.entries[0].item.piecesPerUnit)
    }

    func testFractionalCountAndReviewStateSurviveEncoding() throws {
        let session = AYCESession(cuisine: .sushi, buffetPrice: 30,
                                  entries: [AYCESessionEntry(item: AYCECatalog.all[0], count: 0.5)],
                                  endedAt: Date(), submittedAt: Date())
        XCTAssertEqual(try JSONDecoder().decode(AYCESession.self, from: JSONEncoder().encode(session)), session)
    }

    func testAliasesAndMultipleTokensFindRealMenuNames() {
        func ids(_ query: String, _ cuisine: AYCECuisine) -> [String] {
            AYCECatalog.matchingSections(for: cuisine, query: query).flatMap(\.items).map(\.id)
        }
        XCTAssertTrue(ids("  CHADOL  ", .kbbq).contains("kbbq_brisket"))
        XCTAssertTrue(ids("garlic samgyubsal", .kbbq).contains("kbbq_garlic_pork_belly"))
        XCTAssertEqual(ids("hamachi sashimi", .sushi), ["sushi_yellowtail_sashimi"])
        XCTAssertEqual(ids("spicy salmon roll", .sushi).count, 2)
        XCTAssertTrue(ids("not-a-food-xyz", .sushi).isEmpty)
    }

    func testCategoryAndSearchIntersectWithoutDuplicates() {
        let sections = AYCECatalog.matchingSections(for: .kbbq, query: "garlic", sectionID: "Pork")
        XCTAssertEqual(sections.flatMap(\.items).map(\.id), ["kbbq_garlic_pork_belly"])
        XCTAssertTrue(AYCECatalog.matchingSections(for: .sushi, query: "salmon", sectionID: "Sauces").isEmpty)
        for cuisine in AYCECuisine.allCases {
            XCTAssertEqual(AYCECatalog.matchingSections(for: cuisine).flatMap(\.items), AYCECatalog.items(for: cuisine))
        }
    }

    func testSushiAndKBBQHaveBroadCoverageAndExplicitPortions() {
        XCTAssertGreaterThanOrEqual(AYCECatalog.items(for: .sushi).count, 80)
        XCTAssertGreaterThanOrEqual(AYCECatalog.items(for: .kbbq).count, 45)
        for item in AYCECatalog.items(for: .sushi) where item.unit.hasPrefix("roll (") {
            XCTAssertNotNil(item.piecesPerUnit, item.name)
        }
        for category in ["Beef", "Pork", "Chicken & seafood"] {
            for item in AYCECatalog.matchingSections(for: .kbbq, sectionID: category).flatMap(\.items) {
                XCTAssertEqual(item.cookedGramsPerUnit, 110, item.name)
                XCTAssertTrue(item.unit.contains("cooked"), item.name)
            }
        }
    }

    func testScoreboardReplayReplacesSameSessionInsteadOfDuplicatingIt() {
        var session = AYCESession(id: "one", cuisine: .sushi, buffetPrice: 30,
                                  entries: [AYCESessionEntry(item: AYCECatalog.all[0], count: 4)])
        let record = AYCESessionRecord(session: session)
        session.entries[0].count = 5
        let updated = AYCESessionRecord(session: session)
        XCTAssertEqual(AYCEScoreboard.appending(updated, to: [record]), [updated])
    }
}
