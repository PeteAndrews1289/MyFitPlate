import Foundation

/// Ordered, replayable document writes. IDs are allocated before acceptance, so retrying
/// a completed session or an offline program save cannot create a second document.
public struct WorkoutPendingWrite: Codable, Identifiable {
    public enum Collection: String, Codable {
        case programs = "workoutPrograms"
        case routines = "workoutRoutines"
        case sessions = "workoutSessionLogs"
    }

    public let id: String
    public let userID: String
    public let collection: Collection
    public let documentID: String
    public let payload: Data?
    /// Archive/restore changes only archive metadata; ordinary writes never clear it.
    public let programArchiveIntent: Bool?
    public let programProgressCommand: Data?

    public init<Value: Encodable>(userID: String, collection: Collection, documentID: String, value: Value, programArchiveIntent: Bool = false) throws {
        id = UUID().uuidString
        self.userID = userID
        self.collection = collection
        self.documentID = documentID
        payload = try JSONEncoder().encode(value)
        self.programArchiveIntent = programArchiveIntent ? true : nil
        programProgressCommand = nil
    }

    public init(progress command: WorkoutProgramProgressCommand, proposed: WorkoutProgram) throws {
        id = UUID().uuidString; userID = command.ownerID; collection = .programs; documentID = command.programID
        payload = try JSONEncoder().encode(proposed); programArchiveIntent = nil
        programProgressCommand = try JSONEncoder().encode(command)
    }

    public init(userID: String, deleting collection: Collection, documentID: String) {
        id = UUID().uuidString
        self.userID = userID
        self.collection = collection
        self.documentID = documentID
        payload = nil
        programArchiveIntent = nil
        programProgressCommand = nil
    }
}

public final class WorkoutOutbox: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func pending(userID: String) throws -> [WorkoutPendingWrite] {
        lock.lock()
        defer { lock.unlock() }
        return try read().filter { $0.userID == userID }
    }

    public func append(_ write: WorkoutPendingWrite) throws {
        lock.lock()
        defer { lock.unlock() }
        var writes = try read()
        guard !writes.contains(where: { $0.id == write.id }) else { return }
        writes.append(write)
        try persist(writes)
    }

    public func acknowledge(_ write: WorkoutPendingWrite) throws {
        lock.lock()
        defer { lock.unlock() }
        try persist(read().filter { $0.id != write.id })
    }

    public func removeAll(userID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try persist(read().filter { $0.userID != userID })
    }

    public func overlay<Value: Decodable>(
        _ values: [Value], userID: String, collection: WorkoutPendingWrite.Collection, id: (Value) -> String?
    ) throws -> [Value] {
        var result = values
        for write in try pending(userID: userID) where write.collection == collection {
            let existing = result.first { id($0) == write.documentID }
            if write.programProgressCommand != nil && existing == nil { continue }
            result.removeAll { id($0) == write.documentID }
            if let payload = write.payload {
                let decoded = try JSONDecoder().decode(Value.self, from: payload)
                if collection == .programs, let queued = decoded as? WorkoutProgram, let latest = existing as? WorkoutProgram {
                    var merged: WorkoutProgram
                    if let commandData = write.programProgressCommand {
                        let command = try JSONDecoder().decode(WorkoutProgramProgressCommand.self, from: commandData)
                        merged = try command.overlay(proposed: queued, on: latest)
                    } else { merged = write.programArchiveIntent == true ? latest : try WorkoutLibraryRules.mergingQueuedProgram(queued, with: latest) }
                    merged.archivedAt = write.programArchiveIntent == true ? queued.archivedAt : latest.archivedAt
                    guard let value = merged as? Value else { throw CocoaError(.coderInvalidValue) }
                    result.append(value)
                } else { result.append(decoded) }
            }
        }
        return result
    }

    private func read() throws -> [WorkoutPendingWrite] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([WorkoutPendingWrite].self, from: Data(contentsOf: fileURL))
    }

    private func persist(_ writes: [WorkoutPendingWrite]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(writes).write(to: fileURL, options: .atomic)
    }
}

