import XCTest
@testable import MyFitPlateCore

@MainActor
final class RestaurantBuffetDepthTests: XCTestCase {
    private func food(_ id: String, protein: Double = 30, calories: Double = 400) -> FoodItem {
        FoodItem(id: id, name: id, calories: calories, protein: protein, carbs: 20, fats: 10, servingSize: "1 plate")
    }
    private func item(_ id: String = "salmon", cuisine: AYCECuisine = .sushi, calories: Double = 100) -> AYCECatalogItem {
        AYCECatalogItem(id: id, cuisine: cuisine, name: id, emoji: "", unit: "piece", calories: calories,
            protein: 10, carbs: 2, fats: 5, restaurantPrice: 0, homeCost: 0)
    }
    private func session() -> AYCESession {
        AYCEStableRoundRules.migrated(AYCESession(cuisine: .sushi, buffetPrice: 0))
    }
    func testBundledCatalogPackageHasUniqueStableIDsAndHonestEvidence() throws {
        let package = RestaurantCatalogPackage.bundled(); try package.validate()
        XCTAssertGreaterThan(package.items.count, 100)
        XCTAssertTrue(package.items.allSatisfy { $0.evidence.publicationDate == nil && $0.evidence.market == "US reference menu" })
        let restored = try JSONDecoder().decode(RestaurantCatalogPackage.self, from: JSONEncoder().encode(package))
        XCTAssertEqual(restored, package)
        var invalid = package; invalid.items.append(package.items[0]); XCTAssertThrowsError(try package.replacing(with: invalid))
        XCTAssertEqual(package.version, ChainRestaurantCatalog.catalogVersion)
    }
    func testCollapsedChainOrderRetainsExactComponentNutritionAndUnknownSodium() throws {
        let first = ChainIngredient(id: "a", name: "A", servingDescription: "1 scoop", calories: 100, protein: 10, carbs: 5, fat: 1, sodium: 30)
        let second = ChainIngredient(id: "b", name: "B", servingDescription: "1 scoop", calories: 200, protein: 20, carbs: 10, fat: 2)
        let chain = ChainRestaurant(id: "test", name: "Test", subtitle: "", iconName: "", brandColorHex: "000000",
            categories: [ChainCategory(id: "main", title: "Main", ingredients: [first, second])])
        let order = chain.customMealFoodItem(from: ["a": ChainSelectionItem(id: "a", ingredient: first, portion: .light),
            "b": ChainSelectionItem(id: "b", ingredient: second, portion: .double)], id: "meal")
        XCTAssertEqual(order.calories, 450); XCTAssertEqual(order.mealComposition?.components.count, 2)
        XCTAssertEqual(order.mealComposition?.components.reduce(0) { $0 + $1.calories }, order.calories)
        XCTAssertNil(order.sodium)
    }
    func testSavedOrderChangedAndRemovedComponentsRequireReviewAndDoNotRewriteSnapshot() {
        let chain = ChainRestaurantCatalog.allChains[0]; let ingredient = chain.categories[0].ingredients[0]
        let saved = SavedRestaurantOrder(name: "Favorite", chain: chain, components: [ChainSelectionItem(id: ingredient.id, ingredient: ingredient)], mealName: "Lunch")
        let noItems = ChainRestaurant(id: chain.id, name: chain.name, subtitle: "", iconName: "", brandColorHex: "000000", categories: [])
        XCTAssertEqual(saved.catalogChanges(in: noItems).count, 1)
        XCTAssertEqual(saved.components[0].ingredient, ingredient)
    }
    func testOrderWorkspaceCASAndAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = EditorDraftStore(directory: directory), store = RestaurantOrderStore(userID: "a", drafts: drafts)
        let original = try store.load(); var updated = original; updated.favoriteChainIDs = ["chipotle"]
        try store.save(updated, replacing: original)
        XCTAssertThrowsError(try store.save(original, replacing: original))
        XCTAssertTrue(try RestaurantOrderStore(userID: "b", drafts: drafts).load().favoriteChainIDs.isEmpty)
    }
    func testRankingRejectsUnreviewedZeroAndMixedCurrencyAndChangesDeterministically() {
        var comparison = RestaurantComparison()
        comparison.rows = [RestaurantComparisonRow(food: food("A"), listedPrice: 10, priceConfirmed: true),
            RestaurantComparisonRow(food: food("B", protein: 40), listedPrice: 5, priceConfirmed: true),
            RestaurantComparisonRow(food: food("C", protein: 200), listedPrice: 1, currency: "EUR", priceConfirmed: true),
            RestaurantComparisonRow(food: food("D", protein: 300), listedPrice: 0, priceConfirmed: true)]
        XCTAssertEqual(comparison.ranked(currency: "USD").first?.id, "B")
        comparison.rows[1].listedPrice = 50
        XCTAssertEqual(comparison.ranked(currency: "USD").first?.id, "A")
        comparison.rows[0].priceConfirmed = false
        XCTAssertEqual(comparison.ranked(currency: "USD").first?.id, "B")
        XCTAssertNil(comparison.rows[3].validPrice)
    }
    func testCalorieBudgetAndBalancedPreferencesUseCorrectedServing() {
        var comparison = RestaurantComparison()
        comparison.rows = [RestaurantComparisonRow(food: food("large", protein: 80, calories: 1200), listedPrice: 10, priceConfirmed: true),
            RestaurantComparisonRow(food: food("small", protein: 30, calories: 300), listedPrice: 10, priceConfirmed: true)]
        comparison.objective = .calorieBudget; comparison.calorieBudget = 600
        XCTAssertEqual(comparison.ranked(currency: "USD").first?.id, "small")
        comparison.objective = .proteinValue
        XCTAssertEqual(comparison.ranked(currency: "USD").first?.id, "large")
    }
    func testStableRoundRepeatCreatesNewInstancesAndDuplicateOperationDoesNothing() throws {
        let added = try XCTUnwrap(AYCEStableRoundRules.changeQuantity(2, item: item(), in: session()))
        let finished = try XCTUnwrap(AYCEStableRoundRules.finishing(added))
        let round = try XCTUnwrap(AYCEStableRoundRules.completed(finished).last)
        let repeated = try XCTUnwrap(AYCEStableRoundRules.repeating(round, in: finished, operationID: "repeat"))
        XCTAssertEqual(repeated.entries.reduce(0) { $0 + $1.count }, 4)
        XCTAssertEqual(Set(repeated.entries.map(\.id)).count, 2)
        XCTAssertNil(AYCEStableRoundRules.repeating(round, in: repeated, operationID: "repeat"))
        let restored = try JSONDecoder().decode(AYCESession.self, from: JSONEncoder().encode(repeated))
        XCTAssertEqual(restored.rounds, repeated.rounds); XCTAssertEqual(restored.roundEdits, repeated.roundEdits)
    }
    func testHistoricalRoundCorrectionInvalidatesOldReviewWithoutCompounding() throws {
        let added = try XCTUnwrap(AYCEStableRoundRules.changeQuantity(2, item: item(), in: session()))
        let finished = try XCTUnwrap(AYCEStableRoundRules.finishing(added))
        let round = try XCTUnwrap(AYCEStableRoundRules.completed(finished).last)
        var entries = round.entries; entries[0].count = 0.5
        let corrected = try XCTUnwrap(AYCEStableRoundRules.replacing(round, with: entries, in: finished))
        XCTAssertEqual(corrected.entries.reduce(0) { $0 + $1.calories }, 50)
        XCTAssertNil(AYCEStableRoundRules.repeating(round, in: corrected, operationID: "stale"))
        XCTAssertNil(AYCEStableRoundRules.replacing(round, with: entries, in: corrected))
    }
    func testDurableUndoPreservesUnrelatedLaterAdditionsAndRejectsChangedAffectedFood() throws {
        let added = try XCTUnwrap(AYCEStableRoundRules.changeQuantity(2, item: item(), in: session()))
        let edit = try XCTUnwrap(added.roundEdits?.last)
        let other = try XCTUnwrap(AYCEStableRoundRules.changeQuantity(1, item: item("beef", cuisine: .kbbq), in: added))
        let decoded = try JSONDecoder().decode(AYCESession.self, from: JSONEncoder().encode(other))
        let undone = try XCTUnwrap(AYCEStableRoundRules.undo(edit, in: decoded))
        XCTAssertEqual(undone.entries.map(\.item.id), ["beef"])
        XCTAssertNil(AYCEStableRoundRules.undo(edit, in: undone))
        let changed = try XCTUnwrap(AYCEStableRoundRules.changeQuantity(3, item: item(), in: added))
        XCTAssertNil(AYCEStableRoundRules.undo(edit, in: changed))
    }
    func testNewCutSnapshotCannotRewriteAnEarlierRoundAndMixedCuisineIsPermitted() throws {
        let added = try XCTUnwrap(AYCEStableRoundRules.changeQuantity(1, item: item(), in: session()))
        let finished = try XCTUnwrap(AYCEStableRoundRules.finishing(added))
        let changed = try XCTUnwrap(AYCEStableRoundRules.changeQuantity(2, item: item(calories: 300), in: finished))
        XCTAssertEqual(changed.entries.reduce(0) { $0 + $1.calories }, 400)
        let mixed = try XCTUnwrap(AYCEStableRoundRules.appending([item("beef", cuisine: .kbbq)], in: changed))
        XCTAssertEqual(Set(mixed.entries.map(\.item.cuisine)), [.sushi, .kbbq])
    }
    func testLegacyRoundMigrationPreservesNutritionWithoutInventedTimes() throws {
        var legacy = AYCESession(cuisine: .sushi, buffetPrice: 20,
            entries: [AYCESessionEntry(id: "old", item: item(), count: 3)])
        legacy.roundBaseline = [AYCESessionEntry(id: "old", item: item(), count: 2)]
        let migrated = AYCEStableRoundRules.migrated(legacy)
        XCTAssertEqual(migrated.entries.reduce(0) { $0 + $1.calories }, 300)
        XCTAssertEqual(migrated.rounds?.first?.migrated, true); XCTAssertNil(migrated.rounds?.first?.finishedAt)
        XCTAssertEqual(AYCEStableRoundRules.current(migrated)?.entries.first?.count, 1)
    }
    func testUnpricedReviewedFoodStillLogsNutritionWithoutInventedValue() throws {
        let unpriced = try XCTUnwrap(AYCEPricingRules.reviewedCatalogItem(name: "Sauce", unit: "tbsp", cuisine: .kbbq,
            calories: 30, protein: 1, carbs: 4, fats: 1, restaurantPrice: 0, homeCost: 0, isAIEstimated: false))
        XCTAssertEqual(unpriced.restaurantPrice, 0); XCTAssertEqual(unpriced.homeCost, 0)
        let added = try XCTUnwrap(AYCEStableRoundRules.appending([unpriced], in: session()))
        XCTAssertEqual(AYCERules.totals(for: added).calories, 30)
        XCTAssertEqual(AYCERules.totals(for: added).restaurantValue, 0)
    }
    func testAcceptedCatalogMatchRetainsFrozenSourceOriginalTextAndEstimatedDiaryLineage() throws {
        let source = item("generic-salmon", calories: 100)
        let evidence = AYCECatalogMatchEvidence(item: source, originalText: "photo fish plate", personalAmount: 0.5)
        let reviewed = AYCECatalogItem(id: "reviewed", cuisine: .sushi, name: "My fish", emoji: "", unit: "half piece",
            calories: 50, protein: 5, carbs: 1, fats: 2.5, restaurantPrice: 0, homeCost: 0,
            isLocallyPriced: true, catalogMatch: evidence)
        let restored = try JSONDecoder().decode(AYCECatalogItem.self, from: JSONEncoder().encode(reviewed))
        XCTAssertEqual(restored.catalogMatch, evidence)
        XCTAssertEqual(restored.calories, 50); XCTAssertEqual(restored.catalogMatch?.caloriesPerSourceUnit, 100)
        let diary = AYCERules.foodItem(from: AYCESessionEntry(item: restored, count: 2))
        XCTAssertEqual(diary.calories, 100)
        XCTAssertEqual(diary.sourceMetadata?.sourceType, .chainBuilder)
        XCTAssertEqual(diary.sourceMetadata?.confidence, .estimated)
        XCTAssertTrue(diary.sourceMetadata?.sourceID?.contains("generic-salmon") == true)
        XCTAssertTrue(diary.sourceMetadata?.notes?.contains("photo fish plate") == true)
    }
}
