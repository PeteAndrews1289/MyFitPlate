import XCTest
@testable import MyFitPlateCore

final class MyFoodsLibraryTests: XCTestCase {
    func testEntriesAttachLastUseOnlyThroughSavedFoodIdentity() throws {
        let saved = food(id: "saved", name: "Greek Yogurt")
        let usedAt = Date(timeIntervalSince1970: 2_000)
        var matchingMetadata = saved.sourceMetadata
        matchingMetadata?.sourceID = saved.id
        let matchingRecent = FoodItem(
            id: "logged-copy",
            name: saved.name,
            calories: saved.calories,
            protein: saved.protein,
            carbs: saved.carbs,
            fats: saved.fats,
            servingSize: saved.servingSize,
            servingWeight: saved.servingWeight,
            timestamp: usedAt,
            sourceMetadata: matchingMetadata
        )
        let sameNameWithoutIdentity = FoodItem(
            id: "different-food",
            name: saved.name,
            timestamp: Date(timeIntervalSince1970: 3_000)
        )

        let entry = try XCTUnwrap(
            MyFoodsLibraryRules.entries(
                savedFoods: [saved],
                recentFoods: [sameNameWithoutIdentity, matchingRecent]
            ).first
        )

        XCTAssertEqual(entry.lastUsedAt, usedAt)
    }

    func testFiltersSeparateBarcodeManualRecipeRecentAndReviewStates() {
        let barcode = food(id: "barcode", name: "Cereal", barcode: "0044000087579")
        let manual = food(id: "manual", name: "Oatmeal")
        let recipe = food(
            id: "recipe",
            name: "Chili",
            sourceType: .recipe,
            reviewStatus: .notRequired
        )
        let warning = food(
            id: "warning",
            name: "Cookie",
            fats: 7,
            saturatedFat: 10
        )
        var recentMetadata = manual.sourceMetadata
        recentMetadata?.matchedFoodID = manual.id
        let recent = FoodItem(
            id: "recent",
            name: manual.name,
            timestamp: Date(timeIntervalSince1970: 5_000),
            sourceMetadata: recentMetadata
        )
        let entries = MyFoodsLibraryRules.entries(
            savedFoods: [barcode, manual, recipe, warning],
            recentFoods: [recent]
        )

        XCTAssertEqual(ids(entries, filter: .barcodeCorrections), ["barcode"])
        XCTAssertEqual(Set(ids(entries, filter: .manual)), Set(["manual", "warning"]))
        XCTAssertEqual(ids(entries, filter: .recipes), ["recipe"])
        XCTAssertEqual(ids(entries, filter: .recent), ["manual"])
        XCTAssertEqual(ids(entries, filter: .needsReview), ["warning"])
    }

    func testSearchAndSortAreDeterministic() {
        let alpha = food(id: "alpha", name: "Alpha Bowl")
        let beta = food(id: "beta", name: "Beta Bowl", reviewStatus: .userEdited)
        var betaRecentMetadata = beta.sourceMetadata
        betaRecentMetadata?.sourceID = beta.id
        let betaRecent = FoodItem(
            id: "beta-log",
            name: beta.name,
            timestamp: Date(timeIntervalSince1970: 8_000),
            sourceMetadata: betaRecentMetadata
        )
        let entries = MyFoodsLibraryRules.entries(
            savedFoods: [beta, alpha],
            recentFoods: [betaRecent]
        )

        XCTAssertEqual(
            MyFoodsLibraryRules.visibleEntries(
                entries,
                query: "alpha",
                filter: .all,
                sort: .name
            ).map(\.id),
            ["alpha"]
        )
        XCTAssertEqual(
            MyFoodsLibraryRules.visibleEntries(
                entries,
                query: "",
                filter: .all,
                sort: .lastUsed
            ).map(\.id),
            ["beta", "alpha"]
        )
    }

    func testDuplicatesRequireIdenticalServingNutritionAndBarcodeState() throws {
        let older = food(id: "older", name: "Protein Shake", barcode: "012345678905")
        let recentKeeper = food(id: "recent-keeper", name: "  protein   shake ", barcode: "012345678905")
        let differentServing = food(
            id: "different-serving",
            name: "Protein Shake",
            serving: "2 bottles",
            barcode: "012345678905"
        )
        let noBarcode = food(id: "no-barcode", name: "Protein Shake")
        var recentMetadata = recentKeeper.sourceMetadata
        recentMetadata?.sourceID = recentKeeper.id
        let recent = FoodItem(
            id: "recent-log",
            name: recentKeeper.name,
            timestamp: Date(timeIntervalSince1970: 9_000),
            sourceMetadata: recentMetadata
        )
        let entries = MyFoodsLibraryRules.entries(
            savedFoods: [older, differentServing, noBarcode, recentKeeper],
            recentFoods: [recent]
        )

        let group = try XCTUnwrap(MyFoodsLibraryRules.duplicateGroups(from: entries).first)
        XCTAssertEqual(group.itemCount, 2)
        XCTAssertEqual(group.keeper.id, recentKeeper.id)
        XCTAssertEqual(group.duplicates.map(\.id), [older.id])
    }

