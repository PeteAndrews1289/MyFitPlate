import XCTest
import HealthKit
@testable import MyFitPlateCore

final class TrainingHistoryMathTests: XCTestCase {
    func testRecordedElapsedDurationWinsOverSetCountEstimate() {
        let movement = RoutineExercise(id: "bench", name: "Bench Press")
        let completed = CompletedExercise(exerciseName: movement.name, exercise: movement,
            sets: (0..<12).map { _ in CompletedSet(reps: 8, weight: 100) })
        let session = WorkoutSessionLog(id: "recorded-clock", date: Date(), routineID: "routine", completedExercises: [completed])
        let projection = WorkoutDiaryProjectionRules.make(log: session, name: "Strength", elapsed: 600, weightPounds: 180)
        XCTAssertEqual(projection.durationMinutes, 10, "Measured elapsed time must not be inflated by the fallback set estimate")
    }
    private func exercise(_ sets: [CompletedSet], equipment: StrengthEquipment? = nil) -> CompletedExercise {
        var movement = RoutineExercise(id: "bench", name: "Bench Press")
        movement.loadEquipment = equipment
        return CompletedExercise(exerciseName: movement.name, exercise: movement, sets: sets)
    }
    private func log(_ exercise: CompletedExercise, id: String = "session", date: Date = Date()) -> WorkoutSessionLog {
        WorkoutSessionLog(id: id, date: date, routineID: "routine", completedExercises: [exercise])
    }
    func testWarmupsNeverChangeWorkingVolumeBestSetOrRecord() {
        let work = CompletedSet(reps: 8, weight: 100)
        let value = exercise([CompletedSet(reps: 20, weight: 900, setType: .warmup), work])
        XCTAssertEqual(WorkoutSetMath.volume(value), 800)
        XCTAssertEqual(WorkoutSetMath.workingSetCount(log(value)), 1)
        XCTAssertEqual(WorkoutSetMath.bestSet(value)?.weight, 100)
        let past = log(exercise([CompletedSet(reps: 8, weight: 110)]), id: "past", date: Date().addingTimeInterval(-100))
        XCTAssertEqual(WorkoutSetMath.recordCount(in: log(value), history: [past]), 0)
    }
    func testInvalidNumbersAndTimedCardioCannotCreateStrengthVolume() {
        let invalid = exercise([CompletedSet(reps: 8, weight: .nan), CompletedSet(reps: 8, weight: -1)])
        XCTAssertEqual(WorkoutSetMath.volume(invalid), 0)
        var cardio = exercise([CompletedSet(reps: 100, weight: 500, durationInSeconds: 60)])
        cardio.exercise.type = .cardio
        XCTAssertEqual(WorkoutSetMath.volume(cardio), 0)
        XCTAssertNil(WorkoutSetMath.bestSet(cardio))
    }
    func testPerHandLoadRemainsCanonicalAndDifferentMeaningsCannotCompare() {
        let hand = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [50])
        let total = StrengthEquipment(loadingMeaning: .total, availableWeights: [50])
        let value = exercise([CompletedSet(reps: 8, weight: 50)], equipment: hand)
        XCTAssertEqual(WorkoutSetMath.volume(value), 400, "Do not invent a second implement")
        XCTAssertFalse(WorkoutSetMath.compatible(value, exercise(value.sets, equipment: total)))
        XCTAssertFalse(WorkoutSetMath.compatible(value, exercise(value.sets)))
    }
    func testRecordsRequireCompatibleEarlierEvidenceAndNoFirstEverRecord() {
        let hand = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [50, 60])
        let current = log(exercise([CompletedSet(reps: 8, weight: 60)], equipment: hand))
        XCTAssertEqual(WorkoutSetMath.recordCount(in: current, history: []), 0)
        let old = log(exercise([CompletedSet(reps: 8, weight: 50)], equipment: hand), id: "old", date: current.date.addingTimeInterval(-100))
        XCTAssertEqual(WorkoutSetMath.recordCount(in: current, history: [old, old]), 1)
        let unrelated = log(exercise([CompletedSet(reps: 8, weight: 10)]), id: "other", date: old.date)
        XCTAssertEqual(WorkoutSetMath.recordCount(in: current, history: [unrelated]), 0)
    }
    func testDuplicateSessionReceiptsCountOnce() {
        let value = log(exercise([CompletedSet(reps: 8, weight: 100)]))
        XCTAssertEqual(WorkoutSetMath.uniqueSessions([value, value]).count, 1)
    }
    func testRepeatedCompatibleExerciseUsesItsBestCurrentWorkingSetForOneRecord() {
        let prior = log(exercise([CompletedSet(reps: 8, weight: 100)]), id: "prior", date: Date().addingTimeInterval(-100))
        var current = log(exercise([CompletedSet(reps: 8, weight: 90)]))
        current.completedExercises.append(exercise([CompletedSet(reps: 8, weight: 110)]))
        XCTAssertEqual(WorkoutSetMath.recordCount(in: current, history: [prior]), 1)
    }
    func testWarmupOnlyRecoveryIsUnknown() {
        let value = log(exercise([CompletedSet(reps: 8, weight: 100, setType: .warmup)]))
        let results = MuscleRecoveryRules.estimates(sessions: [value], sleepScore: 90, sleepDate: value.date, asOf: value.date)
        XCTAssertTrue(results.allSatisfy { $0.status == .noRecentSignal })
    }
    func testRecoveryUsesMeasuredWorkingSetsOnlyAndIgnoresFutureReceipts() throws {
        let now = Date()
        let value = log(exercise([CompletedSet(reps: 8, weight: 100), CompletedSet(reps: 8, weight: 200, setType: .warmup)]), date: now.addingTimeInterval(-100))
        let future = log(exercise([CompletedSet(reps: 8, weight: 100)]), id: "future", date: now.addingTimeInterval(100))
        let chest = try XCTUnwrap(MuscleRecoveryRules.estimates(sessions: [value, value, future], sleepScore: nil, sleepDate: nil, asOf: now).first { $0.group == .chest })
        XCTAssertEqual(chest.lastSessionSets, 1)
        XCTAssertEqual(chest.lastTrained, value.date)
    }
    func testStaleSleepCannotShortenRecoveryWindow() throws {
        let now = Date()
        let value = log(exercise([CompletedSet(reps: 8, weight: 100)]), date: now.addingTimeInterval(-100))
        let stale = try XCTUnwrap(MuscleRecoveryRules.estimates(sessions: [value], sleepScore: 90, sleepDate: now.addingTimeInterval(-40 * 3600), asOf: now).first { $0.group == .chest })
        let fresh = try XCTUnwrap(MuscleRecoveryRules.estimates(sessions: [value], sleepScore: 90, sleepDate: now.addingTimeInterval(-3600), asOf: now).first { $0.group == .chest })
        XCTAssertEqual(stale.sleepMultiplier, 1)
        XCTAssertEqual(fresh.sleepMultiplier, 0.9)
    }
}

