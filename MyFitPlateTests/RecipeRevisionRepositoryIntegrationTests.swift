import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class RecipeRevisionEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}
private final class RecipeRevisionEmulatorFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("recipe-revision-test-") ? RecipeRevisionEmulatorCheck() : nil
    }
}

/// Only synthetic accounts and fixed localhost emulator endpoints are used here.
@MainActor
final class RecipeRevisionRepositoryIntegrationTests: XCTestCase {
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
        AppCheck.setAppCheckProviderFactory(RecipeRevisionEmulatorFactory())
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
        let name = "recipe-revision-test-\(UUID())"
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
    private func recipe(_ id: String = "four-serving-recipe") throws -> Recipe {
        var metadata = FoodSourceMetadata.userEntered(sourceName: "Saved ingredient label")
        metadata.createdAt = Date(timeIntervalSince1970: 1_700_000_000.1234567)
        metadata.sourceObservedAt = Date(timeIntervalSince1970: 1_700_000_001.2345678)
        let ingredient = FoodItem(id: "ingredient", name: "Rice", calories: 1_600, protein: 40, carbs: 300, fats: 16,
            servingSize: "400 g", servingWeight: 400, sourceMetadata: metadata, sodium: 10, quantityValue: 400, servingUnit: "g")
        var value = Recipe(id: id, name: "Four-serving rice", ingredients: ["400 g rice"], detailedIngredients: [ingredient],
            instructions: ["Cook the batch."], nutrition: Nutrition(calories: 1_600, protein: 40, carbs: 300, fats: 16, sodium: 10),
            servings: 4, nutritionBasis: .wholeRecipe, nutritionOrigin: .ingredients, unresolvedIngredients: [],
            cookedWeightGrams: 800)
        value.revisionID = try RecipePortionRules.revisionID(for: value)
        return value
    }
    private func reference(_ client: Client, _ id: String) -> DocumentReference {
        client.db.collection("users").document(client.uid).collection("recipes").document(id)
    }
    private func receipt(_ client: Client, _ operationID: UUID) -> DocumentReference {
        client.db.collection("users").document(client.uid).collection("recipeRevisionReceipts").document(operationID.uuidString)
    }
    private func seed(_ value: Recipe, client: Client) async throws -> Recipe {
        let id = try XCTUnwrap(value.id)
        try await reference(client, id).setData(Firestore.Encoder().encode(value))
        return try await reference(client, id).getDocument(source: .server).data(as: Recipe.self)
    }
    private func save(_ value: Recipe, expected: Recipe?, client: Client, operation: UUID = UUID()) async throws -> Recipe {
        try await client.repository.saveRecipeRevision(userID: client.uid, expected: expected, updated: value, operationID: operation)
    }

    func testReceiptReplayAfterNewerEditAndDeliberateContentRevertUseDifferentIntents() async throws {
        let client = try await makeClient(); let first = try recipe(); let initialOperation = UUID()
        let canonical = try await save(first, expected: nil, client: client, operation: initialOperation)
        var second = canonical; second.servings = 8; second.revisionID = try RecipePortionRules.revisionID(for: second)
        let changed = try await save(second, expected: canonical, client: client)
        // A fresh repository models a lost callback followed by process restart.
        let restarted = FirestoreNutritionRepository(db: client.db, outboxURL: client.directory.appendingPathComponent("restart.json"),
                                                     currentUserID: { client.auth.currentUser?.uid })
        let replay = try await restarted.saveRecipeRevision(userID: client.uid, expected: nil, updated: first, operationID: initialOperation)
        XCTAssertEqual(replay.servings, 8); XCTAssertEqual(replay.revisionID, changed.revisionID)
        var reverted = changed; reverted.servings = 4; reverted.revisionID = try RecipePortionRules.revisionID(for: reverted)
        XCTAssertEqual(reverted.revisionID, first.revisionID)
        let acceptedRevert = try await save(reverted, expected: changed, client: client)
        XCTAssertEqual(acceptedRevert.servings, 4)
        let allRecipes = try await reference(client, first.id!).parent.getDocuments(source: .server)
        XCTAssertEqual(allRecipes.documents.count, 1)
        let allReceipts = try await receipt(client, initialOperation).parent.getDocuments(source: .server)
        XCTAssertEqual(allReceipts.documents.count, 3)
    }

