import CoreLocation
import XCTest
@testable import MyFitPlateCore

final class TreadmillRunSubmissionStoreTests: XCTestCase {
    private var directory: URL!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    override func setUp() { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    private func store() -> TreadmillRunSubmissionStore {
        TreadmillRunSubmissionStore(drafts: EditorDraftStore(directory: directory.appendingPathComponent("drafts")))
    }
    private func submission() throws -> TreadmillRunSubmission {
        let run = try XCTUnwrap(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 20,
            movingSeconds: 15, metric: true, activeCalories: 1.4, confirmShortRecording: true))
        return TreadmillRunSubmission(run: run, weightLbs: 165, metric: true,
            distanceInput: "0.02", minutesInput: "0", secondsInput: "15")
    }

    func testSubmittedShortRunRecoversExactReviewIdentityWeightAndEntryUnitsForOwningAccount() throws {
        let pending = try submission()
        try store().prepare(pending, userID: "owner")
        XCTAssertEqual(try store().load(userID: "owner"), pending)
        XCTAssertNil(try store().load(userID: "other"))
        try store().prepare(pending, userID: "owner")
        XCTAssertThrowsError(try store().prepare(submission(), userID: "owner"), "A new identity cannot replace a submitted save")
        XCTAssertEqual(try store().load(userID: "owner"), pending)
        XCTAssertTrue(try store().complete(pending, userID: "owner"))
        let next = try submission()
        try store().prepare(next, userID: "owner")
        XCTAssertFalse(try store().complete(pending, userID: "owner"), "Late completion cannot remove a newer submission")
        XCTAssertEqual(try store().load(userID: "owner"), next)
    }

    func testMalformedOrUnreviewedSubmissionsAndUnreadablePriorReceiptCannotBeOverwritten() throws {
        let pending = try submission()
        var invalid = pending.completion.run; invalid.saveReview = nil
        XCTAssertThrowsError(try store().prepare(TreadmillRunSubmission(run: invalid, weightLbs: 165,
            metric: true, distanceInput: "0.02", minutesInput: "0", secondsInput: "15"), userID: "owner"))
        invalid.saveReview = .shortRecording; invalid.movingSeconds = 0
        XCTAssertThrowsError(try store().prepare(TreadmillRunSubmission(run: invalid, weightLbs: 165,
            metric: true, distanceInput: "0.02", minutesInput: "0", secondsInput: "0"), userID: "owner"))
        let drafts = EditorDraftStore(directory: directory.appendingPathComponent("drafts"))
        try drafts.save("unreadable submitted record", userID: "owner", scope: TreadmillRunSubmissionStore.scope)
        XCTAssertThrowsError(try store().prepare(pending, userID: "owner"))
        XCTAssertEqual(try drafts.load(String.self, userID: "owner", scope: TreadmillRunSubmissionStore.scope)?.value, "unreadable submitted record")
    }

    func testFailedManualSaveRelaunchRetriesSameRecordingAndWeightThenKeepsSingleHealthAlias() throws {
        let pending = try submission()
        let jobs = RunHealthExportJobStore(directory: directory.appendingPathComponent("jobs"))
        let routes = RunRouteArchiveStore(directory: directory.appendingPathComponent("routes"))
        let unavailable = RunFallbackStore(directory: nil)
        let writer = Writer()
        try store().prepare(pending, userID: "owner")
        XCTAssertFalse(unavailable.save(pending.completion.run, for: "owner"))
        RunHealthExportCoordinator(jobs: jobs, routes: routes, fallback: unavailable, writer: writer)
            .export(run: pending.completion.run, weightLbs: pending.completion.weightLbs, userID: "owner") { XCTAssertEqual($0, .failed) }
        writer.finish(.failed)
        let recovered = try XCTUnwrap(store().load(userID: "owner"))
        XCTAssertEqual(recovered, pending)
        let fallback = RunFallbackStore(directory: directory.appendingPathComponent("history"))
        XCTAssertTrue(fallback.save(recovered.completion.run, for: "owner"))
        XCTAssertTrue(try store().complete(recovered, userID: "owner"))
        RunHealthExportCoordinator(jobs: jobs, routes: routes, fallback: fallback, writer: writer)
            .export(run: recovered.completion.run, weightLbs: 220, userID: "owner") { XCTAssertEqual($0, .saved("health-id")) }
        writer.finish(.saved("health-id"))
        XCTAssertEqual(writer.runs, [pending.completion.run, pending.completion.run])
        XCTAssertEqual(writer.weights, [165, 165])
        XCTAssertEqual(fallback.runs(since: .distantPast, for: "owner").map(\.id), ["health-id"])
        XCTAssertNil(try store().load(userID: "owner"))
    }

    func testManualUnreadableHealthSuccessRelaunchReconcilesExistingWriteWithoutSubmittingAgain() throws {
        let pending = try submission()
        let jobs = RunHealthExportJobStore(directory: directory.appendingPathComponent("jobs"))
        let routes = RunRouteArchiveStore(directory: directory.appendingPathComponent("routes"))
        let unavailable = RunFallbackStore(directory: nil)
        let writer = Writer()
        try store().prepare(pending, userID: "owner")
        RunHealthExportCoordinator(jobs: jobs, routes: routes, fallback: unavailable, writer: writer)
            .export(run: pending.completion.run, weightLbs: 165, userID: "owner") { XCTAssertEqual($0, .savedAwaitingReadAccess) }
        writer.finish(.savedAwaitingReadAccess)
        let recovered = try XCTUnwrap(store().load(userID: "owner"))
        RunHealthExportCoordinator(jobs: jobs, routes: routes, fallback: unavailable, writer: writer)
            .export(run: recovered.completion.run, weightLbs: 220, userID: "owner") { XCTAssertEqual($0, .savedAwaitingReadAccess) }
        XCTAssertEqual(writer.runs.count, 1)
        XCTAssertEqual(writer.reconciliations, 1)
        XCTAssertEqual(try store().load(userID: "owner"), pending)
        let fallback = RunFallbackStore(directory: directory.appendingPathComponent("history"))
        XCTAssertTrue(fallback.save(recovered.completion.run, for: "owner"))
        writer.reconciledID = "health-id"
        RunHealthExportCoordinator(jobs: jobs, routes: routes, fallback: fallback, writer: writer)
            .export(run: recovered.completion.run, weightLbs: 220, userID: "owner") { XCTAssertEqual($0, .saved("health-id")) }
        XCTAssertTrue(try store().complete(recovered, userID: "owner"))
        XCTAssertEqual(writer.runs.count, 1)
        XCTAssertEqual(fallback.runs(since: .distantPast, for: "owner").map(\.id), ["health-id"])
    }

    private final class Writer: RunHealthSaving {
        var runs: [Run] = []
        var weights: [Double] = []
        var reconciliations = 0
        var reconciledID: String?
        private var callbacks: [(RunHealthSaveOutcome) -> Void] = []
        func saveWithOutcome(run: Run, locations: [CLLocation], weightLbs: Double, completion: @escaping (RunHealthSaveOutcome) -> Void) {
            runs.append(run); weights.append(weightLbs); callbacks.append(completion)
        }
        func reconcileRecording(recordingID: String, completion: @escaping (String?) -> Void) {
            reconciliations += 1; completion(reconciledID)
        }
        func finish(_ outcome: RunHealthSaveOutcome) { callbacks.removeFirst()(outcome) }
    }
}
