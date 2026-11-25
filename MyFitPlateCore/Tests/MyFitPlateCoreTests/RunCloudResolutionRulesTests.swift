import XCTest
@testable import MyFitPlateCore

@MainActor final class RunCloudResolutionRulesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)
    private actor Repository: RunCloudRepository {
        var revisions: [String: RunCloudRevision] = [:]
        func fetch(userID: String, scope: RunCloudScope) async throws -> [RunCloudRevision] {
            revisions.values.filter { $0.ownerID == userID && $0.scope == scope }
        }
        func publish(_ revision: RunCloudRevision) async throws { revisions[revision.id] = revision }
    }
    @MainActor private final class Device {
        let directory: URL
        let store: RunTrainingBlockStore
        let auth: MockAuthService
        init() {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("run-resolution-" + UUID().uuidString)
            let account = MockAuthService(); account.currentUserID = "runner"
            directory = folder; auth = account
            store = RunTrainingBlockStore(store: EditorDraftStore(directory: folder), auth: account)
        }
        func engine(_ repository: RunCloudRepository) -> RunCloudSyncEngine {
            RunCloudSyncEngine(scope: .blocks, repository: repository, drafts: EditorDraftStore(directory: directory),
                currentOwner: { self.auth.currentUserID }, snapshot: { try self.store.cloudSnapshot(userID: $0) },
                apply: { try self.store.applyCloudSnapshot($0, expectedFingerprint: $1, userID: $2) })
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    func testTwoDevicesCannotPublishChoosingLocalMergeThatErasesOtherCompletedRun() async throws {
        let server = Repository(), one = Device(), two = Device()
        let block = try makeBlock()
        try one.store.applyCloudSnapshot(["block/" + block.id: RunCloudCodec.encode(block)],
            expectedFingerprint: PlanFingerprint.make([String: Data]()), userID: "runner")
        let first = one.engine(server), second = two.engine(server)
        await first.sync(); await second.sync()
        let context = try XCTUnwrap(block.commitment(for: block.slots[0])).withContext
        try one.store.recordCompleted(run: completed(context: context, id: "run-one"), userID: "runner", now: start.addingTimeInterval(900))
        try two.store.recordCompleted(run: completed(context: context, id: "run-two"), userID: "runner", now: start.addingTimeInterval(900))
        await first.sync(); await second.sync(); await first.sync()
        let conflict = try XCTUnwrap(first.conflicts.first { $0.key == "block/" + block.id })
        let local = try one.store.cloudSnapshot(userID: "runner")[conflict.key]
        let choice = try XCTUnwrap(conflict.versions.first { $0.payload == local })
        let before = try await server.fetch(userID: "runner", scope: .blocks)
        do { try await first.resolve(conflict, choosing: choice); XCTFail("An incompatible accepted outcome was resolved away") } catch { }
        let after = try await server.fetch(userID: "runner", scope: .blocks)
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(try one.store.library(userID: "runner").blocks[0].slots[0].outcome?.recordingID, "run-one")
        XCTAssertEqual(try two.store.library(userID: "runner").blocks[0].slots[0].outcome?.recordingID, "run-two")
        XCTAssertEqual(first.conflicts.first?.versions.count, 2)
        await second.sync()
        XCTAssertEqual(second.conflicts.first?.versions.count, 2, "The second device must retain a reviewable conflict")
    }

    func testRemoteAbandonmentRequiresExactImmutableReceiptAndPreservesRecordedOutcome() async throws {
        let server = Repository(), one = Device(), two = Device()
        let block = try makeBlock()
        try one.store.applyCloudSnapshot(["block/" + block.id: RunCloudCodec.encode(block)],
            expectedFingerprint: PlanFingerprint.make([String: Data]()), userID: "runner")
        let context = try XCTUnwrap(block.commitment(for: block.slots[0])).withContext
        try one.store.recordStarted(context: context, recordingID: "temporary", userID: "runner", now: start)
        let first = one.engine(server), second = two.engine(server)
        await first.sync(); await second.sync()
        XCTAssertEqual(try two.store.library(userID: "runner").blocks[0].slots[0].outcome?.state, .started)
        let startedSnapshot = try two.store.cloudSnapshot(userID: "runner")
        var unsupported = startedSnapshot
        var erased = try two.store.library(userID: "runner").blocks[0]
        var wrongReceipt = try XCTUnwrap(erased.slots[0].outcome)
        erased.slots[0].outcome = nil
        unsupported["block/" + block.id] = try RunCloudCodec.encode(erased)
        XCTAssertThrowsError(try two.store.applyCloudSnapshot(unsupported, expectedFingerprint: PlanFingerprint.make(startedSnapshot), userID: "runner"))
        wrongReceipt.state = .abandoned; wrongReceipt.recordingID = "another-recording"; wrongReceipt.acceptedAt = start.addingTimeInterval(30)
        unsupported["abandoned/" + (try PlanFingerprint.make(wrongReceipt))] = try RunCloudCodec.encode(wrongReceipt)
        XCTAssertThrowsError(try two.store.applyCloudSnapshot(unsupported, expectedFingerprint: PlanFingerprint.make(startedSnapshot), userID: "runner"))
        try one.store.recordAbandoned(context: context, recordingID: "temporary", userID: "runner", now: start.addingTimeInterval(30))
        await first.sync(); await second.sync()
        XCTAssertNil(try two.store.library(userID: "runner").blocks[0].slots[0].outcome)
        XCTAssertEqual(try two.store.library(userID: "runner").abandonedAttempts.count, 1)
        XCTAssertTrue(second.conflicts.isEmpty)
        try two.store.recordCompleted(run: completed(context: context, id: "real"), userID: "runner", now: start.addingTimeInterval(900))
        let snapshot = try two.store.cloudSnapshot(userID: "runner")
        let abandonedProjection = try one.store.cloudSnapshot(userID: "runner")
        XCTAssertThrowsError(try two.store.applyCloudSnapshot(abandonedProjection, expectedFingerprint: PlanFingerprint.make(snapshot), userID: "runner"))
        XCTAssertEqual(try two.store.library(userID: "runner").blocks[0].slots[0].outcome?.state, .recorded)
    }

    func testChoosingLocalReviewChainCannotDiscardOtherAcceptedAnnotation() throws {
        let run = Run(id: "import", source: .imported(appName: "Watch"), startDate: start, endDate: start.addingTimeInterval(900), distanceMeters: 3000, movingSeconds: 900)
        let identity = RunReviewStore.identity(run)
        func receipt(_ id: String, note: String) -> RunReviewStore.Receipt {
            .init(review: .init(operationID: id, userID: "runner", identity: identity, original: run, expectedReceiptID: nil,
                                mutation: .annotate(note: note), diaryCorrection: nil), acceptedAt: start)
        }
        let one = receipt("one", note: "First device"), two = receipt("two", note: "Second device")
        let first = try RunCloudRevision(ownerID: "runner", scope: .reviews, key: "head/" + identity, parents: [], payload: RunCloudCodec.encode(one.id))
        let second = try RunCloudRevision(ownerID: "runner", scope: .reviews, key: "head/" + identity, parents: [], payload: RunCloudCodec.encode(two.id))
        let records = try [one, two].map { try RunCloudRevision(ownerID: "runner", scope: .reviews, key: "receipt/" + $0.id, parents: [], payload: RunCloudCodec.encode($0)) }
        let known = Dictionary(uniqueKeysWithValues: ([first, second] + records).map { ($0.id, $0) })
        let conflict = RunCloudConflict(key: first.key, versions: [first, second])
        XCTAssertThrowsError(try RunCloudResolutionRules.validate(scope: .reviews, conflict: conflict, chosen: first, knownRevisions: known))
        XCTAssertThrowsError(try RunCloudResolutionRules.validate(scope: .reviews, conflict: conflict, chosen: second, knownRevisions: known))
    }

    func testUnselectedReviewBranchDoesNotRewriteProjectionOrTriggerAnotherSync() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let originalAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "runner"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = originalAuth; try? FileManager.default.removeItem(at: directory) }
        let store = RunReviewStore(drafts: EditorDraftStore(directory: directory))
        let run = Run(id: "import-noop", source: .imported(appName: "Watch"), startDate: start,
            endDate: start.addingTimeInterval(900), distanceMeters: 3000, movingSeconds: 900)
        let review = try store.review(run: run, mutation: .annotate(note: "Local note"), userID: "runner", operationID: "local")
        _ = try store.commit(review, currentUserID: "runner", now: start)
        let original = try store.cloudSnapshot(userID: "runner")
        let other = RunReviewStore.Receipt(review: .init(operationID: "other", userID: "runner",
            identity: RunReviewStore.identity(run), original: run, expectedReceiptID: nil,
            mutation: .annotate(note: "Other device"), diaryCorrection: nil), acceptedAt: start)
        var incoming = original; incoming["receipt/other"] = try RunCloudCodec.encode(other)
        let notification = expectation(description: "No save event for unchanged active review chain")
        notification.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: .runLibrariesChanged, object: nil, queue: nil) { event in
            if event.object as? String == "runner" { notification.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try store.applyCloudSnapshot(incoming, expectedFingerprint: PlanFingerprint.make(original), userID: "runner")
        try store.applyCloudSnapshot(incoming, expectedFingerprint: PlanFingerprint.make(original), userID: "runner")
        XCTAssertEqual(try store.cloudSnapshot(userID: "runner"), original)
        XCTAssertNil(try store.acceptedReceipt(operationID: "other", userID: "runner"))
        wait(for: [notification], timeout: 0.02)
    }

    private func makeBlock() throws -> RunTrainingBlock {
        try RunTrainingBlockRules.make(brief: .init(start: start, recentWeeklyMinutes: 60, recentLongestMinutes: 25), strengthDays: [], now: Calendar.current.startOfDay(for: start))
    }
    private func completed(context: RunScheduledContext, id: String) -> Run {
        Run(id: id, source: .recorded, startDate: start, endDate: start.addingTimeInterval(900), distanceMeters: 3000,
            movingSeconds: 900, recordingID: id, scheduledContext: context)
    }
}

private extension TrainingRunCommitment {
    var withContext: RunScheduledContext { RunScheduledContext(commitment: self) }
}
