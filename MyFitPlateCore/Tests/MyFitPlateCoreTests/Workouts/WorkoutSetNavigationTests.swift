import XCTest
@testable import MyFitPlateCore

final class WorkoutSetNavigationTests: XCTestCase {
    func testStraightSetsStayOnExerciseThenAdvanceAndFinish() {
        var exercises = [exercise("squat"), exercise("row")]
        XCTAssertEqual(WorkoutSetNavigation.firstUnfinished(in: exercises)?.setID, "squat1")
        exercises[0].sets[0].isCompleted = true
        XCTAssertEqual(WorkoutSetNavigation.next(after: "squat1", in: exercises)?.setID, "squat2")
        exercises[0].sets[1].isCompleted = true
        XCTAssertEqual(WorkoutSetNavigation.next(after: "squat2", in: exercises)?.exerciseID, "row")
        exercises[1].sets.indices.forEach { exercises[1].sets[$0].isCompleted = true }
        XCTAssertNil(WorkoutSetNavigation.next(after: "row2", in: exercises))
    }

    func testSupersetAlternatesAndUnequalSetCountsDoNotSkipWork() {
        var a = exercise("press"), b = exercise("row")
        a.supersetGroupID = "A"; b.supersetGroupID = "A"
        b.sets.append(ExerciseSet(id: "row3"))
        var exercises = [a, b, exercise("carry")]
        for (completed, expected) in [("press1", "row1"), ("row1", "press2"), ("press2", "row2"), ("row2", "row3"), ("row3", "carry1")] {
            for index in exercises.indices {
                if let slot = exercises[index].sets.firstIndex(where: { $0.id == completed }) { exercises[index].sets[slot].isCompleted = true }
            }
            XCTAssertEqual(WorkoutSetNavigation.next(after: completed, in: exercises)?.setID, expected)
        }
    }

    func testWarmupsAndNonadjacentGroupsDoNotJumpPastUnfinishedSets() {
        var a = exercise("press"), b = exercise("row")
        a.supersetGroupID = "A"; b.supersetGroupID = "A"
        a.sets.insert(contentsOf: [ExerciseSet(id: "warm1", isCompleted: true, isWarmup: true), ExerciseSet(id: "warm2", isWarmup: true)], at: 0)
        var exercises = [a, exercise("carry"), b]
        XCTAssertEqual(WorkoutSetNavigation.next(after: "warm1", in: exercises)?.setID, "warm2")
        exercises[0].sets[1].isCompleted = true
        XCTAssertEqual(WorkoutSetNavigation.next(after: "warm2", in: exercises)?.setID, "press1")
        XCTAssertNil(WorkoutSetNavigation.next(after: "row1", in: exercises), "Editing an unfinished set must not advance")
        XCTAssertNil(WorkoutSetNavigation.next(after: "missing", in: exercises))
    }

