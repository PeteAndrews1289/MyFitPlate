import CoreLocation
import Foundation

public protocol RunHealthSaving {
    func saveWithOutcome(run: Run, locations: [CLLocation], weightLbs: Double, completion: @escaping (RunHealthSaveOutcome) -> Void)
    func reconcileRecording(recordingID: String, completion: @escaping (String?) -> Void)
    func repairRoute(run: Run, locations: [CLLocation], healthID: String, completion: @escaping (RunHealthSaveOutcome) -> Void)
}

public extension RunHealthSaving {
    func reconcileRecording(recordingID: String, completion: @escaping (String?) -> Void) { completion(nil) }
    func repairRoute(run: Run, locations: [CLLocation], healthID: String, completion: @escaping (RunHealthSaveOutcome) -> Void) {
        completion(.savedRoutePending(healthID))
    }
}

public struct RunHealthExportJob: Codable, Equatable {
    public enum Phase: String, Codable {
        case queued, writingWorkout, workoutRetryRequired, awaitingWorkoutConfirmation
        case writingRoute, routeRetryRequired, complete
    }
    public let run: Run
    public let weightLbs: Double
    public let expectsRoute: Bool
    public var phase: Phase
    public var healthID: String?
    public var revision: Int
    public var updatedAt: Date
    public var recordingID: String { run.recordingID ?? run.id }

    public var statusText: String {
        switch phase {
        case .queued: return "Saved in MyFitPlate. Ready to sync with Apple Health."
        case .writingWorkout, .awaitingWorkoutConfirmation:
            return "Saved in MyFitPlate. Checking Apple Health before any further write."
        case .workoutRetryRequired: return "Saved in MyFitPlate. Apple Health sync needs another attempt."
        case .writingRoute, .routeRetryRequired:
            return "Workout saved to Apple Health. Its route still needs confirmation."
        case .complete: return "Saved to Apple Health."
        }
    }
}

/// A durable stage receipt contains no coordinates. A write-in-progress never becomes
/// a new write merely because the process restarted. Account deletion removes receipts.
public final class RunHealthExportJobStore {
    private static let lock = NSLock()
    private let directory: URL?
    private struct Envelope: Codable { let version: Int; let job: RunHealthExportJob }

    public convenience init() {
        self.init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MyFitPlate/run-health-export", isDirectory: true))
    }
    public init(directory: URL?) { self.directory = directory }

    public func load(recordingID: String, userID: String) throws -> RunHealthExportJob? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try read(fileURL(recordingID: recordingID, userID: userID))
    }

    public func prepare(run: Run, weightLbs: Double, expectsRoute: Bool, userID: String) throws -> RunHealthExportJob {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard RunFallbackStore.isValid(run), RunSaveReviewRules.canSave(run), run.source == .recorded,
              weightLbs.isFinite, weightLbs > 0 else { throw CocoaError(.coderInvalidValue) }
        let file = try fileURL(recordingID: run.recordingID ?? run.id, userID: userID)
        if let existing = try read(file) {
            guard existing.run.startDate == run.startDate, existing.run.endDate == run.endDate,
                  existing.run.distanceMeters == run.distanceMeters, existing.run.movingSeconds == run.movingSeconds else {
                throw CocoaError(.fileWriteFileExists)
            }
            return existing
        }
        let job = RunHealthExportJob(run: run, weightLbs: weightLbs, expectsRoute: expectsRoute,
                                    phase: .queued, revision: 0, updatedAt: Date())
        try write(job, file: file)
        return job
    }

    public func update(_ job: RunHealthExportJob, phase: RunHealthExportJob.Phase, healthID: String? = nil, userID: String) throws -> RunHealthExportJob {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let file = try fileURL(recordingID: job.recordingID, userID: userID)
        guard let current = try read(file), current.revision == job.revision, current == job else { throw CocoaError(.fileWriteNoPermission) }
        var next = current
        next.phase = phase
        next.healthID = healthID ?? current.healthID
        next.revision += 1
        next.updatedAt = Date()
        try write(next, file: file)
        return next
    }

    public func removeAccountData(userID: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let account = try accountURL(userID)
        if FileManager.default.fileExists(atPath: account.path) { try FileManager.default.removeItem(at: account) }
    }

    private func read(_ file: URL) throws -> RunHealthExportJob? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let envelope = try JSONDecoder().decode(Envelope.self, from: RunRouteFileProtection.read(file))
        guard envelope.version == 1,
              let expectedKey = AccountScopedStorageKey.make(prefix: "recording", userID: envelope.job.recordingID),
              file.deletingPathExtension().lastPathComponent == expectedKey,
              RunFallbackStore.isValid(envelope.job.run), envelope.job.revision >= 0,
              envelope.job.weightLbs.isFinite, envelope.job.weightLbs > 0 else { throw CocoaError(.coderReadCorrupt) }
        return envelope.job
    }
    private func write(_ job: RunHealthExportJob, file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunRouteFileProtection.excludeFromBackup(file.deletingLastPathComponent())
        try RunRouteFileProtection.write(JSONEncoder().encode(Envelope(version: 1, job: job)), to: file)
    }
    private func accountURL(_ userID: String) throws -> URL {
        guard let directory, directory.isFileURL, let key = AccountScopedStorageKey.make(prefix: "exports", userID: userID) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return directory.appendingPathComponent(key, isDirectory: true)
    }
    private func fileURL(recordingID: String, userID: String) throws -> URL {
        guard let key = AccountScopedStorageKey.make(prefix: "recording", userID: recordingID) else { throw CocoaError(.fileWriteNoPermission) }
        return try accountURL(userID).appendingPathComponent(key).appendingPathExtension("json")
    }
}

