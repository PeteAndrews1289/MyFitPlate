import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class WaveTwoNutritionEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}
private final class WaveTwoNutritionEmulatorFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("w2-nutrition-test-") ? WaveTwoNutritionEmulatorCheck() : nil
    }
}

/// Only synthetic accounts and fixed localhost emulator endpoints are used here.
@MainActor
final class WaveTwoNutritionPersistenceTests: XCTestCase {
    private struct Client {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
        let directory: URL
        let uid: String
        let repository: FirestoreNutritionRepository
    }
    private var clients: [Client] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(WaveTwoNutritionEmulatorFactory())
    }
    override func tearDown() {
        for client in clients {
            try? client.auth.signOut(); client.app.delete { _ in }
            try? FileManager.default.removeItem(at: client.directory)
        }
        clients = []; super.tearDown()
    }
    private func makeClient() async throws -> Client {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"; options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "w2-nutrition-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = try XCTUnwrap(FirebaseApp.app(name: name))
        let auth = Auth.auth(app: app); auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app); db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let uid = try await auth.signInAnonymously().user.uid
        let repo = FirestoreNutritionRepository(db: db, outboxURL: directory.appendingPathComponent("outbox.json"),
                                                currentUserID: { auth.currentUser?.uid })
        let client = Client(app: app, auth: auth, db: db, directory: directory, uid: uid, repository: repo)
        clients.append(client); return client
    }
    private func food(_ id: String = "ingredient") -> FoodItem {
        FoodItem(id: id, name: "Rice", calories: 400, protein: 25, carbs: 50, fats: 10,
                 servingSize: "100 g", servingWeight: 100, sourceMetadata: .userEntered(sourceName: "QA measured ingredient"))
    }
    private func owner(_ client: Client) -> DocumentReference { client.db.collection("users").document(client.uid) }
    private func restart(_ client: Client) -> FirestoreNutritionRepository {
        FirestoreNutritionRepository(db: client.db, outboxURL: client.directory.appendingPathComponent("restart.json"), currentUserID: { client.auth.currentUser?.uid })
    }
    private func day() -> MealPlanDay { MealPlanEditingRules.emptyDay(Date()) }

    func testCompositionAcceptedReplayIsImmutableAndCannotOverwriteOrResurrectDocument() async throws {
        let client = try await makeClient()
        var composition = SavedMealComposition(id: "composed-meal", name: "Original meal", components: [food()])
        composition.updatedAt = Date(timeIntervalSince1970: 1_700_000_000.1234567)
        let first = MealCompositionSaveProposal(userID: client.uid, expected: nil, updated: composition)
        let accepted = try await client.repository.saveSavedMealComposition(userID: client.uid, proposal: first)
        var edited = accepted; edited.name = "Later meal"; edited.revisionID = UUID().uuidString
        let later = try await client.repository.saveSavedMealComposition(userID: client.uid, proposal: .init(userID: client.uid, expected: accepted, updated: edited))
        let restarted = restart(client)
        let replay = try await restarted.saveSavedMealComposition(userID: client.uid, proposal: first)
        XCTAssertEqual(replay.name, "Original meal", "Accepted return is the immutable receipt; callers reload current documents separately")
        let ref = owner(client).collection("savedMealCompositions").document(composition.id)
        let current = try await ref.getDocument(source: .server).data(as: SavedMealComposition.self)
        XCTAssertEqual(current.revisionID, later.revisionID)
        try await ref.delete()
        let afterDelete = try await restarted.saveSavedMealComposition(userID: client.uid, proposal: first)
        XCTAssertEqual(afterDelete.name, "Original meal")
        let deleted = try await ref.getDocument(source: .server)
        XCTAssertFalse(deleted.exists)
        let status = try await restarted.resolveSavedMealComposition(userID: client.uid, proposal: first, cancelPending: true)
        XCTAssertEqual(status, .accepted)
    }

    func testCompositionRenamePreservesUnknownNestedSourceFieldsAndNanosecondTimestamp() async throws {
        let client = try await makeClient()
        let value = SavedMealComposition(id: "source-preservation", name: "Breakfast", components: [food()])
        let ref = owner(client).collection("savedMealCompositions").document(value.id)
        var raw = try Firestore.Encoder().encode(value); raw["futureWorkspaceField"] = "keep"
        var components = try XCTUnwrap(raw["components"] as? [[String: Any]])
        components[0]["futureIngredient"] = "keep"
        var metadata = try XCTUnwrap(components[0]["sourceMetadata"] as? [String: Any])
        let originalTimestamp = Timestamp(seconds: 1_700_000_000, nanoseconds: 123_456_789)
        metadata["createdAt"] = originalTimestamp; metadata["futureEvidence"] = ["source": "keep"]
        components[0]["sourceMetadata"] = metadata; raw["components"] = components
        try await ref.setData(raw)
        let serverBefore = try await readRaw(ref)
        let serverFood = try XCTUnwrap((serverBefore["components"] as? [[String: Any]])?.first)
        let serverSource = try XCTUnwrap(serverFood["sourceMetadata"] as? [String: Any])
        let serverTimestamp = try XCTUnwrap(serverSource["createdAt"] as? Timestamp)
        let actual = try await ref.getDocument(source: .server).data(as: SavedMealComposition.self)
        var renamed = actual; renamed.name = "Renamed breakfast"; renamed.revisionID = UUID().uuidString
        _ = try await client.repository.saveSavedMealComposition(userID: client.uid, proposal: .init(userID: client.uid, expected: actual, updated: renamed))
        let after = try await readRaw(ref)
        XCTAssertEqual(after["futureWorkspaceField"] as? String, "keep")
        let savedFood = try XCTUnwrap((after["components"] as? [[String: Any]])?.first)
        XCTAssertEqual(savedFood["futureIngredient"] as? String, "keep")
        let savedSource = try XCTUnwrap(savedFood["sourceMetadata"] as? [String: Any])
        XCTAssertEqual((savedSource["futureEvidence"] as? [String: String])?["source"], "keep")
        let savedTimestamp = try XCTUnwrap(savedSource["createdAt"] as? Timestamp)
        XCTAssertEqual(savedTimestamp.seconds, serverTimestamp.seconds)
        XCTAssertEqual(savedTimestamp.nanoseconds, serverTimestamp.nanoseconds)
    }

    func testSavedWeekCanReadAndResolveOrFenceFrozenReviewAfterTimeZoneTravel() async throws {
        let client = try await makeClient()
        let previous = NSTimeZone.default; defer { NSTimeZone.default = previous }
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        let start = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        var days = (0..<7).map { MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: $0, to: start)!) }
        days[0].meals = [.init(id: "home-meal", mealType: "Dinner", foodItem: food())]
        let value = SavedMealWeekTemplate(id: "home-week", name: "Home week", days: days)
        let proposal = MealWeekTemplateSaveProposal(userID: client.uid, expected: nil, updated: value)
        let accepted = try await client.repository.saveSavedMealWeekTemplate(userID: client.uid, proposal: proposal)
        var edited = accepted; edited.name = "Renamed home week"; edited.revisionID = UUID().uuidString
        _ = try await client.repository.saveSavedMealWeekTemplate(userID: client.uid, proposal: .init(userID: client.uid, expected: accepted, updated: edited))
        let replay = try await restart(client).saveSavedMealWeekTemplate(userID: client.uid, proposal: proposal)
        XCTAssertEqual(replay.name, "Home week")
        var another = value; another.id = "cancelled-week"
        let pending = MealWeekTemplateSaveProposal(userID: client.uid, expected: nil, updated: another)
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let loaded = try await restart(client).fetchSavedMealWeekTemplates(userID: client.uid)
        XCTAssertEqual(loaded.count, 1); XCTAssertEqual(loaded[0].days[0].id, "2026-11-02")
        XCTAssertEqual(loaded[0].name, "Renamed home week")
        XCTAssertNoThrow(try MealWeekTemplateRules.draft(loaded[0], starting: Date()))
        let acceptedStatus = try await client.repository.resolveSavedMealWeekTemplate(userID: client.uid, proposal: proposal, cancelPending: true)
        XCTAssertEqual(acceptedStatus, .accepted)
        let pendingStatus = try await client.repository.resolveSavedMealWeekTemplate(userID: client.uid, proposal: pending, cancelPending: false)
        XCTAssertEqual(pendingStatus, .pending)
        let fence = try await client.repository.resolveSavedMealWeekTemplate(userID: client.uid, proposal: pending, cancelPending: true)
        XCTAssertEqual(fence, .cancelled)
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        do { _ = try await client.repository.saveSavedMealWeekTemplate(userID: client.uid, proposal: pending); XCTFail("Travel cancellation must permanently fence late transport") } catch { XCTAssertEqual(error as? MealPlanChangeReceiptError, .cancelled) }
        let absent = try await owner(client).collection("savedMealWeekTemplates").document(another.id).getDocument(source: .server)
        XCTAssertFalse(absent.exists)
        let originalRef = owner(client).collection("savedMealWeekTemplates").document(value.id)
        try await originalRef.delete()
        let afterDelete = try await restart(client).saveSavedMealWeekTemplate(userID: client.uid, proposal: proposal)
        XCTAssertEqual(afterDelete.name, "Home week")
        let stillDeleted = try await originalRef.getDocument(source: .server)
        XCTAssertFalse(stillDeleted.exists)
    }

    func testPlanningPayloadReuseStaleCASAndAccountChangeCannotCreatePartialRecords() async throws {
        let client = try await makeClient()
        let value = SavedMealComposition(id: "guarded", name: "First", components: [food()])
        let proposal = MealCompositionSaveProposal(userID: client.uid, expected: nil, updated: value)
        let accepted = try await client.repository.saveSavedMealComposition(userID: client.uid, proposal: proposal)
        var altered = value; altered.name = "Another intent"
        do { _ = try await client.repository.saveSavedMealComposition(userID: client.uid, proposal: .init(userID: client.uid, operationID: proposal.operationID, expected: nil, updated: altered)); XCTFail("Reused operation payload") } catch { XCTAssertEqual(error as? MealPlanChangeReceiptError, .changed) }
        var stale = accepted; stale.components[0].calories += 1
        let staleProposal = MealCompositionSaveProposal(userID: client.uid, expected: stale, updated: altered)
        do { _ = try await client.repository.saveSavedMealComposition(userID: client.uid, proposal: staleProposal); XCTFail("Stale CAS") } catch {}
        let receipt = try await owner(client).collection("savedMealCompositionsReceipts").document(staleProposal.operationID.uuidString).getDocument(source: .server)
        XCTAssertFalse(receipt.exists)
        try client.auth.signOut()
        do { _ = try await client.repository.resolveSavedMealComposition(userID: client.uid, proposal: proposal, cancelPending: true); XCTFail("Account guard") } catch { XCTAssertEqual(error as? MealPlanChangeReceiptError, .accountChanged) }
    }

    func testSavedFoodMergeAndCheckedUndoRestoreRawDeletedRecordAndPreserveLaterDiary() async throws {
        let client = try await makeClient(); let foods = owner(client).collection("customFoods")
        let keeper = food("keeper"), duplicate = food("duplicate")
        var rawKeeper = try Firestore.Encoder().encode(keeper); rawKeeper["futureKeeper"] = "keep"
        var rawDuplicate = try Firestore.Encoder().encode(duplicate); rawDuplicate["futureRemoved"] = "restore"
        var source = try XCTUnwrap(rawDuplicate["sourceMetadata"] as? [String: Any])
        let stamp = Timestamp(seconds: 1_700_000_000, nanoseconds: 987_654_321)
        source["createdAt"] = stamp; source["futureEvidence"] = "restore"; rawDuplicate["sourceMetadata"] = source
        try await foods.document(keeper.id).setData(rawKeeper); try await foods.document(duplicate.id).setData(rawDuplicate)
        let serverBefore = try await readRaw(foods.document(duplicate.id))
        let serverSource = try XCTUnwrap(serverBefore["sourceMetadata"] as? [String: Any])
        let serverTimestamp = try XCTUnwrap(serverSource["createdAt"] as? Timestamp)
        let first = try await foods.document(keeper.id).getDocument(source: .server).data(as: FoodItem.self)
        let second = try await foods.document(duplicate.id).getDocument(source: .server).data(as: FoodItem.self)
        let merge = try SavedFoodLibraryMutation.merge([first, second], keeping: first.id)
        let diaryRef = owner(client).collection("dailyLogs").document("2026-11-01")
        let diary = DailyLog(id: "2026-11-01", date: Date(), meals: [.init(name: "Lunch", foodItems: [duplicate])])
        try await diaryRef.setData(Firestore.Encoder().encode(diary))
        try await client.repository.applySavedFoodLibraryMutation(userID: client.uid, mutation: merge)
        let removed = try await foods.document(duplicate.id).getDocument(source: .server)
        XCTAssertFalse(removed.exists)
        try await restart(client).applySavedFoodLibraryMutation(userID: client.uid, mutation: merge.inverse())
        let restored = try await readRaw(foods.document(duplicate.id))
        XCTAssertEqual(restored["futureRemoved"] as? String, "restore")
        let restoredSource = try XCTUnwrap(restored["sourceMetadata"] as? [String: Any])
        XCTAssertEqual(restoredSource["futureEvidence"] as? String, "restore")
        let restoredStamp = try XCTUnwrap(restoredSource["createdAt"] as? Timestamp)
        XCTAssertEqual(restoredStamp.seconds, serverTimestamp.seconds); XCTAssertEqual(restoredStamp.nanoseconds, serverTimestamp.nanoseconds)
        let kept = try await readRaw(foods.document(keeper.id))
        XCTAssertEqual(kept["futureKeeper"] as? String, "keep")
        try await client.repository.applySavedFoodLibraryMutation(userID: client.uid, mutation: merge)
        let replayed = try await foods.document(duplicate.id).getDocument(source: .server)
        XCTAssertTrue(replayed.exists, "Accepted replay must not delete the restored record")
        let savedDiary = try await diaryRef.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(try PlanningDocumentRules.fingerprint(savedDiary), try PlanningDocumentRules.fingerprint(diary))
        do { try await client.repository.applySavedFoodLibraryMutation(userID: client.uid, mutation: merge.inverse()); XCTFail("One accepted merge can be undone only once") } catch { XCTAssertEqual(error as? LibraryMutationError, .changed) }
    }

    func testRecipeMergeMetadataAndUndoPreserveUnknownFieldsWithoutRewritingHistoricalSources() async throws {
        let client = try await makeClient(); let recipes = owner(client).collection("recipes")
        let first = Recipe(id: "recipe-keeper", name: "Rice", ingredients: ["100 g rice"], detailedIngredients: [food()],
            instructions: ["Cook"], nutrition: Nutrition(calories: 400, protein: 25, carbs: 50, fats: 10), servings: 1, nutritionBasis: .perServing)
        var second = first; second.id = "recipe-copy"
        var rawFirst = try Firestore.Encoder().encode(first); rawFirst["futureRecipe"] = "keep"
        rawFirst["libraryMetadata"] = ["favorite": false, "tags": [], "futureOrganization": "keep"]
        var rawSecond = try Firestore.Encoder().encode(second); rawSecond["futureCopy"] = "keep"
        try await recipes.document(first.id!).setData(rawFirst); try await recipes.document(second.id!).setData(rawSecond)
        let keeper = try await recipes.document(first.id!).getDocument(source: .server).data(as: Recipe.self)
        let copy = try await recipes.document(second.id!).getDocument(source: .server).data(as: Recipe.self)
        let merge = try RecipeLibraryRules.merging([keeper, copy], keeping: first.id!)
        try await client.repository.applyRecipeLibraryMutation(userID: client.uid, mutation: merge)
        let afterMerge = try await readRaw(recipes.document(second.id!))
        XCTAssertEqual(afterMerge["futureCopy"] as? String, "keep")
        XCTAssertEqual((afterMerge["libraryMetadata"] as? [String: Any])?["mergedIntoRecipeID"] as? String, first.id)
        try await client.repository.applyRecipeLibraryMutation(userID: client.uid, mutation: merge.inverse())
        let restored = try await readRaw(recipes.document(first.id!))
        XCTAssertEqual(restored["futureRecipe"] as? String, "keep")
        XCTAssertEqual((restored["libraryMetadata"] as? [String: Any])?["futureOrganization"] as? String, "keep")
        let restoredCopy = try await readRaw(recipes.document(second.id!))
        XCTAssertNil((restoredCopy["libraryMetadata"] as? [String: Any])?["mergedIntoRecipeID"])
        try await restart(client).applyRecipeLibraryMutation(userID: client.uid, mutation: merge)
        let afterReplay = try await recipes.document(second.id!).getDocument(source: .server).data(as: Recipe.self)
        XCTAssertNil(afterReplay.libraryMetadata?.mergedIntoRecipeID)
        let cancelled = try RecipeLibraryRules.updating(keeper, metadata: .init(favorite: true), title: "Cancelled favorite")
        let status = try await client.repository.resolveRecipeLibraryMutation(userID: client.uid, mutation: cancelled, cancelPending: true)
        XCTAssertEqual(status, .cancelled)
        do { try await client.repository.applyRecipeLibraryMutation(userID: client.uid, mutation: cancelled); XCTFail("Cancelled metadata intent") } catch { XCTAssertEqual(error as? LibraryMutationError, .cancelled) }
    }

    func testStaleGroceryUndoCannotOverwriteLaterSameRowRevisionOrUnrelatedRows() async throws {
        let client = try await makeClient()
        let first = GroceryListItem(name: "Rice", quantity: 200, unit: "g", source: "manual")
        let other = GroceryListItem(name: "Coffee", quantity: 1, unit: "package", source: "manual")
        let ref = owner(client).collection("userSettings").document("groceryList")
        try await ref.setData(["items": [try Firestore.Encoder().encode(first), try Firestore.Encoder().encode(other)]])
        var checked = first; checked.isCompleted = true
        let check = GroceryListMutation(before: [first], upserts: [checked], removedIDs: [], title: "Check rice")
        let checkedItems = try await client.repository.applyGroceryMutation(userID: client.uid, mutation: check)
        let current = try XCTUnwrap(checkedItems.first { $0.id == first.id })
        var changed = current; changed.quantity = 500
        let later = GroceryListMutation(before: [current], upserts: [changed], removedIDs: [], title: "Larger package")
        _ = try await client.repository.applyGroceryMutation(userID: client.uid, mutation: later)
        do { _ = try await client.repository.applyGroceryMutation(userID: client.uid, mutation: check.inverse()); XCTFail("Stale Undo must not replace later row") } catch { XCTAssertEqual(error as? GroceryChecklistError, .changed) }
        let replay = try await restart(client).applyGroceryMutation(userID: client.uid, mutation: check)
        XCTAssertEqual(replay.first { $0.id == first.id }?.quantity, 500)
        XCTAssertEqual(replay.first { $0.id == first.id }?.revisionID, later.upserts[0].revisionID)
        XCTAssertEqual(replay.first { $0.id == other.id }, other)
    }

    func testGroceryStatusCancelExactPayloadRevisionAndRawDeletedUndoAreTransactional() async throws {
        let client = try await makeClient()
        let item = GroceryListItem(name: "Rice", quantity: 200, unit: "g", source: "manual")
        let other = GroceryListItem(name: "Coffee", quantity: 1, unit: "package", source: "manual")
        let ref = owner(client).collection("userSettings").document("groceryList")
        var raw = try Firestore.Encoder().encode(item); raw["futureRow"] = "restore"
        let stamp = Timestamp(seconds: 1_700_000_000, nanoseconds: 111_222_333); raw["futureObservedAt"] = stamp
        var rawOther = try Firestore.Encoder().encode(other); rawOther["futureOther"] = "keep"
        try await ref.setData(["items": [raw, rawOther], "futureList": "keep"])
        let serverBefore = try await readRaw(ref)
        let serverRows = try XCTUnwrap(serverBefore["items"] as? [[String: Any]])
        let serverRow = try XCTUnwrap(serverRows.first { ($0["id"] as? String) == item.id.uuidString })
        let serverTimestamp = try XCTUnwrap(serverRow["futureObservedAt"] as? Timestamp)
        let baseline = try await client.repository.fetchGroceryList(userID: client.uid)
        let remove = GroceryListMutation(before: [baseline[0]], upserts: [], removedIDs: [item.id], title: "Remove rice")
        let pending = try await client.repository.resolveGroceryMutation(userID: client.uid, mutation: remove, cancelPending: false)
        XCTAssertEqual(pending, .pending)
        _ = try await client.repository.applyGroceryMutation(userID: client.uid, mutation: remove)
        let status = try await restart(client).resolveGroceryMutation(userID: client.uid, mutation: remove, cancelPending: true)
        XCTAssertEqual(status, .accepted)
        let inverse = remove.inverse()
        let restored = try await client.repository.applyGroceryMutation(userID: client.uid, mutation: inverse)
        let restoredItem = try XCTUnwrap(restored.first { $0.id == item.id })
        XCTAssertEqual(restoredItem.revisionID, GroceryListMutation.revisionID(operationID: inverse.id, itemID: item.id))
        let after = try await readRaw(ref)
        XCTAssertEqual(after["futureList"] as? String, "keep")
        let rows = try XCTUnwrap(after["items"] as? [[String: Any]])
        let rawRestored = try XCTUnwrap(rows.first { ($0["id"] as? String) == item.id.uuidString })
        XCTAssertEqual(rawRestored["futureRow"] as? String, "restore")
        let restoredStamp = try XCTUnwrap(rawRestored["futureObservedAt"] as? Timestamp)
        XCTAssertEqual(restoredStamp.seconds, serverTimestamp.seconds)
        XCTAssertEqual(restoredStamp.nanoseconds, serverTimestamp.nanoseconds)
        XCTAssertEqual(rows.first { ($0["id"] as? String) == other.id.uuidString }?["futureOther"] as? String, "keep")
        _ = try await client.repository.applyGroceryMutation(userID: client.uid, mutation: remove)
        let afterReplay = try await client.repository.fetchGroceryList(userID: client.uid)
        XCTAssertTrue(afterReplay.contains { $0.id == item.id })
        var altered = remove; altered.title = "Different command"
        do { _ = try await client.repository.resolveGroceryMutation(userID: client.uid, mutation: altered, cancelPending: false); XCTFail("Exact frozen payload required") } catch { XCTAssertEqual(error as? GroceryChecklistError, .changed) }
        var later = restoredItem; later.quantity = 300
        let cancelled = GroceryListMutation(before: [restoredItem], upserts: [later], removedIDs: [], title: "Cancelled amount")
        let fence = try await client.repository.resolveGroceryMutation(userID: client.uid, mutation: cancelled, cancelPending: true)
        XCTAssertEqual(fence, .cancelled)
        do { _ = try await client.repository.applyGroceryMutation(userID: client.uid, mutation: cancelled); XCTFail("Cancelled transport") } catch { XCTAssertEqual(error as? GroceryChecklistError, .cancelled) }
        let unchanged = try await client.repository.fetchGroceryList(userID: client.uid)
        XCTAssertEqual(unchanged.first { $0.id == item.id }?.quantity, 200)
    }

    func testPlanResizeAndFrozenCookingCannotBothAcceptConflictingDefinitions() async throws {
        let client = try await makeClient(); var source = day()
        let phul = owner(client).collection("workoutPrograms").document("phul")
        try await phul.setData(["currentProgressIndex": 38, "skippedIndices": [2, 7], "futureWorkout": "keep"])
        let diary = owner(client).collection("dailyLogs").document(source.id)
        try await diary.setData(["qaPreservedDiary": "keep"])
        let base = PlannedMeal(id: "cooking-source", mealType: "Dinner", foodItem: food(), ingredients: ["100 g rice"])
        let planned = try MealPlanCookingRules.configuring(base, date: source.date, cookingPortions: 4)
        source.meals = [planned]
        try await client.repository.applyMealPlanChange(userID: client.uid, change: .init(title: "Plan batch", before: [day()], after: [source]))
        let loadedActual = try await client.repository.fetchMealPlan(userID: client.uid, dateString: source.id)
        let actual = try XCTUnwrap(loadedActual)
        let actualMeal = try XCTUnwrap(actual.meals.first)
        let cook = try InventoryPlanningRules.cooked(batch: actualMeal.cookingBatch!, originalMeal: actualMeal, stock: [], selectedLots: [:], userID: client.uid, bestBefore: nil)
        var larger = actualMeal; larger.cookingBatch?.totalPortions = 6
        let resize = try MealPlanCookingRules.editingLinked(larger, original: actualMeal, source: actual, relatedDays: [actual])
        async let resized = attempt { try await client.repository.applyMealPlanChange(userID: client.uid, change: resize) }
        async let cooked = attempt { try await client.repository.applyInventoryMutation(userID: client.uid, mutation: cook) }
        let outcomes = await (resized, cooked)
        XCTAssertNotEqual(outcomes.0, outcomes.1, "Conflicting physical cook and plan resize must not both commit or both fail")
        let loadedCanonical = try await client.repository.fetchMealPlan(userID: client.uid, dateString: source.id)
        let canonical = try XCTUnwrap(loadedCanonical)
        let stock = try await client.repository.fetchInventory(userID: client.uid)
        if outcomes.0 {
            XCTAssertEqual(canonical.meals[0].cookingBatch?.totalPortions, 6)
            XCTAssertFalse(stock.contains(where: \.isCookedBatch))
        } else {
            XCTAssertEqual(canonical.meals[0].cookingBatch?.totalPortions, 4)
            XCTAssertEqual(stock.filter(\.isCookedBatch).count, 1)
            XCTAssertEqual(stock.first(where: \.isCookedBatch)?.quantity, 4)
        }
        let preservedProgram = try await readRaw(phul)
        XCTAssertEqual(preservedProgram["currentProgressIndex"] as? Int, 38)
        XCTAssertEqual(preservedProgram["skippedIndices"] as? [Int], [2, 7])
        XCTAssertEqual(preservedProgram["futureWorkout"] as? String, "keep")
        let preservedDiary = try await readRaw(diary)
        XCTAssertEqual(preservedDiary["qaPreservedDiary"] as? String, "keep")
    }
    private func readRaw(_ reference: DocumentReference) async throws -> [String: Any] {
        let snapshot = try await reference.getDocument(source: .server)
        return try XCTUnwrap(snapshot.data())
    }
    private func attempt(_ action: () async throws -> Void) async -> Bool {
        do { try await action(); return true } catch { return false }
    }
}
