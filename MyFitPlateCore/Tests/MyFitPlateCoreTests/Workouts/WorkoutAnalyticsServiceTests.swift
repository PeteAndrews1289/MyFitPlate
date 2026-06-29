import XCTest
@testable import MyFitPlateCore

@MainActor
final class WorkoutAnalyticsServiceTests: XCTestCase {

    func testImmediateAnalyticsCalculatesVolumeAndStrengthInsights() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(
                    name: "Barbell Bench Press",
                    type: .strength,
                    sets: [
                        CompletedSet(reps: 5, weight: 185),
                        CompletedSet(reps: 8, weight: 165)
                    ]
                ),
                completedExercise(
                    name: "Dumbbell Curl",
                    type: .strength,
                    sets: [
                        CompletedSet(reps: 10, weight: 30)
                    ]
                )
            ]
        )

        let analytics = service.generateImmediateSessionAnalytics(for: log)

        XCTAssertEqual(analytics.totalVolume, 2_545, accuracy: 0.001)
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Session Banked" })
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Barbell Bench Press Drove the Session" })
        XCTAssertTrue(analytics.aiInsights.contains { $0.category == "Mindset" })
    }

    func testImmediateAnalyticsProducesCardioInsightWhenNoStrengthVolumeExists() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(
                    name: "Rowing Machine",
                    type: .cardio,
                    sets: [
                        CompletedSet(reps: 0, weight: 0, distance: 2.5, durationInSeconds: 1_200)
                    ]
                )
            ]
        )

        let analytics = service.generateImmediateSessionAnalytics(for: log)

        XCTAssertEqual(analytics.totalVolume, 0, accuracy: 0.001)
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Conditioning Logged" })
        XCTAssertTrue(analytics.aiInsights.contains { $0.message.contains("20 minutes") })
    }

    func testImmediateAnalyticsRecommendsRecoveryForHighVolumeSession() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(
                    name: "Deadlift",
                    type: .strength,
                    sets: [
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315)
                    ]
                )
            ]
        )

        let analytics = service.generateImmediateSessionAnalytics(for: log)

        XCTAssertGreaterThanOrEqual(analytics.totalVolume, 10_000)
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Recovery Has Leverage" })
    }

    func testMuscleSplitPrioritizesSpecificLegTermsBeforeGenericRaiseOrCurlTerms() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(name: "Standing Calf Raise", type: .strength, sets: [CompletedSet(reps: 12, weight: 90)]),
                completedExercise(name: "Leg Curl", type: .strength, sets: [CompletedSet(reps: 12, weight: 80)]),
                completedExercise(name: "Lateral Raise", type: .strength, sets: [CompletedSet(reps: 12, weight: 20)]),
                completedExercise(name: "Bench Press", type: .strength, sets: [CompletedSet(reps: 8, weight: 185)])
            ]
        )

        let split = service.calculateMuscleSplit(log: log)
        let byMuscle = Dictionary(uniqueKeysWithValues: split.map { ($0.muscleName, $0.setCount) })

        XCTAssertEqual(byMuscle["Legs"], 2)
        XCTAssertEqual(byMuscle["Shoulders"], 1)
        XCTAssertEqual(byMuscle["Chest"], 1)
    }

    func testWorkoutInsightDecodesWithFreshIdentifierAndPreservesPayload() throws {
        let data = Data("""
        {"title":"Progress","message":"Add five pounds next week.","category":"Performance"}
        """.utf8)

        let insight = try JSONDecoder().decode(WorkoutAnalysisInsight.self, from: data)

        XCTAssertFalse(insight.id.uuidString.isEmpty)
        XCTAssertEqual(insight.title, "Progress")
        XCTAssertEqual(insight.message, "Add five pounds next week.")
        XCTAssertEqual(insight.category, "Performance")
    }

    private func makeSessionLog(exercises: [CompletedExercise]) -> WorkoutSessionLog {
        WorkoutSessionLog(id: "session-1", date: Date(), routineID: "routine-1", completedExercises: exercises)
    }

    private func completedExercise(
        name: String,
        type: ExerciseType,
        sets: [CompletedSet]
    ) -> CompletedExercise {
        CompletedExercise(
            exerciseName: name,
            exercise: RoutineExercise(name: name, type: type, sets: []),
            sets: sets
        )
    }
}
