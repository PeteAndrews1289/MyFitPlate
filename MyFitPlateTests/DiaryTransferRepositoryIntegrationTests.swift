import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class DiaryTransferEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}

private final class DiaryTransferEmulatorCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("diary-transfer-test-") ? DiaryTransferEmulatorCheck() : nil
    }
}

/// Opt in using MYFITPLATE_EMULATOR_TESTS=YES. Every Firebase app uses a fake key,
/// synthetic project and fixed localhost endpoints; production is never selected.
@MainActor
final class DiaryTransferRepositoryIntegrationTests: XCTestCase {
    private struct Client {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
        let directory: URL
        let repository: FirestoreNutritionRepository
    }
    private struct Fixture {
        let client: Client
        let uid: String
        let source: DiaryDayContext
        let destination: DiaryDayContext
        let sourceLog: DailyLog
        let destinationLog: DailyLog
    }
    /// The exact durable editor envelope immediately before transport. A dropped
    /// acknowledgement is modeled by not delivering the real repository result here.
    private struct FrozenCheckpoint: Codable {
        let draft: DiaryTransferDraft
        let command: DiaryTransferCommand
        var receipt: DiaryTransferReceipt?
        var undoSubmitted = false
    }
    private var clients: [Client] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(DiaryTransferEmulatorCheckFactory())
    }

    override func tearDown() {
        for client in clients {
            try? client.auth.signOut(); client.app.delete { _ in }
            try? FileManager.default.removeItem(at: client.directory)
        }
        clients = []; super.tearDown()
    }

    private func makeClient() -> Client {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"
        options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "diary-transfer-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = FirebaseApp.app(name: name)!
        let auth = Auth.auth(app: app); auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app); db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let repository = FirestoreNutritionRepository(db: db, outboxURL: directory.appendingPathComponent("outbox.json"),
                                                      currentUserID: { auth.currentUser?.uid })
        let client = Client(app: app, auth: auth, db: db, directory: directory, repository: repository)
        clients.append(client)
        return client
    }

    private func food(_ id: String, calories: Double = 100) -> FoodItem {
        FoodItem(id: id, name: id.capitalized, calories: calories, protein: 8, carbs: 20, fats: 4, fiber: 3,
                 servingSize: "2 x cup", servingWeight: 200, timestamp: Date(timeIntervalSince1970: 1_699_990_000),
                 sourceMetadata: .userEntered(sourceName: "Historical label"), calcium: 140, vitaminC: 12,
                 quantityValue: 2, servingUnit: "cup")
    }

    private func reference(_ fixture: Fixture, day: DiaryDayContext) -> DocumentReference {
        fixture.client.db.collection("users").document(fixture.uid).collection("dailyLogs").document(day.dayKey)
    }

    private func makeFixture() async throws -> Fixture {
        let client = makeClient()
        let uid = try await client.auth.signInAnonymously().user.uid
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let source = try XCTUnwrap(DiaryDayContext(userID: uid, date: Date(timeIntervalSince1970: 1_700_000_000), timeZone: zone))
        let destination = try XCTUnwrap(source.adding(days: 1))
        let sourceLog = DailyLog(id: source.dayKey, date: source.originalDate,
            meals: [Meal(name: "Breakfast", foodItems: [food("oats", calories: 200), food("milk")])],
            totalCaloriesOverride: 700, waterTracker: WaterTracker(totalOunces: 16, date: source.originalDate))
        let destinationLog = DailyLog(id: destination.dayKey, date: destination.originalDate,
            meals: [Meal(name: "Dinner", foodItems: [food("existing", calories: 500)])], totalCaloriesOverride: 900)
        let logs = client.db.collection("users").document(uid).collection("dailyLogs")
        var sourceData = try Firestore.Encoder().encode(sourceLog); sourceData["unrelatedLegacyField"] = "keep-source"
        var destinationData = try Firestore.Encoder().encode(destinationLog); destinationData["unrelatedLegacyField"] = "keep-destination"
        try await logs.document(source.dayKey).setData(sourceData)
        try await logs.document(destination.dayKey).setData(destinationData)
        // Proposals come from actual decoded server snapshots, as the diary does.
        let original = try await logs.document(source.dayKey).getDocument(source: .server).data(as: DailyLog.self)
        let target = try await logs.document(destination.dayKey).getDocument(source: .server).data(as: DailyLog.self)
        return Fixture(client: client, uid: uid, source: source, destination: destination, sourceLog: original, destinationLog: target)
    }

    private func proposal(_ fixture: Fixture, mode: DiaryTransferMode = .copy, sameDay: Bool = false) throws -> DiaryTransferDraft {
        var draft = try DiaryTransferDraft(source: fixture.source, destination: sameDay ? fixture.source : fixture.destination,
                                          sourceLog: fixture.sourceLog, mode: mode, foodIDs: ["oats"])
        draft.entries[0].destinationMealName = "Dinner"
        return draft
    }

    private func read(_ fixture: Fixture, day: DiaryDayContext) async throws -> DailyLog {
        try await reference(fixture, day: day).getDocument(source: .server).data(as: DailyLog.self)
    }

    private func updateRawFirstMeal(_ fixture: Fixture, day: DiaryDayContext,
                                    edit: (inout [[String: Any]]) throws -> Void) async throws {
        let data = try await reference(fixture, day: day).getDocument(source: .server).data()
        var meals = try XCTUnwrap(data?["meals"] as? [[String: Any]])
        var foods = try XCTUnwrap(meals.first?["foodItems"] as? [[String: Any]])
        try edit(&foods)
        meals[0]["foodItems"] = foods
        // An unrelated edit must leave the selected source's raw fractional dates
        // intact. Re-encoding the whole decoded source would itself change it.
        try await reference(fixture, day: day).setData(["meals": meals], merge: true)
    }

    private func rawFood(_ data: [String: Any], id: String) throws -> [String: Any] {
        let meals = try XCTUnwrap(data["meals"] as? [[String: Any]])
        let foods = meals.flatMap { $0["foodItems"] as? [[String: Any]] ?? [] }
        return try XCTUnwrap(foods.first { $0["id"] as? String == id })
    }

    private func assertSameTimestamp(_ first: Any?, _ second: Any?, file: StaticString = #filePath, line: UInt = #line) throws {
        let before = try XCTUnwrap(first as? Timestamp, file: file, line: line)
        let after = try XCTUnwrap(second as? Timestamp, file: file, line: line)
        XCTAssertEqual(before.seconds, after.seconds, file: file, line: line)
        XCTAssertEqual(before.nanoseconds, after.nanoseconds, file: file, line: line)
    }

    func testCrossDayCopyMergesLatestUnrelatedEditsAndReplayPreservesLaterCopyRevision() async throws {
        let fixture = try await makeFixture()
        var draft = try proposal(fixture); draft.entries[0].multiplier = 1.5
        let command = try draft.freeze()
        try await updateRawFirstMeal(fixture, day: fixture.source) { foods in
            foods[1]["calories"] = 130
            foods.append(try Firestore.Encoder().encode(food("new-source", calories: 50)))
        }
        try await updateRawFirstMeal(fixture, day: fixture.destination) { foods in
            foods[0]["calories"] = 550
            foods.append(try Firestore.Encoder().encode(food("new-destination", calories: 70)))
        }
        let result = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command)
        XCTAssertTrue(result.newlyApplied)
        let copy = try XCTUnwrap(result.receipt.placements.first?.destinationFood)
        XCTAssertNotEqual(copy.id, "oats"); XCTAssertEqual(copy.calories, 300); XCTAssertEqual(copy.calcium, 210)
        XCTAssertEqual(result.sourceLog.meals[0].foodItems.first { $0.id == "milk" }?.calories, 130)
        XCTAssertEqual(result.destinationLog.meals[0].foodItems.first { $0.id == "existing" }?.calories, 550)
        XCTAssertNotNil(result.destinationLog.meals[0].foodItems.first { $0.id == "new-destination" })
        XCTAssertEqual(result.sourceLog.waterTracker?.totalOunces, 16)
        XCTAssertEqual(result.destinationLog.totalCaloriesOverride, 900)
        let sourceData = try await reference(fixture, day: fixture.source).getDocument(source: .server).data()
        XCTAssertEqual(sourceData?["unrelatedLegacyField"] as? String, "keep-source")
        var later = try await read(fixture, day: fixture.destination)
        let index = try XCTUnwrap(later.meals[0].foodItems.firstIndex { $0.id == copy.id })
        later.meals[0].foodItems[index].calories = 444
        try await reference(fixture, day: fixture.destination).setData(Firestore.Encoder().encode(later), merge: true)
        let replay = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command)
        XCTAssertFalse(replay.newlyApplied)
        XCTAssertEqual(replay.destinationLog.meals[0].foodItems.filter { $0.id == copy.id }.count, 1)
        XCTAssertEqual(replay.destinationLog.meals[0].foodItems.first { $0.id == copy.id }?.calories, 444)
        let canonical = try await fixture.client.repository.fetchDiaryTransfer(userID: fixture.uid, command: command)
        XCTAssertEqual(canonical.receipt.commandFingerprint, result.receipt.commandFingerprint)
        XCTAssertEqual(canonical.destinationLog.meals[0].foodItems.first { $0.id == copy.id }?.calories, 444)
    }

    func testCopyPreservesFractionalProvenanceAndStrictUndoAfterActualMealWrite() async throws {
        let fixture = try await makeFixture()
        let sourceSnapshotBefore = try await reference(fixture, day: fixture.source).getDocument(source: .server)
        let destinationSnapshotBefore = try await reference(fixture, day: fixture.destination).getDocument(source: .server)
        let rawSourceBefore = try XCTUnwrap(sourceSnapshotBefore.data())
        let rawDestinationBefore = try XCTUnwrap(destinationSnapshotBefore.data())
        let sourceBefore = try await read(fixture, day: fixture.source)
        let command = try proposal(fixture).freeze()
        let accepted = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command)
        let placement = try XCTUnwrap(accepted.receipt.placements.first)
        let stored = try await read(fixture, day: fixture.destination)
        let writtenCopy = try XCTUnwrap(stored.meals.flatMap(\.foodItems).first { $0.id == placement.destinationFood.id })
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(writtenCopy, placement.destinationFood),
                      "Stored copy must retain the exact opaque-receipt snapshot, including fractional provenance")
        let sourceAfter = try await read(fixture, day: fixture.source)
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(sourceBefore.meals[0].foodItems[0], sourceAfter.meals[0].foodItems[0]))
        let sourceSnapshotAfter = try await reference(fixture, day: fixture.source).getDocument(source: .server)
        let destinationSnapshotAfter = try await reference(fixture, day: fixture.destination).getDocument(source: .server)
        let rawSourceAfter = try XCTUnwrap(sourceSnapshotAfter.data())
        let rawDestinationAfter = try XCTUnwrap(destinationSnapshotAfter.data())
        try assertSameTimestamp(rawSourceBefore["date"], rawSourceAfter["date"])
        try assertSameTimestamp(rawDestinationBefore["date"], rawDestinationAfter["date"])
        let originalMetadata = try XCTUnwrap(try rawFood(rawSourceBefore, id: "oats")["sourceMetadata"] as? [String: Any])
        let afterMetadata = try XCTUnwrap(try rawFood(rawSourceAfter, id: "oats")["sourceMetadata"] as? [String: Any])
        let copiedMetadata = try XCTUnwrap(try rawFood(rawDestinationAfter, id: writtenCopy.id)["sourceMetadata"] as? [String: Any])
        let existingBefore = try XCTUnwrap(try rawFood(rawDestinationBefore, id: "existing")["sourceMetadata"] as? [String: Any])
        let existingAfter = try XCTUnwrap(try rawFood(rawDestinationAfter, id: "existing")["sourceMetadata"] as? [String: Any])
        for key in ["createdAt", "sourceObservedAt"] {
            try assertSameTimestamp(originalMetadata[key], afterMetadata[key])
            try assertSameTimestamp(originalMetadata[key], copiedMetadata[key])
            try assertSameTimestamp(existingBefore[key], existingAfter[key])
        }
        try await updateRawFirstMeal(fixture, day: fixture.destination) { foods in
            foods.append(try Firestore.Encoder().encode(food("after-copy", calories: 35)))
        }
        let undo = try await fixture.client.repository.undoDiaryTransfer(userID: fixture.uid, receipt: accepted.receipt)
        XCTAssertTrue(undo.newlyApplied)
        let final = try await read(fixture, day: fixture.destination)
        XCTAssertEqual(Set(final.meals.flatMap(\.foodItems).map(\.id)), ["existing", "after-copy"])
        XCTAssertEqual(final.totalCaloriesOverride, 900)
    }

    func testWaterOnlyDestinationRetainsRawDateAndNonFoodFieldsThroughCopyAndUndo() async throws {
        let fixture = try await makeFixture()
        let rawDate = Timestamp(seconds: Int64(fixture.destination.originalDate.timeIntervalSince1970), nanoseconds: 87_654_321)
        let destinationRef = reference(fixture, day: fixture.destination)
        try await destinationRef.setData(["date": rawDate, "meals": [], "totalCaloriesOverride": 1_234,
            "waterTracker": ["totalOunces": 24.0, "goalOunces": 64.0, "date": rawDate],
            "journalEntries": [], "legacyNote": "keep this empty food day"])
        let seededSnapshot = try await destinationRef.getDocument(source: .server)
        let seeded = try XCTUnwrap(seededSnapshot.data())
        let baselineRawDate = try XCTUnwrap(seeded["date"] as? Timestamp)
        let baselineWater = try XCTUnwrap(seeded["waterTracker"] as? [String: Any])
        let baselineRawWaterDate = try XCTUnwrap(baselineWater["date"] as? Timestamp)
        let command = try proposal(fixture).freeze()
        let accepted = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command)
        _ = try await fixture.client.repository.undoDiaryTransfer(userID: fixture.uid, receipt: accepted.receipt)
        let finalSnapshot = try await destinationRef.getDocument(source: .server)
        let final = try XCTUnwrap(finalSnapshot.data())
        try assertSameTimestamp(baselineRawDate, final["date"])
        let water = try XCTUnwrap(final["waterTracker"] as? [String: Any])
        try assertSameTimestamp(baselineRawWaterDate, water["date"])
        XCTAssertEqual(water["totalOunces"] as? Double, 24)
        XCTAssertEqual(final["totalCaloriesOverride"] as? Int, 1_234)
        XCTAssertEqual(final["legacyNote"] as? String, "keep this empty food day")
        let log = try finalSnapshot.data(as: DailyLog.self)
        XCTAssertTrue(log.meals.flatMap(\.foodItems).isEmpty)
    }

    func testCrossDayMoveAndUndoRecoverLostAcknowledgementsAcrossRepositoryAndEditorRelaunch() async throws {
        let fixture = try await makeFixture()
        let draft = try proposal(fixture, mode: .move), command = try draft.freeze()
        let store = EditorDraftStore(directory: fixture.client.directory.appendingPathComponent("drafts"))
        try store.save(FrozenCheckpoint(draft: draft, command: command), userID: fixture.uid, scope: "diary-transfer")
        // Real server commit succeeds; deliberately drop its result before local ack persistence.
        let committed = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command)
        let restartedRepository = FirestoreNutritionRepository(db: fixture.client.db,
            outboxURL: fixture.client.directory.appendingPathComponent("restarted.json"), currentUserID: { fixture.client.auth.currentUser?.uid })
        let restored = DiaryTransferSession(userID: fixture.uid, store: store, currentUserID: { fixture.client.auth.currentUser?.uid })
        let replayResult = await restored.submit(using: restartedRepository)
        let replay = try XCTUnwrap(replayResult)
        XCTAssertFalse(replay.newlyApplied)
        XCTAssertEqual(replay.sourceLog.meals.flatMap(\.foodItems).map(\.id), ["milk"])
        XCTAssertEqual(replay.destinationLog.meals.flatMap(\.foodItems).filter { $0.id == "oats" }.count, 1)
        XCTAssertEqual(replay.receipt.commandFingerprint, committed.receipt.commandFingerprint)
        var newerSource = try await read(fixture, day: fixture.source)
        newerSource.meals[0].foodItems.append(food("added-after-move", calories: 25))
        try await reference(fixture, day: fixture.source).setData(Firestore.Encoder().encode(newerSource), merge: true)
        try store.save(FrozenCheckpoint(draft: draft, command: command, receipt: replay.receipt, undoSubmitted: true),
                       userID: fixture.uid, scope: "diary-transfer")
        _ = try await restartedRepository.undoDiaryTransfer(userID: fixture.uid, receipt: replay.receipt)
        let resumedUndo = DiaryTransferSession(userID: fixture.uid, store: store, currentUserID: { fixture.client.auth.currentUser?.uid })
        let undoResult = await resumedUndo.undo(using: restartedRepository)
        let undo = try XCTUnwrap(undoResult)
        XCTAssertFalse(undo.newlyApplied); XCTAssertNotNil(undo.receipt.undoneAt)
        XCTAssertEqual(Set(undo.sourceLog.meals.flatMap(\.foodItems).map(\.id)), ["oats", "milk", "added-after-move"])
        XCTAssertFalse(undo.destinationLog.meals.flatMap(\.foodItems).contains { $0.id == "oats" })
        XCTAssertTrue(resumedUndo.finish())
        let receipts = try await fixture.client.db.collection("users").document(fixture.uid).collection("diaryTransferReceipts").getDocuments(source: .server)
        XCTAssertEqual(receipts.documents.count, 1)
        let fetched = try await restartedRepository.fetchDiaryTransfer(userID: fixture.uid, command: command)
        XCTAssertNotNil(fetched.receipt.undoneAt, "A read-only replay exposes the server's undone state")
    }

    func testSameDayMoveIsAtomicAndStaleSourceCannotPartiallyTransfer() async throws {
        let fixture = try await makeFixture()
        let command = try proposal(fixture, mode: .move, sameDay: true).freeze()
        let moved = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command)
        XCTAssertEqual(moved.sourceLog.meals.first { $0.name == "Breakfast" }?.foodItems.map(\.id), ["milk"])
        XCTAssertEqual(moved.sourceLog.meals.first { $0.name == "Dinner" }?.foodItems.map(\.id), ["oats"])
        _ = try await fixture.client.repository.undoDiaryTransfer(userID: fixture.uid, receipt: moved.receipt)
        let stale = try proposal(fixture, mode: .move).freeze()
        var latest = try await read(fixture, day: fixture.source)
        let index = try XCTUnwrap(latest.meals[0].foodItems.firstIndex { $0.id == "oats" })
        latest.meals[0].foodItems[index].calories = 333
        try await reference(fixture, day: fixture.source).setData(Firestore.Encoder().encode(latest), merge: true)
        do { _ = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: stale); XCTFail("Stale source must fail") } catch {}
        let actualSource = try await read(fixture, day: fixture.source)
        let actualDestination = try await read(fixture, day: fixture.destination)
        XCTAssertEqual(actualSource.meals[0].foodItems.first { $0.id == "oats" }?.calories, 333)
        XCTAssertFalse(actualDestination.meals.flatMap(\.foodItems).contains { $0.id == "oats" })
        let receipt = try await fixture.client.db.collection("users").document(fixture.uid).collection("diaryTransferReceipts")
            .document(stale.id.uuidString).getDocument(source: .server)
        XCTAssertFalse(receipt.exists)
    }

    func testStrictUndoRefusesChangedDestinationWithoutRestoringOrDeletingAnything() async throws {
        let fixture = try await makeFixture()
        let result = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: proposal(fixture, mode: .move).freeze())
        var changed = try await read(fixture, day: fixture.destination)
        let index = try XCTUnwrap(changed.meals[0].foodItems.firstIndex { $0.id == "oats" })
        changed.meals[0].foodItems[index].protein = 99
        changed.meals[0].foodItems.append(food("later-food", calories: 40))
        try await reference(fixture, day: fixture.destination).setData(Firestore.Encoder().encode(changed), merge: true)
        do { _ = try await fixture.client.repository.undoDiaryTransfer(userID: fixture.uid, receipt: result.receipt); XCTFail("Edited target must block Undo") } catch {}
        let originalDay = try await read(fixture, day: fixture.source)
        let target = try await read(fixture, day: fixture.destination)
        XCTAssertFalse(originalDay.meals.flatMap(\.foodItems).contains { $0.id == "oats" })
        XCTAssertEqual(target.meals[0].foodItems.first { $0.id == "oats" }?.protein, 99)
        XCTAssertNotNil(target.meals[0].foodItems.first { $0.id == "later-food" })
        let receipt = try await fixture.client.repository.fetchDiaryTransfer(userID: fixture.uid, command: result.receipt.command)
        XCTAssertNil(receipt.receipt.undoneAt)
    }

    func testMissingReceiptFetchAndWrongOwnerNeverCreateOrMoveFoodsAndExactDayReadUsesCapturedKey() async throws {
        let fixture = try await makeFixture()
        let command = try proposal(fixture, mode: .move).freeze()
        do { _ = try await fixture.client.repository.fetchDiaryTransfer(userID: fixture.uid, command: command); XCTFail("Read cannot create missing receipt") } catch {}
        do { _ = try await fixture.client.repository.applyDiaryTransfer(userID: "another-owner", command: command); XCTFail("Wrong owner must fail") } catch {}
        let receipts = try await fixture.client.db.collection("users").document(fixture.uid).collection("diaryTransferReceipts").getDocuments(source: .server)
        XCTAssertTrue(receipts.documents.isEmpty)
        let traveled = try XCTUnwrap(DiaryDayContext(userID: fixture.uid, date: fixture.source.originalDate,
            timeZone: TimeZone(identifier: "Asia/Tokyo")!, dayKey: fixture.source.dayKey))
        let fetched = try await withCheckedThrowingContinuation { continuation in
            fixture.client.repository.fetchLogInternal(userID: fixture.uid, day: traveled) { continuation.resume(with: $0) }
        }
        XCTAssertEqual(fetched.id, fixture.source.dayKey)
        XCTAssertEqual(Set(fetched.meals.flatMap(\.foodItems).map(\.id)), ["oats", "milk"])
    }

    func testAccountDeletionBarrierRejectsActualTransactionWithoutPartialSourceRemoval() async throws {
        let fixture = try await makeFixture()
        let command = try proposal(fixture, mode: .move).freeze()
        let sourcePath = "users/\(fixture.uid)/dailyLogs/\(fixture.source.dayKey)"
        let destinationPath = "users/\(fixture.uid)/dailyLogs/\(fixture.destination.dayKey)"
        let beforeSource = try await adminDocument(path: sourcePath, method: "GET")
        let beforeDestination = try await adminDocument(path: destinationPath, method: "GET")
        let barrier = try await adminDocument(path: "accountDeletionBarriers/\(fixture.uid)", method: "PATCH",
            body: ["fields": ["status": ["stringValue": "deleting"]]])
        XCTAssertEqual(barrier.statusCode, 200)
        do { _ = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command); XCTFail("Deletion barrier must reject transaction") } catch {}
        let afterSource = try await adminDocument(path: sourcePath, method: "GET")
        let afterDestination = try await adminDocument(path: destinationPath, method: "GET")
        XCTAssertEqual(try canonicalJSON(beforeSource.data), try canonicalJSON(afterSource.data))
        XCTAssertEqual(try canonicalJSON(beforeDestination.data), try canonicalJSON(afterDestination.data))
        let receipt = try await adminDocument(path: "users/\(fixture.uid)/diaryTransferReceipts/\(command.id.uuidString)", method: "GET")
        XCTAssertEqual(receipt.statusCode, 404)
        _ = try await adminDocument(path: "accountDeletionBarriers/\(fixture.uid)", method: "DELETE")
    }

    func testCancellationRacingApplyEitherFencesLateMoveOrReturnsAcceptedReceiptWithoutPartialState() async throws {
        let fixture = try await makeFixture()
        let command = try proposal(fixture, mode: .move).freeze()
        let apply = Task { try? await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command) }
        let cancel = Task { try await fixture.client.repository.cancelDiaryTransfer(userID: fixture.uid, command: command) }
        let cancellationResult = try await cancel.value
        let appliedResult = await apply.value
        let source = try await read(fixture, day: fixture.source)
        let destination = try await read(fixture, day: fixture.destination)
        if let accepted = cancellationResult {
            XCTAssertEqual(accepted.receipt.commandFingerprint, try command.fingerprint())
            XCTAssertNotNil(appliedResult)
            XCTAssertFalse(source.meals.flatMap(\.foodItems).contains { $0.id == "oats" })
            XCTAssertEqual(destination.meals.flatMap(\.foodItems).filter { $0.id == "oats" }.count, 1)
        } else {
            XCTAssertNil(appliedResult)
            XCTAssertEqual(source.meals.flatMap(\.foodItems).filter { $0.id == "oats" }.count, 1)
            XCTAssertFalse(destination.meals.flatMap(\.foodItems).contains { $0.id == "oats" })
            do { _ = try await fixture.client.repository.applyDiaryTransfer(userID: fixture.uid, command: command); XCTFail("A late retry must see cancellation") } catch {}
            let repeatedCancellation = try await fixture.client.repository.cancelDiaryTransfer(userID: fixture.uid, command: command)
            XCTAssertNil(repeatedCancellation)
        }
        XCTAssertEqual(source.waterTracker?.totalOunces, 16)
        XCTAssertEqual(destination.totalCaloriesOverride, 900)
    }

    private func canonicalJSON(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
    }

    /// The emulator's documented/test-SDK owner token bypasses rules only at this
    /// fixed localhost address. It is never sent to a configurable or remote host.
    private func adminDocument(path: String, method: String, body: [String: Any]? = nil) async throws -> (statusCode: Int, data: Data) {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/v1/projects/myfitplate-test-project/databases/(default)/documents/\(path)"))
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = try XCTUnwrap(response as? HTTPURLResponse).statusCode
        return (status, data)
    }
}
