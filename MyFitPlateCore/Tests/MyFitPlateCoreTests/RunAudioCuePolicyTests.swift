import XCTest
@testable import MyFitPlateCore

final class RunAudioCuePolicyTests: XCTestCase {
    private let target = RunWorkoutTarget(fastestSecondsPerKm: 300, slowestSecondsPerKm: 330)

    func testPromptsNeedSustainedFreshEvidenceAndRespectCooldown() {
        var policy = RunAudioCuePolicy()
        XCTAssertNil(evaluate(&policy, time: 30, pace: 350))
        XCTAssertNil(evaluate(&policy, time: 44, pace: 350))
        XCTAssertEqual(evaluate(&policy, time: 45, pace: 350), .gentlyQuicker)
        XCTAssertNil(evaluate(&policy, time: 60, pace: 350))
        XCTAssertNil(evaluate(&policy, time: 134, pace: 350))
        XCTAssertEqual(evaluate(&policy, time: 135, pace: 350), .gentlyQuicker)
    }

    func testDeadBandPauseAndStepChangeDoNotSpeakOldCandidate() {
        var policy = RunAudioCuePolicy()
        XCTAssertNil(evaluate(&policy, time: 30, pace: 335))
        XCTAssertNil(evaluate(&policy, time: 60, pace: 335))
        XCTAssertNil(evaluate(&policy, time: 70, pace: 280))
        XCTAssertNil(evaluate(&policy, time: 90, pace: 280, running: false))
        XCTAssertNil(evaluate(&policy, time: 100, pace: 280))
        XCTAssertNil(evaluate(&policy, time: 120, pace: 280, step: "new"))
        XCTAssertEqual(evaluate(&policy, time: 135, pace: 280, step: "new"), .easeBack)
    }

    func testUnavailableEvidenceExplainsOnceWithoutInventingPace() {
        var policy = RunAudioCuePolicy()
        XCTAssertEqual(evaluate(&policy, time: 30, pace: nil, fresh: false), .paceUnavailable)
        XCTAssertNil(evaluate(&policy, time: 60, pace: nil, fresh: false))
        XCTAssertNil(evaluate(&policy, time: 80, pace: 315))
        XCTAssertEqual(evaluate(&policy, time: 90, pace: .infinity), .paceUnavailable)
        XCTAssertNil(evaluate(&policy, time: 120, pace: .infinity))
    }

    private func evaluate(_ policy: inout RunAudioCuePolicy, time: Double, pace: Double?,
                          running: Bool = true, fresh: Bool = true, step: String = "step") -> RunAudioCuePolicy.Cue? {
        policy.evaluate(stepID: step, target: target, pace: pace, activeSeconds: time,
                        stepSeconds: time, stepMeters: 100, isRunning: running, hasFreshSignal: fresh)
    }
}
