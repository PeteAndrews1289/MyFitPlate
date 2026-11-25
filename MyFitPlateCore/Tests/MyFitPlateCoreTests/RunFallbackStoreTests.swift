import XCTest
import CryptoKit
@testable import MyFitPlateCore

final class RunFallbackStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: RunFallbackStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "RunFallbackStoreTests")
        defaults.removePersistentDomain(forName: "RunFallbackStoreTests")
        store = RunFallbackStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "RunFallbackStoreTests")
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testFallbackRunIsAccountScopedAndDropsRouteClaim() {
        let run = Run(
            source: .recorded,
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 2_800),
            distanceMeters: 5_000,
            movingSeconds: 1_800,
            hasRoute: true
        )

        XCTAssertTrue(store.save(run, for: "first-user"))
        XCTAssertEqual(store.runs(since: .distantPast, for: "first-user").count, 1)
        XCTAssertFalse(store.runs(since: .distantPast, for: "first-user")[0].hasRoute)
        XCTAssertTrue(store.runs(since: .distantPast, for: "second-user").isEmpty)
    }

    func testFallbackSaveReplacesSameRunInsteadOfDuplicatingIt() {
        let run = Run(
            id: "run-1",
            source: .recorded,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1_800),
            distanceMeters: 5_000,
            movingSeconds: 1_800
        )

        XCTAssertTrue(store.save(run, for: "user"))
        XCTAssertTrue(store.save(run, for: "user"))
        XCTAssertEqual(store.runs(since: .distantPast, for: "user").count, 1)
    }

    private func recording(_ id: String = "recording") -> Run {
        Run(id: id, source: .recorded, startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 2_800), distanceMeters: 5_000, movingSeconds: 1_500,
            splits: [RunSplit(index: 1, distanceMeters: 1_000, seconds: 300)], hasRoute: true)
    }

    func testAtomicReopenAndHealthRenameRetainCompletionIdentityWithoutDuplicateHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = RunFallbackStore(directory: directory, legacyDefaults: defaults)
        XCTAssertTrue(fileStore.save(recording(), for: "owner"))
        XCTAssertTrue(fileStore.reidentify(id: "recording", as: "health-id", for: "owner"))
        let reopened = RunFallbackStore(directory: directory, legacyDefaults: defaults)
        XCTAssertTrue(reopened.containsRecording(id: "recording", for: "owner"))
        XCTAssertTrue(reopened.containsRecording(id: "health-id", for: "owner"))
        XCTAssertFalse(reopened.containsRecording(id: "recording", for: "other"))
        XCTAssertTrue(reopened.save(recording(), for: "owner"), "A stale completion cannot revive its original ID")
        let runs = reopened.runs(since: .distantPast, for: "owner")
        XCTAssertEqual(runs.map(\.id), ["health-id"])
        XCTAssertEqual(runs.first?.splits, recording().splits)
        XCTAssertFalse(try XCTUnwrap(runs.first).hasRoute)
        XCTAssertTrue(reopened.remove(id: "recording", for: "owner"))
        XCTAssertFalse(reopened.containsRecording(id: "health-id", for: "owner"))
    }

    func testLegacyCopyIsRemovedOnlyAfterAtomicReplacementSucceeds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = "run_fallback_" + SHA256.hash(data: Data("owner".utf8)).map { String(format: "%02x", $0) }.joined()
        let legacy = try JSONEncoder().encode([recording("old")])
        defaults.set(legacy, forKey: key)
        let blocked = directory.appendingPathComponent("blocked")
        try Data("kept".utf8).write(to: blocked)
        XCTAssertFalse(RunFallbackStore(directory: blocked, legacyDefaults: defaults).save(recording("new"), for: "owner"))
        XCTAssertEqual(defaults.data(forKey: key), legacy)
        let fileStore = RunFallbackStore(directory: directory, legacyDefaults: defaults)
        XCTAssertTrue(fileStore.save(recording("new"), for: "owner"))
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertEqual(Set(fileStore.runs(since: .distantPast, for: "owner").map(\.id)), ["old", "new"])
    }

    func testCorruptionAndNewerFormatBlockAutomaticOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = RunFallbackStore(directory: directory, legacyDefaults: defaults)
        XCTAssertTrue(fileStore.save(recording(), for: "owner"))
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: url)
        try Data("corrupt".utf8).write(to: url)
        XCTAssertFalse(fileStore.save(recording("new"), for: "owner"))
        XCTAssertEqual(try Data(contentsOf: url), Data("corrupt".utf8))
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        future["version"] = 2
        let futureData = try JSONSerialization.data(withJSONObject: future)
        try futureData.write(to: url)
        XCTAssertFalse(fileStore.save(recording("new"), for: "owner"))
        XCTAssertEqual(try Data(contentsOf: url), futureData)
    }

    func testNoSilentHundredRunCutoffAndAccountsRemainSeparate() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = RunFallbackStore(directory: directory, legacyDefaults: defaults)
        for index in 0..<105 { XCTAssertTrue(fileStore.save(recording("run-\(index)"), for: "owner")) }
        XCTAssertEqual(fileStore.runs(since: .distantPast, for: "owner").count, 105)
        XCTAssertTrue(fileStore.save(recording("other"), for: "other"))
        fileStore.clear(for: "owner")
        XCTAssertEqual(fileStore.runs(since: .distantPast, for: "other").map(\.id), ["other"])
    }

    func testUnavailableStorageAndInvalidMetricsCannotClaimSaved() {
        XCTAssertFalse(RunFallbackStore(directory: nil).save(recording(), for: "owner"))
        XCTAssertFalse(store.save(recording(), for: "  "))
        var invalid = recording()
        invalid.distanceMeters = .infinity
        XCTAssertFalse(store.save(invalid, for: "owner"))
        XCTAssertFalse(store.containsRecording(id: invalid.id, for: "owner"))
    }

    func testExactHealthIdentityRetainsLocalMetricsWhenHealthHasNoQuantities() {
        let local = recording("health-id")
        var imported = local
        imported.distanceMeters = 0
        imported.movingSeconds = 1_800
        imported.splits = []
        imported.hasRoute = false
        let merged = RunLocalHistoryRules.merging(healthRuns: [imported], localRuns: [local])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.distanceMeters, 5_000)
        XCTAssertEqual(merged.first?.movingSeconds, 1_500)
        XCTAssertEqual(merged.first?.splits, local.splits)
        XCTAssertFalse(merged.first?.hasRoute ?? true)
    }

    func testPauseTimelineSurvivesAtomicRenameAndHealthHistoryMerge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStore = RunFallbackStore(directory: directory, legacyDefaults: defaults)
        var local = recording()
        local.pauseTimeline = RunPauseTimeline(completeness: .complete, intervals: [
            RunPauseInterval(startDate: local.startDate.addingTimeInterval(300),
                             endDate: local.startDate.addingTimeInterval(600), origin: .explicitPause)
        ])
        XCTAssertTrue(fileStore.save(local, for: "owner"))
        XCTAssertTrue(fileStore.reidentify(id: local.id, as: "health-id", for: "owner"))
        let reopened = RunFallbackStore(directory: directory, legacyDefaults: defaults)
        let saved = try XCTUnwrap(reopened.runs(since: .distantPast, for: "owner").first)
        XCTAssertEqual(saved.pauseTimeline, local.pauseTimeline)
        XCTAssertTrue(reopened.containsRecording(id: local.id, for: "owner"))
        var health = saved
        health.pauseTimeline = nil
        health.movingSeconds = 1_800
        let merged = try XCTUnwrap(RunLocalHistoryRules.merging(healthRuns: [health], localRuns: [saved]).first)
        XCTAssertEqual(merged.id, "health-id")
        XCTAssertEqual(merged.movingSeconds, 1_500)
        XCTAssertEqual(merged.startDate, local.startDate)
        XCTAssertEqual(merged.endDate, local.endDate)
        XCTAssertEqual(merged.pauseTimeline, local.pauseTimeline)
    }

    func testInvalidCompletePauseTimelineCannotReplaceTheLastSavedRun() {
        let original = recording()
        XCTAssertTrue(store.save(original, for: "owner"))
        var invalid = original
        invalid.pauseTimeline = RunPauseTimeline(completeness: .complete)
        XCTAssertFalse(store.save(invalid, for: "owner"), "Missing measured pause intervals must not be invented")
        XCTAssertEqual(store.runs(since: .distantPast, for: "owner").first?.pauseTimeline, nil)
        XCTAssertEqual(store.runs(since: .distantPast, for: "owner").first?.movingSeconds, original.movingSeconds)
    }

    func testHealthRecordingMetadataRecoversLocalTimelineAfterUnreadableSave() throws {
        var local = recording("original-recording")
        local.recordingID = local.id
        local.pauseTimeline = RunPauseTimeline(completeness: .complete, intervals: [
            RunPauseInterval(startDate: local.startDate.addingTimeInterval(300),
                             endDate: local.startDate.addingTimeInterval(600), origin: .explicitPause)
        ])
        XCTAssertTrue(store.save(local, for: "owner"))
        var readableHealthRun = local.reidentified(as: "later-readable-health-uuid")
        readableHealthRun.pauseTimeline = nil
        readableHealthRun.splits = []
        readableHealthRun.activeCalories = 450
        let merged = RunLocalHistoryRules.merging(healthRuns: [readableHealthRun],
                                                localRuns: store.runs(since: .distantPast, for: "owner"))
        XCTAssertEqual(merged.count, 1)
        let restored = try XCTUnwrap(merged.first)
        XCTAssertEqual(restored.id, "later-readable-health-uuid")
        XCTAssertEqual(restored.recordingID, local.id)
        XCTAssertEqual(restored.pauseTimeline, local.pauseTimeline)
        XCTAssertEqual(restored.splits, local.splits)
        XCTAssertEqual(restored.movingSeconds, local.movingSeconds)
        XCTAssertTrue(store.runs(since: .distantPast, for: "another-owner").isEmpty)
    }

    func testPermanentAccountRemovalErasesOnlyCapturedOwnersRawFileAndLegacyFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("run-delete-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = RunFallbackStore(directory: root, legacyDefaults: defaults)
        XCTAssertTrue(disk.save(recording("first"), for: "first-owner"))
        XCTAssertTrue(disk.save(recording("second"), for: "second-owner"))
        try disk.removeAccountData(for: "first-owner")
        try disk.removeAccountData(for: "first-owner")
        XCTAssertTrue(disk.runs(since: .distantPast, for: "first-owner").isEmpty)
        XCTAssertEqual(disk.runs(since: .distantPast, for: "second-owner").map(\.id), ["second"])
        let unavailable = RunFallbackStore(directory: nil, legacyDefaults: defaults)
        XCTAssertThrowsError(try unavailable.removeAccountData(for: "first-owner"))
    }
}
