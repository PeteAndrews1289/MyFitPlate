import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
@testable import MyFitPlate

private final class EmulatorAppCheckProvider: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3600)), nil)
    }
}

private final class EmulatorAppCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("diary-test-") ? EmulatorAppCheckProvider() : nil
    }
}

/// Opt in with MYFITPLATE_EMULATOR_TESTS=YES while the local Auth and Firestore emulators run.
/// Named apps have a synthetic project and fake key; these tests cannot use production data.
final class DiaryPersistenceIntegrationTests: XCTestCase {
    func testWholeDayReviewRejectsConcurrentIntakeAndReplayKeepsChangedEvidenceUnknown() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        let day = try XCTUnwrap(DiaryDayContext(userID: uid, date: date))
        let ref = client.db.collection("users").document(uid).collection("dailyLogs").document(day.dayKey)
        let original = DailyLog(id: day.dayKey, date: date, meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "review-food", name: "Rice", calories: 200)])])
        var raw = try Firestore.Encoder().encode(original); raw["futureField"] = "keep"
        try await ref.setData(raw)
        func proposal(_ log: DailyLog, operation: String) throws -> DailyLog {
            var value = log.rememberingMutationBase()
            value.nutritionDayReview = try NutritionDayReview(ownerID: uid, day: day, status: .complete, log: log)
            value.nutritionDayStatus = .complete; value.pendingMutationID = operation
            return value
        }
        func update(_ value: DailyLog) async -> Bool {
            await withCheckedContinuation { continuation in
                client.repository.updateDailyLog(userID: uid, log: value) { continuation.resume(returning: $0) }
            }
        }
        let stale = try proposal(original, operation: "stale-day-review")
        var later = original; later.meals[0].foodItems.append(FoodItem(id: "later-food", name: "Fruit", calories: 100))
        try await ref.updateData(["meals": try Firestore.Encoder().encode(later)["meals"]!])
        let rejected = await update(stale); XCTAssertFalse(rejected)
        let current = try await ref.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertNil(current.nutritionDayReview)
        let fresh = try proposal(current, operation: "accepted-day-review")
        let accepted = await update(fresh); XCTAssertTrue(accepted)
        let saved = try await ref.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertTrue(NutritionDayEvidence.isComplete(saved))
        XCTAssertEqual(saved.nutritionDayReview, fresh.nutritionDayReview)
        var changed = saved; changed.meals[0].foodItems[0].calories = 350
        try await ref.updateData(["meals": try Firestore.Encoder().encode(changed)["meals"]!])
        let replayed = await update(fresh); XCTAssertTrue(replayed)
        let final = try await ref.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(final.meals[0].foodItems[0].calories, 350)
        XCTAssertEqual(NutritionDayEvidence.status(of: final), .unknown)
        XCTAssertEqual(final.appliedMutationIDs?.filter { $0 == "accepted-day-review" }.count, 1)
        let finalRaw = try await ref.getDocument(source: .server).data()
        XCTAssertEqual(finalRaw?["futureField"] as? String, "keep")
    }

    func testAcceptedSkippedPortionQuestionPersistsThroughRealDiaryRepositoryAndServerReload() async throws {
        let client = makeClient(), date = Calendar.current.startOfDay(for: Date())
        let uid = try await client.auth.signInAnonymously().user.uid
        let day = try XCTUnwrap(DiaryDayContext(userID: uid, date: date))
        let reference = client.db.collection("users").document(uid).collection("dailyLogs").document(day.dayKey)
        // Establish the authenticated server baseline before timing the outbox write.
        // The emulator's first Firestore connection can still be starting after Auth is ready.
        let deadline = ContinuousClock.now + .seconds(45)
        while true {
            do {
                let before = try await reference.getDocument(source: .server)
                XCTAssertFalse(before.exists, "The synthetic account should start with an empty diary day.")
                break
            } catch {
                let failure = error as NSError
                guard failure.domain == FirestoreErrorDomain, ContinuousClock.now < deadline,
                      [FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue].contains(failure.code) else { throw error }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        let original = FoodItem(id: "skipped-portion", name: "Rice", calories: 600, protein: 20, carbs: 100, fats: 10, servingWeight: 300)
        let question = try XCTUnwrap(UsefulMealQuestionRules.choose(items: [original], evidence: [
            .init(itemID: original.id, lowGrams: 150, highGrams: 450)
        ], loggedCalories: nil, calorieGuide: nil))
        let skipped = try XCTUnwrap(UsefulMealQuestionRules.preview(answer: .skip, question: question, item: original))
        let diary = DailyLog(id: day.dayKey, date: date, meals: [Meal(name: "Lunch", foodItems: [skipped.food])])
        try await client.repository.saveDailyLog(userID: uid, log: diary)
        try await waitForSync(client, userID: uid)
        let restored = try await reference.getDocument(source: .server).data(as: DailyLog.self)
        let saved = try XCTUnwrap(restored.meals.first?.foodItems.first)
        XCTAssertEqual(saved.id, original.id); XCTAssertEqual(saved.calories, original.calories)
        XCTAssertEqual(saved.servingWeight, original.servingWeight); XCTAssertEqual(saved.sourceMetadata, original.sourceMetadata)
        let receipt = try XCTUnwrap(saved.savedPortionQuestionReceipt)
        XCTAssertEqual(receipt.answer, .skip); XCTAssertEqual(receipt.originalFoodData, receipt.revisedFoodData)
        XCTAssertEqual(try PlanFingerprint.make(receipt.originalFood), try PlanFingerprint.make(original))
    }

    func testWorkoutCorrectionTransactionRejectsConcurrentRevisionAndPreservesItOnCompletionReplay() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let date = Date().addingTimeInterval(-3_600)
        let movement = RoutineExercise(id: "cas-bench", name: "Bench Press", sets: [ExerciseSet(reps: 8, weight: 135)])
        let exercise = CompletedExercise(exerciseName: movement.name, exercise: movement, sets: [CompletedSet(reps: 8, weight: 135)])
        let original = WorkoutSessionLog(id: "cas-session", date: date, routineID: "cas-routine", completedExercises: [exercise],
                                        programContext: WorkoutProgramSessionContext(programID: "preserved-phul", slotIndex: 7))
        let user = client.db.collection("users").document(uid)
        let reference = user.collection("workoutSessionLogs").document("cas-session")
        try await reference.setData(Firestore.Encoder().encode(original))
        let baseline = try await reference.getDocument(source: .server).data(as: WorkoutSessionLog.self)
        let program = WorkoutProgram(id: "preserved-phul", userID: uid, name: "PHUL", currentProgressIndex: 38, skippedIndices: [2, 7])
        try await user.collection("workoutPrograms").document("preserved-phul").setData(Firestore.Encoder().encode(program))
        let repository = FirestoreWorkoutRepository(db: client.db, outboxURL: directories.last!.appendingPathComponent("cas-workouts.json"), currentUserID: { client.auth.currentUser?.uid })
        var first = baseline
        first.correctionRevisionID = "revision-a"
        first.completedExercises[0].sets[0].weight = 145
        try await repository.commitWorkoutCorrection(userID: uid, expected: baseline, updated: first)
        var conflicting = baseline
        conflicting.correctionRevisionID = "revision-b"
        conflicting.completedExercises[0].sets[0].weight = 155
        do {
            try await repository.commitWorkoutCorrection(userID: uid, expected: baseline, updated: conflicting)
            XCTFail("A stale second device must not overwrite the accepted revision")
        } catch { XCTAssertEqual(error as? WorkoutCorrectionError, .conflict) }
        try await repository.commitWorkoutCorrection(userID: uid, expected: baseline, updated: first)
        try await repository.saveWorkoutSessionLog(userID: uid, log: original)
        try await waitForWorkoutSync(repository, userID: uid)
        let saved = try await reference.getDocument(source: .server).data(as: WorkoutSessionLog.self)
        XCTAssertEqual(saved.correctionRevisionID, "revision-a")
        XCTAssertEqual(saved.completedExercises[0].sets[0].weight, 145)
        XCTAssertEqual(saved.programContext, original.programContext)
        let savedProgram = try await user.collection("workoutPrograms").document("preserved-phul").getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(savedProgram.currentProgressIndex, 38)
        XCTAssertEqual(savedProgram.skippedIndices, [2, 7])
    }

    func testWeightTransactionKeepsOneMeasurementAndSeparatesHistoricalProfileUpdates() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let repository = FirestoreSettingsRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        let reference = client.db.collection("users").document(uid)
        try await reference.setData(["weight": 180, "unrelated": "preserve"])
        let now = Date()
        let first = try await repository.saveWeightMeasurement(userID: uid, entryID: "stable-measurement", weight: 179.5, date: now)
        let replay = try await repository.saveWeightMeasurement(userID: uid, entryID: "stable-measurement", weight: 179.5, date: now)
        XCTAssertTrue(first)
        XCTAssertFalse(replay)
        do {
            _ = try await repository.saveWeightMeasurement(userID: uid, entryID: "stable-measurement", weight: 170, date: now)
            XCTFail("A reused measurement ID cannot overwrite another value")
        } catch { }
        _ = try await repository.saveWeightMeasurement(userID: uid, entryID: "historical-measurement", weight: 190, date: now.addingTimeInterval(-86_400))
        let data = try await reference.getDocument(source: .server).data()
        XCTAssertEqual(data?["weight"] as? Double, 179.5)
        XCTAssertEqual(data?["unrelated"] as? String, "preserve")
        let history = try await reference.collection("weightHistory").getDocuments(source: .server)
        XCTAssertEqual(Set(history.documents.map(\.documentID)), ["stable-measurement", "historical-measurement"])
    }

    func testCheckedFoodTransactionRejectsSameEntryConflictAndReceiptReplayKeepsLaterRevision() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let originalFood = food("selected"), unrelated = food("other")
        let original = DailyLog(id: "checked-food-day", date: Date(), meals: [Meal(name: "Lunch", foodItems: [originalFood, unrelated])])
        let reference = client.db.collection("users").document(uid).collection("dailyLogs").document("checked-food-day")
        var remote = original
        remote.meals[0].foodItems[0].calories = 300
        remote.meals[0].foodItems[1].calories = 200
        try await reference.setData(Firestore.Encoder().encode(remote))
        var desired = originalFood; desired.calories = 150
        var stale = original.rememberingMutationBase()
        stale.pendingMutationID = "stale-food-edit"
        stale.pendingFoodEdit = FoodEditPrecondition(original: originalFood, desired: desired)
        stale.meals[0].foodItems[0] = desired
        let rejected = await withCheckedContinuation { continuation in
            client.repository.updateDailyLog(userID: uid, log: stale) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(rejected)
        let afterConflict = try await reference.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(afterConflict.meals[0].foodItems.map(\.calories), [300, 200])
        var accepted = remote.rememberingMutationBase()
        var revised = remote.meals[0].foodItems[0]; revised.calories = 350
        accepted.pendingMutationID = "accepted-food-edit"
        accepted.pendingFoodEdit = FoodEditPrecondition(original: remote.meals[0].foodItems[0], desired: revised)
        accepted.meals[0].foodItems[0] = revised
        await accept(accepted, client: client, userID: uid)
        var later = try await reference.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(later.meals[0].foodItems.map(\.calories), [350, 200])
        later.meals[0].foodItems[0].calories = 450
        try await reference.setData(Firestore.Encoder().encode(later))
        await accept(accepted, client: client, userID: uid)
        let replayed = try await reference.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(replayed.meals[0].foodItems.map(\.calories), [450, 200])
        XCTAssertEqual(replayed.appliedMutationIDs?.filter { $0 == "accepted-food-edit" }.count, 1)
        XCTAssertEqual(client.repository.dailyLogSyncState(userID: uid), .synced, "Checked edits must not enter the optimistic offline queue")
    }

    func testPantryReceiptCreatesOnceAndReplayCannotOverwriteOrResurrectInventory() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let receiptID = UUID()
        let original = PantryItem(name: "Apples", quantity: 2, unit: "item")
        let owner = client.db.collection("users").document(uid)
        let reference = owner.collection("pantryItems").document(original.id.uuidString)
        try await client.repository.createPantryReceiptItem(userID: uid, receiptID: receiptID, item: original)
        var corrected = original; corrected.quantity = 7
        try await client.repository.savePantryItem(userID: uid, item: corrected)
        try await client.repository.createPantryReceiptItem(userID: uid, receiptID: receiptID, item: original)
        let replayed = try await reference.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(replayed.quantity, 7)
        try await reference.delete()
        try await client.repository.createPantryReceiptItem(userID: uid, receiptID: receiptID, item: original)
        let deleted = try await reference.getDocument(source: .server)
        XCTAssertFalse(deleted.exists)
        let receipt = try await owner.collection("pantryImportReceipts")
            .document("\(receiptID.uuidString)_\(original.id.uuidString)").getDocument(source: .server)
        XCTAssertNotNil(receipt.data()?["acceptedAt"])
        let collision = PantryItem(name: "Existing rice", quantity: 5, unit: "item")
        try await client.repository.savePantryItem(userID: uid, item: collision)
        var overwritten = collision; overwritten.quantity = 2
        do {
            try await client.repository.createPantryReceiptItem(userID: uid, receiptID: UUID(), item: overwritten)
            XCTFail("A purchase without its receipt cannot replace an existing inventory ID")
        } catch { }
        let preserved = try await owner.collection("pantryItems").document(collision.id.uuidString)
            .getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(preserved.quantity, 5)
    }

    func testShoppingChoiceMovesAtomicallyAcrossWeeksAndSurvivesALegacyChecklistWrite() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let start = Calendar.current.startOfDay(for: Date()), day = MealPlanEditingRules.dayID(start)
        let list = client.db.collection("users").document(uid).collection("userSettings").document("groceryList")
        var rice = GroceryListItem(name: "Rice", quantity: 400, unit: "g", source: "mealPlan", sourcePlanStart: start)
        rice.skippedForPlan = true
        var rawRice = try Firestore.Encoder().encode(rice)
        rawRice["futureField"] = "preserved"
        try await list.setData(["items": [rawRice]])

        var parked = rice; parked.savedShoppingDay = day
        let leave = GroceryListMutation(before: [rice], upserts: [parked], removedIDs: [])
        let otherWeek = try await client.repository.applyGroceryMutation(userID: uid, mutation: leave)
        XCTAssertTrue(otherWeek.isEmpty)
        let saved = try await client.repository.fetchSavedShoppingChoices(userID: uid, day: day)
        let choice = try XCTUnwrap(saved.first)
        XCTAssertEqual(saved.count, 1); XCTAssertEqual(choice.id, rice.id)
        let oldList = try await list.getDocument(source: .server)
        XCTAssertEqual((oldList.data()?["items"] as? [[String: Any]])?.count, 0)

        let tea = GroceryListItem(name: "Tea", quantity: 1, unit: "item", source: "manual")
        // The 2.3 client replaces only this document's visible items with a merged write.
        try await list.setData(["items": [try Firestore.Encoder().encode(tea)], "lastUpdated": Timestamp(date: Date())], merge: true)
        let restore = GroceryListMutation(before: [choice], upserts: [rice], removedIDs: [])
        let returned = try await client.repository.applyGroceryMutation(userID: uid, mutation: restore)
        let replayed = try await client.repository.applyGroceryMutation(userID: uid, mutation: restore)
        XCTAssertEqual(replayed, returned)
        XCTAssertEqual(Set(returned.map(\.id)), [rice.id, tea.id])
        XCTAssertTrue(returned.first { $0.id == rice.id }?.skippedForPlan == true)
        let raw = try await list.getDocument(source: .server).data()?["items"] as? [[String: Any]]
        XCTAssertTrue(raw?.contains { $0["futureField"] as? String == "preserved" && $0["savedShoppingDay"] == nil } == true)
        let afterRestore = try await client.repository.fetchSavedShoppingChoices(userID: uid, day: day)
        XCTAssertTrue(afterRestore.isEmpty)

        var stale = rice; stale.quantity = 100
        do {
            _ = try await client.repository.applyGroceryMutation(userID: uid, mutation: .init(before: [choice], upserts: [stale], removedIDs: []))
            XCTFail("A stale saved choice cannot overwrite the restored row.")
        } catch { XCTAssertEqual(error as? GroceryChecklistError, .changed) }

        let active = try XCTUnwrap(returned.first { $0.id == rice.id })
        _ = try await client.repository.applyGroceryMutation(userID: uid, mutation: .init(before: [active], upserts: [parked], removedIDs: []))
        // A cached July checklist may also reintroduce the original ID. Removing that
        // visible row must retire the old skip instead of resurrecting it later.
        var legacy = rice; legacy.skippedForPlan = nil
        try await client.repository.saveGroceryList(userID: uid, items: [legacy, tea])
        let remaining = try await client.repository.applyGroceryMutation(userID: uid, mutation: .init(before: [legacy], upserts: [], removedIDs: [legacy.id]))
        XCTAssertEqual(remaining, [tea])
        let superseded = try await client.repository.fetchSavedShoppingChoices(userID: uid, day: day)
        XCTAssertTrue(superseded.isEmpty)
    }

    func testGroceryItemReceiptsMergeDifferentRowsAndRejectStaleSameRow() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let apple = GroceryListItem(name: "Apples", quantity: 2, unit: "item")
        let oats = GroceryListItem(name: "Oats", quantity: 400, unit: "g")
        try await client.repository.saveGroceryList(userID: uid, items: [apple, oats])
        var checkedApple = apple; checkedApple.isCompleted = true
        var checkedOats = oats; checkedOats.isCompleted = true
        let first = GroceryListMutation(before: [apple], upserts: [checkedApple], removedIDs: [])
        let second = GroceryListMutation(before: [oats], upserts: [checkedOats], removedIDs: [])
        // Both operations were reviewed against the same original list. Neither may replace
        // the other row when its transaction retries against a concurrent account change.
        async let appleWrite = client.repository.applyGroceryMutation(userID: uid, mutation: first)
        async let oatsWrite = client.repository.applyGroceryMutation(userID: uid, mutation: second)
        _ = try await (appleWrite, oatsWrite)
        let merged = try await client.repository.fetchGroceryList(userID: uid)
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.allSatisfy(\.isCompleted))
        var newer = checkedApple; newer.quantity = 5
        try await client.repository.saveGroceryList(userID: uid, items: [newer, checkedOats])
        let replayed = try await client.repository.applyGroceryMutation(userID: uid, mutation: first)
        XCTAssertEqual(replayed.first { $0.id == apple.id }?.quantity, 5, "A replayed receipt cannot overwrite a later quantity edit")
        let stale = GroceryListMutation(before: [apple], upserts: [checkedApple], removedIDs: [])
        do {
            _ = try await client.repository.applyGroceryMutation(userID: uid, mutation: stale)
            XCTFail("A stale change to the same row must retain both versions for review")
        } catch { }
        let afterConflict = try await client.repository.fetchGroceryList(userID: uid)
        XCTAssertEqual(afterConflict.first { $0.id == apple.id }?.quantity, 5)
        let receipt = try await client.db.collection("users").document(uid)
            .collection("groceryMutationReceipts").document(first.id.uuidString).getDocument(source: .server)
        XCTAssertTrue(receipt.exists)
        XCTAssertNotNil(receipt.data()?["acceptedAt"])
    }

    func testRecipeBasisPartialIngredientsAndLegacyTotalsRoundTripThroughFirestore() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let collection = client.db.collection("users").document(uid).collection("recipes")
        let oil = FoodItem(
            id: "linked-oil", name: "Oil", calories: 100, protein: 0, carbs: 0, fats: 11,
            servingSize: "12 g", servingWeight: 12,
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "oil")
        )
        let recipe = Recipe(
            id: "explicit-yield", name: "Estimated bean soup", ingredients: ["400 g beans", "Oil"],
            instructions: ["Simmer"],
            nutrition: Nutrition(calories: 800, protein: 40, carbs: 120, fats: 18, calcium: 200, sodium: 1600),
            servings: 4, nutritionBasis: .wholeRecipe, nutritionOrigin: .aiEstimate,
            unresolvedIngredients: ["400 g beans"], linkedIngredients: [oil], nutritionNeedsReview: true
        )
        let saved = try await client.repository.saveRecipe(userID: uid, recipe: recipe)
        try await client.db.waitForPendingWrites()
        let explicitDocument = try await collection.document("explicit-yield").getDocument(source: .server)
        let explicitData = try XCTUnwrap(explicitDocument.data())
        XCTAssertEqual(explicitData["nutritionBasis"] as? String, "wholeRecipe")
        XCTAssertEqual(explicitData["nutritionOrigin"] as? String, "aiEstimate")
        XCTAssertEqual(explicitData["nutritionNeedsReview"] as? Bool, true)
        XCTAssertEqual(explicitData["unresolvedIngredients"] as? [String], ["400 g beans"])
        XCTAssertEqual((explicitData["linkedIngredients"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(explicitData["detailedIngredients"], "Partial matches must not appear complete to older clients")
        let fetchedRecipes = try await client.repository.fetchRecipes(userID: uid)
        let fetched = try XCTUnwrap(fetchedRecipes.first { $0.id == saved.id })
        XCTAssertEqual(fetched, recipe)
        XCTAssertEqual(fetched.servings, 4)
        XCTAssertEqual(fetched.nutrition.calories, 800, "Persist the batch total without rewriting it per serving")
        XCTAssertEqual(fetched.nutritionPerPortion.calories, 200)
        XCTAssertEqual(fetched.nutritionPerPortion.sodium, 400)
        XCTAssertEqual(fetched.nutritionPerPortion.calcium, 50)
        XCTAssertNil(fetched.nutritionPerPortion.vitaminD, "Unknown nutrients must survive as unknown")
        XCTAssertEqual(fetched.resolvedIngredientFoods, [oil])
        XCTAssertFalse(fetched.hasCompleteIngredientNutrition)
        let loggingFood = fetched.foodItemForLogging()
        XCTAssertEqual(loggingFood.calories, 200)
        XCTAssertEqual(loggingFood.sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(loggingFood.sourceMetadata?.originSourceType, .aiText)
        XCTAssertEqual(loggingFood.sourceMetadata?.evidenceLineage, .modelEstimate)
        XCTAssertEqual(loggingFood.markedUserConfirmed(sourceType: .recipe).sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(MealPlanEditingRules.ingredients(for: fetched), ["100 gram beans", "3 g Oil"])

        // A real old-schema document has no new optional fields, even when its unused yield was four.
        let legacyData: [String: Any] = [
            "id": "legacy-recipe", "name": "Legacy soup", "ingredients": ["400 g beans", "2 cups broth"],
            "instructions": ["Simmer"], "servings": 4,
            "nutrition": ["calories": 600, "protein": 24, "carbs": 80, "fats": 12, "sodium": 900]
        ]
        try await collection.document("legacy-recipe").setData(legacyData)
        let withLegacy = try await client.repository.fetchRecipes(userID: uid)
        let legacy = try XCTUnwrap(withLegacy.first { $0.id == "legacy-recipe" })
        XCTAssertNil(legacy.nutritionBasis)
        XCTAssertNil(legacy.nutritionOrigin)
        XCTAssertEqual(legacy.servings, 4)
        XCTAssertEqual(legacy.nutritionPerPortion.calories, 600, "Do not reinterpret a legacy stored amount using its old yield")
        XCTAssertEqual(legacy.foodItemForLogging().sodium, 900)
        XCTAssertEqual(MealPlanEditingRules.ingredients(for: legacy), ["400 g beans", "2 cups broth"])
        _ = try await client.repository.saveRecipe(userID: uid, recipe: legacy)
        try await client.db.waitForPendingWrites()
        let legacyDocument = try await collection.document("legacy-recipe").getDocument(source: .server)
        let restoredLegacy = try legacyDocument.data(as: Recipe.self)
        XCTAssertEqual(restoredLegacy, legacy)
        XCTAssertEqual(restoredLegacy.nutrition.calories, 600)
        XCTAssertNil(legacyDocument.data()?["nutritionBasis"])
        XCTAssertNil(legacyDocument.data()?["nutritionOrigin"])
        XCTAssertNil(legacyDocument.data()?["linkedIngredients"])
        XCTAssertNil(legacyDocument.data()?["nutritionNeedsReview"])
    }

    @MainActor
    func testMealPlanMoveIsAtomicAndStaleUndoKeepsNewerMeals() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let oldAuth = DIContainer.shared.authService, oldRepository = DIContainer.shared.nutritionRepository
        let auth = MockAuthService(); auth.currentUserID = uid
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = client.repository
        defer { DIContainer.shared.authService = oldAuth; DIContainer.shared.nutritionRepository = oldRepository }
        let suite = "planner-emulator-\(UUID())", date = Calendar.current.startOfDay(for: Date())
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var source = MealPlanEditingRules.emptyDay(date)
        source.meals = [PlannedMeal(id: "move-me", mealType: "Lunch", foodItem: food("Rice bowl"))]
        var destination = MealPlanEditingRules.emptyDay(try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: date)))
        destination.meals = [PlannedMeal(id: "keep-me", mealType: "Breakfast", foodItem: food("Toast"))]
        try await client.repository.saveFullMealPlanBatch(userID: uid, plans: [source, destination])
        let move = try MealPlanEditingRules.transferring(source.meals, from: source, to: [destination], moving: true)
        let service = MealPlannerService(recipeService: RecipeService(), userDefaults: defaults)
        try await service.applyPlanChange(move, for: uid)
        var storedSource = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        var storedDestination = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertTrue(storedSource?.meals.isEmpty == true)
        XCTAssertEqual(storedDestination?.meals.count, 2)
        let recreated = MealPlannerService(recipeService: RecipeService(), userDefaults: defaults)
        try await recreated.undoLastPlanChange(for: uid)
        storedSource = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        storedDestination = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertEqual(storedSource?.meals.map(\.id), ["move-me"])
        XCTAssertEqual(storedDestination?.meals.map(\.id), ["keep-me"])
        var repeatedMove = move; repeatedMove.id = UUID()
        try await service.applyPlanChange(repeatedMove, for: uid)
        let concurrentResult = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        var concurrent = try XCTUnwrap(concurrentResult)
        concurrent.meals.append(PlannedMeal(id: "newer-meal", mealType: "Dinner", foodItem: food("Salmon")))
        try await client.repository.saveMealPlan(userID: uid, plan: concurrent)
        do { try await recreated.undoLastPlanChange(for: uid); XCTFail("Stale Undo must reject the whole transaction") } catch { }
        storedSource = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        storedDestination = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertTrue(storedSource?.meals.isEmpty == true, "A failed Undo must not partially restore the source")
        XCTAssertEqual(storedDestination?.meals.count, 3)
        XCTAssertNotNil(recreated.lastPlanChange(for: uid))
    }

    @MainActor
    func testHouseholdBatchLeftoversRoundTripAtomicallyWithoutChangingDiaryOrPHUL() async throws {
        let client = makeClient(), date = Calendar.current.startOfDay(for: Date())
        let uid = try await client.auth.signInAnonymously().user.uid
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: date))
        let original = PlannedMeal(id: "batch-source", mealType: "Dinner",
            foodItem: FoodItem(id: "batch-food", name: "Rice bowl", calories: 400, protein: 25, carbs: 60, fats: 7),
            ingredients: ["100 g dry rice"], instructions: "Cook the rice. Serve.")
        let batchMeal = try MealPlanCookingRules.configuring(original, date: date, cookingPortions: 4)
        var source = MealPlanEditingRules.emptyDay(date); source.meals = [batchMeal]
        let destination = MealPlanEditingRules.emptyDay(tomorrow)
        try await client.repository.saveFullMealPlanBatch(userID: uid, plans: [source, destination])
        let user = client.db.collection("users").document(uid)
        let history = user.collection("dailyLogs").document("existing-log")
        let program = user.collection("workoutPrograms").document("existing-phul")
        try await history.setData(["preservedFood": "owner meal", "calories": 713])
        try await program.setData(["name": "PHUL", "currentProgressIndex": 39, "skippedIndices": [2, 5]])
        let storedSource = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        let reloaded = try XCTUnwrap(storedSource)
        XCTAssertEqual(reloaded.meals[0].cookingBatch, batchMeal.cookingBatch)
        let change = try MealPlanCookingRules.planningLeftover(from: reloaded.meals[0], source: reloaded,
            relatedDays: [reloaded], destination: destination, mealType: "Lunch", portions: 1)
        try await client.repository.applyMealPlanChange(userID: uid, change: change)
        let sourceAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        let destinationAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        let dinner = try XCTUnwrap(sourceAfter), lunch = try XCTUnwrap(destinationAfter)
        XCTAssertEqual(dinner.meals[0].cookingBatch, lunch.meals[0].cookingBatch)
        XCTAssertEqual(lunch.meals.count, 1)
        XCTAssertEqual(dinner.meals[0].plannedFood?.calories, 400)
        XCTAssertEqual(lunch.meals[0].plannedFood?.calories, 400)
        let groceries = GroceryListBuilder.makeGroceryList(from: [dinner, lunch], starting: date, unitSystem: .metric)
        XCTAssertEqual(groceries.count, 1); XCTAssertEqual(groceries.first?.quantity, 400)
        let historyAfter = try await history.getDocument(source: .server).data()
        let phulAfter = try await program.getDocument(source: .server).data()
        XCTAssertEqual(historyAfter?["calories"] as? Int, 713)
        XCTAssertEqual(phulAfter?["currentProgressIndex"] as? Int, 39)
        XCTAssertEqual(phulAfter?["skippedIndices"] as? [Int], [2, 5])
        try await client.repository.applyMealPlanChange(userID: uid, change: change.reversed)
        let sourceUndo = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        let destinationUndo = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertEqual(sourceUndo?.meals[0].cookingBatch, batchMeal.cookingBatch)
        XCTAssertTrue(destinationUndo?.meals.isEmpty == true)
    }

    @MainActor
    func testStaleLeftoverDestinationCannotPartiallyReviseItsSourceBatch() async throws {
        let client = makeClient(), date = Calendar.current.startOfDay(for: Date())
        let uid = try await client.auth.signInAnonymously().user.uid
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: date))
        let original = PlannedMeal(id: "batch-source", mealType: "Dinner", foodItem: food("Rice bowl"), ingredients: ["100 g dry rice"])
        let batchMeal = try MealPlanCookingRules.configuring(original, date: date, cookingPortions: 4)
        var source = MealPlanEditingRules.emptyDay(date); source.meals = [batchMeal]
        let destination = MealPlanEditingRules.emptyDay(tomorrow)
        try await client.repository.saveFullMealPlanBatch(userID: uid, plans: [source, destination])
        let change = try MealPlanCookingRules.planningLeftover(from: batchMeal, source: source,
            relatedDays: [source], destination: destination, mealType: "Lunch", portions: 1)
        var concurrent = destination
        concurrent.meals = [PlannedMeal(id: "keep-concurrent", mealType: "Lunch", foodItem: food("Newer meal"))]
        try await client.repository.saveMealPlan(userID: uid, plan: concurrent)
        do {
            try await client.repository.applyMealPlanChange(userID: uid, change: change)
            XCTFail("A changed destination must reject the entire multi-day allocation")
        } catch { }
        let sourceAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        let destinationAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertEqual(sourceAfter?.meals[0].cookingBatch, batchMeal.cookingBatch)
        XCTAssertEqual(destinationAfter?.meals.map(\.id), ["keep-concurrent"])
    }

    @MainActor
    func testLeftoverReceiptReplayKeepsNewerPlansAndCannotRecreateDeletedDestination() async throws {
        let client = makeClient(), uid = try await client.auth.signInAnonymously().user.uid
        let (source, destination, change) = try frozenLeftoverChange()
        try await client.repository.saveFullMealPlanBatch(userID: uid, plans: [source, destination])
        let pending = try await client.repository.resolveMealPlanChange(userID: uid, change: change, cancelPending: false)
        guard case .pending = pending else { return XCTFail("A new operation must start unresolved") }
        try await client.repository.applyMealPlanChange(userID: uid, change: change)
        var newer = try XCTUnwrap(change.after.first(where: { $0.id == destination.id }))
        newer.meals.append(PlannedMeal(id: "newer", mealType: "Snack", foodItem: food("Newer food")))
        try await client.repository.saveMealPlan(userID: uid, plan: newer)
        try await client.repository.applyMealPlanChange(userID: uid, change: change)
        let replayed = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertEqual(replayed?.meals.map(\.id), newer.meals.map(\.id))
        let reference = client.db.collection("users").document(uid).collection("mealPlans").document(destination.id)
        try await reference.delete()
        try await client.repository.applyMealPlanChange(userID: uid, change: change)
        let afterDelete = try await reference.getDocument(source: .server)
        XCTAssertFalse(afterDelete.exists)
        let resolution = try await client.repository.resolveMealPlanChange(userID: uid, change: change, cancelPending: false)
        guard case .accepted = resolution else { return XCTFail("Permanent evidence must survive later edits and deletion") }
    }

    @MainActor
    func testCancelledLeftoverReceiptFencesLateSaveAndRejectsPayloadReuse() async throws {
        let client = makeClient(), uid = try await client.auth.signInAnonymously().user.uid
        let (source, destination, change) = try frozenLeftoverChange()
        try await client.repository.saveFullMealPlanBatch(userID: uid, plans: [source, destination])
        let cancelled = try await client.repository.resolveMealPlanChange(userID: uid, change: change, cancelPending: true)
        guard case .cancelled = cancelled else { return XCTFail("Cancellation must fence the frozen operation") }
        do {
            try await client.repository.applyMealPlanChange(userID: uid, change: change)
            XCTFail("A late save cannot apply after cancellation")
        } catch { }
        var altered = change; altered.title = "Different command with the same ID"
        do {
            _ = try await client.repository.resolveMealPlanChange(userID: uid, change: altered, cancelPending: false)
            XCTFail("An operation ID cannot be reused for another payload")
        } catch { }
        let sourceAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        let destinationAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertEqual(sourceAfter?.meals[0].cookingBatch, source.meals[0].cookingBatch)
        XCTAssertTrue(destinationAfter?.meals.isEmpty == true)
    }

    @MainActor
    private func frozenLeftoverChange(date requestedDate: Date = Date()) throws -> (MealPlanDay, MealPlanDay, MealPlanChange) {
        let date = Calendar.current.startOfDay(for: requestedDate)
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: date))
        let meal = PlannedMeal(id: "receipt-batch-source", mealType: "Dinner",
            foodItem: food("Rice bowl"), ingredients: ["100 g dry rice"])
        var source = MealPlanEditingRules.emptyDay(date)
        source.meals = [try MealPlanCookingRules.configuring(meal, date: date, cookingPortions: 4)]
        let destination = MealPlanEditingRules.emptyDay(tomorrow)
        let change = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: destination, mealType: "Lunch", portions: 1)
        return (source, destination, change)
    }

    @MainActor
    func testDiscardChecksActualCrossWeekBatchBeforeDeletingAnyPlan() async throws {
        let client = makeClient(), uid = try await client.auth.signInAnonymously().user.uid
        let week = MealPlanEditingRules.week(containing: Date())
        let lastDay = try XCTUnwrap(week.last)
        let (source, destination, change) = try frozenLeftoverChange(date: lastDay)
        try await client.repository.saveFullMealPlanBatch(userID: uid, plans: change.after)
        let manual = GroceryListItem(name: "Keep manual", quantity: 1, unit: "item", source: "manual")
        try await client.repository.saveGroceryList(userID: uid, items: [manual])
        do {
            try await client.repository.discardMealPlans(userID: uid,
                dateStrings: week.map { MealPlanEditingRules.dayID($0) }, retainingGroceryItems: [manual])
            XCTFail("A linked allocation outside the deletion window must reject the whole discard")
        } catch { }
        let sourceAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        let destinationAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertEqual(sourceAfter?.meals[0].cookingBatch?.allocations.count, 2)
        XCTAssertEqual(destinationAfter?.meals.count, 1)
        let groceries = try await client.repository.fetchGroceryList(userID: uid)
        XCTAssertEqual(groceries.map(\.id), [manual.id])
    }

    @MainActor
    func testDiscardRetainsManualGroceryAddedAfterItsEarlierReview() async throws {
        let client = makeClient(), uid = try await client.auth.signInAnonymously().user.uid
        let (source, destination, change) = try frozenLeftoverChange()
        try await client.repository.saveFullMealPlanBatch(userID: uid, plans: change.after)
        let oldManual = GroceryListItem(name: "Old manual", quantity: 1, unit: "item", source: "manual")
        let newManual = GroceryListItem(name: "Added elsewhere", quantity: 2, unit: "item", source: "manual")
        let generated = GroceryListItem(name: "dry rice", quantity: 400, unit: "g", source: "mealPlan", sourcePlanStart: source.date)
        try await client.repository.saveGroceryList(userID: uid, items: [oldManual, newManual, generated])
        try await client.repository.discardMealPlans(userID: uid, dateStrings: [source.id, destination.id],
                                                     retainingGroceryItems: [oldManual])
        let groceries = try await client.repository.fetchGroceryList(userID: uid)
        XCTAssertEqual(Set(groceries.map(\.id)), Set([oldManual.id, newManual.id]))
        let sourceAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: source.id)
        let destinationAfter = try await client.repository.fetchMealPlan(userID: uid, dateString: destination.id)
        XCTAssertNil(sourceAfter); XCTAssertNil(destinationAfter)
    }

    @MainActor
    func testMealPlanStaleCopyCannotOverwriteConcurrentDestination() async throws {
        let client = makeClient(), date = Calendar.current.startOfDay(for: Date())
        let uid = try await client.auth.signInAnonymously().user.uid
        var source = MealPlanEditingRules.emptyDay(date)
        source.meals = [PlannedMeal(id: "source", mealType: "Lunch", foodItem: food("Bowl"))]
        let emptyDestination = MealPlanEditingRules.emptyDay(try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: date)))
        let copy = try MealPlanEditingRules.transferring(source.meals, from: source, to: [emptyDestination], moving: false)
        var concurrent = emptyDestination
        concurrent.meals = [PlannedMeal(id: "concurrent", mealType: "Dinner", foodItem: food("Soup"))]
        try await client.repository.saveMealPlan(userID: uid, plan: concurrent)
        do { try await client.repository.applyMealPlanChange(userID: uid, change: copy); XCTFail("Stale destination must fail") } catch { }
        let stored = try await client.repository.fetchMealPlan(userID: uid, dateString: emptyDestination.id)
        XCTAssertEqual(stored?.meals.map(\.id), ["concurrent"])
    }

    @MainActor
    func testMealComparisonTransactionMergesCheckInsAndHonorsDeletion() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let previousAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = uid
        DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previousAuth }
        let now = Date().addingTimeInterval(-60)
        let routine = WorkoutRoutine(id: "upper", userID: uid, name: "Upper", dateCreated: now,
                                     exercises: [RoutineExercise(name: "Press", sets: [ExerciseSet(target: "8")], targetSets: 1)])
        let program = WorkoutProgram(id: "plan", userID: uid, name: "Plan", routines: [routine], startDate: now,
                                     daysOfWeek: [1, 3, 5], currentProgressIndex: 0)
        let base = try MealExperimentRules.create(program: program, routineID: "upper", mealA: food("Oats"), mealB: food("Toast"),
                                                 minutesBefore: 90, startsWithA: true, now: now)
        func completed(_ id: String) -> WorkoutSessionLog {
            WorkoutSessionLog(id: id, date: Date(), routineID: "upper", completedExercises: [
                CompletedExercise(exerciseName: "Press", exercise: routine.exercises[0],
                                  sets: [CompletedSet(reps: 8, weight: 100, effort: SetEffort(scale: .rpe, value: 8))])
            ])
        }
        let first = try MealExperimentRules.recording(in: base, trialID: base.trials[0].id, session: completed("first"),
            energy: 4, comfort: 4, minutesBefore: 90, confounders: [], note: "")
        let second = try MealExperimentRules.recording(in: base, trialID: base.trials[1].id, session: completed("second"),
            energy: 3, comfort: 5, minutesBefore: 90, confounders: [], note: "")
        var a = MealExperimentCloudState(); a.update(first)
        var b = MealExperimentCloudState(); b.update(second)
        let repository = FirestoreMealExperimentRepository(db: client.db)
        _ = try await repository.merge(a, userID: uid)
        let merged = try await repository.merge(b, userID: uid)
        XCTAssertEqual(Set(merged.experiments[0].trials.compactMap { $0.observation?.sessionID }), ["first", "second"])
        let restarted = FirestoreMealExperimentRepository(db: client.db)
        let recovered = try await restarted.merge(MealExperimentCloudState(), userID: uid)
        XCTAssertEqual(recovered.experiments.first?.id, base.id)
        var deletion = recovered; deletion.deleteAll()
        _ = try await restarted.merge(deletion, userID: uid)
        let replay = try await repository.merge(a, userID: uid)
        XCTAssertTrue(replay.experiments.isEmpty)
        auth.currentUserID = "different-account"
        do { _ = try await repository.merge(a, userID: uid); XCTFail("An account switch must reject the write") } catch { }
    }

    func testDayReviewMergesWithFoodAndClearsOnServer() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let date = Calendar.current.startOfDay(for: Date())
        var original = try await read(client, userID: uid, date: date)
        original.meals = [Meal(name: "Lunch", foodItems: [food("original")])]
        await accept(original, client: client, userID: uid)
        try await waitForSync(client, userID: uid)
        var reviewed = try await read(client, userID: uid, date: date)
        var added = reviewed
        reviewed.nutritionDayStatus = .complete
        added.meals[0].foodItems.append(food("later"))
        await accept(reviewed, client: client, userID: uid)
        await accept(added, client: client, userID: uid)
        try await waitForSync(client, userID: uid)
        var stored = try await read(client, userID: uid, date: date)
        XCTAssertEqual(stored.nutritionDayStatus, .complete)
        XCTAssertEqual(stored.meals[0].foodItems.count, 2)
        stored.nutritionDayStatus = nil
        await accept(stored, client: client, userID: uid)
        try await waitForSync(client, userID: uid)
        let reloaded = try await read(client, userID: uid, date: date)
        XCTAssertNil(reloaded.nutritionDayStatus)
        XCTAssertEqual(reloaded.meals[0].foodItems.count, 2)
    }

    @MainActor
    func testSubmittedMealReplayAfterServiceRestartDoesNotDuplicateCloudEntries() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let previousAuth = DIContainer.shared.authService
        let previousRepository = DIContainer.shared.nutritionRepository
        let auth = MockAuthService()
        auth.currentUserID = uid
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = client.repository
        defer {
            DIContainer.shared.authService = previousAuth
            DIContainer.shared.nutritionRepository = previousRepository
        }
        let date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86400)
        var draft = FoodLoggingDraft(date: date, mealName: "Lunch")
        draft.entries = [FoodLoggingDraft.Entry(food: food("first")), FoodLoggingDraft.Entry(food: food("second"))]
        let payload = draft.foods
        let save: (DailyLogService) async -> Bool = { service in
            await withCheckedContinuation { continuation in
                service.addMealGroupsToLog(for: uid, date: date,
                                           mealGroups: [(mealName: "Lunch", foodItems: payload)],
                                           source: "meal_draft", deduplicateFoodIDs: true) {
                    continuation.resume(returning: $0)
                }
            }
        }
        let undoStore = EditorDraftStore(directory: directories.last!.appendingPathComponent("undo"))
        let first = DailyLogService(undoStore: undoStore)
        first.activateAccount(uid)
        let accepted = await save(first)
        XCTAssertTrue(accepted)
        let originalUndoID = first.undoChangeID
        XCTAssertNotNil(originalUndoID)
        try await waitForSync(client, userID: uid)
        first.activateAccount(nil)
        let restarted = DailyLogService(undoStore: undoStore)
        restarted.activateAccount(uid)
        let replayed = await save(restarted)
        XCTAssertTrue(replayed)
        try await waitForSync(client, userID: uid)
        let saved = try await read(client, userID: uid, date: date)
        XCTAssertEqual(saved.meals.flatMap(\.foodItems).map(\.id), payload.map(\.id))
        XCTAssertEqual(restarted.undoChangeID, originalUndoID, "Replay must retain the original durable Undo receipt rather than creating a new edit")
        restarted.activateAccount(nil)
    }

    @MainActor
    func testUnreadableWorkoutPreservesLastGoodPlanAcrossRepositoryRestart() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let collection = client.db.collection("users").document(uid).collection("workoutPrograms")
        let queueURL = directories.last!.appendingPathComponent("partial-library.json")
        let plan = WorkoutProgram(id: "preferred", userID: uid, name: "PHUL", currentProgressIndex: 35)
        let other = WorkoutProgram(id: "other", userID: uid, name: "Other")
        try await collection.document("preferred").setData(Firestore.Encoder().encode(plan))
        try await collection.document("other").setData(Firestore.Encoder().encode(other))
        let initial = FirestoreWorkoutRepository(db: client.db, outboxURL: queueURL, currentUserID: { client.auth.currentUser?.uid })
        let loaded = expectation(description: "Last good program snapshot saved")
        var received = false
        let first = initial.addProgramLibraryListener(userID: uid) { result in
            if case .success(let snapshot) = result, !snapshot.isFromCache, snapshot.values.count == 2, !received {
                received = true
                loaded.fulfill()
            }
        }
        await fulfillment(of: [loaded], timeout: 10)
        initial.removeListener(first)
        // Missing dateCreated must still be reported, rather than excluded by a query order.
        try await collection.document("preferred").setData(["name": "Unreadable future plan", "routines": "unsupported"])
        try await collection.document("unknown").setData(["name": "Another unreadable record"])
        let restarted = FirestoreWorkoutRepository(db: client.db, outboxURL: queueURL, currentUserID: { client.auth.currentUser?.uid })
        let partial = expectation(description: "Healthy and cached plans survive an unreadable record")
        var receivedPartial = false
        let second = restarted.addProgramLibraryListener(userID: uid) { result in
            if case .success(let snapshot) = result, !snapshot.isFromCache,
               snapshot.unreadableIDs == ["preferred", "unknown"], !receivedPartial {
                receivedPartial = true
                XCTAssertEqual(Set(snapshot.values.compactMap(\.id)), ["preferred", "other"])
                XCTAssertEqual(snapshot.values.first(where: { $0.id == "preferred" })?.currentProgressIndex, 35)
                partial.fulfill()
            }
        }
        await fulfillment(of: [partial], timeout: 10)
        restarted.removeListener(second)
        try await client.db.disableNetwork()
        let offline = FirestoreWorkoutRepository(db: client.db, outboxURL: queueURL, currentUserID: { client.auth.currentUser?.uid })
        let restored = expectation(description: "Last good copy and warning restore offline")
        var didRestore = false
        let third = offline.addProgramLibraryListener(userID: uid) { result in
            if case .success(let snapshot) = result, snapshot.isFromCache,
               snapshot.unreadableIDs.contains("preferred"), !didRestore {
                didRestore = true
                XCTAssertEqual(snapshot.values.first(where: { $0.id == "preferred" })?.name, "PHUL")
                restored.fulfill()
            }
        }
        await fulfillment(of: [restored], timeout: 10)
        offline.removeListener(third)
        try await client.db.enableNetwork()
        let untouched = try await collection.document("preferred").getDocument(source: .server)
        XCTAssertEqual(untouched.data()?["name"] as? String, "Unreadable future plan", "Cache recovery never writes to the cloud")
    }

    @MainActor
    func testLegacyWorkoutRecordsDoNotHideActiveProgramAndKeepDocumentIdentityOnSave() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let user = client.db.collection("users").document(uid)
        let created = Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000))
        // Original strength-only schema: no embedded routine ID, exercise type/targets/rest,
        // warm-up or cardio set fields, or duplicated top-level Firestore IDs.
        let exercise: [String: Any] = [
            "id": "old-exercise", "name": "Bench Press",
            "sets": [
                ["id": "old-set", "isCompleted": false,
                 "target": "6-8", "reps": 8, "weight": 135]
            ]
        ]
        let routine: [String: Any] = [
            "userID": uid, "name": "Older routine", "dateCreated": created, "exercises": [exercise]
        ]
        let legacy: [String: Any] = [
            "userID": uid, "name": "Older plan", "dateCreated": created, "routines": [routine],
            "currentProgressIndex": 4
        ]
        let active = WorkoutProgram(
            id: "active-phul", userID: uid, name: "PHUL", routines: [
                WorkoutRoutine(id: "phul-routine", userID: uid, name: "Upper", dateCreated: Date(),
                               exercises: [RoutineExercise(name: "Row", sets: [ExerciseSet(reps: 8, weight: 100)])])
            ], daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 35
        )
        try await user.collection("workoutPrograms").document("legacy-plan").setData(legacy)
        try await user.collection("workoutPrograms").document("active-phul").setData(Firestore.Encoder().encode(active))
        try await user.collection("workoutRoutines").document("legacy-routine").setData(routine)
        try await user.collection("workoutSessionLogs").document("legacy-session").setData([
            "date": Timestamp(date: Date()), "routineID": "phul-routine",
            "completedExercises": [
                ["id": "completed", "exerciseName": "Bench Press", "exercise": exercise,
                 "sets": [["id": "completed-set", "reps": 8, "weight": 135]]]
            ]
        ])
        let workouts = FirestoreWorkoutRepository(
            db: client.db, outboxURL: directories.last!.appendingPathComponent("legacy-workouts.json"),
            currentUserID: { client.auth.currentUser?.uid }
        )
        let loaded = expectation(description: "Both the older plan and active program load")
        var receivedPrograms: [WorkoutProgram] = []
        var didLoadPrograms = false
        let programsListener = workouts.addProgramsSnapshotListener(userID: uid) { result in
            guard !didLoadPrograms else { return }
            switch result {
            case .success(let programs) where programs.count == 2:
                receivedPrograms = programs
                didLoadPrograms = true
                loaded.fulfill()
            case .failure(let error):
                XCTFail("A legacy record must not hide the active program: \(error)")
                didLoadPrograms = true
                loaded.fulfill()
            default: break
            }
        }
        defer { workouts.removeListener(programsListener) }
        let routinesLoaded = expectation(description: "Standalone legacy routine loads")
        var didLoadRoutines = false
        let routinesListener = workouts.addRoutinesSnapshotListener(userID: uid) { result in
            guard !didLoadRoutines else { return }
            switch result {
            case .success(let routines) where !routines.isEmpty:
                XCTAssertEqual(routines.first?.id, "legacy-routine")
                XCTAssertEqual(routines.first?.exercises.first?.targetReps, "6-8")
                XCTAssertEqual(routines.first?.exercises.first?.restTimeInSeconds, 60)
                XCTAssertEqual(routines.first?.exercises.first?.sets.first?.isWarmup, false)
                didLoadRoutines = true
                routinesLoaded.fulfill()
            case .failure(let error):
                XCTFail("Legacy routine failed: \(error)")
                didLoadRoutines = true
                routinesLoaded.fulfill()
            default: break
            }
        }
        defer { workouts.removeListener(routinesListener) }
        await fulfillment(of: [loaded, routinesLoaded], timeout: 10)
        XCTAssertEqual(receivedPrograms.first(where: { $0.id == "active-phul" })?.currentProgressIndex, 35)
        var restored = try XCTUnwrap(receivedPrograms.first(where: { $0.id == "legacy-plan" }))
        XCTAssertEqual(restored.currentProgressIndex, 4)
        XCTAssertEqual(restored.routines.first?.exercises.first?.sets.first?.weight, 135)
        let history = try await workouts.fetchWorkoutHistory(userID: uid, limit: 10)
        XCTAssertEqual(history.first?.id, "legacy-session")
        XCTAssertEqual(history.first?.completedExercises.first?.exercise.targetSets, 1)
        let original = try await user.collection("workoutPrograms").document("legacy-plan").getDocument(source: .server)
        XCTAssertNil(original.data()?["id"], "Reading a legacy program must not rewrite it")
        restored.name = "Edited older plan"
        _ = try await workouts.saveProgram(userID: uid, program: restored)
        for _ in 0..<100 {
            if workouts.workoutSyncState(userID: uid) == .synced { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(workouts.workoutSyncState(userID: uid), .synced)
        let saved = try await user.collection("workoutPrograms").getDocuments(source: .server)
        XCTAssertEqual(Set(saved.documents.map(\.documentID)), ["legacy-plan", "active-phul"])
        XCTAssertEqual(saved.documents.first(where: { $0.documentID == "legacy-plan" })?.data()["name"] as? String, "Edited older plan")
        XCTAssertEqual(saved.documents.first(where: { $0.documentID == "active-phul" })?.data()["currentProgressIndex"] as? Int, 35)
    }

    @MainActor
    func testEmptyOfflineWorkoutCacheDoesNotReportAnEmptySavedLibrary() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        try await client.db.disableNetwork()
        let workouts = FirestoreWorkoutRepository(
            db: client.db, outboxURL: directories.last!.appendingPathComponent("cold-cache.json"),
            currentUserID: { client.auth.currentUser?.uid }
        )
        let offlineUpdate = expectation(description: "An empty offline cache is not an empty library")
        offlineUpdate.isInverted = true
        let serverUpdate = expectation(description: "Server confirms the empty library after reconnect")
        var waitingForServer = false
        var didReceiveServer = false
        let listener = workouts.addProgramsSnapshotListener(userID: uid) { result in
            if !waitingForServer {
                offlineUpdate.fulfill()
            } else if !didReceiveServer {
                if case .success(let programs) = result { XCTAssertTrue(programs.isEmpty) } else { XCTFail("Expected a server result") }
                didReceiveServer = true
                serverUpdate.fulfill()
            }
        }
        defer { workouts.removeListener(listener) }
        await fulfillment(of: [offlineUpdate], timeout: 0.5)
        waitingForServer = true
        try await client.db.enableNetwork()
        await fulfillment(of: [serverUpdate], timeout: 10)
    }

    @MainActor
    func testEquipmentSessionRecoveryAndFirestoreSavePreserveActivePHUL() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let queue = directories.last!.appendingPathComponent("equipment-workouts.json")
        let workouts = FirestoreWorkoutRepository(db: client.db, outboxURL: queue, currentUserID: { client.auth.currentUser?.uid })
        let oldAuth = DIContainer.shared.authService, oldRepository = DIContainer.shared.workoutRepository
        let auth = MockAuthService(); auth.currentUserID = uid
        DIContainer.shared.authService = auth
        DIContainer.shared.workoutRepository = workouts
        defer { DIContainer.shared.authService = oldAuth; DIContainer.shared.workoutRepository = oldRepository }
        let suite = "equipment-emulator-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date().addingTimeInterval(-60)
        var phul = try XCTUnwrap(WorkoutRules.generatePreBuiltPrograms().first { $0.name.localizedCaseInsensitiveContains("PHUL") })
        phul.id = "equipment-phul"; phul.userID = uid
        phul.currentProgressIndex = 7; phul.skippedIndices = [2]
        for routine in phul.routines { routine.userID = uid }
        let templateEquipment = StrengthEquipment(loadingMeaning: .total, name: "Bench rack", availableWeights: [100, 105, 110])
        phul.routines[0].exercises[0].loadEquipment = templateEquipment
        _ = try await workouts.saveProgram(userID: uid, program: phul)
        func sync(_ repository: FirestoreWorkoutRepository) async throws {
            for attempt in 0..<200 {
                if attempt % 10 == 0 { repository.retryPendingWorkouts(userID: uid) }
                if repository.workoutSyncState(userID: uid) == .synced { return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTFail("Workout changes did not reach the local emulator")
        }
        try await sync(workouts)
        let programRef = client.db.collection("users").document(uid).collection("workoutPrograms").document("equipment-phul")
        let storedProgram = try await programRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(storedProgram.routines[0].exercises[0].loadEquipment, templateEquipment)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let unchangedProgram = try encoder.encode(storedProgram)
        let firstService = WorkoutService(defaults: defaults)
        defer { firstService.detachListener() }
        firstService.setActiveProgram(storedProgram)
        firstService.activateAccount(uid)
        for _ in 0..<100 {
            if firstService.activeProgram?.id == "equipment-phul", firstService.hasLoadedPrograms { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(firstService.activeProgram?.currentProgressIndex, 7)
        let session = try XCTUnwrap(storedProgram.routines[0].deepCopy())
        let sessionEquipment = StrengthEquipment(unit: .kg, loadingMeaning: .total, name: "Bench rack", availableWeights: [100, 110, 120])
        session.exercises[0].loadEquipment = sessionEquipment
        let movement = session.exercises[0]
        let previousSets = try movement.sets.map { set in
            CompletedSet(reps: try XCTUnwrap(ProgressionRules.repRange(set.target ?? movement.targetReps)).upperBound,
                         weight: 100, effort: SetEffort(scale: .rpe, value: 7))
        }
        let previous = WorkoutSessionLog(id: "prior-equipment-session", date: now.addingTimeInterval(-86_400), routineID: session.id,
            completedExercises: [CompletedExercise(exerciseName: movement.name, exercise: movement, sets: previousSets)])
        let targets = try XCTUnwrap(ProgressionRules.plan(for: movement, history: [previous], now: now))
        session.exercises[0] = ProgressionRules.applying(targets, to: movement)
        session.exercises[0].sets[0].isCompleted = true
        let programContext = try XCTUnwrap(WorkoutRules.sessionContext(for: storedProgram, routineID: session.id))
        XCTAssertEqual(programContext.slotIndex, 8, "This seeded fixture starts the next Upper session early; slot 7 remains unfinished")
        var draft = WorkoutSessionDraft(routine: session, now: now, programContext: programContext)
        let draftDirectory = directories.last!.appendingPathComponent("equipment-draft")
        try WorkoutDraftStore(directory: draftDirectory).save(draft, userID: uid)
        firstService.detachListener()
        draft = try XCTUnwrap(WorkoutDraftStore(directory: draftDirectory).load(userID: uid))
        XCTAssertEqual(draft.routine.exercises[0].loadEquipment, sessionEquipment)
        XCTAssertEqual(draft.programContext, programContext)
        XCTAssertEqual(draft.programLinkDecision, .program)
        XCTAssertTrue(draft.routine.exercises[0].sets[0].isCompleted)
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 180, now: now))
        let completion = try XCTUnwrap(draft.completion)
        try await workouts.saveWorkoutSessionLog(userID: uid, log: completion)
        try await workouts.saveWorkoutSessionLog(userID: uid, log: completion)
        try await sync(workouts)
        let recoveredRepository = FirestoreWorkoutRepository(db: client.db, outboxURL: queue, currentUserID: { client.auth.currentUser?.uid })
        DIContainer.shared.workoutRepository = recoveredRepository
        let recoveredService = WorkoutService(defaults: defaults)
        defer { recoveredService.detachListener() }
        recoveredService.activateAccount(uid)
        for _ in 0..<100 {
            if recoveredService.activeProgram?.id == "equipment-phul", recoveredService.hasLoadedPrograms { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(recoveredService.activeProgram?.id, "equipment-phul")
        XCTAssertEqual(recoveredService.activeProgram?.name, phul.name)
        XCTAssertEqual(recoveredService.activeProgram?.currentProgressIndex, 7)
        XCTAssertEqual(recoveredService.activeProgram?.skippedIndices, [2])
        let earlyAccepted = await recoveredService.recordProgramCompletion(completion)
        XCTAssertTrue(earlyAccepted)
        let replayAccepted = await recoveredService.recordProgramCompletion(completion)
        XCTAssertTrue(replayAccepted)
        XCTAssertEqual(recoveredService.activeProgram?.currentProgressIndex, 7)
        let restoredProgram = try await programRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        func withoutProgressEvidence(_ data: Data) throws -> Data {
            var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            for key in ["progressEpoch", "slotCompletionProofs", "lastSkipReceipt"] { fields.removeValue(forKey: key) }
            return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        }
        XCTAssertEqual(try withoutProgressEvidence(encoder.encode(restoredProgram)), try withoutProgressEvidence(unchangedProgram),
                       "A recovered completion may add progress evidence, while every template field and the current PHUL position remain intact")
        let sessions = try await client.db.collection("users").document(uid).collection("workoutSessionLogs").getDocuments(source: .server)
        XCTAssertEqual(sessions.documents.map(\.documentID), [try XCTUnwrap(completion.id)])
        let savedSession = try XCTUnwrap(sessions.documents.first).data(as: WorkoutSessionLog.self)
        XCTAssertEqual(savedSession.completedExercises.first?.exercise.loadEquipment, sessionEquipment)
        XCTAssertEqual(savedSession.completedExercises.first?.sets.first?.weight, 110)
        XCTAssertEqual(savedSession.routineID, session.id)
        XCTAssertEqual(savedSession.programContext, programContext)
        XCTAssertEqual(savedSession.programLinkDecision, .program)
    }

    @MainActor
    func testStandalonePHULRoutineReplayKeepsOneSetOneDiaryActivityAndOriginalSlotOnSecondClient() async throws {
        let client = makeClient()
        let email = "standalone-\(UUID())@example.test"
        let password = UUID().uuidString
        let uid = try await client.auth.createUser(withEmail: email, password: password).user.uid
        let directory = try XCTUnwrap(directories.last)
        let workouts = FirestoreWorkoutRepository(db: client.db, outboxURL: directory.appendingPathComponent("workouts.json"),
                                                  currentUserID: { client.auth.currentUser?.uid })
        let container = DIContainer.shared
        let previous = (container.authService, container.workoutRepository, container.nutritionRepository)
        let auth = MockAuthService(); auth.currentUserID = uid
        container.authService = auth; container.workoutRepository = workouts; container.nutritionRepository = client.repository
        defer { (container.authService, container.workoutRepository, container.nutritionRepository) = previous }
        let now = Date()
        var plan = try XCTUnwrap(WorkoutRules.generatePreBuiltPrograms().first { $0.name.contains("PHUL") })
        plan.id = "phul"; plan.userID = uid; plan.currentProgressIndex = 39
        for routine in plan.routines { routine.userID = uid }
        _ = try await workouts.saveProgram(userID: uid, program: plan)
        let day = try XCTUnwrap(DiaryDayContext(userID: uid, date: now))
        await accept(DailyLog(id: day.dayKey, date: now, meals: [Meal(name: "Lunch", foodItems: [food("existing-lunch")])]), client: client, userID: uid)
        try await waitForSync(client, userID: uid)

        let routine = try XCTUnwrap(plan.routine(forSlot: 39)?.deepCopy())
        routine.exercises[0].sets[0].isCompleted = true
        routine.exercises[0].sets[0].weight = 135
        routine.exercises[0].sets[0].reps = 8
        var draft = WorkoutSessionDraft(routine: routine, now: now)
        draft.elapsed = 180
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 180))
        let log = try XCTUnwrap(draft.completion)
        let exercise = try XCTUnwrap(draft.diaryExercise)
        let suite = "standalone-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let training = WorkoutService(defaults: defaults)
        training.setActiveProgram(plan)
        let diary = DailyLogService()
        for _ in 0..<2 {
            let historyAccepted = await training.saveWorkoutSessionLog(log)
            let diaryAccepted = await diary.saveWorkoutExercise(for: uid, exercise: exercise)
            let programAccepted = await training.recordProgramCompletion(log)
            XCTAssertTrue(historyAccepted && diaryAccepted && programAccepted)
        }
        try await waitForWorkoutSync(workouts, userID: uid)
        try await waitForSync(client, userID: uid)
        let reopened = makeClient()
        _ = try await reopened.auth.signIn(withEmail: email, password: password)
        let user = reopened.db.collection("users").document(uid)
        let history = try await user.collection("workoutSessionLogs").getDocuments(source: .server)
        XCTAssertEqual(history.documents.map(\.documentID), [draft.sessionID])
        let saved = try XCTUnwrap(history.documents.first).data(as: WorkoutSessionLog.self)
        XCTAssertEqual(saved.programLinkDecision, .standalone)
        XCTAssertNil(saved.programContext)
        XCTAssertEqual(saved.completedExercises.flatMap(\.sets).map(\.weight), [135])
        XCTAssertEqual(saved.completedExercises.flatMap(\.sets).map(\.reps), [8])
        let savedDay = try await user.collection("dailyLogs").document(day.dayKey).getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(savedDay.exercises?.map(\.sessionID), [draft.sessionID])
        XCTAssertEqual(savedDay.meals.flatMap(\.foodItems).map(\.id), ["existing-lunch"])
        let savedPlan = try await user.collection("workoutPrograms").document("phul").getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(savedPlan.currentProgressIndex, 39)
        XCTAssertEqual(savedPlan.routine(forSlot: 39)?.id, routine.id)
    }

    func testWorkoutWritesSurviveOfflineQueueAndRetryWithoutDuplicateHistory() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let queueURL = directories.last!.appendingPathComponent("workouts.json")
        let workouts = FirestoreWorkoutRepository(db: client.db, outboxURL: queueURL, currentUserID: { client.auth.currentUser?.uid })
        try await client.db.disableNetwork()
        var plan = WorkoutProgram(id: "offline-plan", userID: uid, name: "Original", routines: [])
        _ = try await workouts.saveProgram(userID: uid, program: plan)
        plan.name = "Edited offline"
        _ = try await workouts.saveProgram(userID: uid, program: plan)
        let log = WorkoutSessionLog(id: "stable-session", date: Date(), routineID: "routine", completedExercises: [])
        try await workouts.saveWorkoutSessionLog(userID: uid, log: log)
        try await workouts.saveWorkoutSessionLog(userID: uid, log: log)
        let diskQueue = WorkoutOutbox(fileURL: queueURL)
        XCTAssertEqual(try diskQueue.pending(userID: uid).count, 4)
        let localHistory = try await workouts.fetchWorkoutHistory(userID: uid, limit: 10)
        XCTAssertEqual(localHistory.map(\.id), ["stable-session"])
        try await client.db.enableNetwork()
        for _ in 0..<200 {
            if workouts.workoutSyncState(userID: uid) == .synced { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(workouts.workoutSyncState(userID: uid), .synced)
        let user = client.db.collection("users").document(uid)
        let remotePlan = try await user.collection("workoutPrograms").document("offline-plan")
            .getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(remotePlan.name, "Edited offline")
        let sessions = try await user.collection("workoutSessionLogs").getDocuments(source: .server)
        XCTAssertEqual(sessions.documents.map(\.documentID), ["stable-session"])
        try await workouts.deleteProgram(userID: uid, programID: "offline-plan")
        for _ in 0..<100 {
            if workouts.workoutSyncState(userID: uid) == .synced { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let deleted = try await user.collection("workoutPrograms").document("offline-plan").getDocument(source: .server)
        XCTAssertFalse(deleted.exists)
        let kept = try await user.collection("workoutSessionLogs").document("stable-session").getDocument(source: .server)
        XCTAssertTrue(kept.exists)
    }

    @MainActor
    func testRescuePersistsWorkoutAndMealTogetherOfflineAndUndoClearsCloudField() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let queueURL = directories.last!.appendingPathComponent("rescue-workouts.json")
        let workouts = FirestoreWorkoutRepository(db: client.db, outboxURL: queueURL, currentUserID: { client.auth.currentUser?.uid })
        let today = Calendar.current.startOfDay(for: Date())
        let routine = WorkoutRoutine(id: "phul-upper", userID: uid, name: "Upper", dateCreated: today,
            exercises: [RoutineExercise(name: "Press", sets: [ExerciseSet(target: "8")])])
        let base = WorkoutProgram(id: "rescue-phul", userID: uid, name: "PHUL", routines: [routine], startDate: today,
            daysOfWeek: [Calendar.current.component(.weekday, from: today)])
        let replacement = MealPlanDay(id: MealPlanEditingRules.dayID(today), date: today,
            meals: [PlannedMeal(mealType: "Dinner", foodItem: food("rescue-meal"))])
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let preview = try WeekRescueRules.preview(program: base, reason: .busyDay, workoutDate: tomorrow,
            mealChanges: [try RescueMealChange(original: nil, replacement: replacement)])
        let changed = try WeekRescueRules.applying(preview, to: base)
        try await client.db.disableNetwork()
        _ = try await workouts.saveProgram(userID: uid, program: changed)
        let pending = try WorkoutOutbox(fileURL: queueURL).pending(userID: uid)
        XCTAssertEqual(pending.count, 1, "Both adjustments must share a single durable receipt")
        let reloaded = try JSONDecoder().decode(WorkoutProgram.self, from: XCTUnwrap(pending[0].payload))
        XCTAssertEqual(reloaded.weekRescue?.id, preview.id)
        XCTAssertEqual(reloaded.weekRescue?.meals[0].replacement.meals[0].foodItem?.id, "rescue-meal")
        try await client.db.enableNetwork()
        for _ in 0..<200 {
            if workouts.workoutSyncState(userID: uid) == .synced { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(workouts.workoutSyncState(userID: uid), .synced)
        let ref = client.db.collection("users").document(uid).collection("workoutPrograms").document("rescue-phul")
        var remote = try await ref.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(remote.weekRescue?.resolving(nil, on: today)?.meals.first?.foodItem?.id, "rescue-meal")
        XCTAssertEqual(remote.date(forSlot: 0), tomorrow)
        remote.currentProgressIndex = 1
        let undone = try WeekRescueRules.undoing(id: preview.id, in: remote)
        _ = try await workouts.saveProgram(userID: uid, program: undone)
        for _ in 0..<200 {
            if workouts.workoutSyncState(userID: uid) == .synced { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let restored = try await ref.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertNil(restored.weekRescue)
        XCTAssertEqual(restored.currentProgressIndex, 1)
        XCTAssertEqual(restored.name, "PHUL")
    }

    func testWorkoutQueueRejectsWrongAccountAndCorruptStorage() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let url = directories.last!.appendingPathComponent("workout-corruption.json")
        let workouts = FirestoreWorkoutRepository(db: client.db, outboxURL: url, currentUserID: { client.auth.currentUser?.uid })
        let log = WorkoutSessionLog(id: "session", date: Date(), routineID: "routine", completedExercises: [])
        do {
            try await workouts.saveWorkoutSessionLog(userID: "another-account", log: log)
            XCTFail("A draft from another account must not be accepted")
        } catch {}
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unreadable".utf8).write(to: url)
        do {
            try await workouts.saveWorkoutSessionLog(userID: uid, log: log)
            XCTFail("A corrupt queue must not be replaced with an apparently successful write")
        } catch {}
        XCTAssertEqual(try String(contentsOf: url), "unreadable")
    }
    private struct Client {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
        let repository: FirestoreNutritionRepository
    }
    private var clients: [Client] = []
    private var directories: [URL] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(EmulatorAppCheckFactory())
    }

    override func tearDown() {
        for client in clients { try? client.auth.signOut(); client.app.delete { _ in } }
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        clients = []
    }

    private func makeClient() -> Client {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"
        options.apiKey = "A" + String(repeating: "0", count: 38) // SDK-valid format, deliberately not a credential.
        let name = "diary-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = FirebaseApp.app(name: name)!
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app)
        db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings
        settings.isSSLEnabled = false
        db.settings = settings
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        directories.append(directory)
        let repository = FirestoreNutritionRepository(db: db, outboxURL: directory.appendingPathComponent("outbox.json"), currentUserID: { auth.currentUser?.uid })
        let client = Client(app: app, auth: auth, db: db, repository: repository)
        clients.append(client)
        return client
    }

    private func read(_ client: Client, userID: String, date: Date) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in
            client.repository.fetchLogInternal(userID: userID, date: date) { continuation.resume(with: $0) }
        }
    }

    private func accept(_ log: DailyLog, client: Client, userID: String) async {
        let accepted = await withCheckedContinuation { continuation in
            client.repository.updateDailyLog(userID: userID, log: log) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(accepted)
    }

    private func waitForWorkoutSync(_ repository: FirestoreWorkoutRepository, userID: String) async throws {
        repository.retryPendingWorkouts(userID: userID)
        for _ in 0..<100 {
            if repository.workoutSyncState(userID: userID) == .synced { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw URLError(.timedOut)
    }

    private func waitForSync(_ client: Client, userID: String) async throws {
        for attempt in 0..<200 {
            if attempt % 10 == 0 { client.repository.retryPendingDailyLogs(userID: userID) }
            if client.repository.dailyLogSyncState(userID: userID) == .synced { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let state = client.repository.dailyLogSyncState(userID: userID)
        throw NSError(domain: "MyFitPlateTests.DiarySync", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Durable diary queue did not reach the local emulator. Final sync state: \(state)."])
    }

    private func food(_ id: String) -> FoodItem {
        FoodItem(id: id, name: id, calories: 100, protein: 10, carbs: 10, fats: 2)
    }

    func testTwoDevicesAndOfflineReplayPreserveFoodAndWater() async throws {
        let first = makeClient()
        let second = makeClient()
        let email = "diary-\(UUID())@example.test"
        let uid = try await first.auth.createUser(withEmail: email, password: "local-test-password").user.uid
        _ = try await second.auth.signIn(withEmail: email, password: "local-test-password")
        let date = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let id = formatter.string(from: date)
        let ref = first.db.collection("users").document(uid).collection("dailyLogs").document(id)
        let original = DailyLog(id: id, date: date, meals: [Meal(name: "Lunch", foodItems: [food("original")])])
        try await ref.setData(Firestore.Encoder().encode(original))
        var a = try await read(first, userID: uid, date: date)
        var b = try await read(second, userID: uid, date: date)
        a.meals[0].foodItems.append(food("first"))
        b.meals[0].foodItems.append(food("second"))
        await accept(a, client: first, userID: uid)
        await accept(b, client: second, userID: uid)
        try await waitForSync(first, userID: uid)
        try await waitForSync(second, userID: uid)
        let merged = try await ref.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(Set(merged.meals.flatMap(\.foodItems).map(\.id)), ["original", "first", "second"])

        let fresh = makeClient()
        _ = try await fresh.auth.signIn(withEmail: email, password: "local-test-password")
        try await fresh.db.disableNetwork()
        var offline = try await read(fresh, userID: uid, date: date)
        XCTAssertTrue(offline.meals.isEmpty)
        offline.meals = [Meal(name: "Dinner", foodItems: [food("offline")])]
        offline.waterTracker = WaterTracker(totalOunces: 8, date: date)
        offline.pendingMutationID = "stable-water-receipt"
        await accept(offline, client: fresh, userID: uid)
        let local = try await read(fresh, userID: uid, date: date)
        XCTAssertEqual(local.waterTracker?.totalOunces, 8)
        try await fresh.db.enableNetwork()
        fresh.repository.retryPendingDailyLogs(userID: uid)
        try await waitForSync(fresh, userID: uid)
        await accept(offline, client: fresh, userID: uid) // Replay after acknowledgement.
        try await waitForSync(fresh, userID: uid)
        let final = try await ref.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(final.meals.flatMap(\.foodItems).count, 4)
        XCTAssertEqual(final.waterTracker?.totalOunces, 8)
    }

    func testUnreadableProfileFailsInsteadOfBecomingMissing() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        try await client.db.disableNetwork()
        let repository = FirestoreSettingsRepository(db: client.db)
        let result: Result<[String: Any]?, Error> = await withCheckedContinuation { continuation in
            repository.fetchAccountProfile(userID: uid, requireServer: false) { continuation.resume(returning: $0) }
        }
        if case .success = result { XCTFail("An unreadable profile must not route to setup") }
    }

    func testListenerKeepsOfflineFoodVisibleThroughAcknowledgement() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let date = Calendar.current.startOfDay(for: Date())
        var log = try await read(client, userID: uid, date: date)
        try await client.db.disableNetwork()
        let accepted = expectation(description: "Offline food is immediately visible")
        let observationLock = NSLock()
        var observedFood = false
        var disappearedAfterAcceptance = false
        let listener = client.repository.addLogSnapshotListener(userID: uid, date: date) { result in
            guard case .success(let visible) = result else { return }
            let containsFood = visible.meals.flatMap(\.foodItems).contains { $0.id == "offline-visible" }
            observationLock.lock()
            defer { observationLock.unlock() }
            if containsFood, !observedFood { observedFood = true; accepted.fulfill() }
            if observedFood, !containsFood { disappearedAfterAcceptance = true }
        }
        defer { client.repository.removeLogSnapshotListener(listener) }
        log.meals = [Meal(name: "Lunch", foodItems: [food("offline-visible")])]
        await accept(log, client: client, userID: uid)
        await fulfillment(of: [accepted], timeout: 5)
        try await client.db.enableNetwork()
        try await waitForSync(client, userID: uid)
        try await Task.sleep(nanoseconds: 200_000_000)
        let disappeared = observationLock.withLock { disappearedAfterAcceptance }
        XCTAssertFalse(disappeared, "Acknowledging the queue must not republish an older empty snapshot")
    }

    func testSetupRetriesCannotOverwriteAnEstablishedProfile() async throws {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let ref = client.db.collection("users").document(uid)
        try await ref.setData(["isFirstLogin": false, "goals": ["calories": 2345], "weight": 177.0])
        let repository = FirestoreSettingsRepository(db: client.db)
        do {
            try await repository.saveOnboardingGoals(userID: uid, data: ["goals": ["calories": 1000]])
            XCTFail("An already configured account must reject a stale setup save")
        } catch { /* Expected: eligibility is checked inside the transaction. */ }
        try await repository.createInitialUserData(userID: uid, email: "retry@example.test", username: "retry")
        let profile = try await ref.getDocument(source: .server).data()
        XCTAssertEqual((profile?["goals"] as? [String: Any])?["calories"] as? Int, 2345)
        XCTAssertEqual(profile?["weight"] as? Double, 177)
        XCTAssertEqual(profile?["isFirstLogin"] as? Bool, false)
    }
}
