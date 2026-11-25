import XCTest
@testable import MyFitPlateCore

@MainActor final class RunCloudSyncTests: XCTestCase {
    @MainActor private final class Device {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var owner: String? = "a"
        var records: [String: Data] = [:]
        var applies = 0
        var protect = false
        var afterApply: (() -> Void)?
        func engine(_ repository: RunCloudRepository) -> RunCloudSyncEngine {
            RunCloudSyncEngine(scope: .workouts, repository: repository, drafts: EditorDraftStore(directory: folder),
                currentOwner: { self.owner }, snapshot: { _ in self.records }, apply: { values, expected, owner in
                    guard self.owner == owner else { throw RunCloudError.accountChanged }
                    guard try PlanFingerprint.make(self.records) == expected else { throw RunCloudError.changed }
                    if self.protect { throw RunCloudError.protectedEvidence }
                    self.records = values; self.applies += 1
                    self.afterApply?()
                })
        }
        deinit { try? FileManager.default.removeItem(at: folder) }
    }
    @MainActor private final class WorkoutDevice {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = UUID().uuidString
        let defaults: UserDefaults
        let auth = MockAuthService()
        let store: RunWorkoutPlanStore
        init() {
            defaults = UserDefaults(suiteName: suite)!
            auth.currentUserID = "a"
            store = RunWorkoutPlanStore(userDefaults: defaults, authService: auth)
        }
        func engine(_ repository: RunCloudRepository) -> RunCloudSyncEngine {
            RunCloudSyncEngine(scope: .workouts, repository: repository, drafts: EditorDraftStore(directory: folder),
                currentOwner: { self.auth.currentUserID }, snapshot: { try self.store.cloudSnapshot(userID: $0) },
                apply: { try self.store.applyCloudSnapshot($0, expectedFingerprint: $1, userID: $2) })
        }
        deinit {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private actor Repository: RunCloudRepository {
        var values: [String: RunCloudRevision] = [:]
        var fail = false
        var delay: UInt64 = 0
        func fetch(userID: String, scope: RunCloudScope) async throws -> [RunCloudRevision] {
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            if fail { throw URLError(.notConnectedToInternet) }
            return values.values.filter { $0.ownerID == userID && $0.scope == scope }
        }
        func publish(_ revision: RunCloudRevision) async throws {
            if fail { throw URLError(.notConnectedToInternet) }
            if let existing = values[revision.id], existing != revision { throw RunCloudError.invalid }
            var next = values; next[revision.id] = revision
            _ = try RunCloudGraph.validated(Array(next.values), ownerID: revision.ownerID, scope: revision.scope)
            values = next
        }
        func setFailure(_ value: Bool) { fail = value }
        func setDelay(_ value: UInt64) { delay = value }
    }
    private func data(_ text: String) -> Data { Data(text.utf8) }
    func testEmptyCloudPreservesLocalAndUnchangedSyncDoesNotPublishOrApplyAgain() async throws {
        let server = Repository(), device = Device()
        device.records = ["plan/one": data("original")]
        let sync = device.engine(server)
        await sync.sync()
        XCTAssertEqual(device.records["plan/one"], data("original")); XCTAssertEqual(device.applies, 0)
        await sync.sync()
        let records = try await server.fetch(userID: "a", scope: .workouts)
        XCTAssertEqual(records.count, 1); XCTAssertEqual(device.applies, 0); XCTAssertTrue(sync.conflicts.isEmpty)
        let restored = Device(); let second = restored.engine(server)
        await second.sync()
        XCTAssertEqual(restored.records, device.records); XCTAssertEqual(restored.applies, 1)
        await second.sync(); XCTAssertEqual(restored.applies, 1)
    }
    func testOfflineConcurrentEditsRemainVisibleUntilExactReviewedMerge() async throws {
        let server = Repository(), one = Device(), two = Device()
        one.records = ["plan/one": data("baseline")]
        let first = one.engine(server), second = two.engine(server)
        await first.sync(); await second.sync()
        one.records["plan/one"] = data("one")
        two.records["plan/one"] = data("two")
        await first.sync(); await second.sync(); await first.sync()
        XCTAssertEqual(one.records["plan/one"], data("one")); XCTAssertEqual(two.records["plan/one"], data("two"))
        let conflict = try XCTUnwrap(first.conflicts.first)
        XCTAssertEqual(conflict.versions.count, 2)
        try await first.resolve(conflict, choosing: XCTUnwrap(conflict.versions.first { $0.payload == data("one") }))
        XCTAssertTrue(first.conflicts.isEmpty)
        await second.sync(); XCTAssertEqual(two.records["plan/one"], data("one"))
        let history = try await server.fetch(userID: "a", scope: .workouts)
        XCTAssertEqual(history.count, 4, "The baseline, both branches and their reviewed merge remain immutable")
    }
    func testConcurrentWorkoutDeleteAndFavoriteStayOneReviewableConflictAndConvergeForEitherChoice() async throws {
        for keepFavorite in [true, false] {
            let server = Repository(), deleting = WorkoutDevice(), favoriting = WorkoutDevice()
            let plan = RunWorkoutPlan(id: "favorite-versus-delete", name: "Easy thirty", subtitle: "Conversational",
                steps: [.init(id: "easy", kind: .hard, title: "Easy run", goal: .duration(seconds: 1800))])
            let saved = try deleting.store.saveReviewed(plan, replacing: nil, operationID: "saved-original", userID: "a")
            let first = deleting.engine(server), second = favoriting.engine(server)
            await first.sync(); await second.sync()
            let baseline = try deleting.store.cloudSnapshot(userID: "a")
            let immutable = baseline.filter { $0.key.hasPrefix("revision/") || $0.key.hasPrefix("receipt/") }
            XCTAssertFalse(immutable.isEmpty)
            XCTAssertFalse(baseline.keys.contains { $0.hasPrefix("favorite/") })
            let record = try RunCloudCodec.decode(RunCloudWorkoutRecord.self, XCTUnwrap(baseline["plan/" + plan.id]))
            XCTAssertFalse(record.isFavorite)

            deleting.store.deletePlan(id: plan.id)
            try favoriting.store.setFavorite(plan, favorite: true, userID: "a")
            await first.sync(); await second.sync(); await first.sync()
            XCTAssertEqual(first.conflicts.count, 1); XCTAssertEqual(second.conflicts.count, 1)
            XCTAssertEqual(first.conflicts.first?.key, "plan/" + plan.id)
            XCTAssertTrue(deleting.store.customPlans.isEmpty)
            XCTAssertTrue(favoriting.store.isFavorite(id: plan.id))
            let conflict = try XCTUnwrap(second.conflicts.first)
            XCTAssertEqual(conflict.versions.count, 2)
            let chosen = try XCTUnwrap(conflict.versions.first { keepFavorite ? $0.payload != nil : $0.payload == nil })
            try await second.resolve(conflict, choosing: chosen)
            await first.sync(); await second.sync()
            XCTAssertTrue(first.conflicts.isEmpty); XCTAssertTrue(second.conflicts.isEmpty)
            XCTAssertNotNil(first.lastSyncedAt); XCTAssertNotNil(second.lastSyncedAt)
            XCTAssertEqual(deleting.store.customPlans.contains { $0.id == plan.id }, keepFavorite)
            XCTAssertEqual(favoriting.store.customPlans.contains { $0.id == plan.id }, keepFavorite)
            XCTAssertEqual(deleting.store.isFavorite(id: plan.id), keepFavorite)
            XCTAssertEqual(favoriting.store.isFavorite(id: plan.id), keepFavorite)
            for device in [deleting, favoriting] {
                let snapshot = try device.store.cloudSnapshot(userID: "a")
                XCTAssertEqual(snapshot.filter { $0.key.hasPrefix("revision/") || $0.key.hasPrefix("receipt/") }, immutable)
                XCTAssertEqual(device.store.revisions(forPlanID: plan.id).map(\.id), [saved.id])
            }
            let fresh = WorkoutDevice(), freshSync = fresh.engine(server)
            await freshSync.sync()
            XCTAssertEqual(fresh.store.customPlans.contains { $0.id == plan.id }, keepFavorite)
            XCTAssertEqual(fresh.store.isFavorite(id: plan.id), keepFavorite)
            XCTAssertTrue(freshSync.conflicts.isEmpty); XCTAssertNotNil(freshSync.lastSyncedAt)
        }
    }

    func testFailedNetworkKeepsPendingRevisionAcrossEngineRecreation() async throws {
        let server = Repository(), device = Device(); device.records["plan/one"] = data("kept")
        await server.setFailure(true)
        let first = device.engine(server); await first.sync()
        XCTAssertNil(first.lastSyncedAt); XCTAssertEqual(device.records["plan/one"], data("kept"))
        await server.setFailure(false)
        let recovered = device.engine(server); await recovered.sync()
        let remote = try await server.fetch(userID: "a", scope: .workouts)
        XCTAssertEqual(remote.count, 1); XCTAssertEqual(remote.first?.payload, data("kept"))
    }
    func testProtectedResolutionDoesNotPublishMergeOrReplaceAcceptedEvidence() async throws {
        let server = Repository(), one = Device(), two = Device()
        one.records["plan/one"] = data("base")
        let first = one.engine(server), second = two.engine(server)
        await first.sync(); await second.sync()
        one.records["plan/one"] = data("accepted-local"); two.records["plan/one"] = data("other")
        await first.sync(); await second.sync(); await first.sync()
        let conflict = try XCTUnwrap(first.conflicts.first)
        one.protect = true
        do { try await first.resolve(conflict, choosing: XCTUnwrap(conflict.versions.first { $0.payload == data("other") })); XCTFail("Protected projection was replaced") }
        catch { XCTAssertEqual(one.records["plan/one"], data("accepted-local")) }
        let remote = try await server.fetch(userID: "a", scope: .workouts)
        XCTAssertEqual(remote.count, 3)
    }
    func testAccountChangeWhileFetchingCannotProjectOldAccount() async throws {
        let server = Repository(), source = Device(), device = Device()
        source.records["plan/a"] = data("private")
        await source.engine(server).sync()
        await server.setDelay(20_000_000)
        let sync = device.engine(server)
        let task = Task { await sync.sync() }
        await Task.yield(); device.owner = "b"; sync.activate("b")
        await task.value
        XCTAssertTrue(device.records.isEmpty); XCTAssertNil(sync.lastSyncedAt)
    }
    func testProjectionCheckpointFailureRecoversWithoutFalseLocalBranch() async throws {
        let server = Repository(), source = Device(), device = Device()
        source.records["plan/one"] = data("remote")
        await source.engine(server).sync()
        var recovery: (URL, Data)?
        device.afterApply = {
            let files = FileManager.default.enumerator(at: device.folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
            guard let file = files.first(where: { $0.pathExtension == "json" }), let bytes = try? Data(contentsOf: file) else { return }
            recovery = (file, bytes)
            try? Data("unreadable after successful projection".utf8).write(to: file)
        }
        let sync = device.engine(server); await sync.sync()
        XCTAssertEqual(device.records["plan/one"], data("remote")); XCTAssertNil(sync.lastSyncedAt)
        let pending = try XCTUnwrap(recovery)
        try pending.1.write(to: pending.0); device.afterApply = nil
        let restored = device.engine(server); await restored.sync()
        XCTAssertNotNil(restored.lastSyncedAt); XCTAssertTrue(restored.conflicts.isEmpty)
        XCTAssertEqual(device.applies, 1)
        let remote = try await server.fetch(userID: "a", scope: .workouts)
        XCTAssertEqual(remote.count, 1, "Recovery must acknowledge the projected revision, not fork it")
    }
    func testReviewedMergeJournalRecoversAfterProjectionBeforeFinalCheckpoint() async throws {
        let server = Repository(), one = Device(), two = Device()
        one.records["plan/one"] = data("base")
        let first = one.engine(server), second = two.engine(server)
        await first.sync(); await second.sync()
        one.records["plan/one"] = data("local"); two.records["plan/one"] = data("remote")
        await first.sync(); await second.sync(); await first.sync()
        let conflict = try XCTUnwrap(first.conflicts.first)
        var recovery: (URL, Data)?
        one.afterApply = {
            let files = FileManager.default.enumerator(at: one.folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
            guard let file = files.first(where: { $0.pathExtension == "json" }), let bytes = try? Data(contentsOf: file) else { return }
            recovery = (file, bytes); try? Data("unreadable checkpoint".utf8).write(to: file)
        }
        do { try await first.resolve(conflict, choosing: XCTUnwrap(conflict.versions.first { $0.payload == data("remote") })); XCTFail("Final checkpoint failure should remain visible") } catch { }
        XCTAssertEqual(one.records["plan/one"], data("remote"))
        let pending = try XCTUnwrap(recovery); try pending.1.write(to: pending.0); one.afterApply = nil
        let recovered = one.engine(server); await recovered.sync()
        XCTAssertNotNil(recovered.lastSyncedAt); XCTAssertTrue(recovered.conflicts.isEmpty)
        let history = try await server.fetch(userID: "a", scope: .workouts)
        XCTAssertEqual(history.count, 4)
    }
    func testImmutableReceiptsCannotBecomeTombstonesOrBeRewrittenByAChild() throws {
        XCTAssertThrowsError(try RunCloudRevision(ownerID: "a", scope: .reviews, key: "receipt/one", parents: [], payload: nil))
        let original = try RunCloudRevision(ownerID: "a", scope: .reviews, key: "receipt/one", parents: [], payload: data("accepted"))
        let changed = try RunCloudRevision(ownerID: "a", scope: .reviews, key: "receipt/one", parents: [original.id], payload: data("rewritten"))
        XCTAssertThrowsError(try RunCloudGraph.validated([original, changed], ownerID: "a", scope: .reviews))
    }
    func testGraphRejectsWrongAccountMissingParentAndWrongItemParent() throws {
        let first = try RunCloudRevision(ownerID: "a", scope: .workouts, key: "plan/a", parents: [], payload: data("a"))
        let wrong = try RunCloudRevision(ownerID: "a", scope: .workouts, key: "plan/b", parents: [first.id], payload: data("b"))
        XCTAssertThrowsError(try RunCloudGraph.validated([first], ownerID: "b", scope: .workouts))
        XCTAssertThrowsError(try RunCloudGraph.validated([wrong], ownerID: "a", scope: .workouts))
        XCTAssertThrowsError(try RunCloudGraph.validated([first, wrong], ownerID: "a", scope: .workouts))
    }
}