public enum WorkoutSyncState: Equatable {
    case synced
    case pending(Int)
    case failed
}

public extension Notification.Name {
    static let workoutSyncStateChanged = Notification.Name("workoutSyncStateChanged")
}

/// A session remains a draft until history and the diary have both accepted it.
/// The completion payload is frozen before the first write and reused on retry.
public struct WorkoutSessionDraft: Codable {
    public var sessionID: String
    public var routine: WorkoutRoutine
    public var startedAt: Date
    public var updatedAt: Date
    public var elapsed: TimeInterval
    /// Optional so drafts saved before rest recovery continue to decode unchanged.
    public var rest: WorkoutRestState?
    public var completion: WorkoutSessionLog?
    public var diaryExercise: LoggedExercise?
    public var programContext: WorkoutProgramSessionContext?
    /// Missing only for older drafts whose launch origin was not recorded.
    public var programLinkDecision: WorkoutProgramLinkDecision?
    /// Last reviewed session-only target/setup change. Retained through recovery for conditional Undo.
    public var sessionToolsReceipt: StrengthSessionChange?
    public var sessionEdits: [WorkoutSessionEditReceipt]?
    public var selectedSetID: String?
    public private(set) var parkedExerciseIDs: [String]?

    public func navigationExercises(_ exercises: [RoutineExercise]) -> [RoutineExercise] {
        guard let parkedExerciseIDs, !parkedExerciseIDs.isEmpty else { return exercises }
        return exercises.map { original in
            guard parkedExerciseIDs.contains(original.id) else { return original }
            var exercise = original
            for i in exercise.sets.indices where !exercise.sets[i].isCompleted { exercise.sets[i].isDeferred = true }
            return exercise
        }
    }

    /// Parking changes only the draft's navigation. The template, set values,
    /// exercise groups, and separately deferred partner rounds keep their identity.
    public mutating func setParked(_ parked: Bool, exerciseID: String, currentSetID: String?) -> Bool {
        guard completion == nil,
              let exercise = routine.exercises.first(where: { $0.id == exerciseID }),
              exercise.sets.contains(where: { !$0.isCompleted }) else { return false }
        var ids = parkedExerciseIDs ?? []
        guard ids.contains(exerciseID) != parked else { return false }
        if parked { ids.append(exerciseID) } else { ids.removeAll { $0 == exerciseID } }
        parkedExerciseIDs = ids.isEmpty ? nil : ids
        let available = navigationExercises(routine.exercises)
        if !parked, let first = WorkoutSetNavigation.firstUnfinished(in: [exercise]) {
            selectedSetID = first.setID
        } else if let currentSetID, available.contains(where: { $0.sets.contains { $0.id == currentSetID && !$0.isCompleted && $0.isDeferred != true } }) {
            selectedSetID = currentSetID
        } else if let currentSetID {
            selectedSetID = WorkoutSetNavigation.nextAfterDeferring(setID: currentSetID, in: available)?.setID
                ?? WorkoutSetNavigation.firstUnfinished(in: available)?.setID
        } else {
            selectedSetID = WorkoutSetNavigation.firstUnfinished(in: available)?.setID
        }
        return true
    }

    public var needsProgramLinkReview: Bool { programContext == nil && programLinkDecision == nil }

