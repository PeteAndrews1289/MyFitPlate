import CryptoKit
import Foundation

/// Completed metrics are committed locally before asynchronous Health writes. Raw route
/// coordinates are excluded; Apple Health remains the route store. Production storage
/// uses atomic account-scoped files and never silently prunes older sessions.
public final class RunFallbackStore: @unchecked Sendable {
    public static let shared = RunFallbackStore()
    private static let lock = NSLock()

    private enum Storage { case preferences, file(URL?) }
    private struct Snapshot: Codable {
        var version = 1
        var runs: [Run] = []
        var recordingAliases: [String: String] = [:]
    }
    private let defaults: UserDefaults
    private let storage: Storage

    public convenience init() {
        self.init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MyFitPlate/run-fallback", isDirectory: true))
    }

    /// Compatibility constructor for existing isolated preference stores. App recordings
    /// use the default atomic file-backed store instead.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        storage = .preferences
    }

    /// Explicit nil represents unavailable storage and cannot claim a successful save.
    public init(directory: URL?, legacyDefaults: UserDefaults = .standard) {
        defaults = legacyDefaults
        storage = .file(directory)
    }

    @discardableResult
    public func save(_ run: Run, for userID: String) -> Bool {
        guard validAccount(userID), Self.isValid(run), RunSaveReviewRules.canSave(run) else { return false }
        var localRun = run
        localRun.source = .recorded
        localRun.hasRoute = false
        localRun.recordingID = run.recordingID ?? run.id
        Self.lock.lock()
        defer { Self.lock.unlock() }
        do {
            var snapshot = try decodedSnapshot(for: userID)
            if let completedID = snapshot.recordingAliases[run.id] {
                return snapshot.runs.contains { $0.id == completedID }
            }
            let recordingID = localRun.recordingID ?? localRun.id
            // The initial local write can fail while Health succeeds. Its first
            // successful local copy then already has the Health UUID. Older copies
            // without an alias map must still reject a stale original-ID append.
            if let confirmed = snapshot.runs.first(where: { $0.id != recordingID && $0.recordingID == recordingID }),
               confirmed.id != localRun.id {
                // Ignore a stale original ID; a conflicting new Health UUID needs
                // explicit reconciliation rather than replacing an accepted alias.
                return localRun.id == recordingID
            }
            let replacedIDs = Set(snapshot.runs.filter { $0.id == localRun.id || ($0.recordingID ?? $0.id) == recordingID }.map(\.id))
            snapshot.runs.removeAll { $0.id == localRun.id || ($0.recordingID ?? $0.id) == recordingID }
            snapshot.runs.append(localRun)
            for key in snapshot.recordingAliases.keys where replacedIDs.contains(snapshot.recordingAliases[key] ?? "") {
                snapshot.recordingAliases[key] = localRun.id
            }
            if localRun.id != recordingID { snapshot.recordingAliases[recordingID] = localRun.id }
            try persist(snapshot, for: userID)
            return true
        } catch { return false }
    }

    public func runs(since: Date, for userID: String) -> [Run] {
        guard validAccount(userID) else { return [] }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return ((try? decodedSnapshot(for: userID).runs) ?? []).filter { $0.startDate >= since }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Recognizes a finished recording even after Health assigned a different UUID.
    /// Recovery can therefore remove an old checkpoint without reviving that run.
    public func containsRecording(id: String, for userID: String) -> Bool {
        guard validAccount(userID) else { return false }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let snapshot = try? decodedSnapshot(for: userID) else { return false }
        let resolved = snapshot.recordingAliases[id] ?? id
        return snapshot.runs.contains { $0.id == resolved || $0.recordingID == id }
    }

    /// Health write permission does not imply read permission. Retain exact local splits
    /// and moving duration under its confirmed identity instead of removing the backup.
    @discardableResult
    public func reidentify(id: String, as healthID: String, for userID: String) -> Bool {
        guard validAccount(userID), !healthID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        do {
            var snapshot = try decodedSnapshot(for: userID)
            let resolved = snapshot.recordingAliases[id] ?? id
            guard let original = snapshot.runs.first(where: { $0.id == resolved }) else { return false }
            let renamed = original.reidentified(as: healthID)
            snapshot.runs.removeAll { $0.id == resolved || $0.id == healthID }
            snapshot.runs.append(renamed)
            for key in snapshot.recordingAliases.keys where snapshot.recordingAliases[key] == resolved {
                snapshot.recordingAliases[key] = healthID
            }
            if id != healthID { snapshot.recordingAliases[id] = healthID }
            try persist(snapshot, for: userID)
            return true
        } catch { return false }
    }

    @discardableResult
    public func remove(id: String, for userID: String) -> Bool {
        guard validAccount(userID) else { return false }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        do {
            var snapshot = try decodedSnapshot(for: userID)
            let resolved = snapshot.recordingAliases[id] ?? id
            snapshot.runs.removeAll { $0.id == resolved }
            snapshot.recordingAliases = snapshot.recordingAliases.filter { $0.key != id && $0.value != resolved }
            try persist(snapshot, for: userID)
            return true
        } catch { return false }
    }

    public func clear(for userID: String) {
        guard validAccount(userID) else { return }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        // Empty atomic snapshots prevent legacy preferences from reappearing.
        try? persist(Snapshot(), for: userID)
    }

    /// Permanent account deletion: explicit raw-file removal also handles an unreadable snapshot.
    public func removeAccountData(for userID: String) throws {
        guard validAccount(userID) else { throw CocoaError(.fileWriteInvalidFileName) }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if case .file = storage {
            let url = try fileURL(for: userID)
            var isDirectory: ObjCBool = false
            let parent = url.deletingLastPathComponent().path
            if FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), !isDirectory.boolValue {
                throw CocoaError(.fileReadInvalidFileName)
            }
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        defaults.removeObject(forKey: storageKey(for: userID))
        guard defaults.object(forKey: storageKey(for: userID)) == nil else { throw CocoaError(.fileWriteUnknown) }
    }

    private func decodedSnapshot(for userID: String) throws -> Snapshot {
        let data: Data?
        switch storage {
        case .preferences:
            data = defaults.data(forKey: storageKey(for: userID))
        case .file:
            let url = try fileURL(for: userID)
            data = FileManager.default.fileExists(atPath: url.path)
                ? try Data(contentsOf: url) : defaults.data(forKey: storageKey(for: userID))
        }
        guard let data else { return Snapshot() }
        // Corruption blocks replacement writes, preserving the recoverable file.
        if let legacy = try? JSONDecoder().decode([Run].self, from: data) {
            return Snapshot(runs: legacy)
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        let identities = Set(snapshot.runs.map(\.id))
        guard snapshot.version == 1,
              snapshot.recordingAliases.values.allSatisfy({ identities.contains($0) }) else { throw CocoaError(.coderReadCorrupt) }
        return snapshot
    }

    private func persist(_ snapshot: Snapshot, for userID: String) throws {
        var sorted = snapshot
        sorted.runs.sort { $0.startDate > $1.startDate }
        let data = try JSONEncoder().encode(sorted)
        switch storage {
        case .preferences:
            defaults.set(data, forKey: storageKey(for: userID))
            guard defaults.data(forKey: storageKey(for: userID)) == data else { throw CocoaError(.fileWriteUnknown) }
        case .file:
            let url = try fileURL(for: userID)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
            defaults.removeObject(forKey: storageKey(for: userID))
        }
    }

    private func fileURL(for userID: String) throws -> URL {
        guard case .file(let directory) = storage, let directory, directory.isFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return directory.appendingPathComponent(storageKey(for: userID)).appendingPathExtension("json")
    }

    private func validAccount(_ userID: String) -> Bool { !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func storageKey(for userID: String) -> String {
        let digest = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "run_fallback_\(digest)"
    }

    static func isValid(_ run: Run) -> Bool {
        !run.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && run.startDate.timeIntervalSinceReferenceDate.isFinite && run.endDate.timeIntervalSinceReferenceDate.isFinite
            && run.endDate >= run.startDate && run.distanceMeters.isFinite && run.distanceMeters >= 0
            && run.movingSeconds.isFinite && run.movingSeconds >= 0
            && RunManualLap.valid(run.manualLaps ?? [], recordingID: run.recordingID ?? run.id, start: run.startDate,
                end: run.endDate, activeSeconds: run.movingSeconds, distanceMeters: run.distanceMeters)
            && (run.sensors?.isValid(recordingID: run.recordingID ?? run.id, startDate: run.startDate, endDate: run.endDate) ?? true)
            && (run.pauseTimeline.map {
                $0.validatedUnionIntervals(startDate: run.startDate, endDate: run.endDate,
                                          activeSeconds: run.movingSeconds) != nil
            } ?? true)
    }
}

public enum RunLocalHistoryRules {
    /// Reconcile exact Health identities first. An overlapping watch recording may
    /// suppress our Health quantities; keep local splits/time without a duplicate row.
    public static func merging(healthRuns: [Run], localRuns: [Run]) -> [Run] {
        var health = healthRuns
        var unmatched: [Run] = []
        for local in localRuns {
            guard let index = health.firstIndex(where: {
                $0.id == local.id || ($0.source == .recorded && $0.recordingID != nil
                    && $0.recordingID == (local.recordingID ?? local.id))
            }) else { unmatched.append(local); continue }
            if health[index].distanceMeters <= 0 { health[index].distanceMeters = local.distanceMeters }
            if local.movingSeconds > 0 { health[index].movingSeconds = local.movingSeconds }
            if !local.splits.isEmpty { health[index].splits = local.splits }
            if health[index].activeCalories == nil { health[index].activeCalories = local.activeCalories }
            if health[index].averageHeartRate == nil { health[index].averageHeartRate = local.averageHeartRate }
            if health[index].sensors == nil { health[index].sensors = local.sensors }
            if health[index].shoeID == nil { health[index].shoeID = local.shoeID }
            if let timeline = local.pauseTimeline { health[index].pauseTimeline = timeline }
            if health[index].recordingID == nil { health[index].recordingID = local.recordingID }
            if health[index].saveReview == nil { health[index].saveReview = local.saveReview }
            if let starts = local.routeSegmentStarts { health[index].routeSegmentStarts = starts }
            if let context = local.scheduledContext { health[index].scheduledContext = context }
            if let laps = local.manualLaps { health[index].manualLaps = laps }
            if var result = local.workoutResult {
                result.runID = health[index].id
                health[index].workoutResult = result
            }
        }
        return RunImportRules.deduplicated(health + unmatched)
    }
}
