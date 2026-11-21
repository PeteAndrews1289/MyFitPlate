import XCTest
@testable import MyFitPlateCore

final class WeekRescueReviewTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }
    private func program() -> WorkoutProgram {
        let routine = WorkoutRoutine(id: "upper", userID: "owner", name: "Upper", dateCreated: now,
            exercises: [RoutineExercise(id: "row", name: "Row", sets: (0..<4).map {
                ExerciseSet(id: "set-\($0)", target: "8-12", reps: 8, weight: 40)
            })])
        return WorkoutProgram(id: "phul", userID: "owner", name: "PHUL", dateCreated: now,
            routines: [routine], startDate: now, daysOfWeek: Array(1...7), currentProgressIndex: 0)
    }
    private func preview(_ program: WorkoutProgram, protected: Set<Int> = []) throws -> WeekRescueAdjustment {
        try WeekRescueReviewRules.preview(program: program, reason: .lessTime, workoutDate: now,
            scope: .remainingWeek, windowDays: 3, minutes: 20, protectedSlots: protected, now: now, calendar: calendar)
    }

    func testWholeWindowShowsEveryChangedSessionAndPreservesActiveEarlyCompleteAndSkippedSlots() throws {
        var source = program()
        source.slotCompletionProofs = [WorkoutSlotCompletionProof(slotIndex: 1, sessionID: "accepted-early")]
        source.skippedIndices = [2]
        let result = try WeekRescueReviewRules.preview(program: source, reason: .lessTime, workoutDate: now,
            scope: .remainingWeek, windowDays: 7, minutes: 20, protectedSlots: [0], now: now, calendar: calendar)
        XCTAssertEqual(result.slots.map(\.index), [3, 4, 5, 6])
        XCTAssertTrue(result.slots.allSatisfy { $0.routine?.exercises[0].sets.count == 2 })
        XCTAssertEqual(source.routines[0].exercises[0].sets.count, 4)
        XCTAssertEqual(source.currentProgressIndex, 0)
        XCTAssertThrowsError(try WeekRescueReviewRules.preview(program: source, reason: .lessTime, workoutDate: now,
            scope: .thisSession, windowDays: 7, protectedSlots: [0], now: now, calendar: calendar))
    }

    func testUnavailableCalendarDoesNotCompressGapsOrForceAWorkoutOutsideWindow() throws {
        let source = program()
        let monday = calendar.component(.weekday, from: now)
        XCTAssertThrowsError(try WeekRescueReviewRules.preview(program: source, reason: .missedWorkout, workoutDate: day(1),
            scope: .remainingWeek, windowDays: 3, availableWeekdays: [monday], now: now, calendar: calendar))
        XCTAssertNil(source.weekRescue)
    }

    func testAuthoredDateExceptionCanBeReviewedWithoutReplacingItsBase() throws {
        var source = program()
        source.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: source)
        source.trainingBlock?.scheduleExceptions = [WorkoutScheduleException(id: "move", slotIndex: 0,
            originalDay: TrainingCalendarDay(now, calendar: calendar), proposedDay: TrainingCalendarDay(day(1), calendar: calendar), revision: 1)]
        let adjustment = try WeekRescueRules.preview(program: source, reason: .missedWorkout, workoutDate: day(2), now: now, calendar: calendar)
        let saved = try WeekRescueRules.applying(adjustment, to: source)
        XCTAssertEqual(saved.date(forSlot: 0, calendar: calendar), day(2))
        XCTAssertEqual(saved.trainingBlock?.scheduleExceptions, source.trainingBlock?.scheduleExceptions)
        let undone = try WeekRescueRules.undoing(id: adjustment.id, in: saved)
        XCTAssertEqual(undone.date(forSlot: 0, calendar: calendar), day(1))
    }

    func testCheckedCommandOnlyChangesOverlayAndRejectsLateStructureProgressOrCapturedActiveWork() throws {
        let source = program()
        let rescue = try preview(source)
        let draft = try WeekRescueReviewDraft(program: source, rescue: rescue)
        let accepted = try draft.command.applying(to: source)
        XCTAssertEqual(accepted.weekRescue?.id, rescue.id)
        XCTAssertEqual(accepted.currentProgressIndex, source.currentProgressIndex)
        XCTAssertEqual(try PlanFingerprint.make(accepted.routines), try PlanFingerprint.make(source.routines))
        var changed = source; changed.name = "Changed elsewhere"
        XCTAssertThrowsError(try draft.command.applying(to: changed))
        changed = source; changed.currentProgressIndex = 1
        XCTAssertThrowsError(try draft.command.applying(to: changed))
        XCTAssertThrowsError(try WeekRescueReviewDraft(program: source, rescue: rescue, protectedSlots: [0]))
        var invalid = accepted; invalid.name = "Unreviewed rename"
        XCTAssertThrowsError(try WorkoutProgramEditCommand(expected: source, proposed: invalid, kind: .weekRescue))
        let undo = try WeekRescueReviewDraft(program: accepted, rescue: rescue, undo: true)
        XCTAssertNil(try undo.command.applying(to: accepted).weekRescue)
        XCTAssertNil(source.weekRescue)
    }

    func testDurableReviewKeepsFrozenCommandAndHistoryIsIdempotentAndAccountScoped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = EditorDraftStore(directory: directory)
        let store = WeekRescueReviewStore(storage: disk)
        let source = program()
        var draft = try WeekRescueReviewDraft(program: source, rescue: preview(source))
        try store.save(draft, userID: "owner")
        let restored = try XCTUnwrap(store.load(userID: "owner", programID: "phul"))
        XCTAssertEqual(try restored.command.fingerprint(), try draft.command.fingerprint())
        XCTAssertNil(try store.load(userID: "other", programID: "phul"))
        XCTAssertThrowsError(try store.save(draft, userID: "other"))
        draft.submitted = true; try store.save(draft, userID: "owner")
        XCTAssertThrowsError(try store.discard(draft, userID: "owner"))
        try store.finish(draft, userID: "owner", now: now)
        try store.finish(draft, userID: "owner", now: now)
        XCTAssertEqual(try store.history(userID: "owner", programID: "phul").count, 1)
        XCTAssertNil(try store.load(userID: "owner", programID: "phul"))
        XCTAssertTrue(try store.history(userID: "other", programID: "phul").isEmpty)
    }

    func testCheckedMockPublishesAcceptedRescueAndUndoToExistingListenerHook() async throws {
        let repository = MockWorkoutRepository()
        let source = program(); repository.mockSaveProgramResult = source
        var published: [WorkoutProgram?] = []
        repository.afterProgramEditCommit = { published.append($0) }
        let draft = try WeekRescueReviewDraft(program: source, rescue: preview(source))
        let result = try await repository.commitProgramEdit(userID: "owner", command: draft.command)
        let accepted = try XCTUnwrap(result)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published[0]?.weekRescue?.id, draft.rescue.id)
        let undo = try WeekRescueReviewDraft(program: accepted, rescue: draft.rescue, undo: true)
        _ = try await repository.commitProgramEdit(userID: "owner", command: undo.command)
        XCTAssertEqual(published.count, 2)
        XCTAssertNil(published[1]?.weekRescue)
        XCTAssertEqual(published[1]?.currentProgressIndex, source.currentProgressIndex)
    }

    func testAcceptedButUnacknowledgedRescueRetryReturnsOneReceiptAndCancellationPreventsLateApply() async throws {
        let repository = MockWorkoutRepository()
        let source = program(); repository.mockSaveProgramResult = source
        let draft = try WeekRescueReviewDraft(program: source, rescue: preview(source))
        repository.programEditFailureAfterCommit = CocoaError(.fileReadUnknown)
        do { _ = try await repository.commitProgramEdit(userID: "owner", command: draft.command); XCTFail("Expected lost acknowledgement") } catch {}
        repository.programEditFailureAfterCommit = nil
        let accepted = try await repository.commitProgramEdit(userID: "owner", command: draft.command)
        XCTAssertEqual(accepted?.weekRescue?.id, draft.rescue.id)
        XCTAssertEqual(repository.programEditReceipts.count, 1)
        let other = try WeekRescueReviewDraft(program: source, rescue: preview(source))
        _ = try await repository.resolveProgramEdit(userID: "owner", command: other.command, cancelPending: true)
        do { _ = try await repository.commitProgramEdit(userID: "owner", command: other.command); XCTFail("Cancelled operation must not apply") } catch {}
        XCTAssertEqual(repository.programEditReceipts.count, 2)
    }
    func testRescueRetainsCompletedWarmupAndSpecialSetsAndUndoAllowsLaterAcceptedProgress() throws {
        let source = program()
        source.routines[0].exercises[0].sets[3].isCompleted = true
        source.routines[0].exercises[0].sets.append(ExerciseSet(id: "warmup", target: "8", setType: .warmup, reps: 8, weight: 20))
        source.routines[0].exercises[0].sets.append(ExerciseSet(id: "drop", target: "8", setType: .drop, reps: 8, weight: 20))
        let rescue = try preview(source)
        let retained = try XCTUnwrap(rescue.slots[0].routine?.exercises[0].sets)
        XCTAssertTrue(retained.contains { $0.id == "set-3" && $0.isCompleted && $0.weight == 40 })
        XCTAssertTrue(retained.contains { $0.id == "warmup" })
        XCTAssertTrue(retained.contains { $0.id == "drop" })
        var accepted = try WeekRescueRules.applying(rescue, to: source)
        accepted.currentProgressIndex = 1
        accepted.slotCompletionProofs = [WorkoutSlotCompletionProof(slotIndex: 0, sessionID: "completed-after-rescue")]
        let undo = try WeekRescueReviewDraft(program: accepted, rescue: rescue, undo: true)
        let undone = try undo.command.applying(to: accepted)
        XCTAssertNil(undone.weekRescue)
        XCTAssertEqual(undone.currentProgressIndex, 1)
        XCTAssertEqual(undone.slotCompletionProofs?.first?.sessionID, "completed-after-rescue")
        XCTAssertEqual(undone.date(forSlot: 0, calendar: calendar), accepted.date(forSlot: 0, calendar: calendar))
        XCTAssertThrowsError(try WeekRescueReviewDraft(program: accepted, rescue: rescue, undo: true, protectedSlots: [1]),
                             "An open shortened workout keeps its current targets until it finishes.")
    }

}