    private enum CodingKeys: String, CodingKey {
        case sessionID, routine, startedAt, updatedAt, elapsed, rest, completion, diaryExercise, programContext, programLinkDecision, sessionToolsReceipt, sessionEdits, selectedSetID, parkedExerciseIDs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        routine = try values.decode(WorkoutRoutine.self, forKey: .routine)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        elapsed = try values.decode(TimeInterval.self, forKey: .elapsed)
        completion = try values.decodeIfPresent(WorkoutSessionLog.self, forKey: .completion)
        diaryExercise = try values.decodeIfPresent(LoggedExercise.self, forKey: .diaryExercise)
        programContext = try values.decodeIfPresent(WorkoutProgramSessionContext.self, forKey: .programContext)
        // Unknown optional metadata must not make completed sets unrecoverable.
        programLinkDecision = try? values.decodeIfPresent(WorkoutProgramLinkDecision.self, forKey: .programLinkDecision)
        sessionToolsReceipt = try? values.decodeIfPresent(StrengthSessionChange.self, forKey: .sessionToolsReceipt)
        sessionEdits = try? values.decodeIfPresent([WorkoutSessionEditReceipt].self, forKey: .sessionEdits)
        parkedExerciseIDs = try? values.decodeIfPresent([String].self, forKey: .parkedExerciseIDs)
        selectedSetID = try? values.decodeIfPresent(String.self, forKey: .selectedSetID)
        // Optional timer metadata must never make a valid set log impossible to recover.
        if completion == nil { rest = try? values.decodeIfPresent(WorkoutRestState.self, forKey: .rest) }
    }

    public init(routine: WorkoutRoutine, now: Date = Date(), programContext: WorkoutProgramSessionContext? = nil) {
        sessionID = UUID().uuidString
        self.routine = routine
        startedAt = now
        updatedAt = now
        elapsed = 0
        self.programContext = programContext
        programLinkDecision = programContext == nil ? .standalone : .program
    }

    /// An explicit decision may add provenance before freezing an older draft.
    /// Already-frozen completions can only be acknowledged as standalone, unchanged.
    @discardableResult
    public mutating func resolveLegacyProgramLink(_ context: WorkoutProgramSessionContext?) -> Bool {
        guard needsProgramLinkReview, completion == nil || context == nil else { return false }
        programContext = context
        programLinkDecision = context == nil ? .standalone : .program
        return true
    }

    public mutating func prepareCompletion(weightPounds: Double, now: Date = Date()) -> Bool {
        if completion != nil { rest = nil; return true }
        let exercises = routine.exercises.compactMap { exercise -> CompletedExercise? in
            let sets = exercise.sets.filter(\.isCompleted).map {
                CompletedSet(reps: $0.reps, weight: $0.weight, distance: $0.distance,
                             durationInSeconds: $0.durationInSeconds, setType: $0.resolvedSetType, effort: $0.effort)
            }
            return sets.isEmpty ? nil : CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: sets)
        }
        guard !exercises.isEmpty else { return false }
        completion = WorkoutSessionLog(id: sessionID, date: now, routineID: routine.id, completedExercises: exercises,
                                       programContext: programContext, programLinkDecision: programLinkDecision)
        rest = nil
        completion?.elapsedSeconds = elapsed
        completion?.projectionBodyWeightPounds = weightPounds.isFinite && weightPounds > 0 ? weightPounds : nil
        if let completed = completion {
            diaryExercise = WorkoutDiaryProjectionRules.make(log: completed, name: routine.name, elapsed: elapsed, weightPounds: weightPounds)
            completion?.generatedDiaryExercise = diaryExercise
        }

        return true
    }
}

public final class WorkoutDraftStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyFitPlate/workout-drafts")
    }

    public func load(userID: String) throws -> WorkoutSessionDraft? {
        let url = fileURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(WorkoutSessionDraft.self, from: Data(contentsOf: url))
    }

    public func save(_ draft: WorkoutSessionDraft, userID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: fileURL(userID: userID), options: .atomic)
    }

    /// Returns the resolved copy only after its explicit decision is durable.
    public func saveLegacyProgramLinkDecision(
        in draft: WorkoutSessionDraft, context: WorkoutProgramSessionContext?, userID: String
    ) throws -> WorkoutSessionDraft? {
        var resolved = draft
        guard resolved.resolveLegacyProgramLink(context) else { return nil }
        try save(resolved, userID: userID)
        return resolved
    }

    public func remove(userID: String) throws {
        let url = fileURL(userID: userID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func fileURL(userID: String) -> URL {
        let key = AccountScopedStorageKey.make(prefix: "workout-draft", userID: userID) ?? "signed-out"
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }
}
