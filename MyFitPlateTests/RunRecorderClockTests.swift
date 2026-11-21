import XCTest
import MyFitPlateCore
import CoreLocation
import ActivityKit
@testable import MyFitPlate

final class RunRecorderClockTests: XCTestCase {
    @MainActor
    func testFutureGPSFixCannotPoisonPauseOrFinishClock() {
        let now = Date(timeIntervalSince1970: 100_000)
        let recorder = RunRecorderViewModel(metric: true, currentDate: { now }, recordsLocation: false)
        let previousAudio = recorder.audioCoachEnabled
        recorder.audioCoachEnabled = false
        defer { recorder.discard(); recorder.audioCoachEnabled = previousAudio }
        recorder.begin()
        recorder.ingest(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -74),
                                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                   timestamp: now.addingTimeInterval(1)))
        XCTAssertNil(recorder.session.lastAcceptedFixTimestamp)
        recorder.pause()
        XCTAssertEqual(recorder.stage, .paused)
        XCTAssertEqual(recorder.session.state, .paused)
        XCTAssertNotNil(recorder.session.finish(at: now))
    }

    func testOlderRunActivityAttributesDecodeWithoutRecordingIdentity() throws {
        let previous = try JSONDecoder().decode(RunActivityAttributes.self, from: Data("{}".utf8))
        XCTAssertNil(previous.recordingID)
        let current = RunActivityAttributes(recordingID: "stable-recording")
        XCTAssertEqual(try JSONDecoder().decode(RunActivityAttributes.self,
                                               from: JSONEncoder().encode(current)).recordingID, "stable-recording")
    }

    @MainActor
    func testRecorderClockCatchesUpWithoutTimerCallbacksAndExcludesPause() {
        let previousAudio = UserDefaults.standard.object(forKey: "runAudioCoachEnabled")
        defer {
            if let previousAudio { UserDefaults.standard.set(previousAudio, forKey: "runAudioCoachEnabled") } else { UserDefaults.standard.removeObject(forKey: "runAudioCoachEnabled") }
        }
        var now = Date(timeIntervalSince1970: 100_000)
        let recorder = RunRecorderViewModel(metric: true, currentDate: { now }, recordsLocation: false)
        recorder.audioCoachEnabled = false
        defer { recorder.discard() }
        recorder.begin()
        XCTAssertEqual(recorder.stage, .running)
        now = now.addingTimeInterval(125)
        recorder.refreshAfterForeground()
        XCTAssertEqual(recorder.elapsedSeconds, 125)
        recorder.pause()
        now = now.addingTimeInterval(600)
        recorder.refreshAfterForeground()
        XCTAssertEqual(recorder.elapsedSeconds, 125)
        XCTAssertNil(recorder.currentPace)
        recorder.resume()
        now = now.addingTimeInterval(35)
        recorder.refreshAfterForeground()
        XCTAssertEqual(recorder.elapsedSeconds, 160)
        recorder.begin()
        XCTAssertEqual(recorder.elapsedSeconds, 160, "Duplicate start must not reset a running recording")
    }

    @MainActor
    func testBackgroundCatchUpAdvancesStructuredStepsAtTheirOriginalBoundaries() {
        let previousAudio = UserDefaults.standard.object(forKey: "runAudioCoachEnabled")
        defer {
            if let previousAudio { UserDefaults.standard.set(previousAudio, forKey: "runAudioCoachEnabled") } else { UserDefaults.standard.removeObject(forKey: "runAudioCoachEnabled") }
        }
        var now = Date(timeIntervalSince1970: 100_000)
        let plan = RunWorkoutPlan(name: "Clock test", subtitle: "Two steps", steps: [
            RunWorkoutStep(kind: .warmup, title: "Warm up", goal: .duration(seconds: 60)),
            RunWorkoutStep(kind: .hard, title: "Work", goal: .duration(seconds: 60))
        ])
        let recorder = RunRecorderViewModel(metric: true, workoutPlan: plan,
                                            currentDate: { now }, recordsLocation: false)
        recorder.audioCoachEnabled = false
        defer { recorder.discard() }
        recorder.begin()
        now = now.addingTimeInterval(90)
        recorder.refreshAfterForeground()
        XCTAssertEqual(recorder.workoutProgress?.currentStepIndex, 1)
        XCTAssertEqual(recorder.workoutProgress?.remainingSeconds, 30)
        recorder.pause()
        now = now.addingTimeInterval(120)
        recorder.refreshAfterForeground()
        XCTAssertEqual(recorder.workoutProgress?.remainingSeconds, 30)
        recorder.resume()
        now = now.addingTimeInterval(30)
        recorder.refreshAfterForeground()
        XCTAssertEqual(recorder.workoutProgress?.isWorkoutComplete, true)
        XCTAssertNil(recorder.nextWorkoutStep)
        XCTAssertEqual(recorder.stage, .running, "Reaching a goal must leave finishing under the runner's control")
        XCTAssertEqual(recorder.session.state, .running)
        recorder.pause()
        let completedElapsed = recorder.elapsedSeconds
        now = now.addingTimeInterval(120)
        recorder.refreshAfterForeground()
        XCTAssertEqual(recorder.stage, .paused)
        XCTAssertEqual(recorder.elapsedSeconds, completedElapsed)
        XCTAssertEqual(recorder.workoutProgress?.isWorkoutComplete, true)
    }
}