    func testInputNavigationSkipsCardioAndMobilityAndStopsAtTheEnd() {
        var cardio = exercise("run"), mobility = exercise("stretch")
        cardio.type = .cardio; mobility.type = .flexibility
        let exercises = [exercise("squat"), cardio, mobility, exercise("row")]
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "squat1", in: exercises)?.setID, "squat2")
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "squat2", in: exercises)?.setID, "row1")
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "row1", in: exercises)?.setID, "row2")
        XCTAssertNil(WorkoutSetNavigation.nextInput(after: "row2", in: exercises))
        XCTAssertNil(WorkoutSetNavigation.nextInput(after: "run1", in: exercises))
        XCTAssertNil(WorkoutSetNavigation.nextInput(after: "missing", in: exercises))
        XCTAssertNil(WorkoutSetNavigation.nextInput(after: "squat1", in: []))
    }

    func testInputNavigationAlternatesSupersetRoundsWithoutCompletingSets() {
        var press = exercise("press"), row = exercise("row")
        press.supersetGroupID = "A"; row.supersetGroupID = "A"
        let exercises = [press, row, exercise("carry")]
        for (current, expected) in [("press1", "row1"), ("row1", "press2"), ("press2", "row2"), ("row2", "carry1")] {
            XCTAssertEqual(WorkoutSetNavigation.nextInput(after: current, in: exercises)?.setID, expected)
        }
        XCTAssertTrue(exercises.flatMap(\.sets).allSatisfy { !$0.isCompleted })
        XCTAssertNil(WorkoutSetNavigation.next(after: "press1", in: exercises), "Input movement cannot count as completion")
    }

    func testInputNavigationSkipsCompletedRowsAndHandlesUnequalSupersets() {
        var press = exercise("press"), row = exercise("row"), carry = exercise("carry")
        press.supersetGroupID = "A"; row.supersetGroupID = "A"
        press.sets[1].isCompleted = true
        press.sets.append(ExerciseSet(id: "press3"))
        row.sets[0].isCompleted = true
        carry.sets.indices.forEach { carry.sets[$0].isCompleted = true }
        let exercises = [press, row, carry]
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "press1", in: exercises)?.setID, "row2")
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "row2", in: exercises)?.setID, "press3")
        XCTAssertNil(WorkoutSetNavigation.nextInput(after: "press3", in: exercises))
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "row1", in: exercises)?.setID, "row2")
    }

    func testInputNavigationKeepsWarmupsTogetherBeforeEachSupersetLift() {
        var press = exercise("press"), row = exercise("row")
        press.supersetGroupID = "A"; row.supersetGroupID = "A"
        press.sets.insert(contentsOf: [ExerciseSet(id: "pressWarm1", isWarmup: true), ExerciseSet(id: "pressWarm2", setType: .warmup)], at: 0)
        row.sets.insert(ExerciseSet(id: "rowWarm1", isWarmup: true), at: 0)
        let exercises = [press, row]
        for (current, expected) in [("pressWarm1", "pressWarm2"), ("pressWarm2", "press1"),
                                    ("press1", "rowWarm1"), ("rowWarm1", "row1"), ("row1", "press2")] {
            XCTAssertEqual(WorkoutSetNavigation.nextInput(after: current, in: exercises)?.setID, expected)
        }
        let warmupsOnly = RoutineExercise(id: "warmup", name: "Warmup", sets: [ExerciseSet(id: "warm1", isWarmup: true), ExerciseSet(id: "warm2", isWarmup: true)])
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "warm1", in: [warmupsOnly])?.setID, "warm2")
        XCTAssertNil(WorkoutSetNavigation.nextInput(after: "warm2", in: [warmupsOnly]))
    }

    func testInputNavigationDoesNotCombineNonadjacentSupersetGroups() {
        var press = exercise("press"), row = exercise("row"), run = exercise("run")
        press.supersetGroupID = "A"; row.supersetGroupID = "A"; run.type = .cardio
        let exercises = [press, run, row]
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "press1", in: exercises)?.setID, "press2")
        XCTAssertEqual(WorkoutSetNavigation.nextInput(after: "press2", in: exercises)?.setID, "row1")
    }

    func testInputNavigationLeavesProgramAndEverySetValueUnchanged() throws {
        var press = exercise("press"), row = exercise("row")
        press.supersetGroupID = "A"; row.supersetGroupID = "A"
        press.sets[0].weight = 135; press.sets[0].reps = 8
        row.sets[1].isCompleted = true; row.sets[1].weight = 95; row.sets[1].reps = 10
        let routine = WorkoutRoutine(id: "routine", userID: "account", name: "Upper", dateCreated: Date(timeIntervalSince1970: 0), exercises: [press, row])
        let program = WorkoutProgram(id: "program", userID: "account", name: "PHUL", routines: [routine], currentProgressIndex: 5, skippedIndices: [2])
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(program)
        for set in routine.exercises.flatMap(\.sets) {
            let next = WorkoutSetNavigation.nextInput(after: set.id, in: routine.exercises)
            XCTAssertNotEqual(next?.setID, set.id)
            let previous = WorkoutSetNavigation.previousInput(before: set.id, in: routine.exercises)
            XCTAssertNotEqual(previous?.setID, set.id)
        }
        XCTAssertEqual(try encoder.encode(program), before, "Moving keyboard focus must preserve program progress, sets and IDs")
    }

    func testPreviousInputUsesTheSameWarmupAndSupersetOrderWithoutWrapping() {
        var press = exercise("press"), row = exercise("row")
        press.supersetGroupID = "A"; row.supersetGroupID = "A"
        press.sets.insert(ExerciseSet(id: "pressWarm", isWarmup: true), at: 0)
        row.sets.insert(ExerciseSet(id: "rowWarm", isWarmup: true), at: 0)
        let exercises = [press, row, exercise("carry")]
        for (current, expected) in [("press1", "pressWarm"), ("rowWarm", "press1"),
                                    ("row1", "rowWarm"), ("press2", "row1"),
                                    ("row2", "press2"), ("carry1", "row2")] {
            XCTAssertEqual(WorkoutSetNavigation.previousInput(before: current, in: exercises)?.setID, expected)
        }
        XCTAssertNil(WorkoutSetNavigation.previousInput(before: "pressWarm", in: exercises))
        XCTAssertTrue(exercises.flatMap(\.sets).allSatisfy { !$0.isCompleted })
    }

    func testPreviousInputSkipsCompletedAndNonStrengthRowsAndRejectsUnknownIdentity() {
        var press = exercise("press"), run = exercise("run")
        press.sets[1].isCompleted = true
        run.type = .cardio
        let exercises = [press, run, exercise("row")]
        XCTAssertEqual(WorkoutSetNavigation.previousInput(before: "row1", in: exercises)?.setID, "press1")
        XCTAssertNil(WorkoutSetNavigation.previousInput(before: "press1", in: exercises))
        XCTAssertNil(WorkoutSetNavigation.previousInput(before: "run1", in: exercises))
        XCTAssertNil(WorkoutSetNavigation.previousInput(before: "missing", in: exercises))
        XCTAssertNil(WorkoutSetNavigation.previousInput(before: "row1", in: []))
    }

    private func exercise(_ id: String) -> RoutineExercise {
        RoutineExercise(id: id, name: id, sets: [ExerciseSet(id: id + "1"), ExerciseSet(id: id + "2")])
    }
}
