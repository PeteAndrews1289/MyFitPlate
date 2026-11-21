import XCTest
@testable import MyFitPlateCore

final class WorkoutProgramIntegrityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var start: Date {
        calendar.date(from: DateComponents(year: 2025, month: 1, day: 6))!
    }

    private func program(index: Int = 0) -> WorkoutProgram {
        let names = ["Upper Power", "Lower Power", "Upper Hypertrophy", "Lower Hypertrophy"]
        let routines = names.enumerated().map { index, name in
            WorkoutRoutine(id: "phul-routine-\(index)", userID: "owner", name: name,
                           dateCreated: start.addingTimeInterval(-86_400),
                           exercises: [RoutineExercise(id: "movement-\(index)", name: "Bench Press",
                                                       sets: [ExerciseSet(id: "set-\(index)", target: "8-12", reps: 8, weight: 165)])])
        }
        return WorkoutProgram(id: "existing-phul", userID: "owner", name: "PHUL",
                              dateCreated: start.addingTimeInterval(-86_400), routines: routines,
                              startDate: start, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: index)
    }

    private func log(_ slot: Int, in program: WorkoutProgram, id: String? = nil, at date: Date? = nil) -> WorkoutSessionLog {
        WorkoutSessionLog(id: id ?? "session-\(slot)", date: date ?? start.addingTimeInterval(Double(slot + 1) * 3_600),
                          routineID: program.routines[slot % program.routines.count].id, completedExercises: [],
                          programContext: WorkoutProgramSessionContext(programID: program.id!, slotIndex: slot))
    }

    func testSeededExistingPHULPointerSkipsIDsAndTemplatesAreUnchangedByOldHistory() throws {
        var existing = program(index: 38)
        existing.skippedIndices = [2, 7, 15]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(existing)
        let oldLogs = (0..<12).map { index -> WorkoutSessionLog in
            var old = log(index, in: existing)
            old.programContext = WorkoutProgramSessionContext(programID: "earlier-phul", slotIndex: index)
            return old
        }
        let unchanged = WorkoutRules.reconcileProgressFromSessionLogs(in: existing, sessionLogs: oldLogs)
        XCTAssertEqual(try encoder.encode(unchanged), original)
        XCTAssertEqual(unchanged.currentProgressIndex, 38, "Seeded session 39 of 48 is preserved; this is not a live account assertion")
        XCTAssertEqual(unchanged.skippedIndices, [2, 7, 15])
    }

    func testFreshPHULAfterTwelveOldSessionsStartsAtZero() {
        var old = program(index: 12)
        old.skippedIndices = [1, 4]
        let oldLogs = (0..<12).map { index -> WorkoutSessionLog in
            let routine = old.routines[index % old.routines.count]
            let exercise = routine.exercises[0]
            return WorkoutSessionLog(id: "old-session-\(index)", date: start.addingTimeInterval(Double(index + 1) * 86_400),
                                     routineID: routine.id, completedExercises: [
                                        CompletedExercise(exerciseName: exercise.name, exercise: exercise,
                                                          sets: [CompletedSet(reps: 8, weight: 165)])
                                     ])
        }
        var fresh = WorkoutRules.preparePreBuiltProgramForUser(old, userID: "owner", startDate: Date(), calendar: calendar)
        fresh.id = "fresh-phul"
        let result = WorkoutRules.reconcileProgressFromSessionLogs(in: fresh, sessionLogs: oldLogs)
        XCTAssertEqual(result.currentProgressIndex, 0)
        XCTAssertNil(result.skippedIndices)
        XCTAssertEqual(old.skippedIndices, [1, 4], "Adoption changes only its new copy")
        XCTAssertTrue(WorkoutRules.sessionLogsBySlot(in: fresh, sessionLogs: oldLogs, calendar: calendar).isEmpty)
        XCTAssertTrue(oldLogs.allSatisfy { !WorkoutRules.logBelongsToProgram($0, program: fresh) })
    }

    func testNewPlanReusingRoutineIDsDoesNotAdoptEarlierLegacySessions() {
        var fresh = program()
        fresh.dateCreated = start.addingTimeInterval(30 * 86_400)
        fresh.startDate = fresh.dateCreated
        let old = WorkoutSessionLog(id: "old", date: start, routineID: fresh.routines[0].id, completedExercises: [])
        XCTAssertFalse(WorkoutRules.logBelongsToProgram(old, program: fresh))
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: fresh, sessionLogs: [old]).currentProgressIndex, 0)
    }

    func testNewPlanDoesNotAdoptLaterNameOnlyHistory() {
        let fresh = program()
        let exercise = fresh.routines[0].exercises[0]
        let unrelated = WorkoutSessionLog(id: "similar", date: start.addingTimeInterval(3_600), routineID: "another-routine",
                                         completedExercises: [CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: [])])
        XCTAssertFalse(WorkoutRules.logBelongsToProgram(unrelated, program: fresh))
    }

    func testExplicitProgramIdentityOverridesMatchingRoutineID() {
        let value = program()
        var other = log(0, in: value)
        other.programContext = WorkoutProgramSessionContext(programID: "other-program", slotIndex: 0)
        XCTAssertFalse(WorkoutRules.logBelongsToProgram(other, program: value))
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [other]).currentProgressIndex, 0)
    }

    func testEarlyCompletionDoesNotMarkInterveningSlotsDone() {
        let value = program()
        let early = log(2, in: value)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [early]).currentProgressIndex, 0)
        let first = log(0, in: value)
        let once = WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [early, first])
        XCTAssertEqual(once.currentProgressIndex, 1)
        let second = log(1, in: value)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: once, sessionLogs: [second, early, first]).currentProgressIndex, 3)
    }

    func testDuplicateAndReorderedExplicitCompletionsAreIdempotent() {
        let value = program()
        let logs = [log(2, in: value), log(0, in: value), log(1, in: value)]
        let forward = WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: logs + logs)
        let backward = WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: Array(logs.reversed()))
        XCTAssertEqual(forward.currentProgressIndex, 3)
        XCTAssertEqual(backward.currentProgressIndex, 3)
        let replayed = WorkoutRules.reconcileProgressFromSessionLogs(in: forward, sessionLogs: logs)
        XCTAssertEqual(replayed.currentProgressIndex, 3)
        XCTAssertEqual(WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: logs + logs).count, 3)
    }

    func testReviewMappingUsesCapturedSlotsInsteadOfChronologicalZip() {
        let value = program(index: 3)
        let first = log(0, in: value, at: start.addingTimeInterval(3 * 86_400))
        let early = log(2, in: value, at: start.addingTimeInterval(3_600))
        let map = WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [early, first])
        XCTAssertEqual(map[0]?.id, first.id)
        XCTAssertEqual(map[2]?.id, early.id)
        XCTAssertNil(map[1])
    }

    func testOneSessionIdentityCannotFulfillTwoSlots() {
        let value = program()
        let first = log(0, in: value, id: "same")
        let second = log(1, in: value, id: "same")
        let map = WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [second, first])
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map[0]?.id, "same")
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [second, first]).currentProgressIndex, 1)
    }

    func testStoredPointerAndSkipsAreNeverLoweredBySparseHistory() {
        var value = program(index: 38)
        value.skippedIndices = [1, 4, 17]
        let result = WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [log(0, in: value)])
        XCTAssertEqual(result.currentProgressIndex, 38)
        XCTAssertEqual(result.skippedIndices, value.skippedIndices)
        XCTAssertEqual(result.routines.map(\.id), value.routines.map(\.id))
    }

    func testCurrentExplicitCompletionAdvancesOnceWithoutChangingSkips() {
        var value = program(index: 38)
        value.skippedIndices = [1, 4, 17]
        let completion = log(38, in: value)
        let next = WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [completion])
        XCTAssertEqual(next.currentProgressIndex, 39)
        XCTAssertEqual(next.skippedIndices, value.skippedIndices)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: next, sessionLogs: [completion]).currentProgressIndex, 39)
    }

    func testLegacyUniqueScheduledRoutineDayCanReviewPassedSlotWithoutInferringNewProgress() {
        let value = program(index: 1)
        let legacy = WorkoutSessionLog(id: "legacy", date: start.addingTimeInterval(12 * 3_600),
                                       routineID: value.routines[0].id, completedExercises: [])
        let map = WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [legacy, legacy], calendar: calendar)
        XCTAssertEqual(map[0]?.id, "legacy")
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [legacy]).currentProgressIndex, 1)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: program(), sessionLogs: [legacy]).currentProgressIndex, 0)
    }

    func testLegacyAmbiguousSameDaySessionsAreLeftUnassigned() {
        let value = program(index: 1)
        let one = WorkoutSessionLog(id: "one", date: start.addingTimeInterval(3_600), routineID: value.routines[0].id, completedExercises: [])
        let two = WorkoutSessionLog(id: "two", date: start.addingTimeInterval(7_200), routineID: value.routines[0].id, completedExercises: [])
        XCTAssertTrue(WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [one, two], calendar: calendar).isEmpty)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [one, two]).currentProgressIndex, 1)
    }

    func testLegacyWrongScheduledDayAndMissingScheduleCannotGuessSlots() {
        var value = program(index: 1)
        let wrongDay = WorkoutSessionLog(id: "wrong-day", date: start.addingTimeInterval(86_400),
                                        routineID: value.routines[0].id, completedExercises: [])
        XCTAssertTrue(WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [wrongDay], calendar: calendar).isEmpty)
        value.startDate = nil
        XCTAssertTrue(WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [wrongDay], calendar: calendar).isEmpty)
    }

    func testExplicitReviewSurvivesScheduleAndRoutineEdits() {
        var value = program()
        let completed = log(0, in: value)
        value.startDate = start.addingTimeInterval(30 * 86_400)
        value.routines[0].id = "edited-routine-id"
        XCTAssertEqual(WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [completed])[0]?.id, completed.id)
    }

    func testSessionContextCapturesRequestedOccurrenceAndRejectsMismatch() {
        let value = program(index: 1)
        let routine = value.routines[0]
        XCTAssertEqual(WorkoutRules.sessionContext(for: value, routineID: routine.id)?.slotIndex, 4)
        XCTAssertEqual(WorkoutRules.sessionContext(for: value, routineID: routine.id, slotIndex: 8)?.slotIndex, 8)
        XCTAssertNil(WorkoutRules.sessionContext(for: value, routineID: routine.id, slotIndex: 1))
        XCTAssertNil(WorkoutRules.sessionContext(for: value, routineID: routine.id, slotIndex: 48))
    }

    func testLegacyProgramAndLogDecodeWithoutProvenanceOrMigration() throws {
        let value = program(index: 38)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        let decoded = try JSONDecoder().decode(WorkoutProgram.self, from: data)
        XCTAssertEqual(try encoder.encode(decoded), data)
        let old = WorkoutSessionLog(id: "legacy", date: start, routineID: value.routines[0].id, completedExercises: [])
        let oldData = try encoder.encode(old)
        let restored = try JSONDecoder().decode(WorkoutSessionLog.self, from: oldData)
        XCTAssertNil(restored.programContext)
        XCTAssertEqual(try encoder.encode(restored), oldData)
    }

    func testFrozenDraftContextSurvivesRecoveryAndCompletionRetry() throws {
        let value = program()
        let routine = try XCTUnwrap(value.routines[0].deepCopy())
        routine.exercises[0].sets[0].isCompleted = true
        let context = try XCTUnwrap(WorkoutRules.sessionContext(for: value, routineID: routine.id, slotIndex: 0))
        var draft = WorkoutSessionDraft(routine: routine, now: start, programContext: context)
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 165, now: start.addingTimeInterval(3_600)))
        let data = try JSONEncoder().encode(draft)
        var recovered = try JSONDecoder().decode(WorkoutSessionDraft.self, from: data)
        recovered.programContext = WorkoutProgramSessionContext(programID: "later-active-program", slotIndex: 12)
        XCTAssertTrue(recovered.prepareCompletion(weightPounds: 180, now: start.addingTimeInterval(7_200)))
        XCTAssertEqual(recovered.completion?.programContext, context, "A frozen completion cannot be retargeted by later active-program state")
        XCTAssertEqual(recovered.completion?.id, draft.completion?.id)
    }

    func testLegacyDraftDecodePreservesDataWithoutInventingAProgramContext() throws {
        let value = program()
        let draft = WorkoutSessionDraft(routine: value.routines[0], now: start)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(draft)
        let restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: data)
        XCTAssertNil(restored.programContext)
        XCTAssertEqual(try encoder.encode(restored), data)
    }

    func testInvalidAndFutureExplicitSlotsCannotAdvanceProgress() {
        let value = program()
        var invalid = log(0, in: value)
        invalid.programContext = WorkoutProgramSessionContext(programID: value.id!, slotIndex: -1)
        var future = log(0, in: value)
        future.date = Date.distantFuture
        XCTAssertTrue(WorkoutRules.sessionLogsBySlot(in: value, sessionLogs: [invalid, future]).isEmpty)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: value, sessionLogs: [invalid, future]).currentProgressIndex, 0)
    }
}
