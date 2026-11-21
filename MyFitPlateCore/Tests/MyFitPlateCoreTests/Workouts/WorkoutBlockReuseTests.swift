import XCTest
@testable import MyFitPlateCore

final class WorkoutBlockReuseTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func fixture(progress: Int = 0, days: Int = 4, routines: Int = 4, weeks: Int = 12) throws -> WorkoutProgram {
        let rotations = (0..<routines).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: "reuse-user", name: "Day \(index + 1)", dateCreated: date,
                exercises: [RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [
                    ExerciseSet(id: "set-\(index)", target: "8–12 reps")])])
        }
        var program = WorkoutProgram(id: "phul", userID: "reuse-user", name: "PHUL", dateCreated: date,
            routines: rotations, startDate: date, daysOfWeek: Array(1...days), currentProgressIndex: progress,
            skippedIndices: [2, 5])
        program.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: program, weekCount: weeks)
        return program
    }

    func testCopyPastWeekIntoFutureKeepsPHUL39Of48AndSourceAndScheduleUnchanged() throws {
        let original = try fixture(progress: 39)
        let before = try WorkoutBlockRules.fingerprint(original)
        var draft = original; draft.trainingBlock?.revisionID = UUID().uuidString
        let review = try WorkoutWeekCopyRules.review(in: draft, sourceWeek: 0, destinationWeek: 10)
        let copied = try WorkoutWeekCopyRules.applying(review, to: draft)
        let saved = try WorkoutBlockRules.applying(copied, to: original, expected: original)
        XCTAssertEqual(saved.currentProgressIndex, 39)
        XCTAssertEqual(saved.totalSlots, 48)
        XCTAssertEqual(saved.skippedIndices, [2, 5])
        XCTAssertEqual(saved.startDate, original.startDate)
        XCTAssertEqual(saved.daysOfWeek, original.daysOfWeek)
        XCTAssertEqual(saved.trainingBlock?.weeks.map(\.id), original.trainingBlock?.weeks.map(\.id))
        XCTAssertEqual(saved.trainingBlock?.id, original.trainingBlock?.id)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(original), before)
        XCTAssertEqual(copied.overrides.map(\.slotIndex), [40, 41, 42, 43])
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(saved.routine(forSlot: 40))),
                       try WorkoutBlockRules.fingerprint(XCTUnwrap(original.routine(forSlot: 0))))
    }

    func testOddRotationCopiesResolvedSessionsRatherThanOnlyOverrides() throws {
        let original = try fixture(days: 3, routines: 2, weeks: 4)
        let review = try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 1)
        let block = try WorkoutWeekCopyRules.applying(review, to: original)
        var copied = original; copied.trainingBlock = block
        XCTAssertEqual((3..<6).compactMap { copied.routine(forSlot: $0)?.id }, ["routine-0", "routine-1", "routine-0"])
        XCTAssertEqual((3..<6).compactMap { original.routine(forSlot: $0)?.id }, ["routine-1", "routine-0", "routine-1"])
    }

    func testCopyDeepSnapshotsAndPrescriptionsKeepDestinationIdentityAndOwnLaterEdits() throws {
        var original = try fixture(weeks: 4)
        let routine = try XCTUnwrap(original.routine(forSlot: 0)?.deepCopy())
        let prescription = WorkoutPrescription(kind: .repetitions, lowerBound: 5, upperBound: 8,
            effort: SetEffort(scale: .rpe, value: 8), loadPercentage: 75,
            loadReference: .init(label: "Training max", weightPounds: 200, date: date))
        routine.exercises[0].sets[0].prescription = prescription
        routine.exercises[0].sets[0].target = prescription.targetText
        original.trainingBlock?.overrides = [WorkoutBlockSlotOverride(slotIndex: 0, routine: routine)]
        original.trainingBlock?.weeks[0].isDeload = true
        original.trainingBlock?.weeks[1].name = "Keep destination name"
        let destinationID = original.trainingBlock?.weeks[1].id
        let review = try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 1)
        let block = try WorkoutWeekCopyRules.applying(review, to: original)
        XCTAssertEqual(block.weeks[1].id, destinationID)
        XCTAssertEqual(block.weeks[1].name, "Keep destination name")
        XCTAssertTrue(block.weeks[1].isDeload)
        let copiedRoutine = try XCTUnwrap(block.overrides.first { $0.slotIndex == 4 }?.routine)
        XCTAssertEqual(copiedRoutine.exercises[0].sets[0].prescription, prescription)
        copiedRoutine.exercises[0].sets[0].target = "Changed destination"
        XCTAssertEqual(routine.exercises[0].sets[0].target, prescription.targetText)
        let replay = try WorkoutWeekCopyRules.applying(review, to: original)
        XCTAssertEqual(replay.overrides.first { $0.slotIndex == 4 }?.routine.exercises[0].sets[0].target, prescription.targetText)
        XCTAssertEqual(replay.overrides.map(\.id), block.overrides.map(\.id))
    }

    func testReplacingExistingDestinationVariationsKeepsOtherWeeksAndPreservesReviewPayload() throws {
        var original = try fixture(weeks: 4)
        let destination = try XCTUnwrap(original.routine(forSlot: 4)?.deepCopy())
        destination.exercises[0].sets[0].target = "Old destination"
        let unrelated = try XCTUnwrap(original.routine(forSlot: 8)?.deepCopy())
        unrelated.exercises[0].sets[0].target = "Other future week"
        let unrelatedOverride = WorkoutBlockSlotOverride(slotIndex: 8, routine: unrelated)
        original.trainingBlock?.overrides = [WorkoutBlockSlotOverride(slotIndex: 4, routine: destination), unrelatedOverride]
        let review = try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 1)
        var copied = original; copied.trainingBlock = try WorkoutWeekCopyRules.applying(review, to: original)
        XCTAssertEqual(copied.trainingBlock?.overrides.filter { $0.slotIndex == 4 }.count, 1)
        XCTAssertEqual(copied.trainingBlock?.overrides.first { $0.slotIndex == 8 }?.id, unrelatedOverride.id)
        XCTAssertEqual(copied.routine(forSlot: 4)?.exercises[0].sets[0].target, "8–12 reps")
        XCTAssertEqual(copied.routine(forSlot: 8)?.exercises[0].sets[0].target, "Other future week")
        XCTAssertEqual(original.routine(forSlot: 4)?.exercises[0].sets[0].target, "Old destination")
    }

    func testMutableSourceRoutineChangeAfterReviewRequiresNewReview() throws {
        let original = try fixture(weeks: 4)
        let review = try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 1)
        original.routines[0].exercises[0].sets[0].target = "Changed after review"
        // The block alone contains the rotation IDs, so the command must also
        // fingerprint the resolved source, not just authored override payloads.
        XCTAssertThrowsError(try WorkoutWeekCopyRules.applying(review, to: original))
    }

    func testProtectedDestinationsRejectWholeCopyWithoutPartiallyChangingDraft() throws {
        let original = try fixture(progress: 39)
        XCTAssertThrowsError(try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 9))
        XCTAssertThrowsError(try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 10, protectedSlots: [43]))
        XCTAssertTrue(WorkoutWeekCopyRules.destinationIsProtected(9, in: original))
        XCTAssertFalse(WorkoutWeekCopyRules.destinationIsProtected(10, in: original))
        XCTAssertTrue(try XCTUnwrap(original.trainingBlock).overrides.isEmpty)
    }

    func testLateProgressAndActiveDraftCannotBeBypassedAfterReview() throws {
        var original = try fixture(progress: 39)
        let changedSource = try XCTUnwrap(original.routine(forSlot: 0)?.deepCopy())
        changedSource.exercises[0].sets[0].target = "5 reps"
        original.trainingBlock?.overrides = [WorkoutBlockSlotOverride(slotIndex: 0, routine: changedSource)]
        var draft = original; draft.trainingBlock?.revisionID = UUID().uuidString
        let review = try WorkoutWeekCopyRules.review(in: draft, sourceWeek: 0, destinationWeek: 10)
        var advancedDraft = draft; advancedDraft.currentProgressIndex = 41
        XCTAssertThrowsError(try WorkoutWeekCopyRules.applying(review, to: advancedDraft))
        XCTAssertThrowsError(try WorkoutWeekCopyRules.applying(review, to: draft, protectedSlots: [42]))
        let copied = try WorkoutWeekCopyRules.applying(review, to: draft)
        var latest = original; latest.currentProgressIndex = 41
        // Existing checked-save rules also protect a new completion at final submission.
        XCTAssertThrowsError(try WorkoutBlockRules.applying(copied, to: latest, expected: original))
    }

    func testChangedReviewedSourceAndAccountAndInvalidWeekAreRejected() throws {
        let original = try fixture(weeks: 4)
        let review = try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 1)
        var changed = original; changed.trainingBlock?.weeks[0].name = "Changed"
        XCTAssertThrowsError(try WorkoutWeekCopyRules.applying(review, to: changed))
        changed = original; changed.userID = "other-user"
        XCTAssertThrowsError(try WorkoutWeekCopyRules.applying(review, to: changed))
        XCTAssertThrowsError(try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 0))
        XCTAssertThrowsError(try WorkoutWeekCopyRules.review(in: original, sourceWeek: 0, destinationWeek: 4))
        XCTAssertThrowsError(try WorkoutWeekCopyRules.review(in: original, sourceWeek: -1, destinationWeek: 1))
    }

    private func log(_ program: WorkoutProgram, slot: Int, id: String, legacy: Bool = false) throws -> WorkoutSessionLog {
        let routine = try XCTUnwrap(program.routine(forSlot: slot))
        return WorkoutSessionLog(id: id, date: try XCTUnwrap(program.date(forSlot: slot)), routineID: routine.id,
            completedExercises: [], programContext: legacy ? nil : WorkoutRules.sessionContext(for: program, routineID: routine.id, slotIndex: slot))
    }

    func testReviewSeparatesPassedLinkedSkippedLegacyAndUnmatchedWithoutChangingProgram() throws {
        let original = try fixture(progress: 8)
        let before = try WorkoutBlockRules.fingerprint(original)
        let first = try log(original, slot: 0, id: "first")
        let second = try log(original, slot: 1, id: "second")
        let legacy = try log(original, slot: 3, id: "older", legacy: true)
        let ahead = try log(original, slot: 12, id: "ahead")
        let review = WorkoutBlockReview.make(program: original, logs: [first, first, second, legacy, ahead],
                                            now: date.addingTimeInterval(365 * 86_400))
        XCTAssertEqual(review.passedSlots, 8)
        XCTAssertEqual(review.totalSlots, 48)
        XCTAssertEqual(review.linkedLogs, 3)
        XCTAssertEqual(review.legacyMatches, 1)
        XCTAssertEqual(review.skippedSlots, 2)
        XCTAssertEqual(review.passedWithoutLog, 3)
        XCTAssertEqual(review.loggedAhead, 1)
        XCTAssertEqual(review.weeks[0].linkedLogs, 2)
        XCTAssertEqual(review.weeks[0].legacyMatches, 1)
        XCTAssertEqual(review.weeks[0].skippedSlots, 1)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(original), before)
    }

    func testReviewIgnoresOtherProgramsStandaloneFutureAndOtherBlocksAndDoesNotTreatPointerAsCompletion() throws {
        let original = try fixture(progress: 39)
        var other = try log(original, slot: 0, id: "other")
        other.programContext = .init(programID: "other-phul", slotIndex: 0)
        var standalone = try log(original, slot: 1, id: "standalone"); standalone.programLinkDecision = .standalone
        var future = try log(original, slot: 3, id: "future"); future.date = Date.distantFuture
        var priorBlock = original; priorBlock.trainingBlock?.id = "different-block"
        let stale = try log(priorBlock, slot: 4, id: "old-block")
        let review = WorkoutBlockReview.make(program: original, logs: [other, standalone, future, stale])
        XCTAssertEqual(review.linkedLogs, 0)
        XCTAssertEqual(review.passedSlots, 39)
        XCTAssertEqual(review.skippedSlots, 2)
        XCTAssertEqual(review.passedWithoutLog, 37)
    }

    func testLogOnPreviouslySkippedSlotIsCountedOnceAsEvidenceWithConflictExplained() throws {
        let original = try fixture(progress: 8)
        let recorded = try log(original, slot: 2, id: "recorded-after-skip")
        let review = WorkoutBlockReview.make(program: original, logs: [recorded])
        XCTAssertEqual(review.linkedLogs, 1)
        XCTAssertEqual(review.skippedSlots, 1)
        XCTAssertEqual(review.logsOnSkippedSlots, 1)
        XCTAssertEqual(review.passedWithoutLog, 6)
    }

    func testLegacyProgramReviewDoesNotInventAuthoredBlockOrCompletedHistory() throws {
        var original = try fixture(progress: 39); original.trainingBlock = nil
        let review = WorkoutBlockReview.make(program: original, logs: [])
        XCTAssertEqual(review.weeks.count, 12)
        XCTAssertEqual(review.weeks[9].passedSlots, 3)
        XCTAssertEqual(review.linkedLogs, 0)
        XCTAssertNil(original.trainingBlock)
    }
}
