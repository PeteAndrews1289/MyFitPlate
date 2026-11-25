import Foundation

/// The original legacy structure is retained independently of the editor checkpoint.
/// Data freezes reference-type routines and their original identifiers.
public struct WorkoutLegacyMigrationRecord: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let userID: String
    public let programID: String
    public let recordedAt: Date
    public let acceptedStructureFingerprint: String
    public let originalPayload: Data
    public var restoredByOperationID: UUID?

    public init(original: WorkoutProgram, block: WorkoutProgramBlock, recordedAt: Date = Date()) throws {
        guard original.trainingBlock == nil, let programID = original.id else { throw WorkoutMigrationError.invalid }
        schemaVersion = 1; id = block.revisionID; userID = original.userID; self.programID = programID
        self.recordedAt = Date(timeIntervalSince1970: floor(recordedAt.timeIntervalSince1970 * 1000) / 1000)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        originalPayload = try encoder.encode(original)
        var accepted = original; accepted.trainingBlock = block
        acceptedStructureFingerprint = try WorkoutBlockRules.structureFingerprint(accepted)
        try validate()
    }

    public func original() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: originalPayload) }

    public func validate() throws {
        guard schemaVersion == 1, Self.validID(id), Self.validID(programID), Self.validID(userID),
              originalPayload.count <= 700_000, !acceptedStructureFingerprint.isEmpty else { throw WorkoutMigrationError.invalid }
        let source = try original()
        guard source.id == programID, source.userID == userID, source.trainingBlock == nil,
              !source.routines.isEmpty else { throw WorkoutMigrationError.invalid }
    }

    public var fingerprint: String {
        get throws {
            struct Identity: Encodable {
                let schemaVersion: Int
                let id: String
                let userID: String
                let programID: String
                let recordedMilliseconds: Int64
                let acceptedStructureFingerprint: String
                let originalPayload: Data
            }
            return try WorkoutBlockRules.fingerprint(Identity(schemaVersion: schemaVersion, id: id, userID: userID,
                programID: programID, recordedMilliseconds: Int64((recordedAt.timeIntervalSince1970 * 1000).rounded()),
                acceptedStructureFingerprint: acceptedStructureFingerprint, originalPayload: originalPayload))
        }
    }

    static func validID(_ value: String) -> Bool { !value.isEmpty && value.count <= 128 && !value.contains("/") }
}

public enum WorkoutMigrationError: Int, Error, LocalizedError, CustomNSError {
    case invalid = 400, accountChanged = 401, changed = 409, cancelled = 410, progressChanged = 412
    case alreadyRestored = 413, activeWorkout = 423, unavailable = 503
    public static var errorDomain: String { "MyFitPlate.LegacyMigration" }
    public var errorCode: Int { rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "Could not restore the original rotation."] }
    public var errorDescription: String? {
        switch self {
        case .invalid: "This original-program receipt could not be reviewed. Its saved data has been kept."
        case .accountChanged: "Return to the account that opened this review. Its pending request is kept."
        case .changed: "This program changed after adoption. Keep those changes, or review an independent copy of the original rotation."
        case .cancelled: "This restore request was cancelled. A late retry cannot change your program."
        case .progressChanged: "Program progress changed after this review. Reopen the review; performed sessions and logs are kept."
        case .alreadyRestored: "This original rotation was already restored. This receipt cannot restore it again."
        case .activeWorkout: "Finish or discard the workout linked to this program before restoring its original rotation."
        case .unavailable: "The restore could not be confirmed. Retry, check saved status, or cancel the pending request."
        }
    }
}

public struct WorkoutMigrationRollbackCommand: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let migration: WorkoutLegacyMigrationRecord
    private let expectedPayload: Data
    public var userID: String { migration.userID }
    public var programID: String { migration.programID }

    public init(migration: WorkoutLegacyMigrationRecord, expected: WorkoutProgram, id: UUID = UUID()) throws {
        schemaVersion = 1; self.id = id; self.migration = migration
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        expectedPayload = try encoder.encode(expected)
        try validate()
    }

    public func expected() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: expectedPayload) }
    public var fingerprint: String { get throws { try WorkoutBlockRules.fingerprint(self) } }
    public func validate() throws {
        try migration.validate()
        let expected = try expected()
        guard schemaVersion == 1, expectedPayload.count <= 700_000, expected.id == programID,
              expected.userID == userID, expected.trainingBlock?.revisionID == migration.id,
              try WorkoutBlockRules.structureFingerprint(expected) == migration.acceptedStructureFingerprint else {
            throw WorkoutMigrationError.changed
        }
        guard migration.restoredByOperationID == nil else { throw WorkoutMigrationError.alreadyRestored }
    }
}

public enum WorkoutMigrationRollbackResolution {
    case pending, cancelled
    case accepted(WorkoutProgram?)
}

public struct WorkoutMigrationRollbackReceipt: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case accepted, cancelled }
    public let id: UUID
    public let userID: String
    public let programID: String
    public let migrationID: String
    public let fingerprint: String
    public let status: Status

    public init(command: WorkoutMigrationRollbackCommand, status: Status) throws {
        id = command.id; userID = command.userID; programID = command.programID
        migrationID = command.migration.id; fingerprint = try command.fingerprint; self.status = status
    }
    public func validate(_ command: WorkoutMigrationRollbackCommand) throws {
        guard id == command.id, userID == command.userID, programID == command.programID,
              migrationID == command.migration.id, try fingerprint == command.fingerprint else { throw WorkoutMigrationError.changed }
    }
}

