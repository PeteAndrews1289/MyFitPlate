import XCTest
@testable import MyFitPlateCore

@MainActor
final class RunDiaryCorrectionTests: XCTestCase {
    private let owner = "run-correction-owner"
    private let healthID = "258F22C6-A8A3-4FD9-AE92-8A02ED13C8C4"
    private var auth: MockAuthService!
    private var repo: MockNutritionRepository!
    private var service: DailyLogService!
    private var drafts: EditorDraftStore!
    private var jobs: RunHealthExportJobStore!
    private var directory: URL!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepo: NutritionRepositoryProtocol?

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepo = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        drafts = EditorDraftStore(directory: directory.appendingPathComponent("drafts"))
        jobs = RunHealthExportJobStore(directory: directory.appendingPathComponent("jobs"))
        reopen()
    }
    override func tearDown() {
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepo
        service = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func reopen() { service = DailyLogService(undoStore: drafts); service.activateAccount(owner) }
    private func coordinator() -> RunDiaryCorrectionCoordinator { RunDiaryCorrectionCoordinator(service: service, drafts: drafts, jobs: jobs) }
    private func reviewStore() -> RunReviewStore { RunReviewStore(drafts: drafts) }

    private func seed() async throws -> Run {
        let run = try XCTUnwrap(ManualRunEntryRules.buildIndoorRun(startDate: Date(timeIntervalSince1970: 1_800_000_000),
            distanceMeters: 5_000, movingSeconds: 1_800, metric: true, activeCalories: 300))
        let job = try jobs.prepare(run: run, weightLbs: 165, expectsRoute: false, userID: owner)
        _ = try jobs.update(job, phase: .complete, healthID: healthID, userID: owner)
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: run.startDate))
        let activity = LoggedExercise(id: healthID, name: "Running", durationMinutes: 30, caloriesBurned: 300,
            date: run.startDate, source: "HealthKit")
        try await repo.saveDailyLog(userID: owner, log: DailyLog(id: day.dayKey, date: day.originalDate, meals: [], exercises: [activity]))
        return run.reidentified(as: healthID)
    }
    private func reload(_ run: Run) async throws -> DailyLog {
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: run.startDate))
        return try await withCheckedThrowingContinuation { continuation in repo.fetchLogInternal(userID: owner, day: day) { continuation.resume(with: $0) } }
    }
    private func prepare(_ run: Run, operation: String = "correction") async throws -> RunReviewStore.Review {
        try await coordinator().prepare(run: run, distanceMeters: 6_000, movingSeconds: 1_920,
            reason: "Treadmill display", userID: owner, operationID: operation)
    }

    func testFailedDiaryWriteRestoresExactPendingReviewAndRetryAcceptsOnceWithMatchingCalories() async throws {
        let original = try await seed()
        let review = try await prepare(original)
        repo.updateLogSuccess = false
        do { _ = try await coordinator().commit(review); XCTFail("Rejected diary save must not accept the overlay") } catch {}
        XCTAssertEqual(try reviewStore().projecting([original], userID: owner), [original])
        XCTAssertTrue(try reviewStore().latestReceipts(userID: owner).isEmpty)
        reopen()
        let pending = try XCTUnwrap(coordinator().pending(run: original, userID: owner))
        XCTAssertEqual(pending.review, review)
        repo.updateLogSuccess = true
        let receipt = try await coordinator().commit(pending.review)
        let replay = try await coordinator().commit(pending.review)
        XCTAssertEqual(receipt, replay)
        let log = try await reload(original)
        let corrected = try XCTUnwrap(reviewStore().projecting([original], userID: owner).first)
        XCTAssertEqual(corrected.distanceMeters, 6_000)
        XCTAssertEqual(corrected.movingSeconds, 1_920)
        XCTAssertEqual(corrected.activeCalories, log.exercises?.first?.caloriesBurned)
        XCTAssertEqual(log.exercises?.first?.durationMinutes, 32)
        XCTAssertEqual(log.exercises?.first?.id, healthID)
        XCTAssertEqual(log.exercises?.first?.date, original.startDate)
        XCTAssertEqual(log.exercises?.first?.source, "HealthKit")
        XCTAssertEqual(log.appliedMutationIDs?.filter { $0 == "run-review.correction" }.count, 1)
        XCTAssertNil(try coordinator().pending(run: original, userID: owner))
        XCTAssertEqual(try jobs.load(recordingID: original.recordingID!, userID: owner)?.run.distanceMeters, 5_000)
        XCTAssertEqual(try reviewStore().originalEvidence(for: corrected, userID: owner), original)
    }

    func testRemoteChangeAfterReviewCannotBeOverwrittenEvenWhenLocalDiaryIsStale() async throws {
        let original = try await seed()
        let review = try await prepare(original)
        let cached = try await reload(original)
        service.currentDailyLog = cached
        var independent = cached
        independent.mutationBase = nil
        independent.exercises?[0].caloriesBurned = 999
        independent.exercises?[0].hasLocalHealthKitEdits = true
        try await repo.saveDailyLog(userID: owner, log: independent)
        do { _ = try await coordinator().commit(review); XCTFail("A stale cached proposal must fail server CAS") } catch {}
        let actual = try await reload(original)
        XCTAssertEqual(actual.exercises?.first?.caloriesBurned, 999)
        XCTAssertEqual(try reviewStore().projecting([original], userID: owner), [original])
        XCTAssertNotNil(try coordinator().pending(run: original, userID: owner))
    }

    func testInterruptedAfterDiaryAcceptanceReconcilesReceiptWithoutApplyingTwice() async throws {
        let original = try await seed()
        let review = try await prepare(original)
        let link = try XCTUnwrap(review.diaryCorrection)
        try drafts.save(RunDiaryCorrectionOperation(review: review, phase: .prepared), userID: owner,
            scope: RunDiaryCorrectionCoordinator.scope(review.identity))
        let result = await service.reconcileRunActivity(for: owner, day: link.day, operationID: "run-review.correction",
            expected: link.before, updated: link.after)
        XCTAssertEqual(result, .updated)
        XCTAssertTrue(try reviewStore().latestReceipts(userID: owner).isEmpty)
        reopen()
        let saved = try XCTUnwrap(coordinator().pending(run: original, userID: owner))
        _ = try await coordinator().commit(saved.review)
        let accepted = try await reload(original)
        XCTAssertEqual(accepted.appliedMutationIDs?.filter { $0 == "run-review.correction" }.count, 1)
        XCTAssertEqual(try reviewStore().projecting([original], userID: owner).first?.activeCalories, accepted.exercises?.first?.caloriesBurned)
    }

    func testAcceptedDiaryReplayCannotPublishOldOverlayOverNewerIndependentEdit() async throws {
        let original = try await seed()
        let review = try await prepare(original)
        let link = try XCTUnwrap(review.diaryCorrection)
        try drafts.save(RunDiaryCorrectionOperation(review: review, phase: .diaryAccepted), userID: owner,
            scope: RunDiaryCorrectionCoordinator.scope(review.identity))
        let result = await service.reconcileRunActivity(for: owner, day: link.day, operationID: "run-review.correction",
            expected: link.before, updated: link.after)
        XCTAssertEqual(result, .updated)
        var later = try await reload(original)
        later.mutationBase = nil; later.exercises?[0].caloriesBurned = 888
        try await repo.saveDailyLog(userID: owner, log: later)
        // Retain the cached accepted diary to exercise permanent operation replay,
        // then the canonical post-acknowledgment verification in the service.
        do { _ = try await coordinator().commit(review); XCTFail("The newer canonical copy must withhold run acceptance") } catch {}
        let canonical = try await reload(original)
        XCTAssertEqual(canonical.exercises?.first?.caloriesBurned, 888)
        XCTAssertTrue(try reviewStore().latestReceipts(userID: owner).isEmpty)
        XCTAssertEqual(try reviewStore().projecting([original], userID: owner), [original])
    }

    func testMissingLinkOrIndependentOverrideCannotAcceptNumericCorrection() async throws {
        let original = try await seed()
        var independent = try await reload(original)
        independent.mutationBase = nil; independent.exercises?[0].hasLocalHealthKitEdits = true
        try await repo.saveDailyLog(userID: owner, log: independent)
        do { _ = try await prepare(original); XCTFail("Independent diary edits must be preserved") } catch {}
        independent.exercises = []
        try await repo.saveDailyLog(userID: owner, log: independent)
        do { _ = try await prepare(original); XCTFail("A missing diary copy is unresolved") } catch {}
        XCTAssertTrue(try reviewStore().latestReceipts(userID: owner).isEmpty)
        XCTAssertNil(try coordinator().pending(run: original, userID: owner))
    }

    func testLinkedUndoRestoresExactDiaryAndOriginalRunWithoutReexport() async throws {
        let original = try await seed()
        let originalLog = try await reload(original)
        let receipt = try await coordinator().commit(prepare(original))
        let corrected = try XCTUnwrap(reviewStore().projecting([original], userID: owner).first)
        let undone = try await coordinator().undo(receipt, userID: owner)
        let replay = try await coordinator().undo(receipt, userID: owner)
        XCTAssertEqual(undone, replay)
        let final = try await reload(original)
        XCTAssertTrue(ActivityEditPrecondition.sameSnapshot(try XCTUnwrap(final.exercises?.first), try XCTUnwrap(originalLog.exercises?.first)))
        XCTAssertEqual(try reviewStore().projecting([corrected], userID: owner), [original])
        XCTAssertEqual(try jobs.load(recordingID: original.recordingID!, userID: owner)?.phase, .complete)
    }

    func testUndoPreservesLaterIndependentDiaryCorrection() async throws {
        let original = try await seed()
        let receipt = try await coordinator().commit(prepare(original))
        var later = try await reload(original)
        later.mutationBase = nil; later.exercises?[0].caloriesBurned = 777
        try await repo.saveDailyLog(userID: owner, log: later)
        reopen()
        do { _ = try await coordinator().undo(receipt, userID: owner); XCTFail("Undo must not replace a later independent correction") } catch {}
        let actual = try await reload(original)
        XCTAssertEqual(actual.exercises?.first?.caloriesBurned, 777)
        XCTAssertEqual(try reviewStore().projecting([original], userID: owner).first?.distanceMeters, 6_000)
        XCTAssertEqual(try coordinator().pending(run: original, userID: owner)?.review.operationID, "undo.correction")
    }
}
