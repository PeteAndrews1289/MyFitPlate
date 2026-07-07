import XCTest
@testable import MyFitPlateCore

final class RunWorkoutPlanTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RunWorkoutPlanTests_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testBuiltinTemplatesAreUsable() {
        let templates = RunWorkoutPlan.builtinTemplates(metric: true)

        XCTAssertEqual(templates.map(\.id), ["5x400m", "30-30-fartlek", "tempo-starter"])
        XCTAssertTrue(templates.allSatisfy { !$0.steps.isEmpty })
        XCTAssertEqual(templates[0].steps.filter { $0.kind == .hard }.count, 5)
        XCTAssertEqual(templates[1].steps.filter { $0.kind == .hard }.count, 10)
    }

    func testTimedStepProgressesAndAdvances() {
        let plan = RunWorkoutPlan(
            name: "Easy opener",
            subtitle: "Test",
            steps: [
                RunWorkoutStep(id: "warm", kind: .warmup, title: "Warm up", goal: .duration(seconds: 60)),
                RunWorkoutStep(id: "go", kind: .hard, title: "Go", goal: .duration(seconds: 30))
            ]
        )
        let tracker = RunWorkoutTracker(plan: plan)

        var progress = tracker.progress(elapsedSeconds: 30, distanceMeters: 80)
        XCTAssertEqual(progress.currentStep?.id, "warm")
        XCTAssertEqual(progress.progressFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.remainingSeconds ?? 0, 30, accuracy: 0.001)

        progress = tracker.progress(elapsedSeconds: 60, distanceMeters: 160)
        XCTAssertEqual(progress.currentStep?.id, "go")
        XCTAssertEqual(progress.currentStepIndex, 1)
        XCTAssertEqual(progress.stepElapsedSeconds, 0, accuracy: 0.001)
    }

    func testDistanceStepProgressesAndAdvances() {
        let plan = RunWorkoutPlan(
            name: "Quarter",
            subtitle: "Test",
            steps: [
                RunWorkoutStep(id: "fast", kind: .hard, title: "400", goal: .distance(meters: 400)),
                RunWorkoutStep(id: "recover", kind: .recovery, title: "Recover", goal: .duration(seconds: 90))
            ]
        )
        let tracker = RunWorkoutTracker(plan: plan)

        var progress = tracker.progress(elapsedSeconds: 45, distanceMeters: 200)
        XCTAssertEqual(progress.currentStep?.id, "fast")
        XCTAssertEqual(progress.progressFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.remainingMeters ?? 0, 200, accuracy: 0.001)

        progress = tracker.progress(elapsedSeconds: 90, distanceMeters: 400)
        XCTAssertEqual(progress.currentStep?.id, "recover")
        XCTAssertEqual(progress.stepDistanceMeters, 0, accuracy: 0.001)
    }

    func testAdvanceReturnsCompletedSteps() {
        let plan = RunWorkoutPlan(
            name: "Stack",
            subtitle: "Test",
            steps: [
                RunWorkoutStep(id: "one", kind: .warmup, title: "One", goal: .duration(seconds: 10)),
                RunWorkoutStep(id: "two", kind: .recovery, title: "Two", goal: .duration(seconds: 20))
            ]
        )
        let tracker = RunWorkoutTracker(plan: plan)

        let completed = tracker.advance(elapsedSeconds: 10, distanceMeters: 40)
        XCTAssertEqual(completed.map(\.id), ["one"])
        XCTAssertEqual(tracker.progress(elapsedSeconds: 15, distanceMeters: 60).currentStep?.id, "two")
    }

    func testWorkoutCompletesAfterFinalStep() {
        let plan = RunWorkoutPlan(
            name: "Done",
            subtitle: "Test",
            steps: [
                RunWorkoutStep(id: "one", kind: .hard, title: "One", goal: .distance(meters: 100))
            ]
        )
        let tracker = RunWorkoutTracker(plan: plan)

        let progress = tracker.progress(elapsedSeconds: 30, distanceMeters: 100)
        XCTAssertTrue(progress.isWorkoutComplete)
        XCTAssertNil(progress.currentStep)
        XCTAssertEqual(progress.currentStepIndex, 1)
        XCTAssertEqual(progress.progressFraction, 1)
    }

    func testWorkoutResultIncludesCompletedAndPartialSteps() throws {
        let plan = RunWorkoutPlan(
            id: "plan-1",
            name: "Two stepper",
            subtitle: "Test",
            steps: [
                RunWorkoutStep(id: "warm", kind: .warmup, title: "Warm", goal: .duration(seconds: 10)),
                RunWorkoutStep(id: "fast", kind: .hard, title: "Fast", goal: .distance(meters: 100))
            ]
        )
        let tracker = RunWorkoutTracker(plan: plan)

        _ = tracker.progress(elapsedSeconds: 12, distanceMeters: 40)
        let result = try XCTUnwrap(tracker.result(
            runID: "run-1",
            completedAt: Date(timeIntervalSince1970: 1_234),
            elapsedSeconds: 20,
            distanceMeters: 80
        ))

        XCTAssertEqual(result.runID, "run-1")
        XCTAssertEqual(result.planID, "plan-1")
        XCTAssertEqual(result.planName, "Two stepper")
        XCTAssertEqual(result.steps.count, 2)
        XCTAssertEqual(result.steps[0].step.id, "warm")
        XCTAssertTrue(result.steps[0].isComplete)
        XCTAssertEqual(result.steps[0].elapsedSeconds, 12, accuracy: 0.001)
        XCTAssertEqual(result.steps[0].distanceMeters, 40, accuracy: 0.001)
        XCTAssertEqual(result.steps[1].step.id, "fast")
        XCTAssertFalse(result.steps[1].isComplete)
        XCTAssertEqual(result.steps[1].elapsedSeconds, 8, accuracy: 0.001)
        XCTAssertEqual(result.steps[1].distanceMeters, 40, accuracy: 0.001)
    }

    func testStepGoalTextUsesRunFormatting() {
        XCTAssertEqual(
            RunWorkoutStep(kind: .hard, title: "400", goal: .distance(meters: 400)).goalText(metric: true),
            "0.40 km"
        )
        XCTAssertEqual(
            RunWorkoutStep(kind: .recovery, title: "Recover", goal: .duration(seconds: 90)).goalText(metric: true),
            "1:30"
        )
    }

    func testTargetTextFormatsPaceRangesAndCue() {
        let target = RunWorkoutTarget(
            cue: "Comfortably hard",
            fastestSecondsPerKm: 300,
            slowestSecondsPerKm: 330
        )

        XCTAssertEqual(target.displayText(metric: true), "Target 5:00-5:30 /km · Comfortably hard")
        XCTAssertEqual(target.displayText(metric: false), "Target 8:03-8:51 /mi · Comfortably hard")
    }

    func testPaceRangeTargetConvertsFromUserUnits() {
        let metricTarget = RunWorkoutTarget.paceRange(
            cue: "Steady",
            fastestSecondsPerUnit: 300,
            slowestSecondsPerUnit: 330,
            metric: true
        )
        XCTAssertEqual(metricTarget.displayText(metric: true), "Target 5:00-5:30 /km · Steady")

        let imperialTarget = RunWorkoutTarget.paceRange(
            cue: "Steady",
            fastestSecondsPerUnit: 480,
            slowestSecondsPerUnit: 510,
            metric: false
        )
        XCTAssertEqual(imperialTarget.displayText(metric: false), "Target 8:00-8:30 /mi · Steady")
        XCTAssertEqual(imperialTarget.fastestSecondsPerKm ?? 0, 298.258, accuracy: 0.001)
    }

    func testPaceRangeTargetNormalizesSwappedInputs() {
        let target = RunWorkoutTarget.paceRange(
            cue: nil,
            fastestSecondsPerUnit: 360,
            slowestSecondsPerUnit: 300,
            metric: true
        )

        XCTAssertEqual(target.displayText(metric: true), "Target 5:00-6:00 /km")
    }

    func testLegacyStepWithoutTargetDecodes() throws {
        let json = """
        {
          "id": "legacy",
          "kind": "hard",
          "title": "Fast",
          "goal": { "duration": { "seconds": 30 } }
        }
        """.data(using: .utf8)!

        let step = try JSONDecoder().decode(RunWorkoutStep.self, from: json)

        XCTAssertEqual(step.id, "legacy")
        XCTAssertNil(step.target)
        XCTAssertNil(step.targetText(metric: true))
    }

    func testRepeatTemplateBuildsWarmupRepeatsRecoveryAndCooldown() {
        let plan = RunWorkoutPlan.repeatTemplate(
            name: "Lunch 200s",
            warmupSeconds: 300,
            repetitions: 3,
            workGoal: .distance(meters: 200),
            recoverySeconds: 60,
            cooldownSeconds: 180,
            workTarget: RunWorkoutTarget(cue: "Smooth")
        )

        XCTAssertEqual(plan.name, "Lunch 200s")
        XCTAssertEqual(plan.subtitle, "3 repeats")
        XCTAssertEqual(plan.steps.map(\.kind), [.warmup, .hard, .recovery, .hard, .recovery, .hard, .cooldown])
        XCTAssertEqual(plan.steps.filter { $0.kind == .hard }.count, 3)
        XCTAssertEqual(plan.steps.first(where: { $0.kind == .hard })?.targetText(metric: true), "Smooth")
    }

    func testPlanStorePersistsCustomPlans() throws {
        let store = RunWorkoutPlanStore(userDefaults: testDefaults)
        let plan = RunWorkoutPlan.repeatTemplate(
            id: "template-1",
            name: "Track day",
            warmupSeconds: 600,
            repetitions: 4,
            workGoal: .duration(seconds: 45),
            recoverySeconds: 75,
            cooldownSeconds: 300
        )

        store.addPlan(plan)

        let reloaded = RunWorkoutPlanStore(userDefaults: testDefaults)
        XCTAssertEqual(reloaded.customPlans.map(\.id), ["template-1"])
        XCTAssertEqual(reloaded.customPlans.first?.name, "Track day")
    }

    func testPlanStoreRekeysDuplicateIDsAndDeletes() {
        let store = RunWorkoutPlanStore(userDefaults: testDefaults)
        let plan = RunWorkoutPlan.repeatTemplate(
            id: "same",
            name: "One",
            warmupSeconds: 0,
            repetitions: 1,
            workGoal: .duration(seconds: 30),
            recoverySeconds: 0,
            cooldownSeconds: 0
        )

        store.addPlan(plan)
        store.addPlan(plan)

        XCTAssertEqual(store.customPlans.count, 2)
        XCTAssertEqual(Set(store.customPlans.map(\.id)).count, 2)

        store.deletePlan(id: "same")
        XCTAssertEqual(store.customPlans.count, 1)
        XCTAssertNotEqual(store.customPlans.first?.id, "same")
    }

    func testResultStorePersistsResultsByRunID() throws {
        let store = RunWorkoutResultStore(userDefaults: testDefaults)
        let result = RunWorkoutResult(
            runID: "run-42",
            planID: "plan-42",
            planName: "Track day",
            completedAt: Date(timeIntervalSince1970: 42),
            steps: [
                RunWorkoutStepResult(
                    stepIndex: 0,
                    step: RunWorkoutStep(id: "work", kind: .hard, title: "Work", goal: .duration(seconds: 30)),
                    startedAtElapsedSeconds: 0,
                    endedAtElapsedSeconds: 31,
                    startedAtDistanceMeters: 0,
                    endedAtDistanceMeters: 120,
                    isComplete: true
                )
            ]
        )

        store.save(result)

        let reloaded = RunWorkoutResultStore(userDefaults: testDefaults)
        XCTAssertEqual(reloaded.result(forRunID: "run-42")?.planName, "Track day")
        let pace = try XCTUnwrap(reloaded.result(forRunID: "run-42")?.steps.first?.paceSecondsPerKm)
        XCTAssertEqual(pace, 258.333, accuracy: 0.001)

        reloaded.deleteResult(forRunID: "run-42")
        XCTAssertNil(store.result(forRunID: "run-42"))
    }
}