public enum WorkoutMigrationRollbackRules {
    public static func applying(_ command: WorkoutMigrationRollbackCommand, to latest: WorkoutProgram,
                                record: WorkoutLegacyMigrationRecord, protectedSlots: Set<Int> = []) throws -> WorkoutProgram {
        try command.validate(); try record.validate()
        guard latest.userID == command.userID, latest.id == command.programID else { throw WorkoutMigrationError.accountChanged }
        guard try record.fingerprint == command.migration.fingerprint else { throw WorkoutMigrationError.changed }
        guard record.restoredByOperationID == nil else { throw WorkoutMigrationError.alreadyRestored }
        guard protectedSlots.isEmpty else { throw WorkoutMigrationError.activeWorkout }
        let expected = try command.expected()
        guard try WorkoutBlockRules.structureFingerprint(latest) == record.acceptedStructureFingerprint else { throw WorkoutMigrationError.changed }
        // Review CAS includes progress, completion proofs and skips; ordinary progress
        // cannot be rewound by a late restore request.
        guard try WorkoutBlockRules.fingerprint(latest) == WorkoutBlockRules.fingerprint(expected) else { throw WorkoutMigrationError.progressChanged }
        var restored = latest; restored.trainingBlock = nil
        let original = try record.original()
        guard try WorkoutBlockRules.structureFingerprint(restored) == WorkoutBlockRules.structureFingerprint(original),
              (latest.currentProgressIndex ?? 0) >= 0, (latest.currentProgressIndex ?? 0) <= restored.totalSlots else { throw WorkoutMigrationError.changed }
        for slot in 0..<max(latest.currentProgressIndex ?? 0, 0) {
            guard let before = latest.routine(forSlot: slot), let after = restored.routine(forSlot: slot),
                  try WorkoutBlockRules.fingerprint(before) == WorkoutBlockRules.fingerprint(after),
                  latest.date(forSlot: slot) == restored.date(forSlot: slot) else { throw WorkoutMigrationError.progressChanged }
        }
        return restored
    }

    /// A separate draft is available even when current work makes rollback unsafe.
    /// It neither reactivates nor edits the source program or its history.
    public static func independentCopy(of record: WorkoutLegacyMigrationRecord, now: Date = Date()) throws -> WorkoutProgram {
        try record.validate()
        var copy = try record.original()
        copy.id = UUID().uuidString; copy.name += " · original copy"; copy.dateCreated = now
        copy.currentProgressIndex = 0; copy.skippedIndices = nil; copy.progressEpoch = copy.id
        copy.slotCompletionProofs = nil; copy.lastSkipReceipt = nil; copy.slotDateSnapshots = nil
        copy.weekRescue = nil; copy.lineage = nil; copy.archivedAt = nil
        copy.startDate = now; copy.scheduleAnchorDay = TrainingCalendarDay(now)
        for routine in copy.routines {
            for exerciseIndex in routine.exercises.indices {
                for setIndex in routine.exercises[exerciseIndex].sets.indices {
                    var set = routine.exercises[exerciseIndex].sets[setIndex]
                    set.isCompleted = false; set.reps = 0; set.weight = 0
                    set.distance = 0; set.durationInSeconds = 0; set.effort = nil
                    set.previousPerformance = nil; set.generatedWarmup = nil; set.isDeferred = nil; set.intervalTimer = nil
                    routine.exercises[exerciseIndex].sets[setIndex] = set
                }
            }
        }
        return copy
    }
}

/// One exact frozen request per program. Cleanup cannot discard a newer review.
public final class WorkoutMigrationRollbackDraftStore {
    private let store: EditorDraftStore
    private static let lock = NSRecursiveLock()
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public static func scope(programID: String) -> String { "workout-migration-rollback-\(programID)" }
    public func load(userID: String, programID: String) throws -> WorkoutMigrationRollbackCommand? {
        try Self.lock.withLock {
            let command = try store.load(WorkoutMigrationRollbackCommand.self, userID: userID, scope: Self.scope(programID: programID))?.value
            if let command {
                guard command.userID == userID, command.programID == programID else { throw WorkoutMigrationError.accountChanged }
                try command.validate()
            }
            return command
        }
    }
    public func freeze(_ command: WorkoutMigrationRollbackCommand) throws {
        try Self.lock.withLock {
            try command.validate()
            if let existing = try load(userID: command.userID, programID: command.programID) {
                guard try existing.fingerprint == command.fingerprint else { throw WorkoutMigrationError.changed }
                return
            }
            try store.save(command, userID: command.userID, scope: Self.scope(programID: command.programID))
        }
    }
    @discardableResult public func removeIfUnchanged(_ command: WorkoutMigrationRollbackCommand) throws -> Bool {
        try Self.lock.withLock {
            try store.removeIfUnchanged(WorkoutMigrationRollbackCommand.self, userID: command.userID,
                scope: Self.scope(programID: command.programID), fingerprint: PlanFingerprint.make(command))
        }
    }
}
