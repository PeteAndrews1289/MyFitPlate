import XCTest
@testable import MyFitPlateCore

final class AYCEPricingTests: XCTestCase {

    // MARK: Prompt

    func testPromptCarriesTheContractTheDecoderExpects() {
        let prompt = AYCEPricingRules.prompt(for: ["Dragon roll", "Miso soup"], cuisine: .sushi)
        XCTAssertTrue(prompt.contains("Sushi"))
        XCTAssertTrue(prompt.contains("- Dragon roll"))
        XCTAssertTrue(prompt.contains("- Miso soup"))
        for key in ["\"items\"", "\"name\"", "\"restaurantPrice\"", "\"homeCost\""] {
            XCTAssertTrue(prompt.contains(key), "Prompt must pin the JSON contract key \(key)")
        }
    }

    // MARK: Decoding

    func testDecodesCleanAndFencedResponses() throws {
        let json = #"{"items": [{"name": "Dragon roll", "restaurantPrice": 12.5, "homeCost": 3.4}]}"#

        let clean = try AYCEPricingRules.decodePrices(from: json)
        XCTAssertEqual(clean, [AYCEPricingRules.PricedItem(name: "Dragon roll", restaurantPrice: 12.5, homeCost: 3.4)])

        let fenced = try AYCEPricingRules.decodePrices(from: "```json\n\(json)\n```")
        XCTAssertEqual(fenced.first?.restaurantPrice ?? 0, 12.5, accuracy: 0.001)
    }

    func testMissingHomeCostFallsBackInsideThePremise() throws {
        let json = #"{"items": [{"name": "Mystery plate", "restaurantPrice": 10.0}]}"#
        let priced = try XCTUnwrap(AYCEPricingRules.decodePrices(from: json).first)
        XCTAssertEqual(priced.homeCost, 3.0, accuracy: 0.001, "Absent home cost defaults to 30% of restaurant")
    }

    func testMalformedResponseThrows() {
        XCTAssertThrowsError(try AYCEPricingRules.decodePrices(from: "sorry, I can't help with that"))
    }

    // MARK: Clamps — the premise is enforced, not assumed

    func testHomeCostCanNeverReachTheRestaurantPrice() {
        let inverted = AYCEPricingRules.clampedPrices(restaurant: 5, home: 9)
        XCTAssertEqual(inverted.home, 4.5, accuracy: 0.001, "Inverted estimates are pulled below the menu price")
        XCTAssertLessThan(inverted.home, inverted.restaurant)
    }

    func testAbsurdPricesAreBounded() {
        let wild = AYCEPricingRules.clampedPrices(restaurant: 500, home: 400)
        XCTAssertEqual(wild.restaurant, 75)
        XCTAssertLessThanOrEqual(wild.home, 75 * 0.9)

        let free = AYCEPricingRules.clampedPrices(restaurant: 0, home: 0)
        XCTAssertEqual(free.restaurant, 0.75, accuracy: 0.001)
        XCTAssertGreaterThan(free.home, 0)

        let nan = AYCEPricingRules.clampedPrices(restaurant: .nan, home: .infinity)
        XCTAssertTrue(nan.restaurant.isFinite)
        XCTAssertTrue(nan.home.isFinite)
    }

    func testHeuristicPricesScaleWithCaloriesAndFloor() {
        let dinner = AYCEPricingRules.heuristicPrices(calories: 600)
        XCTAssertEqual(dinner.restaurant, 9.6, accuracy: 0.001)
        XCTAssertEqual(dinner.home, 9.6 * 0.3, accuracy: 0.001)

        let nibble = AYCEPricingRules.heuristicPrices(calories: 40)
        XCTAssertEqual(nibble.restaurant, 2.0, accuracy: 0.001, "Nothing on a menu costs less than the floor")
    }

    // MARK: Catalog item bridge

    func testScannedItemsAreMarkedAIEstimatedAndEmojiMapped() {
        let item = AYCEPricingRules.catalogItem(
            name: "Dragon Roll", cuisine: .sushi,
            calories: 320, protein: 12, carbs: 40, fats: 11,
            restaurantPrice: 12.5, homeCost: 3.4
        )
        XCTAssertTrue(item.isAIEstimated)
        XCTAssertTrue(item.id.hasPrefix("custom_"))
        XCTAssertEqual(item.emoji, "🍣")
        XCTAssertEqual(AYCEPricingRules.emoji(for: "Beef brisket plate"), "🥩")
        XCTAssertEqual(AYCEPricingRules.emoji(for: "Something unrecognizable"), "🍽️")
    }

    func testAIEstimatedEntriesCarryHonestSourceMetadataIntoTheDiary() {
        let scanned = AYCEPricingRules.catalogItem(
            name: "Dragon roll", cuisine: .sushi,
            calories: 320, protein: 12, carbs: 40, fats: 11,
            restaurantPrice: 12.5, homeCost: 3.4
        )
        let bridged = AYCERules.foodItem(from: AYCESessionEntry(item: scanned, count: 2))
        XCTAssertEqual(bridged.sourceMetadata?.sourceType, .aiImage, "Scanned food must not claim to be user-verified")
        XCTAssertEqual(bridged.sourceMetadata?.confidence, .estimated)

        let catalog = AYCERules.foodItem(from: AYCESessionEntry(item: AYCECatalog.all[0], count: 1))
        XCTAssertEqual(catalog.sourceMetadata?.sourceType, .manual, "Curated catalog entries stay user-entered")
    }