@MainActor
final class WorkoutCorrectionIntegrityTests: XCTestCase {
    private var directory: URL!
    private var auth: MockAuthService!
    private var nutrition: MockNutritionRepository!
    private var workouts: MockWorkoutRepository!
    private var diary: DailyLogService!
    private var original: WorkoutSessionLog!
    private var coordinator: WorkoutCorrectionCoordinator!
    private var store: WorkoutCorrectionStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        auth = MockAuthService(); auth.currentUserID = "owner"
        nutrition = MockNutritionRepository(); nutrition.persistsDailyLogUpdates = true
        workouts = MockWorkoutRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = nutrition; DIContainer.shared.workoutRepository = workouts
        diary = DailyLogService(); diary.activateAccount("owner")
        let date = Date().addingTimeInterval(-2 * 86400)
        let routine = WorkoutRoutine(id: "routine", userID: "owner", name: "PHUL", dateCreated: date,
            exercises: [RoutineExercise(id: "bench", name: "Bench Press", sets: [ExerciseSet(id: "set", isCompleted: true, reps: 8, weight: 100)])])
        var draft = WorkoutSessionDraft(routine: routine, now: date,
            programContext: WorkoutProgramSessionContext(programID: "existing-phul", slotIndex: 38))
        draft.elapsed = 600
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 180, now: date))
        original = draft.completion!
        workouts.mockFetchSessionLogResult = .success(original)
        nutrition.mockLogsByDay = [DailyLog(id: DiaryDayContext.dayKey(for: date), date: date, meals: [], exercises: [draft.diaryExercise!])]
        store = WorkoutCorrectionStore(directory: directory)
        coordinator = WorkoutCorrectionCoordinator(store: store, repository: workouts, diary: diary, auth: auth)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        coordinator = nil; store = nil; diary = nil; workouts = nil; nutrition = nil; auth = nil
        super.tearDown()
    }
    private func edited() -> WorkoutSessionLog {
        var result = original!
        result.completedExercises[0].sets.append(CompletedSet(reps: 8, weight: 110))
        return result
    }
    func testConcurrentRevisionAfterPreflightIsRejectedBeforeHistoryOrDiaryChanges() async throws {
        let receipt = try coordinator.prepare(original: original, updated: edited(), userID: "owner")
        var newer = original!
        newer.correctionRevisionID = "another-device"
        newer.completedExercises[0].sets[0].weight = 140
        workouts.beforeCorrectionCommit = { [weak workouts] in workouts?.mockFetchSessionLogResult = .success(newer) }
        do {
            _ = try await coordinator.resume(receipt)
            XCTFail("A transaction must check again after the cached preflight")
        } catch { XCTAssertEqual(error as? WorkoutCorrectionError, .conflict) }
        XCTAssertTrue(workouts.savedSessionLogs.isEmpty)
        XCTAssertNotNil(try store.pending(sessionID: original.id!, userID: "owner"))
    }
    func testCorrectionUpdatesOneLinkedOriginalDayAndNeverProgramPointer() async throws {
        let service = WorkoutService()
        let program = WorkoutProgram(id: "existing-phul", userID: "owner", name: "PHUL", currentProgressIndex: 38, skippedIndices: [2, 7])
        service.setActiveProgram(program)
        diary.activelyViewedDate = Date()
        let command = try coordinator.prepare(original: original, updated: edited(), userID: "owner")
        let receipt = try await coordinator.resume(command)
        XCTAssertEqual(receipt.diaryResult, .updated)
        XCTAssertTrue(receipt.isComplete)
        XCTAssertEqual(workouts.savedSessionLogs.count, 1)
        XCTAssertEqual(workouts.savedSessionLogs[0].id, original.id)
        XCTAssertEqual(workouts.savedSessionLogs[0].programContext, original.programContext)
        XCTAssertEqual(nutrition.lastUpdatedLog?.exercises?.count, 1)
        XCTAssertEqual(nutrition.lastUpdatedLog?.exercises?.first?.caloriesBurned ?? 0, original.generatedDiaryExercise!.caloriesBurned * 2, accuracy: 0.001)
        let saved = try XCTUnwrap(nutrition.lastUpdatedLog)
        XCTAssertTrue(Calendar.current.isDate(saved.date, inSameDayAs: original.date))
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 38)
        XCTAssertEqual(service.activeProgram?.skippedIndices, [2, 7])
        XCTAssertNil(try store.pending(sessionID: original.id!, userID: "owner"))
        let replay = try await coordinator.resume(receipt)
        XCTAssertTrue(replay.isComplete)
        XCTAssertEqual(workouts.savedSessionLogs.count, 1)
    }
    func testManualDiaryOverrideIsPreservedWithoutWritingDiary() async throws {
        nutrition.mockLogsByDay[0].exercises?[0].caloriesBurned = 123.5
        let result = try await coordinator.resume(coordinator.prepare(original: original, updated: edited(), userID: "owner"))
        XCTAssertEqual(result.diaryResult, .preservedOverride)
        XCTAssertTrue(nutrition.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertEqual(nutrition.mockLogsByDay[0].exercises?.first?.caloriesBurned, 123.5)
    }
    func testMissingDiaryMirrorIsNeverRecreated() async throws {
        nutrition.mockLogsByDay[0].exercises = []
        let result = try await coordinator.resume(coordinator.prepare(original: original, updated: edited(), userID: "owner"))
        XCTAssertEqual(result.diaryResult, .missing)
        XCTAssertTrue(nutrition.dailyLogUpdateUserIDs.isEmpty)
    }
    func testLegacyUnknownEstimateKeepsExistingDiaryTotals() async throws {
        original.generatedDiaryExercise = nil; original.projectionBodyWeightPounds = nil
        workouts.mockFetchSessionLogResult = .success(original)
        let result = try await coordinator.resume(coordinator.prepare(original: original, updated: edited(), userID: "owner"))
        XCTAssertEqual(result.diaryResult, .preservedOverride)
        XCTAssertTrue(nutrition.dailyLogUpdateUserIDs.isEmpty)
    }
    func testExplicitHealthOverrideIsPreserved() async throws {
        nutrition.mockLogsByDay[0].exercises?[0].hasLocalHealthKitEdits = true
        let result = try await coordinator.resume(coordinator.prepare(original: original, updated: edited(), userID: "owner"))
        XCTAssertEqual(result.diaryResult, .preservedOverride)
        XCTAssertTrue(nutrition.dailyLogUpdateUserIDs.isEmpty)
    }
    func testPartialSaveRecoversFromDiskAndRetriesOnlyDiary() async throws {
        nutrition.updateLogSuccess = false
        let first = try await coordinator.resume(coordinator.prepare(original: original, updated: edited(), userID: "owner"))
        XCTAssertTrue(first.historyAccepted); XCTAssertEqual(first.diaryResult, .failed)
        let recovered = try XCTUnwrap(WorkoutCorrectionStore(directory: directory).pending(sessionID: original.id!, userID: "owner"))
        workouts.mockFetchSessionLogResult = .success(recovered.updated)
        nutrition.updateLogSuccess = true
        let second = try await coordinator.resume(recovered)
        XCTAssertEqual(second.diaryResult, .updated)
        XCTAssertEqual(workouts.savedSessionLogs.count, 1)
        XCTAssertEqual(nutrition.lastUpdatedLog?.exercises?.count, 1)
    }
    func testHistoryFailureKeepsReceiptAndDoesNotTouchDiary() async throws {
        workouts.saveWorkoutSessionLogError = CocoaError(.fileWriteUnknown)
        let command = try coordinator.prepare(original: original, updated: edited(), userID: "owner")
        do { _ = try await coordinator.resume(command); XCTFail("Expected rejected save") } catch {}
        XCTAssertNotNil(try store.pending(sessionID: original.id!, userID: "owner"))
        XCTAssertTrue(nutrition.dailyLogUpdateUserIDs.isEmpty)
        workouts.saveWorkoutSessionLogError = nil
        let recovered = try await coordinator.resume(command)
        XCTAssertTrue(recovered.isComplete)
    }
    func testConcurrentChangedHistoryRejectsCorrectionBeforeWrites() async throws {
        let command = try coordinator.prepare(original: original, updated: edited(), userID: "owner")
        var newer = original!; newer.completedExercises[0].sets[0].weight = 999
        workouts.mockFetchSessionLogResult = .success(newer)
        do { _ = try await coordinator.resume(command); XCTFail("Expected conflict") } catch { XCTAssertTrue(error is WorkoutCorrectionError) }
        XCTAssertTrue(workouts.savedSessionLogs.isEmpty)
        XCTAssertTrue(nutrition.dailyLogUpdateUserIDs.isEmpty)
    }
    func testAccountSwitchCannotReplayAnotherOwnersCorrection() async throws {
        let command = try coordinator.prepare(original: original, updated: edited(), userID: "owner")
        auth.currentUserID = "other"
        do { _ = try await coordinator.resume(command); XCTFail("Expected account guard") } catch {}
        XCTAssertTrue(workouts.savedSessionLogs.isEmpty)
        XCTAssertNil(try store.pending(sessionID: original.id!, userID: "other"))
    }
    func testCrossDayAndInvalidQuantityCorrectionsAreRejected() throws {
        // A local calendar day can contain 25 hours at the autumn DST transition.
        var updated = edited(); updated.date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: original.date))
        XCTAssertThrowsError(try coordinator.prepare(original: original, updated: updated, userID: "owner"))
        updated = edited(); updated.completedExercises[0].sets[0].weight = .nan
        XCTAssertThrowsError(try coordinator.prepare(original: original, updated: updated, userID: "owner"))
    }
    func testConflictingProposalCanBeArchivedWithoutWritingHistoryOrDeletingValues() throws {
        let command = try coordinator.prepare(original: original, updated: edited(), userID: "owner")
        let archived = try coordinator.abandon(command)
        XCTAssertTrue(archived.isComplete)
        XCTAssertFalse(archived.historyAccepted)
        XCTAssertEqual(archived.original.completedExercises[0].sets.count, 1)
        XCTAssertEqual(archived.updated.completedExercises[0].sets.count, 2)
        XCTAssertNil(try store.pending(sessionID: original.id!, userID: "owner"))
        XCTAssertTrue(workouts.savedSessionLogs.isEmpty)
        XCTAssertTrue(nutrition.dailyLogUpdateUserIDs.isEmpty)
    }
}
