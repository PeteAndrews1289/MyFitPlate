import XCTest
@testable import MyFitPlateCore

final class WorkoutBlockTests: XCTestCase {
    private func program(days: [Int] = [2, 3, 5, 6], routines: Int = 4, progress: Int = 0) -> WorkoutProgram {
        let rotation = (0..<routines).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: "block-user", name: "Day \(index + 1)",
                dateCreated: Date(timeIntervalSince1970: 1_700_000_000), exercises: [
                    RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [
                        ExerciseSet(id: "set-\(index)", target: "8-12 reps")
                    ])
                ])
        }
        return WorkoutProgram(id: "active-phul", userID: "block-user", name: "PHUL",
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000), routines: rotation,
            startDate: Date(timeIntervalSince1970: 1_700_000_000), daysOfWeek: days,
            currentProgressIndex: progress, skippedIndices: [2, 5])
    }

    private func variation(_ program: WorkoutProgram, slot: Int, target: String) throws -> WorkoutBlockSlotOverride {
        let routine = try XCTUnwrap(program.routine(forSlot: slot)?.deepCopy())
        routine.exercises[0].sets[0].target = target
        return WorkoutBlockSlotOverride(slotIndex: slot, routine: routine)
    }

    func testExplicitPHULBlockRetainsSession39Of48AndAllIdentitiesDatesAndSkips() throws {
        let original = program(progress: 39)
        let block = try WorkoutBlockRules.createRepeatingBlock(for: original)
        let updated = try WorkoutBlockRules.applying(block, to: original, expected: original)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.currentProgressIndex, 39)
        XCTAssertEqual(updated.skippedIndices, [2, 5])
        XCTAssertEqual(updated.totalSlots, 48)
        XCTAssertEqual(updated.startDate, original.startDate)
        XCTAssertEqual(updated.dateCreated, original.dateCreated)
        for slot in 0..<48 {
            XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(updated.routine(forSlot: slot))),
                           try WorkoutBlockRules.fingerprint(XCTUnwrap(original.routine(forSlot: slot))))
            XCTAssertEqual(updated.date(forSlot: slot), original.date(forSlot: slot))
        }
        XCTAssertNil(original.trainingBlock)
        XCTAssertTrue(block.overrides.isEmpty, "Unchanged weeks must not duplicate routine snapshots")
    }

    func testOddRotationContinuesAcrossWeekBoundary() throws {
        let original = program(days: [2, 4, 6], routines: 2)
        let block = try WorkoutBlockRules.createRepeatingBlock(for: original, weekCount: 4)
        let updated = try WorkoutBlockRules.applying(block, to: original, expected: original)
        XCTAssertEqual((0..<6).compactMap { updated.routine(forSlot: $0)?.id },
                       ["routine-0", "routine-1", "routine-0", "routine-1", "routine-0", "routine-1"])
        XCTAssertEqual(updated.totalSlots, 12)
    }

    func testAuthoredVariationChangesOnlyChosenFutureSlot() throws {
        let original = program(progress: 4)
        var block = try WorkoutBlockRules.createRepeatingBlock(for: original, weekCount: 4)
        block.overrides = [try variation(original, slot: 8, target: "5 reps")]
        block.weeks[2].isDeload = true
        block.weeks[2].name = "Lighter week"
        let updated = try WorkoutBlockRules.applying(block, to: original, expected: original)
        XCTAssertEqual(updated.routine(forSlot: 8)?.exercises[0].sets[0].target, "5 reps")
        XCTAssertEqual(updated.routine(forSlot: 4)?.exercises[0].sets[0].target, "8-12 reps")
        XCTAssertEqual(original.routine(forSlot: 8)?.exercises[0].sets[0].target, "8-12 reps")
        XCTAssertEqual(updated.currentProgressIndex, 4)
        XCTAssertTrue(try XCTUnwrap(updated.trainingBlock).weeks[2].isDeload)
    }

    func testPastAndActiveTargetChangesAreRejected() throws {
        let original = program(progress: 8)
        var block = try WorkoutBlockRules.createRepeatingBlock(for: original)
        block.overrides = [try variation(original, slot: 7, target: "5 reps")]
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: original, expected: original))
        block.overrides = [try variation(original, slot: 12, target: "5 reps")]
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: original, expected: original, protectedSlots: [12]))
        XCTAssertNoThrow(try WorkoutBlockRules.applying(block, to: original, expected: original))
    }

    func testCanonicalProgressAndSkipsAdvanceDuringEditingWithoutRewind() throws {
        let baseline = program(progress: 7)
        let block = try WorkoutBlockRules.createRepeatingBlock(for: baseline)
        var latest = baseline
        latest.currentProgressIndex = 9; latest.skippedIndices = [2, 5, 8]
        let saved = try WorkoutBlockRules.applying(block, to: latest, expected: baseline)
        XCTAssertEqual(saved.currentProgressIndex, 9)
        XCTAssertEqual(saved.skippedIndices, [2, 5, 8])
    }

    func testNewCompletionProtectsFormerlyFutureVariation() throws {
        let baseline = program(progress: 7)
        var block = try WorkoutBlockRules.createRepeatingBlock(for: baseline)
        block.overrides = [try variation(baseline, slot: 7, target: "5 reps")]
        var latest = baseline; latest.currentProgressIndex = 8
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: latest, expected: baseline))
    }

    func testConcurrentStructureChangeRequiresNewReview() throws {
        let baseline = program(progress: 4)
        let block = try WorkoutBlockRules.createRepeatingBlock(for: baseline)
        var renamed = baseline; renamed.name = "Renamed remotely"
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: renamed, expected: baseline))
        var rescheduled = baseline; rescheduled.startDate = Date()
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: rescheduled, expected: baseline))
    }

    func testCurrentRevisionAloneCannotBypassStrictCASWithoutReceipt() throws {
        let baseline = program(progress: 4)
        let block = try WorkoutBlockRules.createRepeatingBlock(for: baseline)
        var accepted = try WorkoutBlockRules.applying(block, to: baseline, expected: baseline)
        accepted.currentProgressIndex = 6
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: accepted, expected: baseline))
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: accepted, expected: accepted))
        var collision = block; collision.name = "Reused operation"
        XCTAssertThrowsError(try WorkoutBlockRules.applying(collision, to: accepted, expected: accepted))
    }

    func testShorterBlockCannotRemovePassedOrActiveSlots() throws {
        let original = program(progress: 39)
        let short = try WorkoutBlockRules.createRepeatingBlock(for: original, weekCount: 4)
        XCTAssertThrowsError(try WorkoutBlockRules.applying(short, to: original, expected: original))
        let fresh = program()
        let shortFresh = try WorkoutBlockRules.createRepeatingBlock(for: fresh, weekCount: 4)
        XCTAssertThrowsError(try WorkoutBlockRules.applying(shortFresh, to: fresh, expected: fresh, protectedSlots: [20]))
    }

    func testSessionContextFreezesBlockWeekAndTargets() throws {
        var original = program()
        var block = try WorkoutBlockRules.createRepeatingBlock(for: original, weekCount: 4)
        let routine = try XCTUnwrap(original.routine(forSlot: 4)?.deepCopy())
        let target = WorkoutPrescription(kind: .repetitions, lowerBound: 5, upperBound: 8,
            effort: SetEffort(scale: .rpe, value: 8), loadPercentage: 75,
            loadReference: .init(label: "Squat training max", weightPounds: 200, date: Date(timeIntervalSince1970: 1_700_000_000)))
        routine.exercises[0].sets[0].prescription = target
        routine.exercises[0].sets[0].target = target.targetText
        block.overrides = [WorkoutBlockSlotOverride(slotIndex: 4, routine: routine)]
        original.trainingBlock = block
        let context = try XCTUnwrap(WorkoutRules.sessionContext(for: original, routineID: routine.id, slotIndex: 4))
        let frozen = try XCTUnwrap(context.blockSession)
        XCTAssertEqual(frozen.weekIndex, 1)
        XCTAssertEqual(frozen.targets.first?.prescription, target)
        original.trainingBlock?.weeks[1].name = "Changed afterward"
        routine.exercises[0].sets[0].target = "1 rep"
        XCTAssertEqual(frozen.weekName, "Week 2")
        XCTAssertEqual(frozen.targets.first?.originalText, "5–8 reps")
        let restored = try JSONDecoder().decode(WorkoutProgramSessionContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(restored, context)
    }

    func testLegacyProgramAndSessionContextDecodeWithoutInventedBlock() throws {
        let legacy = program(progress: 39)
        let data = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("trainingBlock"))
        let restored = try JSONDecoder().decode(WorkoutProgram.self, from: data)
        XCTAssertNil(restored.trainingBlock)
        XCTAssertEqual(restored.currentProgressIndex, 39)
        let context = try JSONDecoder().decode(WorkoutProgramSessionContext.self,
            from: Data(#"{"programID":"active-phul","slotIndex":39}"#.utf8))
        XCTAssertNil(context.blockSession)
        XCTAssertEqual(context.slotIndex, 39)
    }

    func testUnknownBlockSchemaAndDuplicateOverrideFailClosed() throws {
        let original = program()
        var block = try WorkoutBlockRules.createRepeatingBlock(for: original)
        block.schemaVersion = 99
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutProgramBlock.self, from: JSONEncoder().encode(block)))
        block.schemaVersion = 1
        block.overrides = [try variation(original, slot: 4, target: "5 reps"), try variation(original, slot: 4, target: "6 reps")]
        var proposed = original; proposed.trainingBlock = block
        XCTAssertThrowsError(try WorkoutBlockRules.validate(proposed))
    }

    func testOversizedAuthoredPayloadIsRejectedBeforeSubmission() throws {
        let original = program()
        var block = try WorkoutBlockRules.createRepeatingBlock(for: original)
        let routine = try XCTUnwrap(original.routine(forSlot: 4)?.deepCopy())
        routine.notes = String(repeating: "x", count: 510_000)
        block.overrides = [WorkoutBlockSlotOverride(slotIndex: 4, routine: routine)]
        XCTAssertThrowsError(try WorkoutBlockRules.applying(block, to: original, expected: original))
    }

    func testOperationReceiptBindsOwnerBaselineAndExactProposal() throws {
        let original = program(progress: 39)
        let block = try WorkoutBlockRules.createRepeatingBlock(for: original)
        let receipt = try WorkoutBlockOperationReceipt(expected: original, block: block, status: .accepted)
        XCTAssertNoThrow(try receipt.validate(expected: original, block: block))
        var advanced = original; advanced.currentProgressIndex = 40; advanced.skippedIndices = [2, 5, 39]
        XCTAssertNoThrow(try receipt.validate(expected: advanced, block: block))
        var changed = block; changed.name = "Changed reviewed payload"
        XCTAssertThrowsError(try receipt.validate(expected: original, block: changed))
        var anotherOwner = original; anotherOwner.userID = "another-account"
        XCTAssertThrowsError(try receipt.validate(expected: anotherOwner, block: block))
        var renamed = original; renamed.name = "Changed baseline"
        XCTAssertThrowsError(try receipt.validate(expected: renamed, block: block))
    }

    func testUnknownOperationReceiptVersionFailsClosed() throws {
        let original = program()
        let block = try WorkoutBlockRules.createRepeatingBlock(for: original)
        let receipt = try WorkoutBlockOperationReceipt(expected: original, block: block, status: .cancelled)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
        raw["schemaVersion"] = 2
        let unknown = try JSONDecoder().decode(WorkoutBlockOperationReceipt.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertThrowsError(try unknown.validate(expected: original, block: block))
    }
}
