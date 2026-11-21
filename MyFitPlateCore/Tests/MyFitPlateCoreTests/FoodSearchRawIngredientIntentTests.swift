import XCTest
@testable import MyFitPlateCore

final class FoodSearchRawIngredientIntentTests: XCTestCase {
    func testCapturedDrinksDoNotDisplaceRawIngredientOrReceiveBrandPromotion() throws {
        let drinks = try capturedDrinks()
        let raw = FoodItem(id: "raw", name: "Strawberries, raw", calories: 32)
        let ranked = FoodSearchRanking.rankedRemoteMatches(query: "strawberries raw", foods: drinks + [raw])
        XCTAssertEqual(ranked.first?.id, raw.id)
        let shown = presentation(query: "strawberries raw", foods: ranked)
        XCTAssertTrue(shown.brandedMatches.isEmpty)
        XCTAssertEqual(shown.otherRemoteMatches.first?.id, raw.id)
        let uncooked = presentation(query: "uncooked strawberries", foods: drinks + [raw])
        XCTAssertTrue(uncooked.brandedMatches.isEmpty)
        XCTAssertEqual(uncooked.otherRemoteMatches.map(\.id), [raw.id])
    }

    func testDrinksAreNotPromotedWhenNoGenuineRawIngredientWasReturned() throws {
        let shown = presentation(query: "strawberries raw", foods: try capturedDrinks())
        XCTAssertTrue(shown.brandedMatches.isEmpty, "The strongest available result is not necessarily an intent match")
        XCTAssertTrue(shown.otherRemoteMatches.isEmpty, "Prepared drinks do not answer a raw ingredient search")
        XCTAssertTrue(FoodSearchRanking.trustedLocalMatches(query: "strawberries raw", savedFoods: try capturedDrinks(), recentFoods: []).isEmpty)
    }

    func testRealBrandedRawProduceKeepsPriorityOverGenericProduce() throws {
        let generic = FoodItem(id: "generic", name: "Strawberries, raw", calories: 32)
        let produce = FoodItem(id: "produce", name: "Orchard Farm Raw Strawberries", calories: 32)
            .withDatabaseSource(.usda, sourceName: "USDA", brandName: "Orchard Farm")
        let ranked = FoodSearchRanking.rankedRemoteMatches(query: "strawberries raw", foods: try capturedDrinks() + [generic, produce])
        XCTAssertEqual(Array(ranked.prefix(2)).map(\.id), [produce.id, generic.id])
        XCTAssertEqual(presentation(query: "strawberries raw", foods: ranked).brandedMatches.map(\.id), [produce.id])
    }

    func testExplicitFullBrandsKeepTheirRequestedRawDrinkIdentity() throws {
        let drinks = try capturedDrinks()
        for (query, id) in [("THE BU strawberries raw", "usda_2283055"), ("GENESIS strawberries raw", "usda_2440412")] {
            XCTAssertEqual(presentation(query: query, foods: drinks).brandedMatches.map(\.id), [id])
        }
    }

    func testExplicitRawJuiceAndKombuchaQueriesKeepBrandedPriority() throws {
        let drinks = try capturedDrinks()
        for (query, id) in [("strawberry raw juice", "usda_2440412"), ("strawberry raw kombucha", "usda_2283055")] {
            XCTAssertEqual(presentation(query: query, foods: drinks).brandedMatches.map(\.id), [id])
        }
        let genericJuice = FoodItem(id: "generic-juice", name: "Raw juice", calories: 40)
        let ranked = FoodSearchRanking.rankedRemoteMatches(query: "raw juice", foods: [genericJuice] + drinks)
        XCTAssertEqual(ranked.first?.id, "usda_2440412")
        XCTAssertEqual(presentation(query: "raw juice", foods: ranked).brandedMatches.map(\.id), ["usda_2440412"])
    }

    func testRawNamedBrandDoesNotOverrideGenericIngredientIntent() {
        let drink = FoodItem(id: "drink", name: "Raw Strawberry Juice", calories: 40)
            .withDatabaseSource(.usda, sourceName: "USDA", brandName: "Raw")
        XCTAssertTrue(presentation(query: "strawberries raw", foods: [drink]).brandedMatches.isEmpty)
        XCTAssertEqual(presentation(query: "strawberry raw juice", foods: [drink]).brandedMatches.map(\.id), [drink.id])
    }

    func testFinalPrefixCannotPromoteAnUnrequestedPreparedForm() throws {
        XCTAssertTrue(presentation(query: "raw straw", foods: try capturedDrinks()).brandedMatches.isEmpty)
    }

    func testQueriesWithoutRawQualifierKeepEstablishedBrandPriority() throws {
        let drinks = try capturedDrinks()
        let generic = FoodItem(id: "generic", name: "Strawberry", calories: 32)
        let ranked = FoodSearchRanking.rankedRemoteMatches(query: "strawberry", foods: [generic] + drinks)
        XCTAssertNotEqual(ranked.first?.id, generic.id)
        XCTAssertEqual(Set(presentation(query: "strawberry", foods: ranked).brandedMatches.map(\.id)), Set(drinks.map(\.id)))
    }

    private func presentation(query: String, foods: [FoodItem]) -> FoodSearchRanking.SearchPresentation {
        FoodSearchRanking.searchPresentation(query: query, trustedMatches: [], remoteMatches: foods, providersComplete: true)
    }

    private func capturedDrinks() throws -> [FoodItem] {
        try USDAFoodParser.foodItems(from: Data(captured.utf8))
    }

    // USDA CC0 public response projections, captured November 4, 2026 for
    // "strawberries raw"; identities, preparation names and macro values retained.
    private let captured = #"{"foods":[{"fdcId":2283055,"description":"STRAWBERRY HIBISCUS RAW KOMBUCHA, STRAWBERRY HIBISCUS","dataType":"Branded","gtinUpc":"819394020453","publishedDate":"2022-05-23","brandOwner":"Makana Beverages Inc","brandName":"THE BU","modifiedDate":"2022-02-05","servingSizeUnit":"ml","servingSize":355.0,"householdServingFullText":"12 ONZ","foodNutrients":[{"nutrientId":1003,"nutrientNumber":"203","unitName":"G","value":0.0},{"nutrientId":1004,"nutrientNumber":"204","unitName":"G","value":0.0},{"nutrientId":1005,"nutrientNumber":"205","unitName":"G","value":2.82},{"nutrientId":1008,"nutrientNumber":"208","unitName":"KCAL","value":11.0}]},{"fdcId":2440412,"description":"100% RAW APPLE STRAWBERRY JUICE, APPLE, STRAWBERRY","dataType":"Branded","gtinUpc":"085762004121","publishedDate":"2022-12-22","brandOwner":"Toby's Family Foods, LLC","brandName":"GENESIS","modifiedDate":"2019-03-20","servingSizeUnit":"ml","servingSize":240.0,"householdServingFullText":"8 OZA","foodNutrients":[{"nutrientId":1003,"nutrientNumber":"203","unitName":"G","value":0.0},{"nutrientId":1004,"nutrientNumber":"204","unitName":"G","value":0.0},{"nutrientId":1005,"nutrientNumber":"205","unitName":"G","value":11.7},{"nutrientId":1008,"nutrientNumber":"208","unitName":"KCAL","value":46.0}]}]}"#
}
