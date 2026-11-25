import XCTest
@testable import MyFitPlateCore

final class RunWorkoutOutlineTests: XCTestCase {
    func testNestedMixedOutlineExpandsStableIdentitiesWithoutInventingOpenTarget() throws {
        let warm = RunWorkoutStep(id: "warm", kind: .warmup, title: "Open warm-up", goal: .open)
        let work = RunWorkoutStep(id: "work", kind: .hard, title: "400 m", goal: .distance(meters: 400))
        let recovery = RunWorkoutStep(id: "recovery", kind: .recovery, title: "Recover", goal: .duration(seconds: 90))
        let pair = RunWorkoutOutlineGroup(id: "pair", repetitions: 2, children: [.step(work), .step(recovery)])
        let block = RunWorkoutOutlineGroup(id: "block", repetitions: 3, children: [.group(pair)])
        let outline: [RunWorkoutOutlineItem] = [.step(warm), .group(block)]
        let steps = try RunWorkoutOutline.expanded(outline)
        XCTAssertEqual(steps.count, 13)
        XCTAssertEqual(steps.first?.id, "warm")
        XCTAssertEqual(steps[1].id, "block.1/pair.1/work")
        XCTAssertEqual(steps[5].id, "block.2/pair.1/work")
        let plan = RunWorkoutPlan(id: "mixed", name: "Mixed repeats", subtitle: "Test", steps: steps, outline: outline)
        try RunWorkoutPlanStore.validate(plan)
        XCTAssertEqual(plan.totalDistanceMeters, 2_400)
        XCTAssertEqual(plan.estimatedDurationSeconds, 540)
        XCTAssertEqual(try JSONDecoder().decode(RunWorkoutPlan.self, from: JSONEncoder().encode(plan)), plan)
        var edited = block
        edited.repetitions = 4
        XCTAssertEqual(Array(try RunWorkoutOutline.expanded([.step(warm), .group(edited)]).prefix(steps.count)), steps)
    }

    func testInvalidDepthIdentityAndExpansionFailBeforeRecording() {
        let leaf = RunWorkoutOutlineItem.step(RunWorkoutStep(id: "leaf", kind: .hard, title: "Work", goal: .duration(seconds: 30)))
        XCTAssertThrowsError(try RunWorkoutOutline.expanded([leaf, leaf]))
        var nested = leaf
        for index in 1...4 { nested = .group(RunWorkoutOutlineGroup(id: "group-\(index)", repetitions: 1, children: [nested])) }
        XCTAssertThrowsError(try RunWorkoutOutline.expanded([nested]))
        let inner = RunWorkoutOutlineGroup(id: "inner", repetitions: 50, children: [leaf])
        XCTAssertThrowsError(try RunWorkoutOutline.expanded([.group(RunWorkoutOutlineGroup(id: "outer", repetitions: 4, children: [.group(inner)]))]))
        XCTAssertThrowsError(try RunWorkoutOutline.expanded([.group(RunWorkoutOutlineGroup(id: "empty", repetitions: 2, children: []))]))
    }

    func testOutlineCannotDisagreeWithSavedExecutableSnapshot() throws {
        let leaf = RunWorkoutStep(id: "leaf", kind: .hard, title: "Run", goal: .duration(seconds: 60))
        var plan = RunWorkoutPlan(id: "plan", name: "Plan", subtitle: "Test", steps: [leaf], outline: [.step(leaf)])
        try RunWorkoutPlanStore.validate(plan)
        plan.steps[0].goal = .duration(seconds: 90)
        XCTAssertThrowsError(try RunWorkoutPlanStore.validate(plan))
        var invalid = leaf
        invalid.target = RunWorkoutTarget(fastestSecondsPerKm: 400, slowestSecondsPerKm: 300)
        let invalidPlan = RunWorkoutPlan(id: "invalid", name: "Invalid", subtitle: "Test", steps: [invalid], outline: [.step(invalid)])
        XCTAssertThrowsError(try RunWorkoutPlanStore.validate(invalidPlan))
    }
}