    func testDifferentMicronutrientsAreNotMerged() {
        var first = food(id: "first", name: "Soup")
        first.sodium = 500
        var second = food(id: "second", name: "Soup")
        second.sodium = 700

        let entries = MyFoodsLibraryRules.entries(
            savedFoods: [first, second],
            recentFoods: []
        )

        XCTAssertTrue(MyFoodsLibraryRules.duplicateGroups(from: entries).isEmpty)
    }

    func testDifferentSourceCategoriesAreNotMerged() {
        let manual = food(id: "manual", name: "Chili")
        let recipe = food(
            id: "recipe",
            name: "Chili",
            sourceType: .recipe,
            reviewStatus: .notRequired
        )

        let entries = MyFoodsLibraryRules.entries(
            savedFoods: [manual, recipe],
            recentFoods: []
        )

        XCTAssertTrue(MyFoodsLibraryRules.duplicateGroups(from: entries).isEmpty)
    }

    func testSavedRecipeRetainsItsLibraryCategory() throws {
        let recipe = food(
            id: "recipe",
            name: "Turkey Chili",
            sourceType: .recipe,
            reviewStatus: .notRequired
        ).savedAsCustomFood()

        XCTAssertEqual(recipe.sourceMetadata?.sourceType, .custom)
        XCTAssertEqual(recipe.sourceMetadata?.originSourceType, .recipe)
        let entry = try XCTUnwrap(
            MyFoodsLibraryRules.entries(savedFoods: [recipe], recentFoods: []).first
        )
        XCTAssertTrue(entry.isRecipe)
        XCTAssertFalse(entry.isManual)
    }

    func testLegacyMetadataWithoutOriginSourceTypeStillDecodes() throws {
        let data = try XCTUnwrap(
            """
            {
              "sourceType": "custom",
              "confidence": "userVerified",
              "reviewStatus": "userConfirmed",
              "sourceName": "My Foods"
            }
            """.data(using: .utf8)
        )

        let metadata = try JSONDecoder().decode(FoodSourceMetadata.self, from: data)
        XCTAssertEqual(metadata.sourceType, .custom)
        XCTAssertNil(metadata.originSourceType)
    }

    func testRemovingBarcodePreservesFoodAndOtherMetadata() throws {
        let original = food(id: "barcode", name: "Granola", barcode: "0044000087579")
        let detached = MyFoodsLibraryRules.removingBarcodeAssociation(from: original)

        XCTAssertEqual(detached.id, original.id)
        XCTAssertEqual(detached.name, original.name)
        XCTAssertEqual(detached.calories, original.calories)
        XCTAssertNil(detached.sourceMetadata?.barcode)
        XCTAssertEqual(detached.sourceMetadata?.sourceType, original.sourceMetadata?.sourceType)
        XCTAssertEqual(detached.sourceMetadata?.reviewStatus, original.sourceMetadata?.reviewStatus)
    }

    private func ids(
        _ entries: [MyFoodsLibraryEntry],
        filter: MyFoodsLibraryFilter
    ) -> [String] {
        MyFoodsLibraryRules.visibleEntries(
            entries,
            query: "",
            filter: filter,
            sort: .name
        ).map(\.id)
    }

    private func food(
        id: String,
        name: String,
        serving: String = "1 serving (100 g)",
        fats: Double = 4,
        saturatedFat: Double? = 1,
        barcode: String? = nil,
        sourceType: FoodSourceType = .custom,
        reviewStatus: FoodReviewStatus = .userConfirmed
    ) -> FoodItem {
        FoodItem(
            id: id,
            name: name,
            calories: 180,
            protein: 20,
            carbs: 16,
            fats: fats,
            saturatedFat: saturatedFat,
            fiber: 3,
            servingSize: serving,
            servingWeight: 100,
            sourceMetadata: FoodSourceMetadata(
                sourceType: sourceType,
                confidence: .userVerified,
                reviewStatus: reviewStatus,
                sourceName: "My Foods",
                sourceID: id,
                barcode: barcode,
                matchedFoodID: id
            )
        )
    }
}
