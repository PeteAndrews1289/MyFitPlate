import XCTest
@testable import MyFitPlateCore

final class WorkoutDedupeTests: XCTestCase {

    private let now = Date()

    private func routine(_ name: String, endedAt: Date, minutes: Int, calories: Double) -> LoggedExercise {
        // MyFitPlate logs `date` as the completion (end) time.
        LoggedExercise(name: name, durationMinutes: minutes, caloriesBurned: calories, date: endedAt, source: "routine")
    }

    private func healthKit(_ name: String, startedAt: Date, minutes: Int, calories: Double) -> LoggedExercise {
        // Apple Health logs `date` as the workout start time.
        LoggedExercise(name: name, durationMinutes: minutes, caloriesBurned: calories, date: startedAt, source: "HealthKit")
    }

    func testOverlappingRoutineAndHealthKitCollapseToOne() {
        let end = now
        let exercises = [
            routine("Lower Power", endedAt: end, minutes: 15, calories: 89),
            healthKit("Strength Training", startedAt: end.addingTimeInterval(-44 * 60), minutes: 44, calories: 235)
        ]
        let result = exercises.dedupedAgainstHealthKit()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Lower Power")                  // keep the MyFitPlate name
        XCTAssertEqual(result.first?.caloriesBurned ?? 0, 235, accuracy: 0.001) // use measured calories
        XCTAssertEqual(result.first?.durationMinutes, 44)                  // and measured duration
    }

    func testNonOverlappingWorkoutsStaySeparate() {
        let exercises = [
            routine("Lower Power", endedAt: now, minutes: 15, calories: 89),
            healthKit("Walking", startedAt: now.addingTimeInterval(-5 * 3600), minutes: 10, calories: 34)
        ]
        let result = exercises.dedupedAgainstHealthKit()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.reduce(0) { $0 + $1.caloriesBurned }, 123, accuracy: 0.001) // 89 + 34, no merge
    }

    func testNoHealthKitDataPassesThroughUnchanged() {
        let exercises = [routine("Lower Power", endedAt: now, minutes: 15, calories: 89)]
        let result = exercises.dedupedAgainstHealthKit()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.caloriesBurned ?? 0, 89, accuracy: 0.001)
    }

    func testRoutineMergesWhileStandaloneWalkSurvives() {
        let end = now
        let exercises = [
            routine("Lower Power", endedAt: end, minutes: 15, calories: 89),
            healthKit("Strength Training", startedAt: end.addingTimeInterval(-44 * 60), minutes: 44, calories: 235),
            healthKit("Walking", startedAt: end.addingTimeInterval(-5 * 3600), minutes: 10, calories: 34)
        ]
        let result = exercises.dedupedAgainstHealthKit()
        XCTAssertEqual(result.count, 2)                                            // merged routine + standalone walk
        XCTAssertEqual(result.reduce(0) { $0 + $1.caloriesBurned }, 269, accuracy: 0.001) // 235 + 34, not 358
        XCTAssertNil(result.first { $0.name == "Strength Training" })              // duplicate HK entry dropped
        XCTAssertNotNil(result.first { $0.name == "Lower Power" })
    }
}
