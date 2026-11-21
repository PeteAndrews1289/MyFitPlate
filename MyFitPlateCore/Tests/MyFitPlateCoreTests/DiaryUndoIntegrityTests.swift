import XCTest
@testable import MyFitPlateCore

private func undoFixtureDayKey(_ date: Date) -> String { DiaryDayContext.dayKey(for: date)! }

@MainActor
final class DiaryUndoIntegrityTests: XCTestCase {
    private var auth: MockAuthService!
    private var repo: MockNutritionRepository!
    private var service: DailyLogService!
    private var store: EditorDraftStore!
    private var directory: URL!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepo: NutritionRepositoryProtocol?
    private let owner = "undo-owner"
    private let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepo = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("undo-tests-\(UUID().uuidString)")
        store = EditorDraftStore(directory: directory)
        reopen()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepo
        service = nil
        super.tearDown()
    }

    private func reopen() { service = DailyLogService(undoStore: store); service.activateAccount(owner) }

    private func prepare() async throws {
        try await repo.saveDailyLog(userID: owner, log: DailyLog(id: undoFixtureDayKey(day), date: day, meals: [Meal(name: "Lunch", foodItems: [
            FoodItem(id: "keep", name: "Keep", calories: 100)
        ])]))
        let accepted = await withCheckedContinuation { continuation in
            service.addMealGroupsToLog(for: owner, date: day, mealGroups: [("Lunch", [FoodItem(id: "undo-food", name: "Added", calories: 200)])],
                                       source: "test", deduplicateFoodIDs: true) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(accepted)
        XCTAssertTrue(service.canUndoDiaryChange)
    }

    private func undo() async -> Bool {
        await withCheckedContinuation { continuation in service.undoLastDiaryChange(for: owner) { continuation.resume(returning: $0) } }
    }

    private func reload(_ userID: String? = nil) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in repo.fetchLogInternal(userID: userID ?? owner, date: day) { continuation.resume(with: $0) } }
    }

    func testRejectedUndoKeepsStableReceiptAcrossRelaunchAndRetriesToCapturedDay() async throws {
        try await prepare()
        let id = try XCTUnwrap(service.undoChangeID)
        service.activelyViewedDate = Date()
        repo.updateLogSuccess = false
        let failed = await undo()
        XCTAssertFalse(failed)
        XCTAssertEqual(service.undoChangeID, id)
        XCTAssertTrue(service.canUndoDiaryChange)
        XCTAssertNotNil(service.undoErrorMessage)
        let afterFailure = try await reload()
        XCTAssertEqual(afterFailure.meals.flatMap(\.foodItems).map(\.id), ["keep", "undo-food"])
        reopen()
        XCTAssertEqual(service.undoChangeID, id)
        repo.updateLogSuccess = true
        let accepted = await undo()
        XCTAssertTrue(accepted)
        let reloaded = try await reload()
        XCTAssertEqual(reloaded.meals.flatMap(\.foodItems).map(\.id), ["keep"])
        XCTAssertEqual(reloaded.appliedMutationIDs?.filter { $0 == "diary-undo-\(id.uuidString)" }.count, 1)
        XCTAssertNil(service.currentDailyLog, "Undoing yesterday must not replace today's projection")
        reopen()
        XCTAssertFalse(service.canUndoDiaryChange)
    }

    func testRepeatedTapWhileDeferredWriteDoesNotReverseTwice() async throws {
        try await prepare()
        repo.shouldDeferDailyLogUpdateCompletions = true
        let completed = expectation(description: "undo accepted")
        service.undoLastDiaryChange(for: owner) { XCTAssertTrue($0); completed.fulfill() }
        await waitForWrite()
        XCTAssertTrue(service.isUndoingDiaryChange)
        let second = await undo()
        XCTAssertFalse(second)
        XCTAssertEqual(repo.deferredDailyLogUpdateCompletions.count, 1)
        repo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [completed], timeout: 1)
        let reloaded = try await reload()
        XCTAssertEqual(reloaded.meals.flatMap(\.foodItems).map(\.id), ["keep"])
    }

    func testPreviouslyAppliedUndoWithUnclearedReceiptDoesNotReapplyAfterRelaunch() async throws {
        try await prepare()
        var receipt = try XCTUnwrap(store.load(DiaryUndoReceipt.self, userID: owner, scope: "diary-undo")?.value)
        receipt.isSubmitted = true
        try store.save(receipt, userID: owner, scope: "diary-undo")
        let before = try await reload()
        let acceptedButUncleared = try receipt.reversal().applying(to: before)
        try await repo.saveDailyLog(userID: owner, log: acceptedButUncleared)
        reopen()
        let accepted = await undo()
        XCTAssertTrue(accepted)
        let final = try await reload()
        XCTAssertEqual(final.meals.flatMap(\.foodItems).map(\.id), ["keep"])
        XCTAssertEqual(final.appliedMutationIDs?.filter { $0 == receipt.operationID }.count, 1)
        XCTAssertNil(try store.load(DiaryUndoReceipt.self, userID: owner, scope: "diary-undo"))
    }

    func testAccountChangeBeforeUndoLeavesOriginalReceiptRecoverable() async throws {
        try await prepare()
        let id = service.undoChangeID
        auth.currentUserID = "other"; service.activateAccount("other")
        let rejected = await undo()
        XCTAssertFalse(rejected)
        XCTAssertFalse(service.canUndoDiaryChange)
        auth.currentUserID = owner; service.activateAccount(owner)
        XCTAssertEqual(service.undoChangeID, id)
        let accepted = await undo()
        XCTAssertTrue(accepted)
    }

    func testAcceptedOriginalAccountUndoAfterSwitchDoesNotPublishIntoNewAccount() async throws {
        try await prepare()
        repo.shouldDeferDailyLogUpdateCompletions = true
        let completed = expectation(description: "original undo accepted")
        service.undoLastDiaryChange(for: owner) { XCTAssertTrue($0); completed.fulfill() }
        await waitForWrite()
        auth.currentUserID = "other"; service.activateAccount("other")
        let otherDay = Date()
        service.currentDailyLog = DailyLog(id: undoFixtureDayKey(otherDay), date: otherDay, meals: [])
        repo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(service.currentDailyLog?.id, undoFixtureDayKey(otherDay))
        let original = try await reload()
        let other = try await reload("other")
        XCTAssertEqual(original.meals.flatMap(\.foodItems).map(\.id), ["keep"])
        XCTAssertTrue(other.meals.isEmpty)
        XCTAssertFalse(service.canUndoDiaryChange)
    }

    func testReceiptIOFailureBlocksUndoBeforeDiaryWriteAndKeepsRetry() async throws {
        try await prepare()
        let id = service.undoChangeID
        let priorWrites = repo.dailyLogUpdateUserIDs.count
        let backup = directory.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: backup) }
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("Not a directory".utf8).write(to: directory)
        let failed = await undo()
        XCTAssertFalse(failed)
        XCTAssertEqual(repo.dailyLogUpdateUserIDs.count, priorWrites)
        XCTAssertEqual(service.undoChangeID, id)
        XCTAssertTrue(service.canUndoDiaryChange)
        XCTAssertNotNil(service.undoErrorMessage)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        let accepted = await undo()
        XCTAssertTrue(accepted)
    }

    func testSameFoodChangedDuringUndoCommitRejectsAndKeepsOriginalReceiptAfterRelaunch() async throws {
        try await prepare()
        let id = service.undoChangeID
        repo.shouldDeferDailyLogUpdateCompletions = true
        let completed = expectation(description: "conflicting undo rejected")
        service.undoLastDiaryChange(for: owner) { XCTAssertFalse($0); completed.fulfill() }
        await waitForWrite()
        var remote = try await reload()
        remote.meals[0].foodItems[1].calories = 350
        try await repo.saveDailyLog(userID: owner, log: remote)
        repo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(service.undoChangeID, id)
        XCTAssertTrue(service.canUndoDiaryChange)
        XCTAssertNotNil(service.undoErrorMessage)
        reopen()
        XCTAssertEqual(service.undoChangeID, id)
        let retained = try await reload()
        XCTAssertEqual(retained.meals.flatMap(\.foodItems).first { $0.id == "undo-food" }?.calories, 350)
    }

    func testUnrelatedConcurrentFoodSurvivesCheckedUndo() async throws {
        try await prepare()
        repo.shouldDeferDailyLogUpdateCompletions = true
        let completed = expectation(description: "independent merge accepted")
        service.undoLastDiaryChange(for: owner) { XCTAssertTrue($0); completed.fulfill() }
        await waitForWrite()
        var remote = try await reload()
        remote.meals[0].foodItems.append(FoodItem(id: "other-device", name: "Concurrent", calories: 80))
        try await repo.saveDailyLog(userID: owner, log: remote)
        repo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [completed], timeout: 1)
        let retained = try await reload()
        XCTAssertEqual(Set(retained.meals.flatMap(\.foodItems).map(\.id)), ["keep", "other-device"])
    }

    func testInversePreconditionsCoverAddRemoveAndFullSnapshotChangesWithoutIncludingUnrelatedFood() throws {
        let first = FoodItem(id: "changed", name: "Before", calories: 100)
        let updated = FoodItem(id: "changed", name: "After", calories: 200)
        let deleted = FoodItem(id: "deleted", name: "Removed", calories: 50)
        let added = FoodItem(id: "added", name: "New", calories: 75)
        let unchanged = FoodItem(id: "same", name: "Same", calories: 20)
        let lunchID = UUID()
        let before = DailyLog(id: undoFixtureDayKey(day), date: day, meals: [Meal(id: lunchID, name: "Lunch", foodItems: [first, deleted, unchanged])])
        let after = DailyLog(id: undoFixtureDayKey(day), date: day, meals: [Meal(id: lunchID, name: "Lunch", foodItems: [updated, added, unchanged])])
        let receipt = DiaryUndoReceipt(id: UUID(), userID: owner, before: before, after: after, expiresAt: Date(), isSubmitted: true)
        let reversal = try receipt.reversal()
        XCTAssertEqual(Set(reversal.foodEditPreconditions?.map(\.foodID) ?? []), ["changed", "deleted", "added"])
        var conflicting = after
        conflicting.meals[0].foodItems.append(FoodItem(id: "deleted", name: "Recreated elsewhere", calories: 90))
        XCTAssertThrowsError(try reversal.applying(to: conflicting, checkingFoodEdits: true))
        let accepted = try reversal.applying(to: after, checkingFoodEdits: true)
        XCTAssertEqual(accepted.meals.flatMap(\.foodItems).first { $0.id == "changed" }?.name, "Before")
        XCTAssertEqual(Set(accepted.meals.flatMap(\.foodItems).map(\.id)), ["changed", "deleted", "same"])
    }

    private func waitForWrite() async {
        for _ in 0..<100 where repo.deferredDailyLogUpdateCompletions.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(repo.deferredDailyLogUpdateCompletions.isEmpty)
    }
}
