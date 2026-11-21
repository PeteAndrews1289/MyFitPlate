import XCTest
@testable import MyFitPlateCore

final class WorkoutWeekLinkTests: XCTestCase {
    private func fixture(progress: Int = 0) throws -> WorkoutProgram {
        let routines = (0..<2).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: "link-user", name: "Day \(index)", dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
                exercises: [RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [ExerciseSet(id: "set-\(index)", target: "8 reps")])])
        }
        var program = WorkoutProgram(id: "program", userID: "link-user", name: "Linked block", routines: routines,
            daysOfWeek: [2, 5], currentProgressIndex: progress)
        program.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: program, weekCount: 4)
        return program
    }

    private func linking(_ source: Int, to destination: Int, in program: WorkoutProgram) throws -> WorkoutProgram {
        let review = try WorkoutWeekCopyRules.review(in: program, sourceWeek: source, destinationWeek: destination)
        var updated = program
        updated.trainingBlock = try WorkoutWeekCopyRules.applying(review, to: program, linked: true)
        return updated
    }

    private func editing(slot: Int, text: String, in program: WorkoutProgram, protectedSlots: Set<Int> = []) throws -> WorkoutProgram {
        var updated = program
        updated.trainingBlock = try WorkoutWeekLinkRules.freezingProtectedWeeks(in: program, protectedSlots: protectedSlots)
        updated.trainingBlock = try WorkoutWeekLinkRules.detaching(week: slot / 2, in: updated)
        let routine = try XCTUnwrap(updated.routine(forSlot: slot)?.deepCopy())
        routine.exercises[0].sets[0].target = text
        updated.trainingBlock?.overrides.removeAll { $0.slotIndex == slot }
        updated.trainingBlock?.overrides.append(WorkoutBlockSlotOverride(slotIndex: slot, routine: routine))
        updated.trainingBlock?.revisionID = UUID().uuidString
        try WorkoutBlockRules.validate(updated)
        return updated
    }

    func testLinkedWeekFollowsFutureSourceTargetsWhileNameAndLighterLabelStayIndependent() throws {
        let original = try fixture()
        var linked = try linking(0, to: 1, in: original)
        linked.trainingBlock?.weeks[1].name = "Own week name"
        linked.trainingBlock?.weeks[1].isDeload = true
        let updated = try editing(slot: 0, text: "5 reps", in: linked)
        XCTAssertEqual(updated.routine(forSlot: 2)?.exercises[0].sets[0].target, "5 reps")
        XCTAssertEqual(updated.trainingBlock?.weeks[1].name, "Own week name")
        XCTAssertEqual(updated.trainingBlock?.weeks[1].isDeload, true)
        XCTAssertEqual(linked.routine(forSlot: 2)?.exercises[0].sets[0].target, "8 reps")
        XCTAssertEqual(original.trainingBlock?.schemaVersion, 1)
        XCTAssertEqual(updated.trainingBlock?.schemaVersion, 2)
    }

    func testEditingOneLinkedDayDetachesWholeWeekWithoutChangingSourceOrSiblingLinks() throws {
        let first = try linking(0, to: 1, in: fixture())
        let original = try linking(0, to: 2, in: first)
        let updated = try editing(slot: 2, text: "10 reps", in: original)
        XCTAssertNil(updated.trainingBlock?.weeks[1].linkedSourceWeekID)
        XCTAssertNotNil(updated.trainingBlock?.weeks[2].linkedSourceWeekID)
        XCTAssertEqual(updated.routine(forSlot: 0)?.exercises[0].sets[0].target, "8 reps")
        XCTAssertEqual(updated.routine(forSlot: 2)?.exercises[0].sets[0].target, "10 reps")
        XCTAssertEqual(updated.routine(forSlot: 3)?.exercises[0].sets[0].target, "8 reps")
        XCTAssertEqual(updated.routine(forSlot: 4)?.exercises[0].sets[0].target, "8 reps")
    }

    func testPassedLinkedWeekFreezesBeforeFutureSourceChangesAndPointerRemainsIntact() throws {
        var original = try linking(2, to: 0, in: fixture())
        original.currentProgressIndex = 1
        let oldTargets = try WorkoutBlockRules.fingerprint(XCTUnwrap(original.routine(forSlot: 0)))
        let proposed = try editing(slot: 4, text: "5 reps", in: original)
        XCTAssertNil(proposed.trainingBlock?.weeks[0].linkedSourceWeekID)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(proposed.routine(forSlot: 0))), oldTargets)
        let saved = try WorkoutBlockRules.applying(XCTUnwrap(proposed.trainingBlock), to: original, expected: original)
        XCTAssertEqual(saved.currentProgressIndex, 1)
        XCTAssertEqual(saved.routine(forSlot: 4)?.exercises[0].sets[0].target, "5 reps")
    }

    func testActiveLinkedWeekFreezesBeforeFutureSourceChanges() throws {
        let original = try linking(2, to: 1, in: fixture())
        let proposed = try editing(slot: 4, text: "5 reps", in: original, protectedSlots: [2])
        XCTAssertNil(proposed.trainingBlock?.weeks[1].linkedSourceWeekID)
        XCTAssertEqual(proposed.routine(forSlot: 2)?.exercises[0].sets[0].target, "8 reps")
        XCTAssertNoThrow(try WorkoutBlockRules.applying(XCTUnwrap(proposed.trainingBlock), to: original, expected: original, protectedSlots: [2]))
    }

    func testCycleAndMissingSourceAndMixedOverrideLinksFailClosed() throws {
        let linked = try linking(0, to: 1, in: fixture())
        let review = try WorkoutWeekCopyRules.review(in: linked, sourceWeek: 1, destinationWeek: 0)
        XCTAssertThrowsError(try WorkoutWeekCopyRules.applying(review, to: linked, linked: true))
        var missing = linked; missing.trainingBlock?.weeks[1].linkedSourceWeekID = "missing"
        XCTAssertThrowsError(try WorkoutBlockRules.validate(missing))
        var mixed = linked
        let routine = try XCTUnwrap(mixed.routine(forSlot: 2)?.deepCopy())
        mixed.trainingBlock?.overrides.append(WorkoutBlockSlotOverride(slotIndex: 2, routine: routine))
        XCTAssertThrowsError(try WorkoutBlockRules.validate(mixed))
    }

    func testIndependentCopyBreaksLinkAndDoesNotFollowLaterSourceEdits() throws {
        let linked = try linking(0, to: 1, in: fixture())
        let review = try WorkoutWeekCopyRules.review(in: linked, sourceWeek: 0, destinationWeek: 1)
        var independent = linked
        independent.trainingBlock = try WorkoutWeekCopyRules.applying(review, to: linked)
        XCTAssertNil(independent.trainingBlock?.weeks[1].linkedSourceWeekID)
        let edited = try editing(slot: 0, text: "5 reps", in: independent)
        XCTAssertEqual(edited.routine(forSlot: 2)?.exercises[0].sets[0].target, "8 reps")
    }

    func testSchema2RoundTripPreservesLinksWhileSchema1RemainsUnlinked() throws {
        let original = try fixture()
        let legacy = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(try XCTUnwrap(legacy.trainingBlock).weeks.allSatisfy { $0.linkedSourceWeekID == nil })
        let linked = try linking(0, to: 1, in: original)
        let restored = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(linked))
        XCTAssertEqual(restored.trainingBlock?.schemaVersion, 2)
        XCTAssertEqual(restored.trainingBlock?.weeks[1].linkedSourceWeekID, restored.trainingBlock?.weeks[0].id)
        XCTAssertEqual(restored.routine(forSlot: 2)?.exercises[0].sets[0].target, "8 reps")
    }

    func testSuccessorMaterializesLinkedTargetsWithFreshWeeksAndNoSourceAliases() throws {
        let source = try editing(slot: 0, text: "5 reps", in: linking(0, to: 1, in: fixture()))
        let next = try WorkoutProgramSuccessorRules.prepare(from: source)
        XCTAssertTrue(try XCTUnwrap(next.trainingBlock).weeks.allSatisfy { $0.linkedSourceWeekID == nil })
        XCTAssertEqual(next.routine(forSlot: 2)?.exercises[0].sets[0].target, "5 reps")
        next.routine(forSlot: 2)?.exercises[0].sets[0].target = "Changed next-block target"
        XCTAssertEqual(source.routine(forSlot: 2)?.exercises[0].sets[0].target, "5 reps")
    }
}
