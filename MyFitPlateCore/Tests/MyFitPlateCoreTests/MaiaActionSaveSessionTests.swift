import XCTest
@testable import MyFitPlateCore

@MainActor
final class MaiaActionSaveSessionTests: XCTestCase {
    private let owner = "maia-action-owner"
    private let date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
    private var directory: URL!
    private var store: EditorDraftStore!
    private var auth: MockAuthService!
    private var repo: MockNutritionRepository!
    private var settings: MockSettingsRepository!
    private var health: MockHealthKitManager!
    private var goals: GoalSettings!
    private var service: DailyLogService!
    private var oldAuth: AuthServiceProtocol!
    private var oldRepo: NutritionRepositoryProtocol!
    private var oldSettings: SettingsRepositoryProtocol!

    override func setUp() {
        super.setUp()
        oldAuth = DIContainer.shared.authService
        oldRepo = DIContainer.shared.nutritionRepository
        oldSettings = DIContainer.shared.settingsRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true
        settings = MockSettingsRepository(); health = MockHealthKitManager()
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repo
        DIContainer.shared.settingsRepository = settings
        goals = GoalSettings(healthKitManager: health, isEditingPreview: true)
        goals.activateAccount(owner)
        service = DailyLogService(); service.activateAccount(owner)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
    }

    override func tearDown() {
        DIContainer.shared.authService = oldAuth
        DIContainer.shared.nutritionRepository = oldRepo
        DIContainer.shared.settingsRepository = oldSettings
        try? FileManager.default.removeItem(at: directory)
        service = nil; goals = nil
        super.tearDown()
    }

