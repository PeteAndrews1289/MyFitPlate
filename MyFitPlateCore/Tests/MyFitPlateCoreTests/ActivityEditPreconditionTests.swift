import XCTest
@testable import MyFitPlateCore

final class ActivityEditPreconditionTests: XCTestCase {
    func testCompleteSnapshotRejectsChangedCaloriesOrSourceEvenWithSameIdentity() throws {
        let original = activity()
        var desired = original; desired.caloriesBurned = 400; desired.hasLocalHealthKitEdits = true
        let rule = ActivityEditPrecondition(expected: original, desired: desired)
        var log = DailyLog(date: original.date, meals: [], exercises: [original])
        XCTAssertNoThrow(try rule.validate(in: log))
        log.exercises = [desired]
        XCTAssertNoThrow(try rule.validate(in: log), "Exact desired replay is allowed")
        var independent = original; independent.caloriesBurned = 500
        XCTAssertEqual(original, independent, "Model identity equality is insufficient for this check")
        log.exercises = [independent]
        XCTAssertThrowsError(try rule.validate(in: log))
        independent = original; independent.source = "manual"
        log.exercises = [independent]
        XCTAssertThrowsError(try rule.validate(in: log))
        log.exercises = [original, original]
        XCTAssertThrowsError(try rule.validate(in: log))
        log.exercises = []
        XCTAssertThrowsError(try rule.validate(in: log), "A removed activity cannot be resurrected")
    }

    func testCheckedMutationPreservesUnrelatedFoodAndWaterAndReplaysWithoutOverwritingLaterEdit() throws {
        let original = activity()
        let before = DailyLog(id: "day", date: original.date, meals: [], exercises: [original]).rememberingMutationBase()
        var changed = before
        var desired = original; desired.caloriesBurned = 400; desired.hasLocalHealthKitEdits = true
        changed.exercises = [desired]; changed.pendingMutationID = "run-review.operation"
        changed.pendingActivityEdit = ActivityEditPrecondition(expected: original, desired: desired)
        let mutation = try DailyLogMutation(userID: "runner", log: changed)
        var concurrent = before
        concurrent.meals = [Meal(name: "Dinner", foodItems: [FoodItem(id: "independent", name: "Rice", calories: 200)])]
        concurrent.waterTracker = WaterTracker(totalOunces: 24, goalOunces: 64, date: original.date)
        let accepted = try mutation.applying(to: concurrent, checkingFoodEdits: true)
        XCTAssertEqual(accepted.exercises?.first?.caloriesBurned, 400)
        XCTAssertEqual(accepted.meals.flatMap(\.foodItems).map(\.id), ["independent"])
        XCTAssertEqual(accepted.waterTracker?.totalOunces, 24)
        var later = accepted; later.exercises?[0].caloriesBurned = 450
        let replay = try mutation.applying(to: later, checkingFoodEdits: true)
        XCTAssertEqual(replay.exercises?.first?.caloriesBurned, 450, "Receipt replay must return the latest canonical copy")
        XCTAssertEqual(replay.appliedMutationIDs?.filter { $0 == mutation.id }.count, 1)
    }

    private func activity() -> LoggedExercise {
        LoggedExercise(id: UUID().uuidString, name: "Running", durationMinutes: 30, caloriesBurned: 300,
            date: Date(timeIntervalSince1970: 1_800_000_000), source: "HealthKit")
    }
}
