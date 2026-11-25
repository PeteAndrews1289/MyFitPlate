import XCTest
@testable import MyFitPlateCore

@MainActor
final class RecipeIntegrityTests: XCTestCase {
    private let legacyJSON = #"{"id":"legacy","name":"Imported soup","ingredients":["400 g beans","2 cups broth"],"instructions":["Simmer"],"nutrition":{"calories":600,"protein":24,"carbs":80,"fats":12,"sodium":900},"servings":4}"#

    private func ingredient(_ name: String, calories: Double, grams: Double) -> FoodItem {
        FoodItem(id: UUID().uuidString, name: name, calories: calories, protein: 8,
                 servingSize: "\(grams) g", servingWeight: grams,
                 sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: name), calcium: 100)
    }

    func testLegacyDecodeAndRoundTripNeverReinterpretUnusedYield() throws {
        let recipe = try JSONDecoder().decode(Recipe.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(recipe.nutritionBasis)
        XCTAssertNil(recipe.nutritionOrigin)
        XCTAssertEqual(recipe.servings, 4)
        XCTAssertEqual(recipe.nutritionPerPortion.calories, 600)
        XCTAssertEqual(recipe.foodItemForLogging().calories, 600)
        XCTAssertEqual(recipe.foodItemForLogging().sodium, 900)
        XCTAssertEqual(recipe.foodItemForLogging().sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(recipe.unresolvedIngredientTexts, recipe.ingredients)
        let decoded = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
        XCTAssertEqual(decoded, recipe)
        XCTAssertEqual(MealPlanEditingRules.ingredients(for: decoded), recipe.ingredients)
    }

    func testAddingIngredientToImportKeepsOriginalNutritionAndUnresolvedText() throws {
        let original = try JSONDecoder().decode(Recipe.self, from: Data(legacyJSON.utf8))
        var edit = RecipeEditingState(recipe: original)
        XCTAssertTrue(edit.ingredients.isEmpty, "Unresolved ingredients must not become zero-nutrition foods")
        edit.ingredients.append(ingredient("Oil", calories: 100, grams: 12))
        let saved = try edit.makeRecipe(name: "Soup with oil", instructions: original.instructions)
        XCTAssertEqual(saved.nutrition, original.nutrition)
        XCTAssertEqual(saved.unresolvedIngredientTexts, original.ingredients)
        XCTAssertNil(saved.detailedIngredients, "Older readers must not mistake a partial list for the complete recipe")
        XCTAssertEqual(saved.linkedIngredients?.count, 1)
        XCTAssertEqual(saved.nutritionNeedsReview, true)
        XCTAssertFalse(saved.hasCompleteIngredientNutrition)
        XCTAssertEqual(RecipeEditingState(recipe: saved).nutrition, original.nutrition)
        XCTAssertEqual(original.nutrition.calories, 600)
        XCTAssertEqual(MealPlanEditingRules.ingredients(for: saved).count, 3, "Planning must retain both unlinked originals and the new food")
    }

    func testExplicitRecalculationRequiresEveryIncludedIngredientResolved() throws {
        let original = try JSONDecoder().decode(Recipe.self, from: Data(legacyJSON.utf8))
        var edit = RecipeEditingState(recipe: original)
        edit.ingredients = [ingredient("Oil", calories: 100, grams: 12)]
        edit.nutritionChoice = .recalculate
        XCTAssertThrowsError(try edit.makeRecipe(name: "Soup", instructions: ["Cook"]))
        edit.unresolvedIngredients = [] // User explicitly matches/removes every unresolved ingredient.
        edit.ingredients.append(ingredient("Beans", calories: 700, grams: 400))
        edit.servings = 4
        let recalculated = try edit.makeRecipe(name: "Soup", instructions: ["Cook"])
        XCTAssertEqual(recalculated.nutrition.calories, 800)
        XCTAssertEqual(recalculated.nutritionPerPortion.calories, 200)
        XCTAssertEqual(recalculated.nutritionBasis, .wholeRecipe)
        XCTAssertTrue(recalculated.hasCompleteIngredientNutrition)
        XCTAssertEqual(recalculated.nutritionOrigin, .ingredients)
        XCTAssertNotEqual(recalculated.foodItemForLogging().sourceMetadata?.confidence, .userVerified)
    }

    func testFourServingRecipeScalesAllNutrientsAndPlanningIngredientsOnce() throws {
        var edit = RecipeEditingState()
        edit.ingredients = [ingredient("Beans", calories: 800, grams: 400)]
        edit.servings = 4
        let recipe = try edit.makeRecipe(name: "Beans", instructions: ["Heat"])
        let one = recipe.foodItemForLogging()
        XCTAssertEqual(recipe.nutrition.calories, 800, "Stored batch nutrition must not be rewritten")
        XCTAssertEqual(one.calories, 200)
        XCTAssertEqual(one.calcium, 25)
        XCTAssertNil(one.vitaminD, "Unreported values stay unknown")
        let oneAndHalf = recipe.foodItemForLogging(portions: 1.5)
        XCTAssertEqual(oneAndHalf.calories, 300)
        XCTAssertEqual(oneAndHalf.calcium, 37.5)
        XCTAssertEqual(oneAndHalf.quantityValue, 1.5)
        XCTAssertEqual(MealPlanEditingRules.ingredients(for: recipe), ["100 g Beans"])
        let restored = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
        XCTAssertEqual(restored.nutritionPerPortion, recipe.nutritionPerPortion)
    }

    func testNewAIRecipeHasExplicitWholeRecipeBasisAndKeepsEstimateLineage() throws {
        let json = #"{"name":"Soup","ingredients":["400 g beans"],"instructions":["Heat"],"servings":4,"nutritionBasis":"wholeRecipe","nutrition":{"calories":800,"protein":40,"carbs":120,"fats":8,"sodium":1600}}"#
        let recipe = try RecipeRules.parseRecipeFromAIResponse(json)
        XCTAssertEqual(recipe.nutrition.calories, 800)
        let food = RecipeService().recipeToFoodItem(recipe: recipe)
        XCTAssertEqual(food.calories, 200)
        XCTAssertEqual(food.sodium, 400)
        XCTAssertEqual(food.sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(food.sourceMetadata?.originSourceType, .aiText)
        XCTAssertEqual(food.sourceMetadata?.evidenceLineage, .modelEstimate)
        XCTAssertEqual(food.markedUserConfirmed(sourceType: .recipe).sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(MealPlanEditingRules.ingredients(for: recipe), ["100 gram beans"])
    }

    func testAIRecipeWithoutNewBasisKeepsStoredNutritionAndExplicitInvalidYieldIsRejected() throws {
        let oldResponse = #"{"name":"Soup","ingredients":["Beans"],"instructions":["Heat"],"nutrition":{"calories":800,"protein":40,"carbs":120,"fats":8}}"#
        let recipe = try RecipeRules.parseRecipeFromAIResponse(oldResponse)
        XCTAssertNil(recipe.nutritionBasis)
        XCTAssertEqual(recipe.nutritionPerPortion.calories, 800)
        XCTAssertEqual(recipe.nutritionOrigin, .aiEstimate)
        let invalid = oldResponse.replacingOccurrences(of: "\"name\":", with: "\"servings\":0,\"nutritionBasis\":\"wholeRecipe\",\"name\":")
        XCTAssertThrowsError(try RecipeRules.parseRecipeFromAIResponse(invalid))
    }

    func testInvalidYieldCannotBeUsedForExplicitRecalculation() {
        var edit = RecipeEditingState()
        edit.ingredients = [ingredient("Beans", calories: 800, grams: 400)]
        for invalid in [0, -1, 101, Double.infinity, Double.nan] {
            edit.servings = invalid
            XCTAssertThrowsError(try edit.makeRecipe(name: "Beans", instructions: ["Heat"]))
        }
    }

    func testKeepingSavedNutritionDoesNotAdoptAnUnconfirmedYield() throws {
        let original = try JSONDecoder().decode(Recipe.self, from: Data(legacyJSON.utf8))
        var edit = RecipeEditingState(recipe: original)
        edit.servings = .nan // A canceled recalculation edit is irrelevant to keep-saved mode.
        let saved = try edit.makeRecipe(name: original.name, instructions: original.instructions)
        XCTAssertEqual(saved.nutrition, original.nutrition)
        XCTAssertNil(saved.nutritionBasis)
        XCTAssertEqual(saved.servings, 4)
        XCTAssertEqual(saved.nutritionPerPortion.calories, 600)
    }

    func testInvalidExplicitBasisCannotBePersistedButLegacyStoredAmountRemainsUnchanged() async throws {
        let auth = MockAuthService(); auth.currentUserID = "recipe-owner"
        let repo = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        let service = RecipeService(); service.activateAccount("recipe-owner")
        var invalid = Recipe(name: "Bad yield", ingredients: [], instructions: [], nutrition: Nutrition(calories: 100), servings: 0, nutritionBasis: .wholeRecipe)
        do { _ = try await service.saveRecipe(invalid, for: "recipe-owner"); XCTFail("Invalid explicit yield must not save") } catch {}
        XCTAssertTrue(repo.savedRecipes.isEmpty)
        invalid.nutritionBasis = nil
        let saved = try await service.saveRecipe(invalid, for: "recipe-owner")
        XCTAssertEqual(saved.nutrition.calories, 100)
        XCTAssertNil(saved.nutritionBasis)
    }

    func testIngredientRecalculationRetainsInferredAIOriginEvenAfterLegacyConfirmation() throws {
        var food = ingredient("Estimated beans", calories: 800, grams: 400)
        food.sourceMetadata = FoodSourceMetadata(sourceType: .aiText, confidence: .userVerified, reviewStatus: .userConfirmed)
        var edit = RecipeEditingState()
        edit.ingredients = [food]
        edit.servings = 4
        let recipe = try edit.makeRecipe(name: "Estimated beans", instructions: ["Heat"])
        XCTAssertEqual(recipe.nutritionOrigin, .aiEstimate)
        XCTAssertEqual(recipe.foodItemForLogging().sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(recipe.foodItemForLogging().sourceMetadata?.evidenceLineage, .modelEstimate)
        XCTAssertEqual(recipe.foodItemForLogging().calories, 200)
    }

    func testRecipeReviewFailureRetainsPayloadAndRestoredRetryIsIdempotent() async throws {
        let auth = MockAuthService(); auth.currentUserID = "recipe-owner"
        let repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recipe-review-\(UUID())")
        let store = EditorDraftStore(directory: folder)
        let logService = DailyLogService(undoStore: store); logService.activateAccount("recipe-owner")
        defer { logService.activateAccount(nil); try? FileManager.default.removeItem(at: folder) }
        let recipe = try RecipeRules.parseRecipeFromAIResponse(#"{"name":"Soup","ingredients":["Beans"],"instructions":["Heat"],"nutrition":{"calories":600,"protein":24,"carbs":80,"fats":12}}"#)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let session = MealReviewSaveSession(items: [recipe.foodItemForLogging()], userID: auth.currentUserID,
            date: date, mealName: "Dinner", source: "recipe", draftScope: "recipe-r1", store: store)
        let pendingID = try XCTUnwrap(session.checkpoint.draft.foods.first?.id)
        XCTAssertNotEqual(pendingID, session.items.first?.id)
        repo.updateLogSuccess = false
        let failed = await save(session, using: logService)
        XCTAssertFalse(failed)
        XCTAssertFalse(session.isAccepted)
        XCTAssertTrue(session.isSubmitted)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertEqual(session.checkpoint.draft.foods.first?.id, pendingID)

        // Simulate an ambiguous response: the exact payload already reached the server.
        repo.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: session.date), date: session.date,
            meals: [Meal(name: "Dinner", foodItems: session.checkpoint.draft.foods)]))
        let freshService = DailyLogService(undoStore: store); freshService.activateAccount("recipe-owner")
        defer { freshService.activateAccount(nil) }
        let restored = MealReviewSaveSession(items: [recipe.foodItemForLogging()], userID: auth.currentUserID,
            date: Date(), mealName: "Breakfast", source: "recipe", draftScope: "recipe-r1", store: store)
        XCTAssertTrue(restored.restoredReview)
        XCTAssertEqual(restored.mealName, "Dinner")
        XCTAssertEqual(restored.date, session.date)
        XCTAssertEqual(restored.checkpoint.draft.foods.first?.id, pendingID)
        repo.updateLogSuccess = true
        let accepted = await save(restored, using: freshService)
        XCTAssertTrue(accepted)
        XCTAssertTrue(restored.isAccepted)
        XCTAssertEqual(repo.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 1)
        XCTAssertEqual(repo.lastUpdatedLog?.meals.flatMap(\.foodItems).first?.sourceMetadata?.confidence, .estimated)
        XCTAssertNil(try store.load(MealReviewCheckpoint.self, userID: "recipe-owner", scope: "recipe-r1"))
    }

    func testRecipeReviewDoubleTapWaitsForActualAcceptance() async throws {
        let auth = MockAuthService(); auth.currentUserID = "recipe-double"
        let repo = MockNutritionRepository(); repo.shouldDeferDailyLogUpdateCompletions = true
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recipe-review-\(UUID())")
        let store = EditorDraftStore(directory: folder)
        let service = DailyLogService(undoStore: store); service.activateAccount("recipe-double")
        defer { service.activateAccount(nil); try? FileManager.default.removeItem(at: folder) }
        let session = MealReviewSaveSession(items: [ingredient("Beans", calories: 200, grams: 100)],
            userID: auth.currentUserID, date: Date(), mealName: "Lunch", source: "recipe", store: store)
        var acceptedCount = 0
        session.save(using: service) { if $0 { acceptedCount += 1 } }
        session.save(using: service) { if $0 { acceptedCount += 1 } }
        XCTAssertTrue(session.isSaving)
        XCTAssertFalse(session.isAccepted)
        XCTAssertEqual(acceptedCount, 0)
        for _ in 0..<100 where repo.deferredDailyLogUpdateCompletions.isEmpty { await Task.yield() }
        XCTAssertEqual(repo.deferredDailyLogUpdateCompletions.count, 1)
        repo.deferredDailyLogUpdateCompletions.first?(true)
        for _ in 0..<100 where !session.isAccepted { await Task.yield() }
        XCTAssertTrue(session.isAccepted)
        XCTAssertEqual(acceptedCount, 1)
    }

    private func save(_ session: MealReviewSaveSession, using service: DailyLogService) async -> Bool {
        await withCheckedContinuation { continuation in
            session.save(using: service) { continuation.resume(returning: $0) }
        }
    }
}
