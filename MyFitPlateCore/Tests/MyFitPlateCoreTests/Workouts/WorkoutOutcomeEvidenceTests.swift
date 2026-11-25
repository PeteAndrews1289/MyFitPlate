import XCTest
@testable import MyFitPlateCore

final class WorkoutOutcomeEvidenceTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func program() throws -> WorkoutProgram {
        let exercise = RoutineExercise(id: "squat", name: "Squat", sets: [
            ExerciseSet(id: "warm", target: "5", isWarmup: true),
            ExerciseSet(id: "work1", target: "8"), ExerciseSet(id: "work2", target: "8")])
        let routine = WorkoutRoutine(id: "day1", userID: "owner", name: "Lower", dateCreated: date, exercises: [exercise])
        var result = WorkoutProgram(id: "phul", userID: "owner", name: "PHUL", dateCreated: date, routines: [routine],
            startDate: date, daysOfWeek: [2, 4], currentProgressIndex: 0)
        result.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: result, weekCount: 2)
        return result
    }
    private func log(_ program: WorkoutProgram, slot: Int = 0, completed: [String], id: String = "log", at: Date? = nil) throws -> WorkoutSessionLog {
        let routine = try XCTUnwrap(program.routine(forSlot: slot)?.deepCopy())
        let original = routine.exercises[0]
        var exercise = original
        for index in exercise.sets.indices {
            exercise.sets[index].isCompleted = completed.contains(exercise.sets[index].id)
            exercise.sets[index].reps = completed.contains(exercise.sets[index].id) ? 8 : 0
            exercise.sets[index].weight = completed.contains(exercise.sets[index].id) ? 100 : 0
        }
        let performed = exercise.sets.filter(\.isCompleted).map { CompletedSet(reps: $0.reps, weight: $0.weight, setType: $0.resolvedSetType) }
        return WorkoutSessionLog(id: id, date: at ?? date, routineID: routine.id,
            completedExercises: [CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: performed)],
            programContext: WorkoutRules.sessionContext(for: program, routineID: routine.id, slotIndex: slot), programLinkDecision: .program)
    }
    func testCompleteOriginalWorkingSetsIgnoreWarmupAndDoNotClaimTargetsAchieved() throws {
        let source = try program(), receipt = try log(source, completed: ["work1", "work2"])
        let before = try PlanFingerprint.make(receipt)
        let result = WorkoutOutcomeEvidenceRules.session(receipt)
        XCTAssertEqual(result.completion, .completed); XCTAssertEqual(result.expectedWorkingSets, 2)
        XCTAssertEqual(result.recordedOriginalWorkingSets, 2); XCTAssertEqual(result.recordedWorkingSets, 2)
        XCTAssertTrue(result.explanation.contains("not whether rep, load or effort targets were achieved"))
        XCTAssertEqual(try PlanFingerprint.make(receipt), before)
    }
    func testPartialOriginalSetCoverageIsExplicitEvenWhenPointerHasPassed() throws {
        var source = try program(); source.currentProgressIndex = 1
        let receipt = try log(source, completed: ["warm", "work1"])
        let result = WorkoutOutcomeEvidenceRules.session(receipt)
        XCTAssertEqual(result.completion, .partial); XCTAssertEqual(result.recordedOriginalWorkingSets, 1)
        XCTAssertEqual(result.expectedWorkingSets, 2); XCTAssertEqual(result.recordedWorkingSets, 1)
        XCTAssertEqual(WorkoutOutcomeEvidenceRules.slots(program: source, logs: [receipt], now: date)[0].state, .partial)
    }
    func testWarmupOnlyRecordCannotCountAsCompletedWorkingPrescription() throws {
        let result = WorkoutOutcomeEvidenceRules.session(try log(program(), completed: ["warm"]))
        XCTAssertEqual(result.completion, .partial); XCTAssertEqual(result.recordedOriginalWorkingSets, 0)
        XCTAssertEqual(result.recordedWorkingSets, 0)
    }
    func testMissingFullLegacyPrescriptionIsUnknownAndStandaloneIsUnassigned() throws {
        var receipt = try log(program(), completed: ["work1", "work2"])
        receipt.programContext = nil; receipt.programLinkDecision = .standalone
        let result = WorkoutOutcomeEvidenceRules.session(receipt)
        XCTAssertEqual(result.completion, .unknown); XCTAssertTrue(result.isUnassigned)
        XCTAssertNil(result.expectedWorkingSets); XCTAssertTrue(result.title.contains("Unassigned"))
    }
    func testAbsentWholeExerciseRolesStayUnknownInsteadOfInventingWorkingSetCount() throws {
        var source = try program()
        source.routines[0].exercises.append(RoutineExercise(id: "press", name: "Press", sets: [ExerciseSet(id: "press1", target: "8")]))
        let result = WorkoutOutcomeEvidenceRules.session(try log(source, completed: ["work1", "work2"]))
        XCTAssertEqual(result.completion, .unknown); XCTAssertNil(result.expectedWorkingSets)
        XCTAssertTrue(result.explanation.contains("original set roles are absent"))
    }
    func testInconsistentCompletedFlagAndMeasurementsFailClosedToUnknown() throws {
        var receipt = try log(program(), completed: ["work1", "work2"])
        receipt.completedExercises[0].sets.removeLast()
        XCTAssertEqual(WorkoutOutcomeEvidenceRules.session(receipt).completion, .unknown)
    }
    func testDuplicatedExerciseOrTargetIdentitiesCannotManufactureCompletion() throws {
        var receipt = try log(program(), completed: ["work1", "work2"])
        receipt.completedExercises.append(receipt.completedExercises[0])
        XCTAssertEqual(WorkoutOutcomeEvidenceRules.session(receipt).completion, .unknown)
    }
    func testSubstitutionIsSeparateEvidenceAndDoesNotBecomeEquivalentOriginalWork() throws {
        let source = try program()
        var receipt = try log(source, completed: [])
        let original = receipt.completedExercises[0].exercise
        var replacement = RoutineExercise(id: "substitute", name: "Leg press", sets: [
            ExerciseSet(id: "replacement1", isCompleted: true, target: "8", reps: 8, weight: 120),
            ExerciseSet(id: "replacement2", isCompleted: true, target: "8", reps: 8, weight: 120)])
        replacement.substitution = WorkoutSubstitutionProvenance(originalSlotID: original.id, originalMovement: nil,
            originalName: original.name, originalPrescription: try JSONEncoder().encode(original), reason: .unavailable, acceptedAt: date)
        receipt.completedExercises = [CompletedExercise(exerciseName: replacement.name, exercise: replacement,
            sets: [CompletedSet(reps: 8, weight: 120), CompletedSet(reps: 8, weight: 120)])]
        let result = WorkoutOutcomeEvidenceRules.session(receipt)
        XCTAssertEqual(result.completion, .partial); XCTAssertEqual(result.recordedOriginalWorkingSets, 0)
        XCTAssertEqual(result.recordedWorkingSets, 2); XCTAssertEqual(result.substitutionExerciseIDs, ["substitute"])
        XCTAssertTrue(result.explanation.contains("not declared equivalent"))
    }
    func testMovedSkippedPassedUnknownAndFutureNotLoggedAreDistinctWithoutMutation() throws {
        var source = try program(); source.currentProgressIndex = 2; source.skippedIndices = [1]
        source.trainingBlock?.scheduleExceptions = [WorkoutScheduleException(id: "move", slotIndex: 2,
            originalDay: TrainingCalendarDay(date, calendar: calendar), proposedDay: TrainingCalendarDay(date.addingTimeInterval(86_400), calendar: calendar), revision: 1)]
        let before = try WorkoutBlockRules.fingerprint(source)
        let result = WorkoutOutcomeEvidenceRules.slots(program: source, logs: [], now: date, calendar: calendar)
        XCTAssertEqual(result.map(\.state), [.unknown, .skipped, .notLogged, .notLogged])
        XCTAssertTrue(result[2].isMoved); XCTAssertNotEqual(result[2].originalDay, result[2].scheduledDay)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(source), before)
    }
    func testSeparatePartialReceiptsCannotBeCombinedIntoACompleteWorkout() throws {
        let source = try program()
        let a = try log(source, completed: ["work1"], id: "one")
        let b = try log(source, completed: ["work2"], id: "two")
        let slot = WorkoutOutcomeEvidenceRules.slots(program: source, logs: [a, a, b], now: date)[0]
        XCTAssertEqual(slot.state, .partial); XCTAssertEqual(slot.sessions.count, 2)
        XCTAssertEqual(Set(slot.sessions.map(\.sessionID)), ["one", "two"])
    }
    func testExplicitStandaloneReceiptCannotFillLinkedProgramSlot() throws {
        let source = try program(); var receipt = try log(source, completed: ["work1", "work2"])
        receipt.programLinkDecision = .standalone
        XCTAssertTrue(WorkoutOutcomeEvidenceRules.session(receipt).isUnassigned)
        XCTAssertEqual(WorkoutOutcomeEvidenceRules.slots(program: source, logs: [receipt], now: date)[0].state, .notLogged)
    }
    func testBlockReviewIncludesPerWeekOutcomesWithoutChangingExistingProgressCounts() throws {
        var source = try program(); source.currentProgressIndex = 3; source.skippedIndices = [2]
        let complete = try log(source, completed: ["work1", "work2"], id: "complete")
        let partial = try log(source, slot: 1, completed: ["work1"], id: "partial")
        let review = WorkoutBlockReview.make(program: source, logs: [complete, partial, partial], now: date, calendar: calendar)
        XCTAssertEqual(review.passedSlots, 3); XCTAssertEqual(review.linkedLogs, 2); XCTAssertEqual(review.skippedSlots, 1)
        XCTAssertEqual(review.completedSlots, 1); XCTAssertEqual(review.partialSlots, 1)
        XCTAssertEqual(review.weeks.first?.outcomes.map(\.state), [.completed, .partial])
        XCTAssertEqual(review.weeks.last?.outcomes.map(\.state), [.skipped, .notLogged])
    }
    func testReportExportKeepsCoverageSeparateFromPerformanceAndAppliesSameScope() throws {
        let source = try program()
        let complete = try log(source, completed: ["work1", "work2"], id: "complete")
        var unassigned = try log(source, completed: ["work1"], id: "standalone")
        unassigned.programContext = nil; unassigned.programLinkDecision = .standalone
        let document = try WorkoutOutcomeReportDocument(logs: [complete, complete, unassigned], scope: WorkoutReportScope(programID: "phul"), now: date)
        XCTAssertEqual(document.performance.sessionIDs, ["complete"])
        XCTAssertEqual(document.sessionOutcomes.count, 1)
        XCTAssertEqual(document.sessionOutcomes.first?.completion, .completed)
        XCTAssertEqual(document.performance.workingSets, 2)
        XCTAssertEqual(document.derivationVersion, 1)
        let decoded = try JSONDecoder().decode(WorkoutOutcomeReportDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.sessionOutcomes, document.sessionOutcomes)
        XCTAssertEqual(decoded.performance.fingerprint, document.performance.fingerprint)
    }
    func testRecordedBreakDeduplicatesAndRetainsExactSupportingDates() throws {
        let source = try program()
        let a = try log(source, completed: ["work1"], id: "one")
        let b = try log(source, completed: ["work1"], id: "two", at: date.addingTimeInterval(22 * 86_400))
        let result = WorkoutOutcomeEvidenceRules.breaks([b, a, a])
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result.first?.days, 22)
        XCTAssertEqual(result.first?.previousSessionID, "one"); XCTAssertEqual(result.first?.nextSessionID, "two")
        XCTAssertEqual(result.first?.from, a.date); XCTAssertEqual(result.first?.through, b.date)
    }
}
