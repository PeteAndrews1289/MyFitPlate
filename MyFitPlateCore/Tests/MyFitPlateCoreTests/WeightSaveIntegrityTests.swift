import XCTest
@testable import MyFitPlateCore

@MainActor
final class WeightSaveIntegrityTests: XCTestCase {
    private let owner = "weight-owner"
    private var auth: MockAuthService!
    private var repo: MockSettingsRepository!
    private var health: MockHealthKitManager!
    private var goals: GoalSettings!
    private var directory: URL!
    private var store: EditorDraftStore!
    private var oldAuth: AuthServiceProtocol?
    private var oldRepo: SettingsRepositoryProtocol?

    override func setUp() {
        super.setUp()
        oldAuth = DIContainer.shared.authService; oldRepo = DIContainer.shared.settingsRepository
        auth = MockAuthService(); auth.currentUserID = owner; repo = MockSettingsRepository(); health = MockHealthKitManager()
        DIContainer.shared.authService = auth; DIContainer.shared.settingsRepository = repo
        goals = GoalSettings(healthKitManager: health, isEditingPreview: true); goals.activateAccount(owner)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("weight-save-\(UUID().uuidString)")
        store = EditorDraftStore(directory: directory)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        DIContainer.shared.authService = oldAuth; DIContainer.shared.settingsRepository = oldRepo
        super.tearDown()
    }
    private func save(_ session: WeightSaveSession, date: Date) async -> Bool {
        await withCheckedContinuation { continuation in
            session.save(weightLbs: 165.3465, enteredValue: 75, unit: "kg", date: date, using: goals) { continuation.resume(returning: $0) }
        }
    }

    func testRejectedMeasurementRestoresOriginalIdentityUnitsDateAndRetriesWithoutChangingToday() async throws {
        let date = Date().addingTimeInterval(-86_400)
        let session = WeightSaveSession(userID: owner, store: store)
        repo.saveWeightEntryError = URLError(.notConnectedToInternet)
        let failed = await save(session, date: date)
        XCTAssertFalse(failed)
        let draft = try XCTUnwrap(session.draft)
        XCTAssertEqual(goals.weight, 150)
        XCTAssertTrue(repo.savedWeightMeasurements.isEmpty)
        XCTAssertTrue(health.savedWeightSamples.isEmpty)
        let reopened = WeightSaveSession(userID: owner, store: store)
        XCTAssertEqual(reopened.draft?.id, draft.id)
        XCTAssertEqual(reopened.draft?.date, date)
        XCTAssertEqual(reopened.draft?.unit, "kg")
        XCTAssertEqual(reopened.draft?.enteredValue, 75)
        repo.saveWeightEntryError = nil
        let accepted = await save(reopened, date: Date())
        XCTAssertTrue(accepted)
        XCTAssertEqual(repo.savedWeightMeasurements["\(owner):\(draft.id)"]?.date, date)
        XCTAssertEqual(repo.savedWeightEntries.count, 1)
        XCTAssertEqual(goals.weight, 150)
        XCTAssertEqual(health.savedWeightSamples.count, 1, "This records a Health write request, not a completed Health receipt")
    }

    func testAmbiguousAcceptedHistoryWithUnclearedDraftRetriesWithoutDuplicateHistoryOrHealthRequest() async throws {
        let session = WeightSaveSession(userID: owner, store: store)
        let date = Date().addingTimeInterval(-86_400)
        let accepted = await save(session, date: date)
        XCTAssertTrue(accepted)
        let draft = try XCTUnwrap(session.draft)
        try store.save(draft, userID: owner, scope: "weight-measurement-save")
        let reopened = WeightSaveSession(userID: owner, store: store)
        let replayed = await save(reopened, date: Date())
        XCTAssertTrue(replayed)
        XCTAssertEqual(repo.savedWeightEntries.count, 1)
        XCTAssertEqual(health.savedWeightSamples.count, 1)
        XCTAssertTrue(reopened.isAccepted)
    }

    func testRapidTapAndAccountSwitchDuringWriteKeepOriginalMeasurementScoped() async throws {
        let session = WeightSaveSession(userID: owner, store: store)
        repo.weightSaveDelayNanoseconds = 40_000_000
        let pending = Task { await save(session, date: Date()) }
        for _ in 0..<100 where !session.isSaving { try? await Task.sleep(nanoseconds: 1_000_000) }
        for _ in 0..<100 where repo.weightSaveAttemptIDs.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000) }
        let duplicate = await save(session, date: Date())
        XCTAssertFalse(duplicate)
        auth.currentUserID = "other"; goals.activateAccount("other")
        let result = await pending.value
        XCTAssertFalse(result)
        XCTAssertEqual(goals.weight, 150)
        XCTAssertEqual(repo.savedWeightMeasurements.values.map(\.userID), [owner])
        XCTAssertTrue(health.savedWeightSamples.isEmpty)
        XCTAssertNotNil(WeightSaveSession(userID: owner, store: store).draft)
        XCTAssertNil(WeightSaveSession(userID: "other", store: store).draft)
    }

    func testActualCheckpointWriteFailureBlocksMeasurementAndAllowsRepairRetry() async throws {
        try Data("not a directory".utf8).write(to: directory)
        let session = WeightSaveSession(userID: owner, store: store)
        let failed = await save(session, date: Date())
        XCTAssertFalse(failed)
        XCTAssertTrue(repo.savedWeightMeasurements.isEmpty)
        XCTAssertNotNil(session.errorMessage)
        try FileManager.default.removeItem(at: directory)
        let accepted = await save(session, date: Date())
        XCTAssertTrue(accepted)
        XCTAssertEqual(repo.savedWeightMeasurements.count, 1)
    }

    func testStableImportIDUsesExactCaptureAndSameIdentityCannotOverwriteAnotherValue() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let id = WeightMeasurementDraft.importID(date: date, weightLbs: 150)
        XCTAssertEqual(id, WeightMeasurementDraft.importID(date: date, weightLbs: 150))
        XCTAssertNotEqual(id, WeightMeasurementDraft.importID(date: date.addingTimeInterval(1), weightLbs: 150))
        let first = try await repo.saveWeightMeasurement(userID: owner, entryID: id, weight: 150, date: date)
        let repeated = try await repo.saveWeightMeasurement(userID: owner, entryID: id, weight: 150, date: date)
        XCTAssertTrue(first); XCTAssertFalse(repeated)
        do { _ = try await repo.saveWeightMeasurement(userID: owner, entryID: id, weight: 170, date: date); XCTFail("Expected conflict") } catch {}
        XCTAssertEqual(repo.savedWeightMeasurements["\(owner):\(id)"]?.weight, 150)
    }
}
