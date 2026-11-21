import XCTest
@testable import MyFitPlateCore

final class RunExperienceCompletionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testQuickGoalsPreserveExactSecondsAndRejectAmbiguousOrOverflowInput() {
        XCTAssertEqual(RunQuickGoalRules.durationSeconds("23:45"), 1425)
        XCTAssertEqual(RunQuickGoalRules.durationSeconds(" 30 "), 1800)
        XCTAssertEqual(RunQuickGoalRules.durationSeconds("0:01"), 1)
        XCTAssertEqual(RunQuickGoalRules.durationSeconds("360:00"), 21600)
        for bad in ["", "0", "30:60", "30:5", "-1", "360:01", "1:00:00", "1.5", "99999999999999999999999999"] {
            XCTAssertNil(RunQuickGoalRules.durationSeconds(bad), bad)
        }
    }

    func testResultsKeepWarmupSeparateAndPairWorkWithItsRecovery() {
        let result = RunWorkoutResult(runID: "run", planID: "plan", planName: "Repeats", completedAt: start,
            steps: [step(0, .warmup), step(1, .hard), step(2, .recovery), step(3, .hard), step(4, .cooldown)])
        let groups = RunResultPresentation.groups(result)
        XCTAssertEqual(groups.map { $0.steps.map(\.stepIndex) }, [[0], [1, 2], [3], [4]])
        XCTAssertEqual(groups.flatMap(\.steps), result.steps)
        XCTAssertEqual(groups[1].elapsedSeconds, 20)
        XCTAssertEqual(groups[1].distanceMeters, 40)
    }

    func testNestedOutlineResultsKeepOuterRepetitionBoundaries() {
        let result = RunWorkoutResult(runID: "run", planID: "plan", planName: "Nested", completedAt: start,
            steps: [step(0, .hard, id: "group.1/child.1/a"), step(1, .recovery, id: "group.1/child.1/b"),
                    step(2, .hard, id: "group.2/child.1/a")])
        XCTAssertEqual(RunResultPresentation.groups(result).map(\.title), ["Repeat 1", "Repeat 2"])
        let draft = RunResultPresentation.observedStepsDraft(result)
        XCTAssertNotEqual(draft?.id, result.planID)
        XCTAssertEqual(draft?.steps.count, 3)
        XCTAssertEqual(Set(draft?.steps.map(\.id) ?? []).count, 3)
        XCTAssertTrue(draft?.subtitle.contains("Observed steps only") == true)
    }

    func testRepeatUsesFinalReviewedGoalInNewCopyAndRejectsBrokenRevisionChain() throws {
        let originalStep = RunWorkoutStep(id: "goal", kind: .hard, title: "Run", goal: .duration(seconds: 1200))
        let original = RunWorkoutPlan(id: "original", name: "20 min run", subtitle: "Time goal", steps: [originalStep])
        let revision = RunWorkoutGoalRevision(id: "reviewed", stepID: "goal", previousGoal: .duration(seconds: 1200),
            revisedGoal: .duration(seconds: 1800), activeSeconds: 600, distanceMeters: 1500)
        var finalStep = originalStep; finalStep.goal = .duration(seconds: 1800)
        let stepResult = RunWorkoutStepResult(stepIndex: 0, step: finalStep, startedAtElapsedSeconds: 0, endedAtElapsedSeconds: 1800,
            startedAtDistanceMeters: 0, endedAtDistanceMeters: 4000, isComplete: true)
        var result = RunWorkoutResult(runID: "run", planID: "original", planName: original.name, completedAt: start,
            steps: [stepResult], goalRevisions: [revision], planSnapshot: original)
        let copy = try XCTUnwrap(RunResultPresentation.repeatPlan(result, metric: true, newID: "new-copy"))
        XCTAssertEqual(copy.name, "30 min run")
        XCTAssertEqual(copy.steps[0].goal, .duration(seconds: 1800))
        XCTAssertEqual(copy.id, "new-copy")
        XCTAssertEqual(result.planSnapshot, original)
        result.goalRevisions = [RunWorkoutGoalRevision(id: "broken", stepID: "goal", previousGoal: .duration(seconds: 1500),
            revisedGoal: .duration(seconds: 1800), activeSeconds: 600, distanceMeters: 1500)]
        XCTAssertNil(RunResultPresentation.repeatPlan(result, metric: true))
        result.goalRevisions = [revision, revision]
        XCTAssertNil(RunResultPresentation.repeatPlan(result, metric: true))
    }

    func testCustomThresholdBoundariesApplyExactlyAndLegacySettingsDecode() throws {
        let settings = RunHeartRateZoneSettings(method: .enteredThresholds, maximumBPM: 190, thresholdsBPM: [110, 130, 150, 170])
        XCTAssertEqual([109.9, 110, 130, 150, 170, 240].map { settings.zone(for: $0)?.number }, [1, 2, 3, 4, 5, 5])
        XCTAssertFalse(RunHeartRateZoneSettings(method: .enteredThresholds, maximumBPM: 190, thresholdsBPM: [110, 150, 130, 170]).isValid)
        XCTAssertFalse(RunHeartRateZoneSettings(method: .enteredThresholds, maximumBPM: 190, thresholdsBPM: [110, 130, 150, .nan]).isValid)
        let legacy = try JSONDecoder().decode(RunHeartRateZoneSettings.self, from: Data(#"{"method":"enteredMaximum","maximumBPM":190}"#.utf8))
        XCTAssertTrue(legacy.isValid)
        XCTAssertNil(legacy.thresholdsBPM)
    }

    func testCustomThresholdCoverageDoesNotFillSensorGaps() {
        let run = run(id: "r", distance: 1000)
        let settings = RunHeartRateZoneSettings(method: .enteredThresholds, maximumBPM: 190, thresholdsBPM: [110, 130, 150, 170])
        let samples = [(0.0, 130.0), (10, 130), (80, 170), (90, 170)].map {
            RunHeartRateSample(date: start.addingTimeInterval($0.0), bpm: $0.1, sourceID: "sensor", sourceName: "Watch")
        }
        let evidence = RunHeartRateEvidence.coverage(samples: samples, run: run, settings: settings)
        XCTAssertEqual(evidence.coveredSeconds, 20)
        XCTAssertEqual(evidence.zoneSeconds, [0, 0, 10, 0, 10])
    }

    func testPauseCorrectionPreservesRecoveryGapAndRejectsImportedUnknownOrAllPaused() {
        let gap = RunPauseInterval(startDate: start.addingTimeInterval(20), endDate: start.addingTimeInterval(30), origin: .recoveryGap)
        var original = run(id: "r", distance: 1000)
        original.pauseTimeline = RunPauseTimeline(completeness: .complete, intervals: [gap])
        original.movingSeconds = 90
        let pause = RunPauseInterval(startDate: start.addingTimeInterval(25), endDate: start.addingTimeInterval(40), origin: .explicitPause)
        let timeline = RunPauseTimeline(completeness: .complete, intervals: [gap, pause])
        XCTAssertEqual(RunPauseCorrectionRules.review(original: original, timeline: timeline)?.activeSeconds, 80)
        XCTAssertNil(RunPauseCorrectionRules.review(original: original, timeline: .init(completeness: .complete, intervals: [pause])))
        let all = RunPauseInterval(startDate: start, endDate: original.endDate, origin: .explicitPause)
        XCTAssertNil(RunPauseCorrectionRules.review(original: original, timeline: .init(completeness: .complete, intervals: [gap, all])))
        original.source = .imported(appName: "Watch")
        XCTAssertNil(RunPauseCorrectionRules.review(original: original, timeline: timeline))
        original.source = .recorded; original.pauseTimeline = .init(completeness: .partial)
        XCTAssertNil(RunPauseCorrectionRules.review(original: original, timeline: timeline))
    }

    func testComparisonsRequireEarlierSameContextAndExcludeCanonicalAliases() {
        let current = run(id: "current", distance: 5000)
        var good = run(id: "good", distance: 4100); good.startDate = start.addingTimeInterval(-86400)
        var indoor = run(id: "indoor", distance: 5000); indoor.startDate = good.startDate; indoor.isIndoor = true
        var short = run(id: "short", distance: 3000); short.startDate = good.startDate
        var structured = run(id: "structured", distance: 5000); structured.startDate = good.startDate
        structured.workoutResult = RunWorkoutResult(runID: structured.id, planID: "p", planName: "Intervals", completedAt: start, steps: [step(0, .hard), step(1, .recovery)])
        var alias = current.reidentified(as: "health-alias"); alias.startDate = good.startDate
        let future = run(id: "future", distance: 5000)
        XCTAssertEqual(RunComparisonRules.eligible(for: current, among: [good, indoor, short, structured, alias, future]).map(\.id), ["good"])
    }

    func testEasyComparisonRequiresExplicitCueAndDoesNotGuessFromSlowPace() {
        var easy = run(id: "easy", distance: 1000)
        var easyStep = step(0, .hard)
        easyStep.step.target = RunWorkoutTarget(cue: "Comfortable conversational effort")
        easy.workoutResult = RunWorkoutResult(runID: easy.id, planID: "plan", planName: "Easy", completedAt: start, steps: [easyStep])
        var hard = run(id: "hard", distance: 1000)
        var hardStep = easyStep; hardStep.step.target = RunWorkoutTarget(cue: "Not easy")
        hard.workoutResult = RunWorkoutResult(runID: hard.id, planID: "hard-plan", planName: "Hard", completedAt: start, steps: [hardStep])
        let unknown = run(id: "open", distance: 1000)
        XCTAssertEqual(RunComparisonRules.easyRuns([easy, hard, unknown]).map(\.id), ["easy"])
    }

    func testRouteOverlayNeverBridgesSegmentsAndRejectsTeleportOrLongGap() {
        func fix(_ seconds: Double, _ meters: Double) -> RunLocationFix {
            RunLocationFix(latitude: 0, longitude: meters / 111_195, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(seconds))
        }
        let segments = [[fix(0, 0), fix(10, 20), fix(20, 40)], [fix(80, 1000), fix(90, 1020), fix(100, 1040)]]
        let slices = RunRoutePaceOverlay.slices(segments)
        XCTAssertEqual(slices.count, 2)
        XCTAssertTrue(slices.allSatisfy { abs($0.secondsPerKm - 500) < 1 })
        XCTAssertEqual(slices[1].fixes.first?.timestamp, start.addingTimeInterval(80))
        XCTAssertTrue(RunRoutePaceOverlay.slices([[fix(0, 0), fix(10, 500), fix(40, 550)]]).isEmpty)
    }

    @MainActor
    func testCloudCorrectionRejectsMissingAndCrossAccountDiaryLinksWithoutChangingLocalEvidence() throws {
        let previousAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "runner"
        DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previousAuth }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("run-cloud-review-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunReviewStore(drafts: EditorDraftStore(directory: directory))
        let original = try XCTUnwrap(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 5000, movingSeconds: 1800, metric: true))
        let review = try store.review(run: original, mutation: .correctManual(distanceMeters: 5100, movingSeconds: 1860, reason: "Treadmill"), userID: "runner")
        let fingerprint = try PlanFingerprint.make(store.cloudSnapshot(userID: "runner"))
        func snapshot(_ reviewed: RunReviewStore.Review) throws -> [String: Data] {
            let receipt = RunReviewStore.Receipt(review: reviewed, acceptedAt: start)
            return ["receipt/" + receipt.id: try RunCloudCodec.encode(receipt), "head/" + reviewed.identity: try RunCloudCodec.encode(receipt.id)]
        }
        XCTAssertThrowsError(try store.applyCloudSnapshot(snapshot(review), expectedFingerprint: fingerprint, userID: "runner"))
        let healthID = UUID().uuidString
        let activity = LoggedExercise(id: healthID, name: "Run", durationMinutes: 30, caloriesBurned: 300, date: start, source: "HealthKit")
        var after = activity; after.durationMinutes = 31; after.hasLocalHealthKitEdits = true
        let link = RunDiaryCorrectionLink(healthID: healthID, day: try XCTUnwrap(DiaryDayContext(userID: "another-owner", date: start)),
            before: activity, after: after, estimateWeightLbs: 150, ownedPriorReceiptID: nil)
        XCTAssertThrowsError(try store.applyCloudSnapshot(snapshot(review.withDiaryCorrection(link)), expectedFingerprint: fingerprint, userID: "runner"))
        XCTAssertEqual(try store.projecting([original], userID: "runner"), [original])
        XCTAssertTrue(try store.latestReceipts(userID: "runner").isEmpty)
    }

    @MainActor
    func testCloudBlocksRejectInvalidCompletedEvidenceAndWeekBoundsBeforeAnyWrite() throws {
        let auth = MockAuthService(); auth.currentUserID = "runner"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("run-cloud-block-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunTrainingBlockStore(store: EditorDraftStore(directory: directory), auth: auth)
        let brief = RunTrainingBlockBrief(start: start, recentWeeklyMinutes: 60, recentLongestMinutes: 25)
        let block = try RunTrainingBlockRules.make(brief: brief, strengthDays: [], now: Calendar.current.startOfDay(for: start))
        let originalFingerprint = try PlanFingerprint.make(store.cloudSnapshot(userID: "runner"))
        var invalid = block
        invalid.slots[0].weekIndex = 99
        XCTAssertThrowsError(try store.applyCloudSnapshot(["block/" + invalid.id: RunCloudCodec.encode(invalid)], expectedFingerprint: originalFingerprint, userID: "runner"))
        invalid = block
        let context = RunScheduledContext(commitment: try XCTUnwrap(block.commitment(for: block.slots[0])))
        invalid.slots[0].outcome = RunBlockOutcome(state: .recorded, recordingID: "recording", runID: nil,
            acceptedAt: start.addingTimeInterval(1800), actualStart: start, movingSeconds: -1, distanceMeters: 5000, prescription: context)
        XCTAssertThrowsError(try store.applyCloudSnapshot(["block/" + invalid.id: RunCloudCodec.encode(invalid)], expectedFingerprint: originalFingerprint, userID: "runner"))
        XCTAssertTrue(try store.library(userID: "runner").blocks.isEmpty)
        try store.applyCloudSnapshot(["block/" + block.id: RunCloudCodec.encode(block)], expectedFingerprint: originalFingerprint, userID: "runner")
        XCTAssertEqual(try store.library(userID: "runner").blocks, [block])
    }

    private func run(id: String, distance: Double) -> Run {
        Run(id: id, source: .recorded, startDate: start, endDate: start.addingTimeInterval(100),
            distanceMeters: distance, movingSeconds: 100, pauseTimeline: .init(completeness: .complete), recordingID: id)
    }
    private func step(_ index: Int, _ kind: RunWorkoutStep.Kind, id: String? = nil) -> RunWorkoutStepResult {
        RunWorkoutStepResult(stepIndex: index, step: RunWorkoutStep(id: id ?? "s\(index)", kind: kind, title: "Step", goal: .duration(seconds: 10)),
            startedAtElapsedSeconds: Double(index * 10), endedAtElapsedSeconds: Double(index * 10 + 10),
            startedAtDistanceMeters: Double(index * 20), endedAtDistanceMeters: Double(index * 20 + 20), isComplete: true)
    }
}
