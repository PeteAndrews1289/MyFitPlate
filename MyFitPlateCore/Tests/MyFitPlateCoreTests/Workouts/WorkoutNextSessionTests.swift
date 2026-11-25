import XCTest
@testable import MyFitPlateCore

final class WorkoutNextSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let owner = "next-session-owner"

    private func program(progress: Int = 5) -> WorkoutProgram {
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "day-\(index)", userID: owner, name: "Training day \(index + 1)",
                dateCreated: now.addingTimeInterval(-100 * 86_400), exercises: [
                    RoutineExercise(id: "bench-\(index)", name: "Bench press", sets: (0..<3).map {
                        ExerciseSet(id: "set-\(index)-\($0)", target: "8-12", reps: 8, weight: 100)
                    }, targetSets: 3, targetReps: "8-12")
                ])
        }
        return WorkoutProgram(id: "phul", userID: owner, name: "PHUL", dateCreated: now.addingTimeInterval(-100 * 86_400),
            routines: routines, startDate: now.addingTimeInterval(-100 * 86_400), daysOfWeek: [2, 3, 5, 6],
            currentProgressIndex: progress, skippedIndices: [2, 9, 20])
    }

    private func log(_ program: WorkoutProgram, slot: Int = 0) throws -> WorkoutSessionLog {
        let routine = try XCTUnwrap(program.routine(forSlot: slot))
        let exercise = try XCTUnwrap(routine.exercises.first)
        return WorkoutSessionLog(id: "accepted-session", date: now.addingTimeInterval(-2 * 86_400), routineID: routine.id,
            completedExercises: [CompletedExercise(id: "performance", exerciseName: exercise.name, exercise: exercise,
                sets: (0..<3).map { CompletedSet(id: "recorded-\($0)", reps: 12, weight: 100, effort: SetEffort(scale: .rpe, value: 7)) })],
            programContext: WorkoutProgramSessionContext(programID: "phul", slotIndex: slot))
    }

    private func context(_ program: WorkoutProgram, evidence: WorkoutSessionLog? = nil) throws -> WorkoutNextSessionContext {
        try XCTUnwrap(WorkoutNextSessionContext.next(for: program, ownerID: owner, evidenceSession: evidence, now: now))
    }

    private func plan(_ context: WorkoutNextSessionContext, program: WorkoutProgram, history: [WorkoutSessionLog]) throws -> ProgressionPlan {
        try XCTUnwrap(WorkoutNextSessionRules.recommendations(for: context, program: program, history: history, ownerID: owner, now: now).first?.plan)
    }

    func testCompletionChoosesNextSameRoutineWhileCoachChoosesNextPendingSlot() throws {
        var program = program()
        let evidence = try log(program)
        XCTAssertEqual(try context(program, evidence: evidence).slotIndex, 8)
        XCTAssertEqual(try context(program).slotIndex, 5)
        program.slotCompletionProofs = [WorkoutSlotCompletionProof(slotIndex: 8, sessionID: "early-session")]
        let captured = try XCTUnwrap(WorkoutNextSessionContext.next(for: program, ownerID: owner,
            evidenceSession: evidence, protectedSlots: [12], now: now))
        XCTAssertEqual(captured.slotIndex, 16)
        var complete = program; complete.currentProgressIndex = 48
        XCTAssertNil(try WorkoutNextSessionContext.next(for: complete, ownerID: owner, now: now))
    }

    func testLegacyPHULReviewChangesOnlyOneFutureOccurrenceAndPreservesHistoryAndPosition39() throws {
        let original = program(progress: 39)
        let evidence = try log(original, slot: 35)
        let before = try WorkoutBlockRules.fingerprint(original)
        let historyBefore = try WorkoutBlockRules.fingerprint(evidence)
        let captured = try context(original, evidence: evidence)
        var reviewed = try plan(captured, program: original, history: [evidence])
        reviewed.targets[0].weight = 102.5; reviewed.targets[0].reps = 9
        let block = try WorkoutNextSessionRules.proposedBlock(context: captured, program: original,
            reviewedPlans: [reviewed], history: [evidence], ownerID: owner, now: now)
        let saved = try WorkoutBlockRules.applying(block, to: original, expected: original)
        XCTAssertEqual(captured.slotIndex, 39)
        XCTAssertEqual(saved.currentProgressIndex, 39)
        XCTAssertEqual(saved.totalSlots, 48)
        XCTAssertEqual(saved.skippedIndices, original.skippedIndices)
        XCTAssertEqual(saved.progressEpoch, original.progressEpoch)
        XCTAssertEqual(saved.routine(forSlot: 39)?.exercises[0].sets[0].weight, 102.5)
        XCTAssertEqual(saved.routine(forSlot: 39)?.exercises[0].sets[0].reps, 9)
        XCTAssertEqual(saved.routine(forSlot: 39)?.exercises[0].sets[0].target, "8-12")
        for slot in 0..<48 where slot != 39 {
            XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(saved.routine(forSlot: slot))),
                           try WorkoutBlockRules.fingerprint(XCTUnwrap(original.routine(forSlot: slot))))
            XCTAssertEqual(saved.date(forSlot: slot), original.date(forSlot: slot))
        }
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(original), before)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(evidence), historyBefore)
        XCTAssertNil(original.trainingBlock, "Staging must never adopt a block implicitly.")
    }

    func testContextRejectsAccountStructureExpiryAndLateProtectedProgress() throws {
        let original = program()
        let captured = try context(original)
        XCTAssertThrowsError(try WorkoutNextSessionRules.validate(captured, program: original, ownerID: "other", now: now))
        XCTAssertThrowsError(try WorkoutNextSessionRules.validate(captured, program: original, ownerID: owner, now: now.addingTimeInterval(86_401)))
        XCTAssertThrowsError(try WorkoutNextSessionRules.validate(captured, program: original, ownerID: owner, now: now.addingTimeInterval(-61)))
        XCTAssertThrowsError(try WorkoutNextSessionRules.validate(captured, program: original, ownerID: owner, protectedSlots: [5], now: now))
        var changed = original; changed.currentProgressIndex = 6
        XCTAssertThrowsError(try WorkoutNextSessionRules.validate(captured, program: changed, ownerID: owner, now: now))
        changed = original; changed.slotCompletionProofs = [WorkoutSlotCompletionProof(slotIndex: 5, sessionID: "late-completion")]
        XCTAssertThrowsError(try WorkoutNextSessionRules.validate(captured, program: changed, ownerID: owner, now: now))
        changed = original; changed.name = "Changed elsewhere"
        XCTAssertThrowsError(try WorkoutNextSessionRules.validate(captured, program: changed, ownerID: owner, now: now))
    }

    func testCorrectedOrMissingEvidenceCannotSavePreviouslyReviewedTargets() throws {
        let program = program()
        let evidence = try log(program)
        let captured = try context(program, evidence: evidence)
        let reviewed = try plan(captured, program: program, history: [evidence])
        var corrected = evidence; corrected.completedExercises[0].sets[0].weight = 85
        for history in [[], [corrected]] {
            XCTAssertThrowsError(try WorkoutNextSessionRules.proposedBlock(context: captured, program: program,
                reviewedPlans: [reviewed], history: history, ownerID: owner, now: now))
        }
        XCTAssertThrowsError(try WorkoutNextSessionRules.proposedBlock(context: captured, program: program,
            reviewedPlans: [], history: [evidence], ownerID: owner, now: now))
        XCTAssertThrowsError(try WorkoutNextSessionRules.proposedBlock(context: captured, program: program,
            reviewedPlans: [reviewed, reviewed], history: [evidence], ownerID: owner, now: now))
    }

    func testHistoryCannotBorrowOtherTrainingDaysOrOtherPrograms() throws {
        let program = program()
        let evidence = try log(program)
        let captured = try context(program, evidence: evidence)
        var foreign = evidence
        foreign.programContext = WorkoutProgramSessionContext(programID: "another-program", slotIndex: 0)
        let otherDay = try log(program, slot: 1)
        let rows = try WorkoutNextSessionRules.recommendations(for: captured, program: program,
            history: [foreign, otherDay], ownerID: owner, now: now)
        XCTAssertNil(rows.first?.plan)
        XCTAssertNil(rows.first?.recorded)
        XCTAssertThrowsError(try WorkoutNextSessionContext.next(for: program, ownerID: owner, evidenceSession: foreign, now: now))
    }

    func testEquipmentSuggestionAndReviewedManualValuesUseSameAvailableLoads() throws {
        let program = program()
        program.routines[0].exercises[0].loadEquipment = StrengthEquipment(availableWeights: [100, 105, 110])
        let evidence = try log(program)
        let captured = try context(program, evidence: evidence)
        var reviewed = try plan(captured, program: program, history: [evidence])
        XCTAssertEqual(reviewed.targets.map(\.weight), [105, 105, 105])
        reviewed.targets[0].weight = 103
        XCTAssertThrowsError(try WorkoutNextSessionRules.proposedBlock(context: captured, program: program,
            reviewedPlans: [reviewed], history: [evidence], ownerID: owner, now: now))
        reviewed.targets[0].weight = 110; reviewed.targets[0].reps = 9
        let block = try WorkoutNextSessionRules.proposedBlock(context: captured, program: program,
            reviewedPlans: [reviewed], history: [evidence], ownerID: owner, now: now)
        var result = program; result.trainingBlock = block
        XCTAssertEqual(result.routine(forSlot: captured.slotIndex)?.exercises[0].sets[0].weight, 110)
        XCTAssertEqual(result.routine(forSlot: captured.slotIndex)?.exercises[0].loadEquipment,
                       program.routines[0].exercises[0].loadEquipment)
    }

    func testOneSlotProposalDoesNotPropagateThroughLinkedFutureWeeks() throws {
        var original = program(progress: 4)
        original.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: original)
        original.trainingBlock?.schemaVersion = 2
        let sourceID = try XCTUnwrap(original.trainingBlock?.weeks[1].id)
        original.trainingBlock?.weeks[2].linkedSourceWeekID = sourceID
        let childID = original.trainingBlock?.weeks[2].id
        original.trainingBlock?.weeks[3].linkedSourceWeekID = childID
        let evidence = try log(original)
        let captured = try context(original, evidence: evidence)
        XCTAssertEqual(captured.slotIndex, 4)
        let reviewed = try plan(captured, program: original, history: [evidence])
        let block = try WorkoutNextSessionRules.proposedBlock(context: captured, program: original,
            reviewedPlans: [reviewed], history: [evidence], ownerID: owner, now: now)
        let saved = try WorkoutBlockRules.applying(block, to: original, expected: original)
        XCTAssertEqual(saved.routine(forSlot: 4)?.exercises[0].sets[0].weight, 105)
        for slot in 0..<48 where slot != 4 {
            XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(saved.routine(forSlot: slot))),
                           try WorkoutBlockRules.fingerprint(XCTUnwrap(original.routine(forSlot: slot))))
        }
    }

    func testCompletedTargetsAndWarmupsCannotBeRewrittenByProposal() throws {
        let original = program()
        original.routines[0].exercises[0].sets.insert(ExerciseSet(id: "warmup", target: "10", setType: .warmup, reps: 10, weight: 45), at: 0)
        let evidence = try log(original)
        let captured = try context(original, evidence: evidence)
        let reviewed = try plan(captured, program: original, history: [evidence])
        let block = try WorkoutNextSessionRules.proposedBlock(context: captured, program: original,
            reviewedPlans: [reviewed], history: [evidence], ownerID: owner, now: now)
        var saved = original; saved.trainingBlock = block
        XCTAssertEqual(saved.routine(forSlot: 8)?.exercises[0].sets[0].weight, 45)
        XCTAssertEqual(saved.routine(forSlot: 8)?.exercises[0].sets[0].resolvedSetType, .warmup)
        original.routines[0].exercises[0].sets[1].isCompleted = true
        let updatedContext = try context(original, evidence: evidence)
        XCTAssertThrowsError(try WorkoutNextSessionRules.proposedBlock(context: updatedContext, program: original,
            reviewedPlans: [reviewed], history: [evidence], ownerID: owner, now: now))
    }

    func testLinearRationaleDescribesMinimumInsteadOfInventingCeilingPerformance() throws {
        let program = program()
        program.routines[0].exercises[0].progressionPolicy = WorkoutProgressionPolicy(kind: .linear)
        var evidence = try log(program)
        for index in evidence.completedExercises[0].sets.indices { evidence.completedExercises[0].sets[index].reps = 8 }
        let captured = try context(program, evidence: evidence)
        let reviewed = try plan(captured, program: program, history: [evidence])
        XCTAssertEqual(reviewed.move, .addWeight)
        XCTAssertTrue(reviewed.rationale.contains("minimum"))
        XCTAssertFalse(reviewed.rationale.contains("top of"))
    }
    func testLinearRationaleDoesNotInventCurrentEffortWhenOlderCeilingSupportsIncrease() throws {
        let program = program()
        program.routines[0].exercises[0].progressionPolicy = WorkoutProgressionPolicy(kind: .linear)
        var current = try log(program)
        var older = current; older.id = "older"; older.date = now.addingTimeInterval(-9 * 86_400)
        for index in current.completedExercises[0].sets.indices {
            current.completedExercises[0].sets[index].reps = 8
            current.completedExercises[0].sets[index].effort = nil
        }
        let captured = try context(program, evidence: current)
        let reviewed = try plan(captured, program: program, history: [current, older])
        XCTAssertEqual(reviewed.move, .addWeight)
        XCTAssertTrue(reviewed.rationale.contains("Current effort was not recorded"))
        XCTAssertFalse(reviewed.rationale.contains("RPE 8"))
    }

}
