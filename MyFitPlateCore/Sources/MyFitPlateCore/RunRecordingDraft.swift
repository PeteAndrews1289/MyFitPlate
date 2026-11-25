import Foundation

/// Totals and accepted route evidence commit as one atomic checkpoint. Legacy drafts
/// have no route. Restoring deliberately pauses until the runner explicitly resumes.
public struct RunRecordingDraft: Codable, Equatable {
    public let session: RunSession.Snapshot
    public let workout: RunWorkoutTracker.Snapshot?
    public let updatedAt: Date
    public let route: RunRouteRecording?
    public let sensors: RunSensorCheckpoint?
    public let scheduledContext: RunScheduledContext?
    public let pendingCompletion: RunRecordingCompletion?
    public internal(set) var recoveredPreviousCheckpoint = false

    private enum CodingKeys: String, CodingKey { case session, workout, updatedAt, route, scheduledContext, sensors, pendingCompletion }

    public init(session: RunSession.Snapshot, workout: RunWorkoutTracker.Snapshot? = nil, updatedAt: Date = Date(),
                route: RunRouteRecording? = nil, scheduledContext: RunScheduledContext? = nil, sensors: RunSensorCheckpoint? = nil,
                pendingCompletion: RunRecordingCompletion? = nil) {
        self.sensors = sensors
        self.session = session
        self.workout = workout
        self.updatedAt = updatedAt
        self.route = route
        self.scheduledContext = scheduledContext
        self.pendingCompletion = pendingCompletion
    }

    fileprivate var isValid: Bool {
        guard updatedAt.timeIntervalSinceReferenceDate.isFinite, updatedAt >= session.recordedAt,
              RunSession(snapshot: session, at: updatedAt) != nil else { return false }
        if let pending = pendingCompletion {
            guard pending.weightLbs.isFinite, pending.weightLbs > 0,
                  RunFallbackStore.isValid(pending.run), RunSaveReviewRules.canSave(pending.run),
                  pending.run.source == .recorded, pending.run.saveReview != nil,
                  (pending.run.recordingID ?? pending.run.id) == session.id,
                  pending.run.startDate == session.startDate, pending.run.endDate == session.recordedAt,
                  abs(pending.run.movingSeconds - session.movingSeconds) < 0.001,
                  abs(pending.run.distanceMeters - session.distanceMeters) < 0.01,
                  pending.run.scheduledContext == scheduledContext,
                  pending.run.sensors == sensors else { return false }
        }
        if let sensors, !sensors.isValid(recordingID: session.id, startDate: session.startDate, endDate: session.recordedAt) { return false }
        if let route {
            guard route.recordingID == session.id, route.isValid(startDate: session.startDate, endDate: session.recordedAt) else { return false }
        }
        if let scheduledContext, scheduledContext.plan != workout?.plan { return false }
        guard let workout else { return true }
        return RunWorkoutTracker(snapshot: workout) != nil
            && workout.observedElapsedSeconds <= session.activeElapsedSeconds + 0.001
            && workout.observedDistanceMeters <= session.distanceMeters + 0.01
    }
}

public final class RunRecordingDraftStore {
    private struct Envelope: Codable {
        let version: Int
        let value: RunRecordingDraft
        let checksum: String?
    }

    private static let lock = NSLock()
    private let directory: URL?

    public convenience init() {
        self.init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MyFitPlate/run-recording-drafts", isDirectory: true))
    }

    public init(directory: URL?) { self.directory = directory }

    public func load(userID: String) throws -> RunRecordingDraft? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try read(userID: userID)
    }

    public func save(_ draft: RunRecordingDraft, userID: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard draft.isValid else { throw CocoaError(.coderInvalidValue) }
        if let previous = try read(userID: userID) {
            guard previous.session.id == draft.session.id else { throw CocoaError(.fileWriteFileExists) }
            if let pending = previous.pendingCompletion, draft.pendingCompletion != pending {
                throw CocoaError(.fileWriteNoPermission)
            }
            if let priorSensors = previous.sensors {
                guard let nextSensors = draft.sensors,
                      Array(nextSensors.heartRate.prefix(priorSensors.heartRate.count)) == priorSensors.heartRate,
                      Array(nextSensors.cadence.prefix(priorSensors.cadence.count)) == priorSensors.cadence else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            guard draft.updatedAt >= previous.updatedAt,
                  draft.session.distanceMeters + 0.01 >= previous.session.distanceMeters,
                  draft.session.activeElapsedSeconds + 0.001 >= previous.session.activeElapsedSeconds,
                  (draft.route?.acceptedSequence ?? 0) >= (previous.route?.acceptedSequence ?? 0) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let url = try fileURL(userID: userID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunRouteFileProtection.excludeFromBackup(url.deletingLastPathComponent())
        // The last verified generation is independent of the new atomic replacement.
        // A truncated new checkpoint can recover its matching prior totals and route.
        if let prior = try? readEnvelope(url) {
            try RunRouteFileProtection.write(JSONEncoder().encode(prior), to: previousURL(url))
        }
        let envelope = Envelope(version: 2, value: draft, checksum: try RunRouteFileProtection.checksum(draft))
        try RunRouteFileProtection.write(JSONEncoder().encode(envelope), to: url)
    }

    /// Supplying the captured session ID prevents a late save callback from removing
    /// another recording that began while the earlier Health request was in flight.
    public func remove(userID: String, sessionID: String? = nil) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let url = try fileURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: previousURL(url).path) else { return }
        if let sessionID {
            guard try read(userID: userID)?.session.id == sessionID else { throw CocoaError(.fileWriteNoPermission) }
        }
        for file in [url, previousURL(url)] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func read(userID: String) throws -> RunRecordingDraft? {
        let url = try fileURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: previousURL(url).path) else { return nil }
        do {
            return try readEnvelope(url).value
        } catch {
            // A future format is never rolled back or overwritten by this app version.
            if let data = try? RunRouteFileProtection.read(url),
               let version = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let number = version["version"] as? Int, number > 2 { throw error }
            guard var previous = try? readEnvelope(previousURL(url)).value else { throw error }
            previous.recoveredPreviousCheckpoint = true
            return previous
        }
    }

    private func readEnvelope(_ url: URL) throws -> Envelope {
        let saved = try JSONDecoder().decode(Envelope.self, from: RunRouteFileProtection.read(url))
        guard [1, 2].contains(saved.version), saved.value.isValid else { throw CocoaError(.coderReadCorrupt) }
        if saved.version == 2 {
            guard saved.checksum == (try RunRouteFileProtection.checksum(saved.value)) else { throw CocoaError(.coderReadCorrupt) }
        } else if saved.value.route != nil { throw CocoaError(.coderReadCorrupt) }
        return saved
    }

    private func previousURL(_ url: URL) -> URL { url.appendingPathExtension("previous") }

    private func fileURL(userID: String) throws -> URL {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let key = AccountScopedStorageKey.make(prefix: "run", userID: userID),
              let directory, directory.isFileURL else { throw CocoaError(.fileWriteNoPermission) }
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }
}
