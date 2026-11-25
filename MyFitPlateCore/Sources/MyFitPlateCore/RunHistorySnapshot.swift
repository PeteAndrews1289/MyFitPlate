import Foundation

public struct RunHistorySnapshot: Codable, Equatable {
    public let capturedAt: Date
    public let runs: [Run]
    public let isTruncated: Bool
}

/// A dated offline cache of the last available history scope. It never claims Health
/// read access is complete and never replaces primary saved runs or route checkpoints.
public final class RunHistorySnapshotStore {
    public static let maximumRuns = 10_000
    private let drafts: EditorDraftStore
    public init(directory: URL? = nil) { drafts = EditorDraftStore(directory: directory) }
    public func load(userID: String) throws -> RunHistorySnapshot? {
        let saved = try drafts.load(RunHistorySnapshot.self, userID: userID, scope: "run-history.available.v1")?.value
        guard let saved else { return nil }
        guard saved.capturedAt.timeIntervalSinceReferenceDate.isFinite, saved.runs.count <= Self.maximumRuns,
              saved.runs.allSatisfy(RunFallbackStore.isValid) else { throw CocoaError(.coderReadCorrupt) }
        return saved
    }
    public func save(_ runs: [Run], userID: String, now: Date = Date()) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite, runs.allSatisfy(RunFallbackStore.isValid) else { throw CocoaError(.coderInvalidValue) }
        let ordered = runs.sorted { $0.startDate > $1.startDate }
        let snapshot = RunHistorySnapshot(capturedAt: now, runs: Array(ordered.prefix(Self.maximumRuns)), isTruncated: runs.count > Self.maximumRuns)
        try drafts.save(snapshot, userID: userID, scope: "run-history.available.v1", now: now)
    }
}