/// Persists the intent before invoking Health. A recovered uncertain write only queries
/// for its stable recording identity. Route repair never writes another workout.
public final class RunHealthExportCoordinator {
    private static let lock = NSLock()
    private static var inFlight: Set<String> = []
    private let jobs: RunHealthExportJobStore
    private let routes: RunRouteArchiveStore
    private let fallback: RunFallbackStore
    private let writer: RunHealthSaving

    public init(jobs: RunHealthExportJobStore = RunHealthExportJobStore(), routes: RunRouteArchiveStore = RunRouteArchiveStore(),
                fallback: RunFallbackStore = .shared, writer: RunHealthSaving = RunRecorderStore()) {
        self.jobs = jobs; self.routes = routes; self.fallback = fallback; self.writer = writer
    }

    public func export(run: Run, weightLbs: Double, userID: String, locations: [CLLocation]? = nil,
                       completion: @escaping (RunHealthSaveOutcome) -> Void) {
        let key = userID + ":" + (run.recordingID ?? run.id)
        Self.lock.lock()
        let acquired = Self.inFlight.insert(key).inserted
        Self.lock.unlock()
        guard acquired else { completion(.failed); return }
        let finish: (RunHealthSaveOutcome) -> Void = { outcome in
            Self.lock.lock(); Self.inFlight.remove(key); Self.lock.unlock()
            completion(outcome)
        }
        do {
            let job = try jobs.prepare(run: run, weightLbs: weightLbs,
                                       expectsRoute: run.hasRoute, userID: userID)
            let retained = try? routes.load(recordingID: job.recordingID, userID: userID)
            let points = locations ?? retained?.segments.flatMap { $0 }.map {
                CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), altitude: 0,
                           horizontalAccuracy: $0.horizontalAccuracy, verticalAccuracy: -1, timestamp: $0.timestamp)
            } ?? []
            resume(job, userID: userID, locations: points, completion: finish)
        } catch { finish(.failed) }
    }

    private func resume(_ job: RunHealthExportJob, userID: String, locations: [CLLocation],
                        completion: @escaping (RunHealthSaveOutcome) -> Void) {
        switch job.phase {
        case .complete:
            completion(job.healthID.map(RunHealthSaveOutcome.saved) ?? .confirmationRequired)
        case .writingWorkout, .awaitingWorkoutConfirmation:
            writer.reconcileRecording(recordingID: job.recordingID) { [self] healthID in
                guard let healthID else {
                    completion(job.phase == .awaitingWorkoutConfirmation ? .savedAwaitingReadAccess : .confirmationRequired)
                    return
                }
                do {
                    let confirmed = try jobs.update(job, phase: job.expectsRoute ? .routeRetryRequired : .complete, healthID: healthID, userID: userID)
                    _ = fallback.reidentify(id: job.run.id, as: healthID, for: userID)
                    resume(confirmed, userID: userID, locations: locations, completion: completion)
                } catch { completion(.confirmationRequired) }
            }
        case .writingRoute, .routeRetryRequired:
            guard let healthID = job.healthID, !locations.isEmpty || !job.expectsRoute else {
                completion(job.healthID.map(RunHealthSaveOutcome.savedRoutePending) ?? .confirmationRequired)
                return
            }
            do {
                let writing = try jobs.update(job, phase: .writingRoute, userID: userID)
                writer.repairRoute(run: job.run, locations: locations, healthID: healthID) { [self] outcome in
                    accept(outcome, job: writing, userID: userID, completion: completion)
                }
            } catch { completion(.savedRoutePending(healthID)) }
        case .queued, .workoutRetryRequired:
            do {
                let writing = try jobs.update(job, phase: .writingWorkout, userID: userID)
                writer.saveWithOutcome(run: job.run, locations: locations, weightLbs: job.weightLbs) { [self] outcome in
                    if case .saved(let id) = outcome, job.expectsRoute, locations.isEmpty {
                        accept(.savedRoutePending(id), job: writing, userID: userID, completion: completion)
                    } else {
                        accept(outcome, job: writing, userID: userID, completion: completion)
                    }
                }
            } catch { completion(.failed) }
        }
    }

    private func accept(_ outcome: RunHealthSaveOutcome, job: RunHealthExportJob, userID: String,
                        completion: @escaping (RunHealthSaveOutcome) -> Void) {
        let phase: RunHealthExportJob.Phase
        let healthID: String?
        switch outcome {
        case .saved(let id): phase = .complete; healthID = id
        case .savedRoutePending(let id): phase = .routeRetryRequired; healthID = id
        case .savedAwaitingReadAccess: phase = .awaitingWorkoutConfirmation; healthID = nil
        case .confirmationRequired: phase = .writingWorkout; healthID = nil
        case .failed: phase = job.healthID == nil ? .workoutRetryRequired : .routeRetryRequired; healthID = job.healthID
        }
        do {
            _ = try jobs.update(job, phase: phase, healthID: healthID, userID: userID)
            if let healthID { _ = fallback.reidentify(id: job.run.id, as: healthID, for: userID) }
            completion(outcome)
        } catch {
            // The confirmed operation may outlive a local write failure or account
            // deletion. Never reconstruct a deleted job or invite a new workout write.
            completion(job.healthID.map(RunHealthSaveOutcome.savedRoutePending) ?? .confirmationRequired)
        }
    }
}
