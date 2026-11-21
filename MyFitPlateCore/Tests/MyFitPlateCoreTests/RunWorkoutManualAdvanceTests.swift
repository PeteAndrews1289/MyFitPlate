import XCTest
@testable import MyFitPlateCore

final class RunWorkoutManualAdvanceTests: XCTestCase {
    func testOpenStepWaitsWithoutInventedTargetThenAdvancesAtObservedPosition() throws {
        let plan = makePlan(first: .open)
        let tracker = RunWorkoutTracker(plan: plan)
        let waiting = tracker.progress(elapsedSeconds: 600, distanceMeters: 1_700)
        XCTAssertEqual(waiting.currentStep?.id, "first")
        XCTAssertNil(waiting.remainingSeconds)
        XCTAssertNil(waiting.remainingMeters)
        XCTAssertEqual(plan.estimatedDurationSeconds, 60)
        XCTAssertEqual(plan.totalDistanceMeters, 0)
        XCTAssertTrue(tracker.advanceManually(expectedStepID: "first", elapsedSeconds: 601, distanceMeters: 1_704))
        let next = tracker.progress(elapsedSeconds: 611, distanceMeters: 1_734)
        XCTAssertEqual(next.currentStep?.id, "second")
        XCTAssertEqual(next.stepElapsedSeconds, 10)
        XCTAssertEqual(next.stepDistanceMeters, 30)
        let receipt = try XCTUnwrap(tracker.result(runID: "run", elapsedSeconds: 611, distanceMeters: 1_734))
        XCTAssertTrue(receipt.steps[0].isComplete)
        XCTAssertEqual(receipt.steps[0].completionReason, .manuallyCompleted)
        XCTAssertEqual(receipt.steps[0].elapsedSeconds, 601)
        XCTAssertFalse(receipt.steps[1].isComplete)
    }

    func testSkipKeepsActualTotalsAndSurvivesCheckpointWithoutCountingCompletion() throws {
        let tracker = RunWorkoutTracker(plan: makePlan(first: .distance(meters: 400)))
        XCTAssertTrue(tracker.advanceManually(expectedStepID: "first", elapsedSeconds: 30, distanceMeters: 100))
        let data = try JSONEncoder().encode(tracker.snapshot())
        let snapshot = try JSONDecoder().decode(RunWorkoutTracker.Snapshot.self, from: data)
        let recovered = try XCTUnwrap(RunWorkoutTracker(snapshot: snapshot))
        let progress = recovered.progress(elapsedSeconds: 45, distanceMeters: 150)
        XCTAssertEqual(progress.currentStep?.id, "second")
        XCTAssertEqual(progress.stepElapsedSeconds, 15)
        XCTAssertEqual(progress.stepDistanceMeters, 50)
        let receipt = try XCTUnwrap(recovered.result(runID: "run", elapsedSeconds: 90, distanceMeters: 300))
        XCTAssertEqual(receipt.steps.count, 2)
        XCTAssertEqual(receipt.steps[0].completionReason, .skipped)
        XCTAssertFalse(receipt.steps[0].isComplete)
        XCTAssertEqual(receipt.steps[0].elapsedSeconds, 30)
        XCTAssertTrue(receipt.steps[1].isComplete)
        XCTAssertEqual(receipt.steps[1].elapsedSeconds, 60)
    }

    func testLateSkipCannotAdvanceStepThatJustCompletedAutomatically() {
        let tracker = RunWorkoutTracker(plan: makePlan(first: .duration(seconds: 10)))
        XCTAssertFalse(tracker.advanceManually(expectedStepID: "first", elapsedSeconds: 12, distanceMeters: 30))
        XCTAssertEqual(tracker.progress(elapsedSeconds: 12, distanceMeters: 30).currentStep?.id, "second")
        XCTAssertFalse(tracker.advanceManually(expectedStepID: "second", elapsedSeconds: 11, distanceMeters: 29))
        XCTAssertFalse(tracker.advanceManually(expectedStepID: "second", elapsedSeconds: .infinity, distanceMeters: 30))
        XCTAssertEqual(tracker.snapshot().completedSteps.count, 1)
    }

    func testLegacyResultWithoutReasonAndOpenGoalRoundTrip() throws {
        let tracker = RunWorkoutTracker(plan: makePlan(first: .duration(seconds: 10)))
        _ = tracker.progress(elapsedSeconds: 10, distanceMeters: 20)
        let data = try JSONEncoder().encode(tracker.snapshot())
        XCTAssertNotNil(RunWorkoutTracker(snapshot: try JSONDecoder().decode(RunWorkoutTracker.Snapshot.self, from: data)))
        let openPlan = makePlan(first: .open)
        XCTAssertEqual(try JSONDecoder().decode(RunWorkoutPlan.self, from: JSONEncoder().encode(openPlan)), openPlan)
    }

    private func makePlan(first: RunWorkoutStep.Goal) -> RunWorkoutPlan {
        RunWorkoutPlan(id: "manual-steps", name: "Flexible session", subtitle: "Test", steps: [
            RunWorkoutStep(id: "first", kind: .warmup, title: "Prepare", goal: first),
            RunWorkoutStep(id: "second", kind: .hard, title: "Run", goal: .duration(seconds: 60))
        ])
    }
}
