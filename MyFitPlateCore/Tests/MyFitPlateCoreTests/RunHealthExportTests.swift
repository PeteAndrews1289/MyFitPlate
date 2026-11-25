import CoreLocation
import XCTest
@testable import MyFitPlateCore

final class RunHealthExportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!
    private var jobs: RunHealthExportJobStore!
    private var routes: RunRouteArchiveStore!
    private var fallback: RunFallbackStore!
    private var writer: Writer!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        jobs = RunHealthExportJobStore(directory: directory.appendingPathComponent("jobs"))
        routes = RunRouteArchiveStore(directory: directory.appendingPathComponent("routes"), now: { self.start.addingTimeInterval(20) })
        fallback = RunFallbackStore(directory: directory.appendingPathComponent("history"))
        writer = Writer()
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func recordedRun(id: String = "recording", hasRoute: Bool = false) -> Run {
        Run(id: id, source: .recorded, startDate: start, endDate: start.addingTimeInterval(10), distanceMeters: 10,
            movingSeconds: 10, hasRoute: hasRoute, recordingID: id, routeSegmentStarts: hasRoute ? [start] : nil)
    }
    private func coordinator() -> RunHealthExportCoordinator {
        RunHealthExportCoordinator(jobs: jobs, routes: routes, fallback: fallback, writer: writer)
    }
    private func retainRoute(for run: Run) throws {
        var route = RunRouteRecording(recordingID: run.recordingID!)
        route.append(RunLocationFix(latitude: 40, longitude: -74, horizontalAccuracy: 5, timestamp: start), startsNewSegment: true)
        route.append(RunLocationFix(latitude: 40.00001, longitude: -74, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(5)), startsNewSegment: false)
        try routes.save(route, run: run, userID: "owner")
    }

    func testRouteFailureAfterWorkoutSaveSurvivesRelaunchAndRepairsOnlyRoute() throws {
        let recorded = recordedRun(hasRoute: true)
        XCTAssertTrue(fallback.save(recorded, for: "owner"))
        try retainRoute(for: recorded)
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .savedRoutePending("health-id")) }
        XCTAssertEqual(try jobs.load(recordingID: recorded.id, userID: "owner")?.phase, .writingWorkout)
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .failed) }
        XCTAssertEqual(writer.workoutWrites, 1)
        writer.finish(.savedRoutePending("health-id"))
        XCTAssertEqual(try jobs.load(recordingID: recorded.id, userID: "owner")?.phase, .routeRetryRequired)
        coordinator().export(run: recorded, weightLbs: 200, userID: "owner") { XCTAssertEqual($0, .saved("health-id")) }
        XCTAssertEqual(writer.workoutWrites, 1)
        XCTAssertEqual(writer.routeWrites, 1)
        XCTAssertEqual(writer.locations.count, 2)
        writer.finish(.saved("health-id"))
        XCTAssertEqual(try jobs.load(recordingID: recorded.id, userID: "owner")?.phase, .complete)
        XCTAssertEqual(try jobs.load(recordingID: recorded.id, userID: "owner")?.weightLbs, 165)
        XCTAssertEqual(fallback.runs(since: .distantPast, for: "owner").count, 1)
        XCTAssertEqual(fallback.runs(since: .distantPast, for: "owner").first?.id, "health-id")
    }

    func testInterruptedWorkoutWriteOnlyReconcilesAndNeverAssumesEmptyHealthMeansSafeToDuplicate() throws {
        let recorded = recordedRun()
        let initial = try jobs.prepare(run: recorded, weightLbs: 165, expectsRoute: false, userID: "owner")
        _ = try jobs.update(initial, phase: .writingWorkout, userID: "owner")
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .confirmationRequired) }
        XCTAssertEqual(writer.reconciliations, 1)
        XCTAssertEqual(writer.workoutWrites, 0)
        writer.reconciledID = "known-health-id"
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .saved("known-health-id")) }
        XCTAssertEqual(writer.workoutWrites, 0)
        XCTAssertEqual(try jobs.load(recordingID: recorded.id, userID: "owner")?.phase, .complete)
    }

    func testUnreadableCommitCannotBecomeAnotherWorkoutAndMissingRouteCannotBecomeComplete() throws {
        let recorded = recordedRun(hasRoute: true)
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .savedAwaitingReadAccess) }
        writer.finish(.savedAwaitingReadAccess)
        writer.reconciledID = "confirmed-id"
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .savedRoutePending("confirmed-id")) }
        XCTAssertEqual(writer.workoutWrites, 1)
        XCTAssertEqual(writer.routeWrites, 0)
        XCTAssertEqual(try jobs.load(recordingID: recorded.id, userID: "owner")?.phase, .routeRetryRequired)
    }

    func testAccountDeletionDuringCallbackCannotResurrectExportJob() throws {
        let recorded = recordedRun()
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .confirmationRequired) }
        XCTAssertNil(try jobs.load(recordingID: recorded.id, userID: "other"))
        try jobs.removeAccountData(userID: "owner")
        writer.finish(.saved("confirmed-id"))
        XCTAssertNil(try jobs.load(recordingID: recorded.id, userID: "owner"))
        XCTAssertTrue(fallback.runs(since: .distantPast, for: "owner").isEmpty)
    }

    func testRetryKeepsFrozenMetricsAndChangedOriginalCannotReplaceIntent() throws {
        let recorded = recordedRun()
        coordinator().export(run: recorded, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .failed) }
        writer.finish(.failed)
        var changed = recorded
        changed.distanceMeters = 5_000
        coordinator().export(run: changed, weightLbs: 200, userID: "owner") { XCTAssertEqual($0, .failed) }
        XCTAssertEqual(writer.workoutWrites, 1)
        coordinator().export(run: recorded, weightLbs: 200, userID: "owner") { XCTAssertEqual($0, .saved("health-id")) }
        XCTAssertEqual(writer.workoutWrites, 2)
        XCTAssertEqual(writer.weights, [165, 165])
        writer.finish(.saved("health-id"))
    }

    private final class Writer: RunHealthSaving {
        var workoutWrites = 0
        var routeWrites = 0
        var reconciliations = 0
        var reconciledID: String?
        var locations: [CLLocation] = []
        var weights: [Double] = []
        var pending: [(RunHealthSaveOutcome) -> Void] = []
        func saveWithOutcome(run: Run, locations: [CLLocation], weightLbs: Double, completion: @escaping (RunHealthSaveOutcome) -> Void) {
            workoutWrites += 1; self.locations = locations; weights.append(weightLbs); pending.append(completion)
        }
        func reconcileRecording(recordingID: String, completion: @escaping (String?) -> Void) {
            reconciliations += 1; completion(reconciledID)
        }
        func repairRoute(run: Run, locations: [CLLocation], healthID: String, completion: @escaping (RunHealthSaveOutcome) -> Void) {
            routeWrites += 1; self.locations = locations; pending.append(completion)
        }
        func finish(_ outcome: RunHealthSaveOutcome) { pending.removeFirst()(outcome) }
    }
}
