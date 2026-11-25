import XCTest
@testable import MyFitPlateCore

final class WorkoutBlockPerformanceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func program() throws -> WorkoutProgram {
        let exercise = RoutineExercise(id: "exercise", name: "Squat", sets: [ExerciseSet(id: "target", target: "8 reps")])
        let routine = WorkoutRoutine(id: "routine", userID: "performance-user", name: "Lower", dateCreated: date, exercises: [exercise])
        var program = WorkoutProgram(id: "block-program", userID: "performance-user", name: "PHUL", dateCreated: date,
            routines: [routine], startDate: date, daysOfWeek: [2])
        program.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: program, weekCount: 4)
        return program
    }
    private func log(_ program: WorkoutProgram, slot: Int, weight: Double, reps: Int = 8,
                     equipment: StrengthEquipment? = nil, id: String? = nil) throws -> WorkoutSessionLog {
        let routine = try XCTUnwrap(program.routine(forSlot: slot))
        var exercise = routine.exercises[0]; exercise.loadEquipment = equipment
        return WorkoutSessionLog(id: id ?? "session-\(slot)", date: date.addingTimeInterval(Double(slot) * 7 * 86_400),
            routineID: routine.id, completedExercises: [CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: [
                CompletedSet(reps: reps, weight: weight, effort: SetEffort(scale: .rpe, value: 8)),
                CompletedSet(reps: 1, weight: 900, setType: .warmup)
            ])], programContext: WorkoutRules.sessionContext(for: program, routineID: routine.id, slotIndex: slot))
    }

    func testComparesRecordedLoadAtSameRepsAndContextAndExcludesWarmups() throws {
        let program = try program()
        let first = try log(program, slot: 0, weight: 100)
        let last = try log(program, slot: 2, weight: 110)
        let review = WorkoutBlockPerformance.make(program: program, logs: [last, first, first])
        XCTAssertEqual(review.comparisons.count, 1)
        XCTAssertEqual(review.comparisons[0].firstWeightPounds, 100)
        XCTAssertEqual(review.comparisons[0].latestWeightPounds, 110)
        XCTAssertEqual(review.comparisons[0].repetitions, 8)
        XCTAssertEqual(review.comparisons[0].comparableSessions, 2)
        XCTAssertEqual(review.workingSets, 2)
        XCTAssertEqual(review.effortRecordedSets, 2)
        XCTAssertEqual(review.longestGapDays, 14)
    }

    func testDifferentRepsOrEquipmentCannotInventComparableLoadTrend() throws {
        let program = try program()
        let first = try log(program, slot: 0, weight: 100)
        let differentReps = try log(program, slot: 1, weight: 110, reps: 5)
        XCTAssertTrue(WorkoutBlockPerformance.make(program: program, logs: [first, differentReps]).comparisons.isEmpty)
        let firstMachine = StrengthEquipment(loadingMeaning: .total, name: "Machine A", availableWeights: [100, 110])
        let secondMachine = StrengthEquipment(loadingMeaning: .total, name: "Machine B", availableWeights: [100, 110])
        let earlier = try log(program, slot: 0, weight: 100, equipment: firstMachine)
        let later = try log(program, slot: 1, weight: 110, equipment: secondMachine)
        XCTAssertTrue(WorkoutBlockPerformance.make(program: program, logs: [earlier, later]).comparisons.isEmpty)
    }

    func testOnlyExactProgramAndBlockEvidenceCountsAndInvalidEffortStaysMissing() throws {
        let program = try program()
        var other = try log(program, slot: 0, weight: 100)
        other.programContext = .init(programID: "other-program", slotIndex: 0)
        var standalone = try log(program, slot: 1, weight: 110); standalone.programLinkDecision = .standalone
        var future = try log(program, slot: 2, weight: 120); future.date = .distantFuture
        var oldBlockProgram = program; oldBlockProgram.trainingBlock?.id = "previous-block"
        let previous = try log(oldBlockProgram, slot: 3, weight: 130)
        let absent = WorkoutBlockPerformance.make(program: program, logs: [other, standalone, future, previous])
        XCTAssertTrue(absent.comparisons.isEmpty)
        XCTAssertEqual(absent.workingSets, 0)
        var invalidEffort = try log(program, slot: 0, weight: 100)
        invalidEffort.completedExercises[0].sets[0].effort = SetEffort(scale: .rpe, value: 99)
        XCTAssertEqual(WorkoutBlockPerformance.make(program: program, logs: [invalidEffort]).effortRecordedSets, 0)
    }

    func testKilogramsDisplayDoesNotRewriteCanonicalLoads() throws {
        let program = try program()
        let equipment = StrengthEquipment(unit: .kg, loadingMeaning: .perHand, name: "Dumbbells", availableWeights: [40, 50])
        let first = try log(program, slot: 0, weight: 100, equipment: equipment)
        let later = try log(program, slot: 1, weight: 110, equipment: equipment)
        let trend = try XCTUnwrap(WorkoutBlockPerformance.make(program: program, logs: [first, later]).comparisons.first)
        XCTAssertEqual(trend.unit, .kg)
        XCTAssertEqual(trend.firstWeightPounds, 100)
        XCTAssertEqual(trend.unit.displayWeight(trend.firstWeightPounds), 45.359237, accuracy: 0.000001)
        XCTAssertTrue(trend.context.contains("Per hand"))
    }
}
