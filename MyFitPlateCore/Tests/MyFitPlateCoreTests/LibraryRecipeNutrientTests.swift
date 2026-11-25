import XCTest
@testable import MyFitPlateCore

@MainActor
final class LibraryRecipeNutrientTests: XCTestCase {
    private func food(id: String = "beans", calories: Double = 2_000, grams: Double = 400) -> FoodItem {
        FoodItem(id: id, name: "Beans", calories: calories, protein: 80, carbs: 300, fats: 40,
            fiber: 20, servingSize: "\(grams) g", servingWeight: grams,
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "beans"),
            calcium: 800, sodium: 2_000, quantityValue: grams, servingUnit: "g")
    }
    private func recipe(id: String = "r") -> Recipe {
        Recipe(id: id, name: "Bean pot", ingredients: ["400 g Beans"], detailedIngredients: [food()],
            instructions: ["Simmer the beans."], nutrition: Nutrition(calories: 2_000, protein: 80, carbs: 300, fats: 40),
            servings: 4, nutritionBasis: .wholeRecipe, nutritionOrigin: .ingredients, unresolvedIngredients: [],
            cookedWeightGrams: 800, ingredientBasis: .wholeRecipe)
    }
    private func store() -> (EditorDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (EditorDraftStore(directory: directory), directory)
    }

    func testNeutralMetadataDecodesDefaultsAndDoesNotChangeSourceRevision() throws {
        let metadata = try JSONDecoder().decode(RecipeLibraryMetadata.self, from: Data(#"{"unknownFutureField":"retained by server"}"#.utf8))
        XCTAssertFalse(metadata.favorite); XCTAssertEqual(metadata.tags, []); XCTAssertTrue(metadata.isNeutral)
        let original = recipe(); var organized = original
        organized.libraryMetadata = metadata
        XCTAssertEqual(try RecipeLibraryMutation.snapshotFingerprint(original), try RecipeLibraryMutation.snapshotFingerprint(organized))
        organized.libraryMetadata = RecipeLibraryMetadata(favorite: true, tags: ["Lunch"])
        XCTAssertEqual(try RecipePortionRules.revisionID(for: original), try RecipePortionRules.revisionID(for: organized))
        XCTAssertNotEqual(try RecipeLibraryMutation.snapshotFingerprint(original), try RecipeLibraryMutation.snapshotFingerprint(organized))
    }

    func testArchiveRestoreNeverChangesFrozenLogsOrSourceContent() throws {
        let original = recipe()
        let logged = try RecipePortionRules.foodItem(for: original, selection: .init(unit: .servings, amount: 1.5))
        let mutation = try RecipeLibraryRules.updating(original, metadata: RecipeLibraryMetadata(archivedAt: Date()), title: "Archive recipe")
        let archived = try mutation.applying(to: [original])
        XCTAssertFalse(RecipeLibraryRules.isVisible(archived[0]))
        XCTAssertEqual(logged.calories, 750)
        XCTAssertEqual(logged.recipePortionSnapshot?.sourceNutrition.calories, 2_000)
        XCTAssertEqual(try mutation.inverse().applying(to: archived), [original])
    }

    func testRecipeMergeKeepsChosenContentAndRejectsStaleMetadata() throws {
        let first = recipe(id: "a"); var second = recipe(id: "b")
        second.libraryMetadata = RecipeLibraryMetadata(favorite: true, tags: ["Batch"])
        let merged = try RecipeLibraryRules.merging([first, second], keeping: "a")
        let result = try merged.applying(to: [first, second])
        XCTAssertTrue(result[0].libraryMetadata?.favorite == true)
        XCTAssertEqual(result[1].libraryMetadata?.mergedIntoRecipeID, "a")
        XCTAssertEqual(RecipeLibraryRules.resolvedRecipe(id: "b", in: result)?.id, "a")
        XCTAssertEqual(result[1].detailedIngredients, second.detailedIngredients)
        var changed = second; changed.libraryMetadata?.tags = ["Changed elsewhere"]
        XCTAssertThrowsError(try merged.applying(to: [first, changed]))
        XCTAssertEqual(try merged.inverse().applying(to: result), [first, second])
    }

    func testRecipeMetadataMutationCannotChangeNutritionOrWriteOversizedPayload() {
        let original = recipe(); var changed = original; changed.nutrition.calories = 1
        XCTAssertThrowsError(try RecipeLibraryMutation(title: "Organize", before: [original], after: [changed]).validate())
        let long = Recipe(id: "long", name: "Long", ingredients: [String(repeating: "x", count: 350_000)], instructions: ["Cook"], nutrition: .zero)
        XCTAssertThrowsError(try RecipeLibraryMutation(title: "Organize", before: [long], after: [long]).validate())
    }

    func testLibrarySearchFindsTagsIngredientsAndRetainedSourceAcross1000Recipes() {
        var recipes = (0..<1_000).map { recipe(id: "recipe-\($0)") }
        recipes[714].libraryMetadata = RecipeLibraryMetadata(tags: ["Picnic"])
        recipes[714].importProvenance = RecipeImportProvenance(kind: .url, sourceURL: "https://example.com/special", originalText: "Retained publisher text")
        recipes[100].libraryMetadata = RecipeLibraryMetadata(archivedAt: Date())
        XCTAssertEqual(RecipeLibraryRules.filtered(recipes, query: "picnic").map(\.id), ["recipe-714"])
        XCTAssertEqual(RecipeLibraryRules.filtered(recipes, query: "publisher").map(\.id), ["recipe-714"])
        XCTAssertEqual(RecipeLibraryRules.filtered(recipes, query: "beans").count, 999)
        XCTAssertEqual(RecipeLibraryRules.filtered(recipes, filter: .archived).count, 1)
    }

    func testMergeBarcodesRemainDistinctAndSharedAssociationFollowsKeeperWithoutTrustUpgrade() throws {
        var first = food(id: "a"), second = food(id: "b")
        first.sourceMetadata?.barcode = "123456789012"; second.sourceMetadata?.barcode = "123456789013"
        XCTAssertThrowsError(try SavedFoodLibraryMutation.merge([first, second], keeping: "a"))
        first.sourceMetadata?.barcode = nil
        let mutation = try SavedFoodLibraryMutation.merge([first, second], keeping: "a")
        let result = try mutation.applying(to: [first, second])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sourceMetadata?.barcode, "123456789013")
        XCTAssertEqual(result[0].sourceMetadata?.confidence, first.sourceMetadata?.confidence)
        XCTAssertEqual(try mutation.inverse().applying(to: result), [first, second])
    }

    func testDuplicateClassificationKeepsBrandAndCorrectionVersionsVisible() {
        var first = food(id: "a"), second = food(id: "b")
        XCTAssertTrue(MyFoodsLibraryRules.areExactDuplicates([first, second]))
        second.sourceMetadata?.brandName = "Another brand"
        XCTAssertFalse(MyFoodsLibraryRules.areExactDuplicates([first, second]))
        second = first; second.id = "b"; second.sourceMetadata?.sourceUpdatedAt = Date()
        XCTAssertFalse(MyFoodsLibraryRules.areExactDuplicates([first, second]))
        first.sourceMetadata?.barcode = "123456789012"; second.sourceMetadata?.barcode = "123456789013"
        let entries = MyFoodsLibraryRules.entries(savedFoods: [first, second], recentFoods: [])
        XCTAssertEqual(MyFoodsLibraryRules.reviewGroups(from: entries).count, 1)
        XCTAssertTrue(MyFoodsLibraryRules.duplicateGroups(from: entries).isEmpty)
    }

    func testSavedFoodInverseProtectsLaterEditsAndPreservesUnrelatedNewFood() throws {
        let first = food(id: "a"), second = food(id: "b"), other = food(id: "unrelated")
        let mutation = try SavedFoodLibraryMutation.merge([first, second], keeping: "a")
        let merged = try mutation.applying(to: [first, second, other])
        XCTAssertEqual(try mutation.inverse().applying(to: merged).count, 3)
        var edited = merged; edited[0].calories += 1
        XCTAssertThrowsError(try mutation.inverse().applying(to: edited))
    }

    func testAcknowledgementLossResolvesOnceAndHistoryRebuildsAfterReinstall() async throws {
        let previousAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "library-owner"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previousAuth }
        let repository = MockNutritionRepository(); repository.mockRecipes = [recipe()]
        repository.libraryMutationFailureAfterCommit = LibraryMutationError.unavailable
        let (drafts, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let mutation = try RecipeLibraryRules.updating(recipe(), metadata: RecipeLibraryMetadata(favorite: true), title: "Favorite")
        let session = LibraryMutationSession(userID: auth.currentUserID, store: drafts)
        XCTAssertTrue(session.prepare(.recipes(mutation))); await session.submit(using: repository)
        XCTAssertNotNil(session.pending)
        let recovered = LibraryMutationSession(userID: auth.currentUserID, store: drafts)
        await recovered.resolve(using: repository, cancelPending: false)
        XCTAssertNil(recovered.pending); XCTAssertEqual(recovered.checkpoint.history.count, 1)
        let (freshStore, freshDirectory) = store(); defer { try? FileManager.default.removeItem(at: freshDirectory) }
        let reinstall = LibraryMutationSession(userID: auth.currentUserID, store: freshStore)
        await reinstall.loadHistory(using: repository)
        XCTAssertEqual(reinstall.checkpoint.history.count, 1)
        XCTAssertNil(reinstall.checkpoint.history[0].acceptedAt, "Do not invent a receipt date when the discovery API returns commands only")
        XCTAssertTrue(reinstall.undo(reinstall.checkpoint.history[0]))
        repository.libraryMutationFailureAfterCommit = nil
        await reinstall.submit(using: repository)
        XCTAssertNil(repository.mockRecipes[0].libraryMetadata)
        XCTAssertNotNil(reinstall.checkpoint.history.first(where: { $0.id == mutation.id })?.undoneBy)
    }

    func testCancelledLibraryMutationHasPermanentFenceAndDoesNotChangeRecords() async throws {
        let repository = MockNutritionRepository(); let original = recipe(); repository.mockRecipes = [original]
        let mutation = try RecipeLibraryRules.updating(original, metadata: RecipeLibraryMetadata(favorite: true), title: "Favorite")
        let pending = try await repository.resolveRecipeLibraryMutation(userID: "u", mutation: mutation, cancelPending: false)
        let cancelled = try await repository.resolveRecipeLibraryMutation(userID: "u", mutation: mutation, cancelPending: true)
        XCTAssertEqual(pending, .pending); XCTAssertEqual(cancelled, .cancelled)
        do { try await repository.applyRecipeLibraryMutation(userID: "u", mutation: mutation); XCTFail("Cancelled proposal must stay cancelled") } catch {}
        XCTAssertEqual(repository.mockRecipes, [original])
    }

    func testStaleDeviceSessionCannotOverwriteNewPendingLibraryWork() throws {
        let previous = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "owner"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previous }
        let (drafts, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = LibraryMutationSession(userID: "owner", store: drafts)
        let stale = LibraryMutationSession(userID: "owner", store: drafts)
        let one = try RecipeLibraryRules.updating(recipe(id: "one"), metadata: RecipeLibraryMetadata(favorite: true), title: "One")
        let two = try RecipeLibraryRules.updating(recipe(id: "two"), metadata: RecipeLibraryMetadata(favorite: true), title: "Two")
        XCTAssertTrue(first.prepare(.recipes(one))); XCTAssertFalse(stale.prepare(.recipes(two)))
        let recovered = LibraryMutationSession(userID: "owner", store: drafts)
        XCTAssertEqual(recovered.checkpoint.queue.map(\.id), [one.id])
        auth.currentUserID = "another"
        XCTAssertFalse(recovered.prepare(.recipes(two)))
    }

    func testInstructionRegenerationChangesOnlyReviewedComponentAndRejectsNewIngredient() throws {
        let original = recipe()
        let proposal = Recipe(name: "Invented title discarded", ingredients: RecipePortionRules.originalIngredientLines(for: original),
            instructions: ["Cover and simmer the beans."], nutrition: Nutrition(calories: 1))
        let result = try RecipeComponentRules.applying(.instructions, from: proposal, to: original)
        XCTAssertEqual(result.name, original.name); XCTAssertEqual(result.nutrition, original.nutrition)
        XCTAssertEqual(result.detailedIngredients, original.detailedIngredients); XCTAssertEqual(result.servings, original.servings)
        XCTAssertEqual(result.instructions, proposal.instructions)
        XCTAssertEqual(result.importProvenance?.componentRevisions?.last?.component, "instructions")
        let changed = Recipe(name: "Beans", ingredients: ["Add butter"], instructions: ["Fry in butter"], nutrition: .zero)
        XCTAssertThrowsError(try RecipeComponentRules.applying(.instructions, from: changed, to: original))
    }

    func testGroundedRecalculationCannotUsePartialIngredientsOrInventAIOrigin() throws {
        let result = try RecipeComponentRules.applying(.ingredientNutrition, from: nil, to: recipe())
        XCTAssertNil(result.importProvenance); XCTAssertEqual(result.nutritionOrigin, .ingredients)
        var incomplete = recipe(); incomplete.unresolvedIngredients = ["Oil to taste"]
        XCTAssertThrowsError(try RecipeComponentRules.applying(.ingredientNutrition, from: nil, to: incomplete))
    }

    func testAdjustedLoggedRecipeRecoversRawAmountsAndCreatesIndependentVariation() throws {
        let source = recipe()
        let adjusted = try XCTUnwrap(RecipeIngredientQuantityRules.adjustedIngredient(food(), newQuantity: 600))
        let logged = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .servings, amount: 1.5),
            finalNutritionOverride: Nutrition.total(for: [adjusted]).scaled(by: 1.5 / 4),
            ingredientsAdjusted: true, adjustedIngredientFoods: [adjusted])
        let repeated = try XCTUnwrap(FoodRepeatRules.adjusting(logged, by: 2))
        XCTAssertEqual(repeated.recipePortionSnapshot?.adjustedIngredientFoods?.first?.servingWeight, 600)
        let restored = try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(repeated))
        let variation = try RecipeVariationRules.variation(from: restored)
        XCTAssertNil(variation.id); XCTAssertNil(variation.cookedWeightGrams); XCTAssertNil(variation.libraryMetadata)
        XCTAssertEqual(variation.servings, 4); XCTAssertEqual(variation.nutritionPerPortion.calories, 750)
        XCTAssertEqual(variation.instructions, source.instructions)
        XCTAssertEqual(logged.calories, 1_125); XCTAssertEqual(repeated.calories, 2_250)
        XCTAssertEqual(source.nutrition.calories, 2_000)
    }

    func testLegacyLogWithoutRetainedAdjustedAmountsCannotInventVariation() throws {
        let logged = try RecipePortionRules.foodItem(for: recipe(), selection: .init(unit: .servings))
        XCTAssertThrowsError(try RecipeVariationRules.variation(from: logged))
    }

    func testNutrientEvidenceSeparatesUnknownZeroPartialAndCompleteWithoutChangingFoods() {
        var zero = food(id: "zero"); zero.vitaminD = 0
        let unknown = food(id: "unknown")
        let log = DailyLog(date: Date(), meals: [Meal(name: "Dinner", foodItems: [zero, unknown])])
        let vitamin = DailyNutrientDashboardRules.evidence(for: .vitaminD, log: log)
        XCTAssertEqual(vitamin.amount, 0); XCTAssertEqual(vitamin.coverage.reportedFoodCount, 1)
        XCTAssertFalse(vitamin.coverage.isComplete); XCTAssertTrue(vitamin.coverageDescription.contains("Partial"))
        let sodium = DailyNutrientDashboardRules.evidence(for: .sodium, log: log)
        XCTAssertEqual(sodium.amount, 4_000); XCTAssertTrue(sodium.coverage.isComplete)
        XCTAssertTrue(sodium.exceedsLimit(2_300)); XCTAssertFalse(vitamin.exceedsLimit(20))
        let missing = DailyNutrientDashboardRules.evidence(for: .vitaminK, log: log)
        XCTAssertNil(missing.amount); XCTAssertFalse(missing.coverage.hasReportedData)
        let empty = DailyNutrientDashboardRules.evidence(for: .sodium, log: DailyLog(date: Date(), meals: []))
        XCTAssertNil(empty.amount); XCTAssertEqual(empty.coverage.totalFoodCount, 0)
    }

    func testContributorsRetainExactHistoricalMealAndFoodIdentity() {
        var first = food(id: "shared"); first.sodium = 300
        var second = first; second.sodium = 700
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let log = DailyLog(date: date, meals: [Meal(name: "Breakfast", foodItems: [first]), Meal(name: "Dinner", foodItems: [second])])
        let evidence = DailyNutrientDashboardRules.evidence(for: .sodium, log: log)
        XCTAssertEqual(evidence.contributions.map(\.mealName), ["Dinner", "Breakfast"])
        XCTAssertEqual(Set(evidence.contributions.map(\.id)).count, 2)
        XCTAssertEqual(evidence.contributions.first?.food.sodium, 700)
        XCTAssertEqual(log.date, date)
    }

    func testNutrientPinsPersistAndCannotCrossAccounts() throws {
        let previous = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "pins-owner"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previous }
        let (drafts, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let pins = NutrientDashboardPinStore(userID: "pins-owner", store: drafts)
        try pins.save([.calcium, .sodium]); XCTAssertEqual(try pins.pins(), [.calcium, .sodium])
        auth.currentUserID = "another"; XCTAssertThrowsError(try pins.save([.vitaminD]))
        XCTAssertEqual(try NutrientDashboardPinStore(userID: "another", store: drafts).pins(), [.fiber, .sodium, .potassium, .vitaminD])
    }

    func testPartialCompositeAndDerivedRecipeDoNotBecomeFullyReportedAggregate() throws {
        var known = food(id: "known", calories: 100, grams: 100); known.vitaminD = 10
        let unknown = food(id: "unknown", calories: 100, grams: 100)
        var composite = FoodItem(id: "composite", name: "Meal", calories: 200, vitaminD: 10)
        composite.mealComposition = MealCompositionSnapshot(title: "Meal", components: [known, unknown])
        let combined = DailyNutrientDashboardRules.evidence(for: .vitaminD,
            log: DailyLog(date: Date(), meals: [Meal(name: "Lunch", foodItems: [composite])]))
        XCTAssertEqual(combined.amount, 10); XCTAssertFalse(combined.coverage.isComplete)
        XCTAssertTrue(combined.coverageDescription.contains("Partial derived"))
        let source = Recipe(name: "Batch", ingredients: ["Known", "Unknown"], detailedIngredients: [known, unknown],
            instructions: ["Cook"], nutrition: Nutrition.total(for: [known, unknown]), servings: 4,
            nutritionBasis: .wholeRecipe, nutritionOrigin: .ingredients, unresolvedIngredients: [], ingredientBasis: .wholeRecipe)
        let portion = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .servings))
        let recipeEvidence = DailyNutrientDashboardRules.evidence(for: .vitaminD,
            log: DailyLog(date: Date(), meals: [Meal(name: "Dinner", foodItems: [portion])]))
        XCTAssertEqual(recipeEvidence.amount, 2.5); XCTAssertFalse(recipeEvidence.coverage.isComplete)
        XCTAssertNotNil(recipeEvidence.contributions[0].reportingNote)
        let reported = FoodItem(id: "label", name: "Published product", calories: 100, vitaminD: 2.5)
        XCTAssertTrue(DailyNutrientDashboardRules.evidence(for: .vitaminD,
            log: DailyLog(date: Date(), meals: [Meal(name: "Dinner", foodItems: [reported])])).coverage.isComplete)
    }
}
