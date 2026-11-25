import XCTest
@testable import MyFitPlateCore

@MainActor
final class ExerciseLogStoreTests: XCTestCase {
    private var service: DailyLogService!
    private var mockRepo: MockNutritionRepository!
    private var authService: MockAuthService!
    private var store: ExerciseLogStore!

    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        DIContainer.shared.nutritionRepository = mockRepo
        authService = MockAuthService()
        authService.currentUserID = "user-1"
        DIContainer.shared.authService = authService
        service = DailyLogService()
        service.activateAccount("user-1")
        store = ExerciseLogStore(dailyLogService: service)
    }

    override func tearDown() {
        store = nil
        service = nil
        mockRepo = nil
        authService = nil
        super.tearDown()
    }

    private func fixedDay(_ dayOffset: Int = 0) -> Date {
        let base = Date(timeIntervalSince1970: 1_725_235_200)
        return Calendar.current.startOfDay(for: base.addingTimeInterval(Double(dayOffset) * 86_400))
    }

    /// Repository-backed diary fixtures use the same civil-day document identity as production.
    private func dayID(_ date: Date) -> String { DiaryDayContext.dayKey(for: date)! }

    private func exercise(
        id: String,
        name: String,
        date: Date,
        source: String = "manual",
        calories: Double = 200
    ) -> LoggedExercise {
        LoggedExercise(
            id: id,
            name: name,
            durationMinutes: 30,
            caloriesBurned: calories,
            date: date,
            source: source
        )
    }

    func testAddExerciseUsesCapturedActivityDateInsteadOfViewedDate() async throws {
        let viewedDate = fixedDay()
        let chosenDate = fixedDay(-1).addingTimeInterval(10 * 3_600)
        service.activelyViewedDate = viewedDate
        mockRepo.persistsDailyLogUpdates = true

        let accepted = await add(exercise(id: "exercise-1", name: "Rowing", date: chosenDate, calories: 180))
        XCTAssertTrue(accepted)

        let updatedLog = try await reload(chosenDate)
        let exercises = try XCTUnwrap(updatedLog.exercises)
        XCTAssertEqual(exercises.map(\.id), ["exercise-1"])
        XCTAssertEqual(exercises[0].name, "Rowing")
        XCTAssertEqual(exercises[0].caloriesBurned, 180)
        XCTAssertEqual(exercises[0].date, chosenDate)
        XCTAssertTrue(Calendar.current.isDate(updatedLog.date, inSameDayAs: chosenDate))
        let today = try await reload(viewedDate)
        XCTAssertTrue(today.exercises?.isEmpty ?? true)
        XCTAssertNil(service.currentDailyLog, "A historical activity must not replace the currently viewed day's projection")
    }

    func testRetryAndRepeatedSubmissionKeepOneStoredActivity() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let entry = exercise(id: "stable-draft", name: "Walk", date: fixedDay(-1))
        mockRepo.updateLogSuccess = false
        let failed = await add(entry)
        XCTAssertFalse(failed)
        let afterFailure = try await reload(entry.date)
        XCTAssertTrue(afterFailure.exercises?.isEmpty ?? true)

        mockRepo.updateLogSuccess = true
        let retried = await add(entry)
        let repeated = await add(entry)
        XCTAssertTrue(retried)
        XCTAssertTrue(repeated)
        let stored = try await reload(entry.date)
        XCTAssertEqual(stored.exercises?.map(\.id), ["stable-draft"])
        var correctedRetry = entry
        correctedRetry.caloriesBurned = 245.5
        let corrected = await add(correctedRetry)
        XCTAssertTrue(corrected)
        let reloaded = try await reload(entry.date)
        XCTAssertEqual(reloaded.exercises?.count, 1)
        XCTAssertEqual(reloaded.exercises?.first?.caloriesBurned, 245.5)
    }

    func testEditingReplacesIdentityAndPreservesStoredSourceAndSessionMetadata() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let date = fixedDay(-1).addingTimeInterval(15 * 3_600)
        let original = LoggedExercise(id: "linked", name: "Strength", durationMinutes: 30,
                                      caloriesBurned: 200, date: date, source: "routine",
                                      workoutID: "workout-1", sessionID: "session-1")
        let other = exercise(id: "keep", name: "Walk", date: date)
        let food = FoodItem(id: "food", name: "Lunch", calories: 400, protein: 30, carbs: 40, fats: 10)
        try await mockRepo.saveDailyLog(userID: "user-1", log: DailyLog(
            id: dayID(fixedDay(-1)), date: fixedDay(-1), meals: [Meal(name: "Lunch", foodItems: [food])],
            exercises: [original, other]
        ))
        service.activelyViewedDate = fixedDay()
        let proposed = LoggedExercise(id: original.id, name: "Corrected strength", durationMinutes: 45,
                                      caloriesBurned: 275, date: date, source: "manual")
        let accepted = await update(original: original, updated: proposed)
        XCTAssertTrue(accepted)
        let stored = try await reload(date)
        XCTAssertEqual(stored.exercises?.map(\.id), ["linked", "keep"])
        let corrected = try XCTUnwrap(stored.exercises?.first { $0.id == original.id })
        XCTAssertEqual(corrected.name, "Corrected strength")
        XCTAssertEqual(corrected.durationMinutes, 45)
        XCTAssertEqual(corrected.caloriesBurned, 275)
        XCTAssertEqual(corrected.date, date)
        XCTAssertEqual(corrected.source, "routine")
        XCTAssertEqual(corrected.workoutID, "workout-1")
        XCTAssertEqual(corrected.sessionID, "session-1")
        XCTAssertEqual(stored.meals.first?.foodItems.map(\.id), ["food"])
        XCTAssertNil(service.currentDailyLog)
    }

    func testFailedEditRetainsStoredEntryAndRetryUpdatesItOnce() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let original = exercise(id: "edit-retry", name: "Bike", date: fixedDay())
        try await mockRepo.saveDailyLog(userID: "user-1", log: DailyLog(id: dayID(fixedDay()), date: fixedDay(), meals: [], exercises: [original]))
        var updated = original
        updated.caloriesBurned = 333
        mockRepo.updateLogSuccess = false
        let failed = await update(original: original, updated: updated)
        XCTAssertFalse(failed)
        let afterFailure = try await reload(original.date)
        XCTAssertEqual(afterFailure.exercises?.first?.caloriesBurned, original.caloriesBurned)
        mockRepo.updateLogSuccess = true
        let retried = await update(original: original, updated: updated)
        XCTAssertTrue(retried)
        let stored = try await reload(original.date)
        XCTAssertEqual(stored.exercises?.count, 1)
        XCTAssertEqual(stored.exercises?.first?.caloriesBurned, 333)
    }

    func testHealthKitCorrectionSurvivesReloadAndRefreshWhileOtherImportsRefresh() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let date = fixedDay(-1).addingTimeInterval(12 * 3_600)
        let original = LoggedExercise(id: "corrected-health-id", name: "Walk", durationMinutes: 30,
                                      caloriesBurned: 150, date: date, source: "HealthKit",
                                      workoutID: "linked-workout", sessionID: "linked-session")
        let refreshable = exercise(id: "refreshable", name: "Run", date: date, source: "HealthKit", calories: 200)
        let manual = exercise(id: "manual", name: "Mobility", date: date)
        try await mockRepo.saveDailyLog(userID: "user-1", log: DailyLog(id: dayID(date), date: date, meals: [], exercises: [original, refreshable, manual]))
        var correction = original
        correction.name = "Corrected walk"
        correction.durationMinutes = 42
        correction.caloriesBurned = 240
        let accepted = await update(original: original, updated: correction)
        XCTAssertTrue(accepted)
        let afterEdit = try await reload(date)
        XCTAssertEqual(afterEdit.exercises?.first?.hasLocalHealthKitEdits, true)

        // A fresh service must recover the marker from persisted data, not an in-memory override.
        service = DailyLogService()
        service.activateAccount("user-1")
        service.activelyViewedDate = fixedDay()
        store = ExerciseLogStore(dailyLogService: service)
        var changedHealthOriginal = original
        changedHealthOriginal.caloriesBurned = 180
        var changedRefreshable = refreshable
        changedRefreshable.caloriesBurned = 315
        let fresh = exercise(id: "fresh-health", name: "Swim", date: date, source: "HealthKit", calories: 400)
        await sync([changedHealthOriginal, changedRefreshable, fresh], date: date)

        let reloaded = try await reload(date)
        let storedCorrection = try XCTUnwrap(reloaded.exercises?.first { $0.id == original.id })
        XCTAssertEqual(storedCorrection.name, correction.name)
        XCTAssertEqual(storedCorrection.durationMinutes, 42)
        XCTAssertEqual(storedCorrection.caloriesBurned, 240)
        XCTAssertEqual(storedCorrection.date, date)
        XCTAssertEqual(storedCorrection.source, "HealthKit")
        XCTAssertEqual(storedCorrection.workoutID, "linked-workout")
        XCTAssertEqual(storedCorrection.sessionID, "linked-session")
        XCTAssertEqual(storedCorrection.hasLocalHealthKitEdits, true)
        XCTAssertEqual(reloaded.exercises?.first { $0.id == refreshable.id }?.caloriesBurned, 315)
        XCTAssertEqual(reloaded.exercises?.first { $0.id == fresh.id }?.caloriesBurned, 400)
        XCTAssertEqual(Set(reloaded.exercises?.map(\.id) ?? []), Set([original.id, refreshable.id, fresh.id, manual.id]))
        XCTAssertNil(service.currentDailyLog, "A historical refresh must not publish over the viewed day")
    }

    func testHealthKitRefreshQueuedDuringEditKeepsAcceptedCorrection() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let date = fixedDay()
        let original = exercise(id: "concurrent-health", name: "Walk", date: date, source: "HealthKit")
        try await mockRepo.saveDailyLog(userID: "user-1", log: DailyLog(id: dayID(date), date: date, meals: [], exercises: [original]))
        var correction = original
        correction.caloriesBurned = 275
        mockRepo.shouldDeferDailyLogUpdateCompletions = true
        let edited = expectation(description: "edit accepted")
        store.updateExerciseInLog(for: "user-1", original: original, updated: correction) { accepted in
            XCTAssertTrue(accepted)
            edited.fulfill()
        }
        await waitForWrite()
        let refreshed = expectation(description: "queued refresh accepted")
        store.addOrUpdateHealthKitWorkouts(for: "user-1", exercises: [original], date: date) { refreshed.fulfill() }
        XCTAssertEqual(mockRepo.dailyLogUpdateUserIDs.count, 1, "Refresh must wait behind the in-flight edit")
        mockRepo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [edited], timeout: 1)
        await waitForWrite()
        XCTAssertEqual(mockRepo.lastUpdatedLog?.exercises?.first?.caloriesBurned, 275)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.exercises?.first?.hasLocalHealthKitEdits, true)
        mockRepo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [refreshed], timeout: 1)
        let reloaded = try await reload(date)
        XCTAssertEqual(reloaded.exercises?.count, 1)
        XCTAssertEqual(reloaded.exercises?.first?.caloriesBurned, 275)
    }

    func testHealthKitCopyCannotBeDeletedFromDiary() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let imported = exercise(id: "health-owned", name: "Walk", date: fixedDay(), source: "HealthKit")
        try await mockRepo.saveDailyLog(userID: "user-1", log: DailyLog(id: dayID(fixedDay()), date: fixedDay(), meals: [], exercises: [imported]))
        let accepted = await withCheckedContinuation { continuation in
            store.deleteExerciseFromLog(for: "user-1", exerciseID: imported.id, date: imported.date) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertFalse(accepted, "Removing only the imported copy would be undone by the next Health refresh")
        XCTAssertTrue(mockRepo.dailyLogUpdateUserIDs.isEmpty)
        let reloaded = try await reload(imported.date)
        XCTAssertEqual(reloaded.exercises?.map(\.id), [imported.id])
    }

    func testLegacyExerciseDecodesWithoutLocalHealthEditMarkerAndMarkedCopyRoundTrips() throws {
        let legacy = exercise(id: "legacy", name: "Walk", date: fixedDay(), source: "HealthKit")
        let encodedLegacy = try JSONEncoder().encode(legacy)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedLegacy) as? [String: Any])
        XCTAssertNil(payload["hasLocalHealthKitEdits"])
        XCTAssertNil(try JSONDecoder().decode(LoggedExercise.self, from: encodedLegacy).hasLocalHealthKitEdits)
        var corrected = legacy
        corrected.hasLocalHealthKitEdits = true
        let decoded = try JSONDecoder().decode(LoggedExercise.self, from: JSONEncoder().encode(corrected))
        XCTAssertEqual(decoded.hasLocalHealthKitEdits, true)
        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertEqual(decoded.source, "HealthKit")
    }

    func testEditCannotRecreateDeletedActivityOrMoveAcrossDays() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let original = exercise(id: "missing", name: "Run", date: fixedDay())
        let missing = await update(original: original, updated: original)
        XCTAssertFalse(missing)
        XCTAssertTrue(mockRepo.dailyLogUpdateUserIDs.isEmpty)
        try await mockRepo.saveDailyLog(userID: "user-1", log: DailyLog(id: dayID(fixedDay()), date: fixedDay(), meals: [], exercises: [original]))
        var moved = original
        moved.date = fixedDay(-1)
        let rejected = await update(original: original, updated: moved)
        XCTAssertFalse(rejected)
        let stored = try await reload(original.date)
        let yesterday = try await reload(moved.date)
        XCTAssertEqual(stored.exercises?.map(\.id), [original.id])
        XCTAssertTrue(yesterday.exercises?.isEmpty ?? true)
    }

    func testViewedDateChangeWhileSavingDoesNotRedirectOrPublishActivity() async throws {
        mockRepo.persistsDailyLogUpdates = true
        mockRepo.shouldDeferDailyLogUpdateCompletions = true
        let selected = fixedDay(-1)
        let entry = exercise(id: "captured", name: "Walk", date: selected)
        let completed = expectation(description: "activity accepted")
        store.addExerciseToLog(for: "user-1", exercise: entry) { accepted in
            XCTAssertTrue(accepted)
            completed.fulfill()
        }
        await waitForWrite()
        service.activelyViewedDate = fixedDay(1)
        service.currentDailyLog = DailyLog(id: dayID(fixedDay(1)), date: fixedDay(1), meals: [])
        mockRepo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [completed], timeout: 1)
        let stored = try await reload(selected)
        XCTAssertEqual(stored.exercises?.map(\.id), [entry.id])
        XCTAssertEqual(service.currentDailyLog?.id, dayID(fixedDay(1)))
        XCTAssertTrue(service.currentDailyLog?.exercises?.isEmpty ?? true)
    }

    func testAccountChangeBeforeWriteRejectsOldEditorWithoutWritingToNewAccount() async throws {
        mockRepo.persistsDailyLogUpdates = true
        let completed = expectation(description: "old editor rejected")
        store.addExerciseToLog(for: "user-1", exercise: exercise(id: "private", name: "Walk", date: fixedDay(-1))) { accepted in
            XCTAssertFalse(accepted)
            completed.fulfill()
        }
        authService.currentUserID = "user-2"
        service.activateAccount("user-2")
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertTrue(mockRepo.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertNil(service.currentDailyLog)
    }

    func testAlreadyAcceptedWriteAfterAccountChangeStaysOwnedByOriginalAccount() async throws {
        mockRepo.persistsDailyLogUpdates = true
        mockRepo.shouldDeferDailyLogUpdateCompletions = true
        let entry = exercise(id: "accepted", name: "Walk", date: fixedDay())
        let completed = expectation(description: "accepted original operation")
        store.addExerciseToLog(for: "user-1", exercise: entry) { accepted in
            XCTAssertTrue(accepted, "Changing accounts cannot pretend an accepted original-account write was cancelled")
            completed.fulfill()
        }
        await waitForWrite()
        authService.currentUserID = "user-2"
        service.activateAccount("user-2")
        mockRepo.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [completed], timeout: 1)
        let originalAccount = try await reload(entry.date, userID: "user-1")
        let newAccount = try await reload(entry.date, userID: "user-2")
        XCTAssertEqual(originalAccount.exercises?.map(\.id), [entry.id])
        XCTAssertTrue(newAccount.exercises?.isEmpty ?? true)
        XCTAssertEqual(mockRepo.dailyLogUpdateUserIDs, ["user-1"])
        XCTAssertNil(service.currentDailyLog)
    }

    private func add(_ exercise: LoggedExercise) async -> Bool {
        await withCheckedContinuation { continuation in
            store.addExerciseToLog(for: "user-1", exercise: exercise) { continuation.resume(returning: $0) }
        }
    }

    private func update(original: LoggedExercise, updated: LoggedExercise) async -> Bool {
        await withCheckedContinuation { continuation in
            store.updateExerciseInLog(for: "user-1", original: original, updated: updated) { continuation.resume(returning: $0) }
        }
    }

    private func sync(_ exercises: [LoggedExercise], date: Date) async {
        await withCheckedContinuation { continuation in
            store.addOrUpdateHealthKitWorkouts(for: "user-1", exercises: exercises, date: date) { continuation.resume() }
        }
    }

    private func reload(_ date: Date, userID: String = "user-1") async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in
            mockRepo.fetchLogInternal(userID: userID, date: date) { continuation.resume(with: $0) }
        }
    }

    private func waitForWrite() async {
        for _ in 0..<100 where mockRepo.deferredDailyLogUpdateCompletions.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(mockRepo.deferredDailyLogUpdateCompletions.isEmpty)
    }

    func testAddExerciseInitializesMissingExerciseArray() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        var log = DailyLog(id: dayID(viewedDate), date: viewedDate, meals: [])
        log.exercises = nil
        mockRepo.mockFetchLogResult = .success(log)

        store.addExerciseToLog(
            for: "user-1",
            exercise: exercise(id: "exercise-1", name: "Bike", date: viewedDate)
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.name), ["Bike"])
    }

    func testDeleteExerciseRemovesOnlyMatchingEntry() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        let keep = exercise(id: "keep", name: "Run", date: viewedDate)
        let remove = exercise(id: "remove", name: "Swim", date: viewedDate)
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: dayID(viewedDate), date: viewedDate, meals: [], exercises: [keep, remove])
        )

        store.deleteExerciseFromLog(for: "user-1", exerciseID: "remove")

        try await Task.sleep(nanoseconds: 50_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.id), ["keep"])
        XCTAssertEqual(service.currentDailyLog?.exercises?.map(\.id), ["keep"])
    }

    func testDeleteExerciseSkipsUpdateWhenExerciseIsMissing() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        let existing = exercise(id: "keep", name: "Run", date: viewedDate)
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: dayID(viewedDate), date: viewedDate, meals: [], exercises: [existing])
        )

        store.deleteExerciseFromLog(for: "user-1", exerciseID: "missing")

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(mockRepo.lastUpdatedLog)
        XCTAssertNil(service.currentDailyLog)
    }

    func testHealthKitSyncReplacesPreviousHealthKitWorkoutsAndKeepsManualEntries() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        let manual = exercise(id: "manual", name: "Strength", date: viewedDate, source: "routine")
        let oldHealthKit = exercise(id: "old-hk", name: "Old Walk", date: viewedDate, source: "HealthKit")
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: dayID(viewedDate), date: viewedDate, meals: [], exercises: [manual, oldHealthKit])
        )

        let synced = [
            exercise(id: "new-hk-1", name: "Outdoor Run", date: viewedDate, source: "HealthKit", calories: 325),
            exercise(id: "new-hk-2", name: "Cooldown", date: viewedDate, source: "HealthKit", calories: 80)
        ]
        let finished = expectation(description: "HealthKit sync completion")

        store.addOrUpdateHealthKitWorkouts(for: "user-1", exercises: synced, date: viewedDate) {
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.id), ["manual", "new-hk-1", "new-hk-2"])
        XCTAssertEqual(updatedLog.exercises?.map(\.source), ["routine", "HealthKit", "HealthKit"])
        XCTAssertEqual(service.currentDailyLog?.exercises?.map(\.id), ["manual", "new-hk-1", "new-hk-2"])
    }

    func testHealthKitSyncStillSavesWhenSyncedDateIsNotCurrentlyViewed() async throws {
        let viewedDate = fixedDay()
        let syncedDate = fixedDay(-1)
        service.activelyViewedDate = viewedDate
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: dayID(syncedDate), date: syncedDate, meals: [], exercises: [])
        )
        let finished = expectation(description: "HealthKit sync completion")

        store.addOrUpdateHealthKitWorkouts(
            for: "user-1",
            exercises: [exercise(id: "new-hk", name: "Walk", date: syncedDate, source: "HealthKit")],
            date: syncedDate
        ) {
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.id), ["new-hk"])
        XCTAssertNil(service.currentDailyLog)
    }

    func testHealthKitSyncCallsCompletionWithoutSavingWhenFetchFails() async {
        service.activelyViewedDate = fixedDay()
        mockRepo.mockFetchLogResult = .failure(URLError(.notConnectedToInternet))
        let finished = expectation(description: "HealthKit sync completion")

        store.addOrUpdateHealthKitWorkouts(
            for: "user-1",
            exercises: [exercise(id: "new-hk", name: "Walk", date: fixedDay(), source: "HealthKit")],
            date: fixedDay()
        ) {
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testExerciseMutationForAnotherAccountIsIgnored() async throws {
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: dayID(fixedDay()), date: fixedDay(), meals: [])
        )

        store.addExerciseToLog(
            for: "user-2",
            exercise: exercise(id: "private", name: "Private", date: fixedDay())
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(mockRepo.lastUpdatedLog)
        XCTAssertNil(service.currentDailyLog)
    }
}
