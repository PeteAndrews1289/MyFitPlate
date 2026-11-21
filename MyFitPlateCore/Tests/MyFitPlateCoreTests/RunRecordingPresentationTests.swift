import XCTest
@testable import MyFitPlateCore

final class RunRecordingPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testSignalRequiresFreshValidCoordinatesAndAccuracy() {
        XCTAssertEqual(RunGPSSignal.evaluate(fix: nil, at: now), .acquiring)
        XCTAssertEqual(RunGPSSignal.evaluate(fix: nil, at: now, hasError: true), .lost)
        XCTAssertEqual(signal(accuracy: 10), .ready)
        XCTAssertEqual(signal(accuracy: 30), .ready)
        XCTAssertEqual(signal(accuracy: 31), .weak)
        XCTAssertEqual(signal(accuracy: -1), .weak)
        XCTAssertEqual(signal(accuracy: .nan), .weak)
        XCTAssertEqual(signal(age: 21), .lost)
        XCTAssertEqual(signal(age: -3), .lost)
        let invalid = RunLocationFix(latitude: 91, longitude: 0, horizontalAccuracy: 10, timestamp: now)
        XCTAssertEqual(RunGPSSignal.evaluate(fix: invalid, at: now), .weak)
        XCTAssertFalse(RunGPSSignal.lost.detail.isEmpty)
        for signal in [RunGPSSignal.acquiring, .ready, .weak, .lost] {
            XCTAssertFalse(signal.title.isEmpty)
            XCTAssertFalse(signal.detail.isEmpty)
        }
    }

    func testPaceFeedbackWaitsForSignalAndUsesInclusiveCanonicalRange() {
        let target = RunWorkoutTarget(fastestSecondsPerKm: 300, slowestSecondsPerKm: 360)
        func feedback(_ pace: Double?, seconds: Double = 20, meters: Double = 25) -> RunPaceGuidance? {
            RunPaceGuidance.evaluate(target: target, paceSecondsPerKm: pace,
                                     stepElapsedSeconds: seconds, stepDistanceMeters: meters)
        }
        XCTAssertEqual(feedback(330, seconds: 19), .settling)
        XCTAssertEqual(feedback(330, meters: 24), .settling)
        XCTAssertEqual(feedback(nil), .settling)
        XCTAssertEqual(feedback(.nan), .settling)
        XCTAssertEqual(feedback(299), .fasterThanTarget)
        XCTAssertEqual(feedback(300), .onTarget)
        XCTAssertEqual(feedback(360), .onTarget)
        XCTAssertEqual(feedback(361), .slowerThanTarget)
        XCTAssertNil(RunPaceGuidance.evaluate(target: nil, paceSecondsPerKm: 330,
                                            stepElapsedSeconds: 60, stepDistanceMeters: 100))
        let reversed = RunWorkoutTarget(fastestSecondsPerKm: 360, slowestSecondsPerKm: 300)
        XCTAssertNil(RunPaceGuidance.evaluate(target: reversed, paceSecondsPerKm: 330,
                                            stepElapsedSeconds: 60, stepDistanceMeters: 100))
        for guidance in [RunPaceGuidance.settling, .onTarget, .fasterThanTarget, .slowerThanTarget] {
            XCTAssertFalse(guidance.title.isEmpty)
        }
    }

    private func signal(accuracy: Double = 10, age: Double = 0) -> RunGPSSignal {
        RunGPSSignal.evaluate(fix: RunLocationFix(latitude: 40, longitude: -74,
                                                horizontalAccuracy: accuracy,
                                                timestamp: now.addingTimeInterval(-age)), at: now)
    }
}
