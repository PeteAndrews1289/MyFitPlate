import XCTest
@testable import MyFitPlateCore

final class RunWorkoutGoalRevisionTests: XCTestCase {
    func testRevisionKeepsOriginalPlanAndExactAppliedPositionThroughRecoveryAndFinish() throws {
        let original = plan(goal: .duration(seconds: 1_800))
        let tracker = RunWorkoutTracker(plan: original)
        XCTAssertTrue(tracker.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .duration(seconds: 1_800),
            newGoal: .duration(seconds: 2_100), operationID: "extend", elapsedSeconds: 300, distanceMeters: 900))
        XCTAssertEqual(tracker.plan, original)
        let saved = try JSONEncoder().encode(tracker.snapshot())
        let restored = try XCTUnwrap(RunWorkoutTracker(snapshot: JSONDecoder().decode(RunWorkoutTracker.Snapshot.self, from: saved)))
        XCTAssertEqual(restored.progress(elapsedSeconds: 300, distanceMeters: 900).remainingSeconds, 1_800)
        let result = try XCTUnwrap(restored.result(runID: "run", elapsedSeconds: 2_200, distanceMeters: 6_000))
        XCTAssertEqual(result.steps[0].step.goal, .duration(seconds: 2_100))
        XCTAssertEqual(result.steps[0].elapsedSeconds, 2_100)
        XCTAssertEqual(result.goalRevisions?.first?.previousGoal, .duration(seconds: 1_800))
        XCTAssertEqual(result.goalRevisions?.first?.activeSeconds, 300)
        XCTAssertEqual(result.goalRevisions?.first?.distanceMeters, 900)
    }

    func testReplayAcknowledgesOriginalChangeWithoutOverwritingNewerRevision() {
        let tracker = RunWorkoutTracker(plan: plan(goal: .distance(meters: 5_000)))
        XCTAssertTrue(tracker.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .distance(meters: 5_000),
            newGoal: .distance(meters: 6_000), operationID: "first", elapsedSeconds: 60, distanceMeters: 150))
        XCTAssertTrue(tracker.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .distance(meters: 6_000),
            newGoal: .distance(meters: 7_000), operationID: "second", elapsedSeconds: 120, distanceMeters: 300))
        XCTAssertTrue(tracker.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .distance(meters: 5_000),
            newGoal: .distance(meters: 6_000), operationID: "first", elapsedSeconds: 130, distanceMeters: 320))
        XCTAssertEqual(tracker.goalRevisions.count, 2)
        XCTAssertEqual(tracker.progress(elapsedSeconds: 130, distanceMeters: 320).currentStep?.goal, .distance(meters: 7_000))
        XCTAssertFalse(tracker.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .distance(meters: 6_000),
            newGoal: .distance(meters: 8_000), operationID: "stale", elapsedSeconds: 130, distanceMeters: 320))
    }

    func testCompletedOrAlreadyPassedTargetsCannotBeRetroactivelyChanged() {
        let tracker = RunWorkoutTracker(plan: plan(goal: .duration(seconds: 60)))
        XCTAssertFalse(tracker.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .duration(seconds: 60),
            newGoal: .duration(seconds: 120), operationID: "late", elapsedSeconds: 61, distanceMeters: 180))
        XCTAssertTrue(tracker.progress(elapsedSeconds: 61, distanceMeters: 180).isWorkoutComplete)
        XCTAssertTrue(tracker.goalRevisions.isEmpty)
        let fresh = RunWorkoutTracker(plan: plan(goal: .distance(meters: 5_000)))
        XCTAssertFalse(fresh.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .distance(meters: 5_000),
            newGoal: .distance(meters: 100), operationID: "passed", elapsedSeconds: 60, distanceMeters: 150))
        XCTAssertFalse(fresh.reviseCurrentGoal(expectedStepID: "goal", expectedGoal: .distance(meters: 5_000),
            newGoal: .duration(seconds: 300), operationID: "different-kind", elapsedSeconds: 60, distanceMeters: 150))
    }

    func testForgedRevisionSnapshotIsRejected() {
        let tracker = RunWorkoutTracker(plan: plan(goal: .duration(seconds: 60)))
        _ = tracker.progress(elapsedSeconds: 30, distanceMeters: 100)
        var snapshot = tracker.snapshot()
        snapshot.goalRevisions = [RunWorkoutGoalRevision(id: "invalid", stepID: "goal", previousGoal: .duration(seconds: 90),
            revisedGoal: .duration(seconds: 120), activeSeconds: 20, distanceMeters: 80)]
        XCTAssertNil(RunWorkoutTracker(snapshot: snapshot))
    }

    private func plan(goal: RunWorkoutStep.Goal) -> RunWorkoutPlan {
        RunWorkoutPlan(id: "goal-plan", name: "Run goal", subtitle: "Test",
            steps: [RunWorkoutStep(id: "goal", kind: .hard, title: "Run", goal: goal)])
    }
}