    func testFreshIntentCannotBypassExactOpeningSnapshotEvenForMatchingContent() async throws {
        let client = try await makeClient(); let canonical = try await seed(recipe(), client: client)
        var stale = canonical
        stale.detailedIngredients?[0].sourceMetadata?.createdAt = Date(timeIntervalSince1970: 1)
        XCTAssertEqual(try RecipePortionRules.revisionID(for: stale), try RecipePortionRules.revisionID(for: canonical))
        let operation = UUID()
        do { _ = try await save(canonical, expected: stale, client: client, operation: operation); XCTFail("A new intent requires exact opening CAS") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let absentReceipt = try await receipt(client, operation).getDocument(source: .server)
        XCTAssertFalse(absentReceipt.exists)
        let remoteInstructions = ["Newer instructions"]
        try await reference(client, canonical.id!).updateData(["instructions": remoteInstructions])
        var proposal = canonical; proposal.servings = 6; proposal.revisionID = try RecipePortionRules.revisionID(for: proposal)
        do { _ = try await save(proposal, expected: canonical, client: client); XCTFail("Must retain newer source") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let after = try await reference(client, canonical.id!).getDocument(source: .server).data(as: Recipe.self)
        XCTAssertEqual(after.instructions, remoteInstructions); XCTAssertEqual(after.servings, 4)
    }

    func testAcceptedCreateReplayCannotRecreateLaterDeletedRecipeAndStatusCanFinish() async throws {
        let client = try await makeClient(); let value = try recipe(); let operation = UUID()
        _ = try await save(value, expected: nil, client: client, operation: operation)
        try await reference(client, value.id!).delete()
        do { _ = try await save(value, expected: nil, client: client, operation: operation); XCTFail("Retry must not resurrect deleted recipe") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let status = try await client.repository.resolveRecipeRevision(userID: client.uid, expected: nil, updated: value,
            operationID: operation, cancelIfUnaccepted: true)
        XCTAssertEqual(status, .accepted(nil))
        let after = try await reference(client, value.id!).getDocument(source: .server)
        XCTAssertFalse(after.exists)
    }

    func testPermanentCancellationFencesLateSaveAndDeliberateNewIntentStillWorks() async throws {
        let client = try await makeClient(); let value = try recipe(); let operation = UUID()
        let missing = try await client.repository.resolveRecipeRevision(userID: client.uid, expected: nil, updated: value,
            operationID: operation, cancelIfUnaccepted: false)
        XCTAssertEqual(missing, .pending)
        let cancelled = try await client.repository.resolveRecipeRevision(userID: client.uid, expected: nil, updated: value,
            operationID: operation, cancelIfUnaccepted: true)
        XCTAssertEqual(cancelled, .cancelled)
        do { _ = try await save(value, expected: nil, client: client, operation: operation); XCTFail("Late transport must respect cancellation fence") } catch { XCTAssertEqual(error as? RecipeRevisionError, .cancelled) }
        let absent = try await reference(client, value.id!).getDocument(source: .server)
        XCTAssertFalse(absent.exists)
        let deliberate = try await save(value, expected: nil, client: client)
        XCTAssertEqual(deliberate.id, value.id)
    }

    func testOperationIdentityCannotBeReusedForAnotherPayload() async throws {
        let client = try await makeClient(); let value = try recipe(); let operation = UUID()
        _ = try await save(value, expected: nil, client: client, operation: operation)
        var different = value; different.servings = 6; different.revisionID = try RecipePortionRules.revisionID(for: different)
        do { _ = try await save(different, expected: nil, client: client, operation: operation); XCTFail("One operation cannot name two commands") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let saved = try await reference(client, value.id!).getDocument(source: .server).data(as: Recipe.self)
        XCTAssertEqual(saved.servings, 4)
    }

    func testYieldEditPreservesRawSourceAndHistoricalPortionWhileClearingUnknownNutrient() async throws {
        let client = try await makeClient(); let original = try await seed(recipe(), client: client)
        let ref = reference(client, original.id!)
        try await ref.updateData(["futureField": "retain"])
        let beforeSnapshot = try await ref.getDocument(source: .server)
        let before = try XCTUnwrap(beforeSnapshot.data())
        let logged = try RecipePortionRules.foodItem(for: original, selection: .init(unit: .servings, amount: 1.5))
        XCTAssertEqual(logged.calories, 600)
        let diaryRef = client.db.collection("users").document(client.uid).collection("dailyLogs").document("2026-10-28")
        let diary = DailyLog(id: "2026-10-28", date: Date(timeIntervalSince1970: 1_793_188_800),
            meals: [Meal(name: "Dinner", foodItems: [logged])])
        try await diaryRef.setData(Firestore.Encoder().encode(diary))
        let diaryBefore = try await diaryRef.getDocument(source: .server).data(as: DailyLog.self)
        var edited = original; edited.servings = 8; edited.nutrition.sodium = nil
        edited.revisionID = try RecipePortionRules.revisionID(for: edited)
        let accepted = try await save(edited, expected: original, client: client)
        XCTAssertEqual(accepted.servings, 8); XCTAssertNil(accepted.nutrition.sodium)
        XCTAssertEqual(accepted.revisionID, try RecipePortionRules.revisionID(for: accepted))
        let afterSnapshot = try await ref.getDocument(source: .server)
        let after = try XCTUnwrap(afterSnapshot.data())
        XCTAssertEqual(after["futureField"] as? String, "retain")
        XCTAssertNil((after["nutrition"] as? [String: Any])?["sodium"])
        let oldFood = try XCTUnwrap((before["detailedIngredients"] as? [[String: Any]])?.first)
        let newFood = try XCTUnwrap((after["detailedIngredients"] as? [[String: Any]])?.first)
        let oldSource = try XCTUnwrap(oldFood["sourceMetadata"] as? [String: Any])
        let newSource = try XCTUnwrap(newFood["sourceMetadata"] as? [String: Any])
        for key in ["createdAt", "sourceObservedAt"] {
            let old = try XCTUnwrap(oldSource[key] as? Timestamp); let new = try XCTUnwrap(newSource[key] as? Timestamp)
            XCTAssertEqual(old.seconds, new.seconds); XCTAssertEqual(old.nanoseconds, new.nanoseconds)
        }
        let diaryAfter = try await diaryRef.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(try PlanFingerprint.make(diaryBefore), try PlanFingerprint.make(diaryAfter))
        XCTAssertEqual(diaryAfter.meals[0].foodItems[0].recipePortionSnapshot?.yieldServings, 4)
        XCTAssertEqual(diaryAfter.meals[0].foodItems[0].calories, 600)
        let newPortion = try RecipePortionRules.foodItem(for: accepted, selection: .init(unit: .cookedGrams, amount: 300))
        XCTAssertEqual(newPortion.calories, 600)
    }

    func testOwnerChangeRejectsReadSaveAndCancellationBeforeTransmission() async throws {
        let client = try await makeClient(); let value = try recipe(); try client.auth.signOut()
        do { _ = try await save(value, expected: nil, client: client); XCTFail("Owner guard must reject save") } catch { XCTAssertEqual(error as? RecipeRevisionError, .accountChanged) }
        do {
            _ = try await client.repository.resolveRecipeRevision(userID: client.uid, expected: nil, updated: value,
                operationID: UUID(), cancelIfUnaccepted: true); XCTFail("Owner guard must reject cancellation")
        } catch { XCTAssertEqual(error as? RecipeRevisionError, .accountChanged) }
        do { _ = try await client.repository.fetchRecipes(userID: client.uid); XCTFail("Owner guard must reject read") } catch { XCTAssertEqual(error as? RecipeRevisionError, .accountChanged) }
    }

    func testDeletionBarrierRejectsRecipeAndReceiptAtomically() async throws {
        let client = try await makeClient(); let value = try recipe(); let operation = UUID()
        _ = try await admin("accountDeletionBarriers/\(client.uid)", method: "PATCH",
            body: ["fields": ["status": ["stringValue": "deleting"]]])
        do { _ = try await save(value, expected: nil, client: client, operation: operation); XCTFail("Barrier must reject save") } catch {}
        let recipeAfter = try await admin("users/\(client.uid)/recipes/\(value.id!)", method: "GET")
        let receiptAfter = try await admin("users/\(client.uid)/recipeRevisionReceipts/\(operation.uuidString)", method: "GET")
        XCTAssertEqual(recipeAfter, 404); XCTAssertEqual(receiptAfter, 404)
        _ = try await admin("accountDeletionBarriers/\(client.uid)", method: "DELETE")
    }

    func testVersionHistoryRestorePreservesServerSourceBytesUnknownFieldsAndLoggedSnapshot() async throws {
        let client = try await makeClient(); let original = try await seed(recipe(), client: client)
        let ref = reference(client, original.id!)
        let noHistory = try await client.repository.fetchRecipeVersionHistory(userID: client.uid, recipeID: original.id!, limit: 60)
        XCTAssertTrue(noHistory.isEmpty, "Legacy content must not fabricate old versions")
        try await ref.updateData(["futureField": "original extension"])
        let originalDocument = try await ref.getDocument(source: .server)
        let originalRaw = try XCTUnwrap(originalDocument.data())
        let originalSource = try XCTUnwrap((originalRaw["detailedIngredients"] as? [[String: Any]])?.first?["sourceMetadata"] as? [String: Any])
        let logged = try RecipePortionRules.foodItem(for: original, selection: .init(unit: .servings, amount: 1))
        let diaryRef = client.db.collection("users").document(client.uid).collection("dailyLogs").document("2026-10-28")
        let diary = DailyLog(id: "2026-10-28", date: Date(timeIntervalSince1970: 1_793_188_800), meals: [Meal(name: "Dinner", foodItems: [logged])])
        try await diaryRef.setData(Firestore.Encoder().encode(diary))
        let diaryBefore = try await diaryRef.getDocument(source: .server).data(as: DailyLog.self)
        var edited = original; edited.servings = 8; edited.revisionID = try RecipePortionRules.revisionID(for: edited)
        let current = try await save(edited, expected: original, client: client)
        let history = try await client.repository.fetchRecipeVersionHistory(userID: client.uid, recipeID: original.id!, limit: 60)
        XCTAssertEqual(history.count, 2)
        let version = try XCTUnwrap(history.first { $0.phase == .before })
        XCTAssertEqual(version.snapshot.servings, 4)
        try await ref.updateData(["futureField": "newer extension", "futureAddedAfterEdit": ["token": "preserve"]])
        let proposal = RecipeVersionRestoreProposal(userID: client.uid, version: version, expected: current)
        let restored = try await client.repository.restoreRecipeVersion(userID: client.uid, proposal: proposal)
        XCTAssertEqual(restored.id, original.id); XCTAssertEqual(restored.servings, 4)
        let restoredDocument = try await ref.getDocument(source: .server)
        let restoredRaw = try XCTUnwrap(restoredDocument.data())
        XCTAssertEqual(restoredRaw["futureField"] as? String, "newer extension")
        XCTAssertEqual((restoredRaw["futureAddedAfterEdit"] as? [String: String])?["token"], "preserve")
        let restoredSource = try XCTUnwrap((restoredRaw["detailedIngredients"] as? [[String: Any]])?.first?["sourceMetadata"] as? [String: Any])
        for key in ["createdAt", "sourceObservedAt"] {
            let before = try XCTUnwrap(originalSource[key] as? Timestamp), after = try XCTUnwrap(restoredSource[key] as? Timestamp)
            XCTAssertEqual(after.seconds, before.seconds); XCTAssertEqual(after.nanoseconds, before.nanoseconds)
        }
        let diaryAfter = try await diaryRef.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(try PlanFingerprint.make(diaryAfter), try PlanFingerprint.make(diaryBefore))
        let afterHistory = try await client.repository.fetchRecipeVersionHistory(userID: client.uid, recipeID: original.id!, limit: 60)
        XCTAssertEqual(afterHistory.count, 4)
        XCTAssertEqual(afterHistory.filter { $0.operationID == proposal.id && $0.phase == .restored }.count, 1)
    }

    func testRecipeRestoreReceiptReplayAfterNewerEditOrDeletionNeverReappliesSnapshot() async throws {
        let client = try await makeClient(); let original = try await save(recipe(), expected: nil, client: client)
        var edited = original; edited.servings = 8; edited.revisionID = try RecipePortionRules.revisionID(for: edited)
        let current = try await save(edited, expected: original, client: client)
        let history = try await client.repository.fetchRecipeVersionHistory(userID: client.uid, recipeID: original.id!, limit: 60)
        let version = try XCTUnwrap(history.first { $0.phase == .before })
        let proposal = RecipeVersionRestoreProposal(userID: client.uid, version: version, expected: current)
        let restored = try await client.repository.restoreRecipeVersion(userID: client.uid, proposal: proposal)
        var later = restored; later.servings = 12; later.revisionID = try RecipePortionRules.revisionID(for: later)
        _ = try await save(later, expected: restored, client: client)
        let replay = try await client.repository.restoreRecipeVersion(userID: client.uid, proposal: proposal)
        XCTAssertEqual(replay.servings, 12)
        let historyAfterReplay = try await client.repository.fetchRecipeVersionHistory(userID: client.uid, recipeID: original.id!, limit: 60)
        XCTAssertEqual(historyAfterReplay.count, 7)
        try await reference(client, original.id!).delete()
        let status = try await client.repository.resolveRecipeVersionRestore(userID: client.uid, proposal: proposal, cancelIfUnaccepted: true)
        XCTAssertEqual(status, .accepted(nil))
        do { _ = try await client.repository.restoreRecipeVersion(userID: client.uid, proposal: proposal); XCTFail("Accepted intent cannot resurrect") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let absent = try await reference(client, original.id!).getDocument(source: .server)
        XCTAssertFalse(absent.exists)
    }

    func testRecipeRestoreRejectsStaleCASAndPermanentCancellationFencesLateSubmit() async throws {
        let client = try await makeClient(); let original = try await save(recipe(), expected: nil, client: client)
        var edited = original; edited.servings = 8; edited.revisionID = try RecipePortionRules.revisionID(for: edited)
        let current = try await save(edited, expected: original, client: client)
        let history = try await client.repository.fetchRecipeVersionHistory(userID: client.uid, recipeID: original.id!, limit: 60)
        let version = try XCTUnwrap(history.first { $0.phase == .before })
        let proposal = RecipeVersionRestoreProposal(userID: client.uid, version: version, expected: current)
        try await reference(client, original.id!).updateData(["instructions": ["Newer owner edit"]])
        do { _ = try await client.repository.restoreRecipeVersion(userID: client.uid, proposal: proposal); XCTFail("Restore requires exact opening snapshot") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let noRestore = try await client.db.collection("users").document(client.uid).collection("recipeVersionRestoreReceipts").document(proposal.id.uuidString).getDocument(source: .server)
        XCTAssertFalse(noRestore.exists)
        let cancelled = try await client.repository.resolveRecipeVersionRestore(userID: client.uid, proposal: proposal, cancelIfUnaccepted: true)
        XCTAssertEqual(cancelled, .cancelled)
        do { _ = try await client.repository.restoreRecipeVersion(userID: client.uid, proposal: proposal); XCTFail("Cancelled old intent cannot arrive late") } catch { XCTAssertEqual(error as? RecipeRevisionError, .cancelled) }
        let different = RecipeVersionRestoreProposal(userID: client.uid, id: proposal.id, version: version, expected: original)
        do { _ = try await client.repository.resolveRecipeVersionRestore(userID: client.uid, proposal: different, cancelIfUnaccepted: false); XCTFail("Payload identity is immutable") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let after = try await reference(client, original.id!).getDocument(source: .server).data(as: Recipe.self)
        XCTAssertEqual(after.instructions, ["Newer owner edit"]); XCTAssertEqual(after.servings, 8)
        let unchangedHistory = try await client.repository.fetchRecipeVersionHistory(userID: client.uid, recipeID: original.id!, limit: 60)
        XCTAssertEqual(unchangedHistory.count, 3)
    }

    private func admin(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Int {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/v1/projects/myfitplate-test-project/databases/(default)/documents/" + path))
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        return try XCTUnwrap(response as? HTTPURLResponse).statusCode
    }
}