    // MARK: City-aware pricing

    func testCityLookupFallsBackToNationalForUnknownSlugs() {
        XCTAssertEqual(AYCECityIndex.city(slug: "nyc").name, "New York")
        XCTAssertEqual(AYCECityIndex.city(slug: nil).slug, "us_average")
        XCTAssertEqual(AYCECityIndex.city(slug: "atlantis").slug, "us_average")
        XCTAssertEqual(AYCECityIndex.pickerOptions.first?.slug, "us_average", "Baseline leads the picker")
    }

    func testCityMultipliersStayMidMarket() {
        for city in AYCECityIndex.pickerOptions {
            XCTAssertGreaterThanOrEqual(city.restaurantMultiplier, 0.9, "\(city.name) below plausible range")
            XCTAssertLessThanOrEqual(city.restaurantMultiplier, 1.35, "\(city.name): mid-market calibration, not premium")
            XCTAssertLessThanOrEqual(
                abs(city.homeMultiplier - 1), abs(city.restaurantMultiplier - 1) * 0.5,
                "\(city.name): groceries must swing less than menus"
            )
        }
    }

    func testCuratedItemsScaleByCityButScannedItemsDoNot() {
        let nigiri = AYCECatalog.item(id: "sushi_salmon_nigiri")!
        let scanned = AYCEPricingRules.catalogItem(
            name: "Dragon roll", cuisine: .sushi,
            calories: 320, protein: 12, carbs: 40, fats: 11,
            restaurantPrice: 14.0, homeCost: 4.0
        )
        let nyc = AYCESession(
            cuisine: .sushi, buffetPrice: 40,
            entries: [AYCESessionEntry(item: nigiri, count: 2), AYCESessionEntry(item: scanned, count: 1)],
            citySlug: "nyc"
        )

        let totals = AYCERules.totals(for: nyc)
        let expectedCurated = nigiri.restaurantPrice * 1.30 * 2
        XCTAssertEqual(totals.restaurantValue, expectedCurated + 14.0, accuracy: 0.001,
                       "NYC scales the catalog nigiri; the NYC-prompted scan passes through untouched")

        let unit = AYCERules.unitPrices(for: nigiri, in: nyc)
        XCTAssertEqual(unit.restaurant, nigiri.restaurantPrice * 1.30, accuracy: 0.001)
        XCTAssertEqual(unit.home, nigiri.homeCost * AYCECityIndex.city(slug: "nyc").homeMultiplier, accuracy: 0.001)
    }

    func testRestaurantFoodCostSitsBelowBothOtherTiers() {
        let foodCost = AYCERules.restaurantFoodCost(homeCost: 0.95, menuPrice: 3.25)
        XCTAssertEqual(foodCost, 0.95 * 0.7, accuracy: 0.001)
        XCTAssertLessThan(foodCost, 0.95)

        let capped = AYCERules.restaurantFoodCost(homeCost: 100, menuPrice: 10)
        XCTAssertEqual(capped, 4.5, accuracy: 0.001, "Never above 45% of the menu price")
        XCTAssertEqual(AYCERules.restaurantFoodCost(homeCost: 0.01, menuPrice: 1), 0.15, "Floor holds")
    }

    func testIngredientCostLineAndTotalsCarryTheThirdTier() {
        let session = AYCESession(
            cuisine: .sushi, buffetPrice: 30,
            entries: [AYCESessionEntry(item: AYCECatalog.item(id: "sushi_salmon_nigiri")!, count: 4)]
        )
        let totals = AYCERules.totals(for: session)
        XCTAssertEqual(totals.restaurantFoodCost, 0.95 * 0.7 * 4, accuracy: 0.001)
        XCTAssertEqual(AYCERules.ingredientCostLine(session: session), "Their ingredients: about $2.66")
    }

    func testPromptNamesTheCityAndForbidsPremiumReferences() {
        let nyc = AYCEPricingRules.prompt(for: ["Dragon roll"], cuisine: .sushi, city: AYCECityIndex.city(slug: "nyc"))
        XCTAssertTrue(nyc.contains("in New York"))
        XCTAssertTrue(nyc.contains("MID-RANGE"))
        XCTAssertTrue(nyc.contains("never premium"))

        let national = AYCEPricingRules.prompt(for: ["Dragon roll"], cuisine: .sushi)
        XCTAssertTrue(national.contains("typical US city"))
    }

    func testOldSessionDraftsWithoutCityStillDecode() throws {
        let legacy = """
        {"id": "s1", "cuisine": "sushi", "buffetPrice": 30, "startedAt": 700000000, "entries": []}
        """
        let session = try JSONDecoder().decode(AYCESession.self, from: Data(legacy.utf8))
        XCTAssertNil(session.citySlug)
        XCTAssertEqual(session.city.slug, "us_average")
    }

    func testOldDraftsWithoutTheNewFieldStillDecode() throws {
        let legacyJSON = """
        {"id": "x", "cuisine": "sushi", "name": "Salmon nigiri", "emoji": "🍣", "unit": "piece",
         "calories": 60, "protein": 3.5, "carbs": 9, "fats": 1.5, "restaurantPrice": 3.25, "homeCost": 0.95}
        """
        let item = try JSONDecoder().decode(AYCECatalogItem.self, from: Data(legacyJSON.utf8))
        XCTAssertFalse(item.isAIEstimated, "Pre-field drafts default to curated")
    }
}