    func testRejectedWaterRelaunchUsesOriginalDayAndAcceptedCardCannotAddAgain() async throws {
        let first = make("message-water")
        XCTAssertTrue(first.prepare(command: .water(ounces: 16), date: date, mealName: "Dinner"))
        let captured = try XCTUnwrap(first.receipt)
        repo.updateLogSuccess = false
        let rejected = await save(first)
        XCTAssertFalse(rejected)
        let restored = make("message-water")
        XCTAssertTrue(restored.prepare(command: .water(ounces: 16), date: date.addingTimeInterval(86_400), mealName: "Breakfast"))
        XCTAssertEqual(restored.receipt?.entryID, captured.entryID)
        XCTAssertEqual(restored.receipt?.date, date)
        repo.updateLogSuccess = true
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let beforeReplayWrites = repo.dailyLogUpdateUserIDs.count
        let replay = await save(make("message-water"))
        XCTAssertTrue(replay)
        XCTAssertEqual(repo.dailyLogUpdateUserIDs.count, beforeReplayWrites)
        let savedLog = try await read(date)
        XCTAssertEqual(savedLog.waterTracker?.totalOunces, 16)
        XCTAssertTrue(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: "message-water", store: store)?.isAccepted == true)
    }

    func testDistinctCardOccurrencesAreDistinctIntentionalWaterEntries() async throws {
        for identity in ["message-action-0", "message-action-1"] {
            let session = make(identity)
            XCTAssertTrue(session.prepare(command: .water(ounces: 16), date: date, mealName: "Lunch"))
            let accepted = await save(session)
            XCTAssertTrue(accepted)
        }
        let savedLog = try await read(date)
        XCTAssertEqual(savedLog.waterTracker?.totalOunces, 32)
    }

    func testInterruptedAcceptedWaterAcknowledgmentRetriesWithoutDoubling() async throws {
        let first = make("ambiguous-water")
        XCTAssertTrue(first.prepare(command: .water(ounces: 12), date: date, mealName: "Lunch"))
        let pending = try XCTUnwrap(first.receipt)
        let accepted = await save(first)
        XCTAssertTrue(accepted)
        let committed = try await read(date)
        XCTAssertTrue(committed.appliedMutationIDs?.contains(pending.entryID) == true)
        XCTAssertNil(committed.pendingMutationID, "Only the durable applied receipt survives repository reload")
        // Model process death after server commit, before the accepted receipt checkpoint.
        try store.save(pending, userID: owner, scope: "maia-action-ambiguous-water")
        let retry = await save(make("ambiguous-water"))
        XCTAssertTrue(retry)
        let savedLog = try await read(date)
        XCTAssertEqual(savedLog.waterTracker?.totalOunces, 12)
    }

    func testWorkoutReplayPreservesLaterManualCorrection() async throws {
        let session = make("workout")
        XCTAssertTrue(session.prepare(command: .workout(name: "Walk", minutes: 30, calories: 150), date: date, mealName: "Dinner"))
        let pending = try XCTUnwrap(session.receipt)
        let saved = await save(session)
        XCTAssertTrue(saved)
        let originalLog = try await read(date)
        let original = try XCTUnwrap(originalLog.exercises?.first)
        var corrected = original
        corrected.caloriesBurned = 123.5
        let correctionAccepted = await withCheckedContinuation { continuation in
            service.saveActivityExercise(for: owner, exercise: corrected, replacing: original) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(correctionAccepted)
        try store.save(pending, userID: owner, scope: "maia-action-workout")
        let replay = await save(make("workout"))
        XCTAssertTrue(replay)
        let result = try await read(date)
        XCTAssertEqual(result.exercises?.count, 1)
        XCTAssertEqual(result.exercises?.first?.id, pending.entryID)
        XCTAssertEqual(result.exercises?.first?.caloriesBurned, 123.5)
    }

    func testMealReplayKeepsEstimatedLineageAndMicronutrients() async throws {
        let food = FoodItem(id: "temporary-preview", name: "Rice bowl", calories: 500, protein: 25, carbs: 60, fats: 15,
            servingSize: "1 serving (AI Est.)", servingWeight: 0, sodium: 320).withAIEstimateSource(.aiChat, sourceName: "Maia")
        let session = make("meal")
        XCTAssertTrue(session.prepare(command: .meal(food), date: date, mealName: "Dinner"))
        let pending = try XCTUnwrap(session.receipt)
        let saved = await save(session)
        XCTAssertTrue(saved)
        try store.save(pending, userID: owner, scope: "maia-action-meal")
        let replay = await save(make("meal"))
        XCTAssertTrue(replay)
        let result = try await read(date)
        XCTAssertEqual(result.meals.first?.name, "Dinner")
        XCTAssertEqual(result.meals.flatMap(\.foodItems).count, 1)
        XCTAssertEqual(result.meals.first?.foodItems.first?.sodium, 320)
        XCTAssertEqual(result.meals.first?.foodItems.first?.sourceMetadata, food.sourceMetadata)
    }

    func testChangedCardCannotSilentlyReplaceFrozenWeight() throws {
        let session = make("weight")
        XCTAssertTrue(session.prepare(command: .weight(pounds: 165), date: date, mealName: "Lunch"))
        let restored = make("weight")
        XCTAssertFalse(restored.prepare(command: .weight(pounds: 180), date: date.addingTimeInterval(86_400), mealName: "Dinner"))
        XCTAssertEqual(restored.receipt?.command, .weight(pounds: 165))
        XCTAssertEqual(restored.receipt?.date, date)
        XCTAssertNotNil(restored.errorMessage)
    }

    func testWeightAcceptedReplayKeepsMeasurementIDAndOneHealthRequest() async throws {
        let session = make("weight")
        XCTAssertTrue(session.prepare(command: .weight(pounds: 165), date: date, mealName: "Lunch"))
        let pending = try XCTUnwrap(session.receipt)
        let accepted = await save(session)
        XCTAssertTrue(accepted)
        try store.save(pending, userID: owner, scope: "maia-action-weight")
        let replay = await save(make("weight"))
        XCTAssertTrue(replay)
        XCTAssertEqual(settings.savedWeightMeasurements.count, 1)
        XCTAssertNotNil(settings.savedWeightMeasurements["\(owner):\(pending.entryID)"])
        XCTAssertEqual(health.savedWeightSamples.count, 1)
    }

    func testTwoPrecreatedSessionsAgreeOnFirstCapture() throws {
        let first = make("same-card")
        let second = make("same-card")
        XCTAssertTrue(first.prepare(command: .water(ounces: 8), date: date, mealName: "Dinner"))
        XCTAssertTrue(second.prepare(command: .water(ounces: 8), date: date.addingTimeInterval(86_400), mealName: "Breakfast"))
        XCTAssertEqual(first.receipt?.entryID, second.receipt?.entryID)
        XCTAssertEqual(second.receipt?.date, date)
        XCTAssertEqual(second.receipt?.mealName, "Dinner")
    }

    func testOtherAccountCannotPrepareSubmitOrAcceptReceipt() async throws {
        let session = make("account")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        auth.currentUserID = "other"
        XCTAssertFalse(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        let saved = await save(session)
        XCTAssertFalse(saved)
        XCTAssertTrue(repo.dailyLogUpdateUserIDs.isEmpty)
    }

    func testDoubleTapWhileWriteDeferredMakesOneWrite() async throws {
        repo.shouldDeferDailyLogUpdateCompletions = true
        let session = make("double-tap")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        let accepted = expectation(description: "accepted")
        session.save(using: service, goals: goals, waterGoal: 100) { result in XCTAssertTrue(result); accepted.fulfill() }
        var duplicate: Bool?
        session.save(using: service, goals: goals, waterGoal: 100) { duplicate = $0 }
        XCTAssertEqual(duplicate, false)
        for _ in 0..<100 where repo.deferredDailyLogUpdateCompletions.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        repo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [accepted], timeout: 3)
        XCTAssertEqual(repo.dailyLogUpdateUserIDs.count, 1)
    }

    func testTransientQuickActionRestoresFailureButNextAcceptedTapIsNewIntent() async throws {
        let first = MaiaActionSaveSession(userID: owner, actionID: nil, store: store)
        XCTAssertTrue(first.prepare(command: .water(ounces: 16), date: date, mealName: "Lunch"))
        repo.updateLogSuccess = false
        let rejected = await save(first)
        XCTAssertFalse(rejected)
        let restored = MaiaActionSaveSession(userID: owner, actionID: nil, store: store)
        XCTAssertEqual(restored.actionID, first.actionID)
        repo.updateLogSuccess = true
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let next = MaiaActionSaveSession(userID: owner, actionID: nil, store: store)
        XCTAssertNotEqual(next.actionID, first.actionID)
    }

    func testPayloadIdentityIsStableAndInvalidHoursAreNotRenderable() throws {
        let data = Data(#"{"type":"log_water","amountOunces":16}"#.utf8)
        let first = try JSONDecoder().decode(MaiaActionPayload.self, from: data)
        let second = try JSONDecoder().decode(MaiaActionPayload.self, from: data)
        XCTAssertEqual(first.id, first.id)
        XCTAssertEqual(first.id, second.id)
        let invalid = try JSONDecoder().decode(MaiaActionPayload.self, from: Data(#"{"type":"start_fast","fastHours":24}"#.utf8))
        XCTAssertFalse(invalid.isRenderableAction)
    }

    func testUnreadableReceiptIsNeverOverwrittenOrReportedAccepted() throws {
        try store.save("future-unreadable-action", userID: owner, scope: "maia-action-corrupt")
        let session = make("corrupt")
        XCTAssertFalse(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        XCTAssertNotNil(session.errorMessage)
        XCTAssertEqual(try store.load(String.self, userID: owner, scope: "maia-action-corrupt")?.value, "future-unreadable-action")
    }

    func testLocalCheckpointFailureCanRetryAfterStorageIsRepaired() throws {
        try Data("blocks-directory".utf8).write(to: directory)
        let session = make("disk")
        XCTAssertFalse(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        XCTAssertTrue(repo.dailyLogUpdateUserIDs.isEmpty)
        try FileManager.default.removeItem(at: directory)
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        XCTAssertNotNil(session.receipt)
    }

    func testAcceptedDiaryWriteWithFailedReceiptCheckpointStaysReplaySafe() async throws {
        repo.shouldDeferDailyLogUpdateCompletions = true
        let session = make("receipt-io")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        let result = Task { await save(session) }
        for _ in 0..<100 where repo.deferredDailyLogUpdateCompletions.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        let backup = directory.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        repo.completeDeferredDailyLogUpdates(success: true)
        let acceptedWithoutReceipt = await result.value
        XCTAssertFalse(acceptedWithoutReceipt)
        XCTAssertFalse(session.receipt?.isAccepted == true)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        repo.shouldDeferDailyLogUpdateCompletions = false
        let retried = await save(make("receipt-io"))
        XCTAssertTrue(retried)
        let savedLog = try await read(date)
        XCTAssertEqual(savedLog.waterTracker?.totalOunces, 8)
    }

    func testAccountChangeDuringAcceptanceDoesNotCompleteAnotherAccountsCard() async throws {
        repo.shouldDeferDailyLogUpdateCompletions = true
        let session = make("account-during")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        let result = Task { await save(session) }
        for _ in 0..<100 where repo.deferredDailyLogUpdateCompletions.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        auth.currentUserID = "other-owner"
        service.activateAccount("other-owner")
        repo.completeDeferredDailyLogUpdates(success: true)
        let accepted = await result.value
        XCTAssertFalse(accepted)
        XCTAssertFalse(session.isSaving)
        XCTAssertFalse(session.receipt?.isAccepted == true)
        auth.currentUserID = owner
        service.activateAccount(owner)
        repo.shouldDeferDailyLogUpdateCompletions = false
        let retried = await save(make("account-during"))
        XCTAssertTrue(retried)
        let savedLog = try await read(date)
        XCTAssertEqual(savedLog.waterTracker?.totalOunces, 8)
    }

    func testClearDiscardsOnlyExplicitlyUnsubmittedAndRejectsStaleSessionSave() async throws {
        let prepared = make("clear-prepared")
        XCTAssertTrue(prepared.prepare(command: .weight(pounds: 165), date: date, mealName: "Lunch"))
        let submitted = make("clear-submitted")
        XCTAssertTrue(submitted.prepare(command: .water(ounces: 16), date: date, mealName: "Lunch"))
        repo.updateLogSuccess = false
        let rejected = await save(submitted)
        XCTAssertFalse(rejected)
        let review = try MaiaActionSaveSession.reviewConversationClear(userID: owner, store: store)
        XCTAssertEqual(review.unsubmittedActions.map(\.actionID), [prepared.actionID])
        XCTAssertEqual(review.submittedActions.map(\.actionID), [submitted.actionID])

        try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: true, store: store)
        XCTAssertNil(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: prepared.actionID, store: store))
        let kept = try XCTUnwrap(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: submitted.actionID, store: store))
        XCTAssertTrue(kept.hasBeenSubmitted)
        XCTAssertTrue(kept.conversationCleared)
        XCTAssertEqual(kept.command, .water(ounces: 16))
        let before = repo.dailyLogUpdateUserIDs.count
        let staleResult = await save(prepared)
        XCTAssertFalse(staleResult)
        XCTAssertEqual(repo.dailyLogUpdateUserIDs.count, before)
    }

    func testClearMinimizesAcceptedPayloadsAndKeepsExistingLogsAndReplayIdentity() async throws {
        let food = FoodItem(id: "private-source", name: "Private meal name", calories: 320, protein: 20, carbs: 30, fats: 10,
                            servingSize: "1 bowl", servingWeight: 250)
        let commands: [MaiaSavedCommand] = [.water(ounces: 16), .weight(pounds: 165), .meal(food)]
        var originalIDs: [String: String] = [:]
        for (index, command) in commands.enumerated() {
            let session = make("clear-accepted-\(index)")
            XCTAssertTrue(session.prepare(command: command, date: date, mealName: "Private meal slot"))
            let accepted = await save(session)
            XCTAssertTrue(accepted)
            originalIDs[session.actionID] = session.receipt?.entryID
        }
        let writes = repo.dailyLogUpdateUserIDs.count
        let measurements = settings.savedWeightMeasurements.count
        let beforeLog = try await read(date)
        try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: true, store: store)
        for (index, command) in commands.enumerated() {
            let session = make("clear-accepted-\(index)")
            let minimized = try XCTUnwrap(session.receipt)
            XCTAssertTrue(minimized.isAccepted)
            XCTAssertNil(minimized.command)
            XCTAssertEqual(minimized.entryID, originalIDs[session.actionID])
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(minimized)) as? [String: Any])
            XCTAssertEqual(Set(object.keys), Set(["actionID", "entryID", "isAccepted"]))
            XCTAssertTrue(session.prepare(command: command, date: date.addingTimeInterval(86_400), mealName: "Different slot"))
            let replayed = await save(session)
            XCTAssertTrue(replayed)
        }
        let afterLog = try await read(date)
        XCTAssertEqual(afterLog.waterTracker?.totalOunces, beforeLog.waterTracker?.totalOunces)
        XCTAssertEqual(afterLog.meals.flatMap(\.foodItems), beforeLog.meals.flatMap(\.foodItems))
        XCTAssertEqual(repo.dailyLogUpdateUserIDs.count, writes)
        XCTAssertEqual(settings.savedWeightMeasurements.count, measurements)
    }

    func testClearWhileSubmittedWriteInFlightMinimizesLateAcceptance() async throws {
        repo.shouldDeferDailyLogUpdateCompletions = true
        let session = make("clear-inflight")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        let result = Task { await save(session) }
        for _ in 0..<100 where repo.deferredDailyLogUpdateCompletions.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(session.isSaving)
        try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: true, store: store)
        let pending = try XCTUnwrap(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: session.actionID, store: store))
        XCTAssertEqual(pending.command, .water(ounces: 8))
        XCTAssertTrue(pending.hasBeenSubmitted)
        repo.completeDeferredDailyLogUpdates(success: true)
        let accepted = await result.value
        XCTAssertTrue(accepted)
        XCTAssertNil(make(session.actionID).receipt?.command)
        XCTAssertTrue(make(session.actionID).receipt?.isAccepted == true)
        let log = try await read(date)
        XCTAssertEqual(log.waterTracker?.totalOunces, 8)
    }

    func testLegacyPendingWithoutSubmissionMarkerIsPreservedAsAmbiguous() throws {
        let session = make("legacy-pending")
        XCTAssertTrue(session.prepare(command: .weight(pounds: 165), date: date, mealName: "Lunch"))
        let receipt = try XCTUnwrap(session.receipt)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
        object.removeValue(forKey: "hasBeenSubmitted")
        object.removeValue(forKey: "conversationCleared")
        let legacy = try JSONDecoder().decode(MaiaSavedActionReceipt.self, from: JSONSerialization.data(withJSONObject: object))
        try store.save(legacy, userID: owner, scope: "maia-action-\(session.actionID)")
        XCTAssertTrue(legacy.hasBeenSubmitted)
        try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: true, store: store)
        XCTAssertEqual(make(session.actionID).receipt?.command, .weight(pounds: 165))
    }

    func testClearKeepsUnsubmittedChoiceRetryableAndMinimizesItsLaterAcceptance() async throws {
        let session = make("keep-prepared")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: false, store: store)
        let restored = make(session.actionID)
        XCTAssertFalse(try XCTUnwrap(restored.receipt).hasBeenSubmitted)
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        XCTAssertNil(make(session.actionID).receipt?.command)
    }

    func testClearIsAccountScopedAndCannotRunFromStaleAccount() throws {
        let session = make("owner-action")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        auth.currentUserID = "other-owner"
        let other = MaiaActionSaveSession(userID: "other-owner", actionID: "owner-action", store: store)
        XCTAssertTrue(other.prepare(command: .weight(pounds: 180), date: date, mealName: "Lunch"))
        XCTAssertThrowsError(try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: true, store: store))
        try MaiaActionSaveSession.clearConversation(userID: "other-owner", messages: [], discardUnsubmitted: true, store: store)
        XCTAssertNil(MaiaActionSaveSession.savedReceipt(userID: "other-owner", actionID: "owner-action", store: store))
        XCTAssertEqual(make(session.actionID).receipt?.command, .water(ounces: 8))
        XCTAssertTrue(repo.dailyLogUpdateUserIDs.isEmpty)
    }

    func testClearPreservesUnreadableReceiptAndDisclosesIt() throws {
        let session = make("unreadable-on-clear")
        XCTAssertTrue(session.prepare(command: .water(ounces: 8), date: date, mealName: "Lunch"))
        // A newer checkpoint may have replaced the receipt. Never erase it as a draft.
        try store.remove(userID: owner, scope: "maia-action-\(session.actionID)")
        try store.save("future-record", userID: owner, scope: "maia-action-\(session.actionID)")
        let review = try MaiaActionSaveSession.reviewConversationClear(userID: owner, store: store)
        XCTAssertEqual(review.unreadableActionCount, 1)
        try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: true, store: store)
        XCTAssertEqual(try store.load(String.self, userID: owner, scope: "maia-action-\(session.actionID)")?.value, "future-record")
    }

    func testClearFindsOrphanReceiptWithoutIndexAndPreservesUnrelatedOrMismatchedDrafts() async throws {
        let session = make("old-orphan")
        XCTAssertTrue(session.prepare(command: .weight(pounds: 165), date: date, mealName: "Lunch"))
        let accepted = await save(session)
        XCTAssertTrue(accepted)
        let acceptedReceipt = try XCTUnwrap(session.receipt)
        try store.save("unrelated-private-draft", userID: owner, scope: "food-editor")
        try store.save(acceptedReceipt, userID: owner, scope: "unrelated-receipt-shaped-draft")
        try store.remove(userID: owner, scope: "maia-action-index")
        let review = try MaiaActionSaveSession.reviewConversationClear(userID: owner, store: store)
        XCTAssertEqual(review.acceptedActionCount, 1)
        try MaiaActionSaveSession.clearConversation(userID: owner, messages: [], discardUnsubmitted: true, store: store)
        XCTAssertNil(make(session.actionID).receipt?.command)
        XCTAssertEqual(try store.load(String.self, userID: owner, scope: "food-editor")?.value, "unrelated-private-draft")
        XCTAssertEqual(try store.load(MaiaSavedActionReceipt.self, userID: owner, scope: "unrelated-receipt-shaped-draft")?.value.command,
                       .weight(pounds: 165))
        XCTAssertEqual(settings.savedWeightMeasurements.count, 1)
    }

    private func make(_ actionID: String) -> MaiaActionSaveSession { MaiaActionSaveSession(userID: owner, actionID: actionID, store: store) }
    private func save(_ session: MaiaActionSaveSession) async -> Bool {
        await withCheckedContinuation { continuation in
            session.save(using: service, goals: goals, waterGoal: 100) { continuation.resume(returning: $0) }
        }
    }
    private func read(_ date: Date) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in repo.fetchLogInternal(userID: owner, date: date) { continuation.resume(with: $0) } }
    }
}
