#if DEBUG
import Foundation
import Combine

public enum MockWorkoutRepositoryError: Error, Equatable {
    case resultNotConfigured
}

public final class MockWorkoutRepository: WorkoutRepositoryProtocol, @unchecked Sendable {
    public var mockFetchSessionLogResult: Result<WorkoutSessionLog, Error>?
    public var mockFetchSessionLogsResult: [WorkoutSessionLog] = []
    public var mockFetchRecentSessionLogsResult: [WorkoutSessionLog] = []
    public var fetchRecentSessionLogsError: Error?
    public var mockSaveProgramResult: WorkoutProgram?
    public var beforeCorrectionCommit: (() -> Void)?
    private let correctionLock = NSRecursiveLock()
    public var savedRoutines: [WorkoutRoutine] = []
    public var savedSessionLogs: [WorkoutSessionLog] = []
    private var storedSessionsByOwner: [String: [String: WorkoutSessionLog]] = [:]
    public var savedInsights: [[String: Any]] = []

    public var mockFetchHistoryResult: [WorkoutSessionLog] = []
    public var mockFetchPreviousPerformanceResult: CompletedExercise?

    public init() {}
    public func fetchWorkoutSessionLog(userID: String, sessionID: String) async throws -> WorkoutSessionLog {
        try correctionLock.withLock { try session(userID: userID, id: sessionID) }
    }
    private func session(userID: String, id: String) throws -> WorkoutSessionLog {
        if let result = mockFetchSessionLogResult { return try result.get() }
        guard let saved = storedSessionsByOwner[userID]?[id] else { throw MockWorkoutRepositoryError.resultNotConfigured }
        return saved
    }
    private func storedSessions(userID: String) -> [WorkoutSessionLog] {
        correctionLock.withLock { storedSessionsByOwner[userID].map { Array($0.values) } ?? [] }
    }
    public func fetchSessionLogs(userID: String, routineIDs: [String]) async throws -> [WorkoutSessionLog] { return mockFetchSessionLogsResult }
    public func fetchRecentSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog] {
        if let fetchRecentSessionLogsError { throw fetchRecentSessionLogsError }
        let since = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date()) ?? .distantPast
        let written = storedSessions(userID: userID).filter { $0.date >= since }.sorted { $0.date > $1.date }
        return WorkoutSetMath.uniqueSessions(written + mockFetchRecentSessionLogsResult)
    }
    public var onProgramsSnapshotListenerAdded: ((String, @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Void)?
    public var onProgramLibraryListenerAdded: ((String, @escaping (Result<WorkoutLibrarySnapshot<WorkoutProgram>, Error>) -> Void) -> Void)?
    public func addProgramLibraryListener(userID: String, onUpdate: @escaping (Result<WorkoutLibrarySnapshot<WorkoutProgram>, Error>) -> Void) -> Any {
        if let onProgramLibraryListenerAdded {
            onProgramLibraryListenerAdded(userID, onUpdate)
            return UUID()
        }
        return addProgramsSnapshotListener(userID: userID) { onUpdate($0.map { WorkoutLibrarySnapshot(values: $0) }) }
    }
    public func addProgramsSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Any {
        onProgramsSnapshotListenerAdded?(userID, onUpdate)
        return UUID()
    }
    public var onRoutinesSnapshotListenerAdded: ((String, @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Void)?
    public func addRoutinesSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Any {
        onRoutinesSnapshotListenerAdded?(userID, onUpdate)
        return UUID()
    }
    public var removeListenerCalledCount = 0
    public func removeListener(_ handle: Any) {
        removeListenerCalledCount += 1
    }
    public var saveProgramError: Error?
    public var progressReceipts: [String: WorkoutProgramProgressOperationReceipt] = [:]
    public var progressCommands: [WorkoutProgramProgressCommand] = []
    public func pendingProgramProgress(userID: String, programID: String) throws -> [WorkoutProgramProgressCommand] { [] }
    public func enqueueProgramProgress(userID: String, command: WorkoutProgramProgressCommand, locallyVerifiedLogs: [WorkoutSessionLog]) async throws -> WorkoutProgram {
        try correctionLock.withLock {
            guard command.ownerID == userID else { throw WorkoutBlockError.accountChanged }
            let key = "\(userID):\(command.id)"
            let expected = try command.expected()
            if let stored = progressReceipts[key] {
                guard stored.fingerprint == (try command.fingerprint()) else { throw WorkoutBlockError.changed }
                if stored.status == .cancelled { throw WorkoutBlockError.cancelled }
                guard !deletedProgramIDs.contains(command.programID) else { throw WorkoutBlockError.unavailable }
                return committedBlockPrograms.first { $0.id == command.programID } ?? mockSaveProgramResult ?? expected
            }
            guard !deletedProgramIDs.contains(command.programID) else { throw WorkoutBlockError.unavailable }
            if let saveProgramError { throw saveProgramError }
            let latest = committedBlockPrograms.first { $0.id == command.programID } ?? mockSaveProgramResult ?? expected
            let updated = try command.applying(to: latest, verifiedLogs: locallyVerifiedLogs, trustStoredProofsForLocalProjection: command.kind == .completion)
            committedBlockPrograms.removeAll { $0.id == command.programID }; committedBlockPrograms.append(updated)
            progressCommands.append(command)
            progressReceipts[key] = WorkoutProgramProgressOperationReceipt(id: command.id, fingerprint: try command.fingerprint(), programID: command.programID, status: .accepted)
            return updated
        }
    }
    public func resolveProgramProgress(userID: String, command: WorkoutProgramProgressCommand, cancelPending: Bool) async throws -> WorkoutProgramProgressResolution {
        try correctionLock.withLock {
            guard command.ownerID == userID else { throw WorkoutBlockError.accountChanged }
            let key = "\(userID):\(command.id)"
            let current = deletedProgramIDs.contains(command.programID) ? nil : committedBlockPrograms.first { $0.id == command.programID } ?? mockSaveProgramResult
            if let stored = progressReceipts[key] {
                guard stored.fingerprint == (try command.fingerprint()) else { throw WorkoutBlockError.changed }
                return stored.status == .accepted ? .accepted(current) : .cancelled(current)
            }
            if cancelPending {
                guard command.kind != .completion else { throw WorkoutBlockError.invalid }
                progressReceipts[key] = WorkoutProgramProgressOperationReceipt(id: command.id, fingerprint: try command.fingerprint(), programID: command.programID, status: .cancelled)
                return .cancelled(current)
            }
            return .pending
        }
    }
    public var programEditReceipts: [String: WorkoutProgramEditOperationReceipt] = [:]
    public var beforeProgramEditCommit: (() -> Void)?
    /// Opt-in fixture hook for the canonical listener event emitted by the real repository after a checked save.
    public var afterProgramEditCommit: ((WorkoutProgram?) -> Void)?
    public var programEditFailureAfterCommit: Error?
    public func commitProgramEdit(userID: String, command: WorkoutProgramEditCommand) async throws -> WorkoutProgram? {
        let result: WorkoutProgram? = try correctionLock.withLock {
            guard command.ownerID == userID else { throw WorkoutBlockError.accountChanged }
            let key = "\(userID):\(command.id)"
            if let receipt = programEditReceipts[key] {
                guard receipt.fingerprint == (try command.fingerprint()) else { throw WorkoutBlockError.changed }
                if receipt.status == .cancelled { throw WorkoutBlockError.cancelled }
                return deletedProgramIDs.contains(command.programID) ? nil : committedBlockPrograms.first { $0.id == command.programID } ?? mockSaveProgramResult
            }
            beforeProgramEditCommit?()
            if let saveProgramError { throw saveProgramError }
            guard !deletedProgramIDs.contains(command.programID), let latest = committedBlockPrograms.first(where: { $0.id == command.programID }) ?? mockSaveProgramResult else { throw WorkoutBlockError.unavailable }
            let updated = try command.applying(to: latest)
            committedBlockPrograms.removeAll { $0.id == command.programID }; committedBlockPrograms.append(updated)
            programEditReceipts[key] = WorkoutProgramEditOperationReceipt(id: command.id, fingerprint: try command.fingerprint(), programID: command.programID, status: .accepted)
            return updated
        }
        afterProgramEditCommit?(result)
        if let programEditFailureAfterCommit { throw programEditFailureAfterCommit }
        return result
    }
    public func resolveProgramEdit(userID: String, command: WorkoutProgramEditCommand, cancelPending: Bool) async throws -> WorkoutProgramEditResolution {
        try correctionLock.withLock {
            guard command.ownerID == userID else { throw WorkoutBlockError.accountChanged }
            let key = "\(userID):\(command.id)"
            if let receipt = programEditReceipts[key] {
                guard receipt.fingerprint == (try command.fingerprint()) else { throw WorkoutBlockError.changed }
                if receipt.status == .cancelled { return .cancelled }
                return .accepted(deletedProgramIDs.contains(command.programID) ? nil : committedBlockPrograms.first { $0.id == command.programID } ?? mockSaveProgramResult)
            }
            if cancelPending {
                programEditReceipts[key] = WorkoutProgramEditOperationReceipt(id: command.id, fingerprint: try command.fingerprint(), programID: command.programID, status: .cancelled)
                return .cancelled
            }
            return .pending
        }
    }
    public var programBlockCommitError: Error?
    public var beforeProgramBlockCommit: (() -> Void)?
    public var committedBlockPrograms: [WorkoutProgram] = []
    public var programBlockReceipts: [String: WorkoutBlockOperationReceipt] = [:]
    public var legacyMigrationRecords: [String: WorkoutLegacyMigrationRecord] = [:]
    public var migrationRollbackReceipts: [String: WorkoutMigrationRollbackReceipt] = [:]
    public var migrationRollbackFailureAfterCommit: Error?
    public func commitProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock, protectedSlots: Set<Int>) async throws -> WorkoutProgram? {
        try correctionLock.withLock {
            beforeProgramBlockCommit?()
            if let error = programBlockCommitError ?? saveProgramError { throw error }
            guard expected.userID == userID else { throw WorkoutBlockError.accountChanged }
            let key = "\(userID):\(block.revisionID)"
            if let receipt = programBlockReceipts[key] {
                try receipt.validate(expected: expected, block: block)
                if receipt.status == .cancelled { throw WorkoutBlockError.cancelled }
                return deletedProgramIDs.contains(expected.id ?? "") ? nil
                    : committedBlockPrograms.first { $0.id == expected.id } ?? mockSaveProgramResult ?? expected
            }
            guard !deletedProgramIDs.contains(expected.id ?? "") else { throw WorkoutBlockError.unavailable }
            let latest = committedBlockPrograms.first { $0.id == expected.id } ?? mockSaveProgramResult ?? expected
            let updated = try WorkoutBlockRules.applying(block, to: latest, expected: expected, protectedSlots: protectedSlots)
            committedBlockPrograms.removeAll { $0.id == updated.id }
            committedBlockPrograms.append(updated)
            programBlockReceipts[key] = try WorkoutBlockOperationReceipt(expected: expected, block: block, status: .accepted)
            if let record = programBlockReceipts[key]?.legacyMigration { legacyMigrationRecords[key] = record }
            return updated
        }
    }
    public func resolveProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock,
                                    cancelPending: Bool) async throws -> WorkoutBlockResolution? {
        try correctionLock.withLock {
            guard expected.userID == userID else { throw WorkoutBlockError.accountChanged }
            let key = "\(userID):\(block.revisionID)"
            if let receipt = programBlockReceipts[key] {
                try receipt.validate(expected: expected, block: block)
                if receipt.status == .cancelled { return .cancelled }
                return .accepted(deletedProgramIDs.contains(expected.id ?? "") ? nil
                    : committedBlockPrograms.first { $0.id == expected.id } ?? mockSaveProgramResult ?? expected)
            }
            guard cancelPending else { return nil }
            programBlockReceipts[key] = try WorkoutBlockOperationReceipt(expected: expected, block: block, status: .cancelled)
            return .cancelled
        }
    }
    public func fetchLegacyMigrations(userID: String, programID: String) async throws -> [WorkoutLegacyMigrationRecord] {
        try correctionLock.withLock {
            let records = legacyMigrationRecords.values.filter { $0.userID == userID && $0.programID == programID }
            try records.forEach { try $0.validate() }
            return records.sorted { $0.recordedAt > $1.recordedAt }
        }
    }
    public func commitMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, protectedSlots: Set<Int>) async throws -> WorkoutProgram? {
        try correctionLock.withLock {
            guard userID == command.userID else { throw WorkoutMigrationError.accountChanged }
            if let error = programBlockCommitError { throw error }
            let key = "\(userID):\(command.id.uuidString)"
            if let receipt = migrationRollbackReceipts[key] {
                try receipt.validate(command)
                guard receipt.status == .accepted else { throw WorkoutMigrationError.cancelled }
                return deletedProgramIDs.contains(command.programID) ? nil : committedBlockPrograms.first { $0.id == command.programID } ?? mockSaveProgramResult
            }
            guard !deletedProgramIDs.contains(command.programID),
                  let latest = committedBlockPrograms.first(where: { $0.id == command.programID }) ?? mockSaveProgramResult,
                  var record = legacyMigrationRecords["\(userID):\(command.migration.id)"] else { throw WorkoutMigrationError.unavailable }
            let restored = try WorkoutMigrationRollbackRules.applying(command, to: latest, record: record, protectedSlots: protectedSlots)
            committedBlockPrograms.removeAll { $0.id == command.programID }; committedBlockPrograms.append(restored)
            record.restoredByOperationID = command.id; legacyMigrationRecords["\(userID):\(record.id)"] = record
            migrationRollbackReceipts[key] = try WorkoutMigrationRollbackReceipt(command: command, status: .accepted)
            if let migrationRollbackFailureAfterCommit { throw migrationRollbackFailureAfterCommit }
            return restored
        }
    }
    public func resolveMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, cancelPending: Bool) async throws -> WorkoutMigrationRollbackResolution {
        try correctionLock.withLock {
            guard userID == command.userID else { throw WorkoutMigrationError.accountChanged }
            let key = "\(userID):\(command.id.uuidString)"
            if let receipt = migrationRollbackReceipts[key] {
                try receipt.validate(command)
                if receipt.status == .cancelled { return .cancelled }
                return .accepted(deletedProgramIDs.contains(command.programID) ? nil : committedBlockPrograms.first { $0.id == command.programID } ?? mockSaveProgramResult)
            }
            guard cancelPending else { return .pending }
            migrationRollbackReceipts[key] = try WorkoutMigrationRollbackReceipt(command: command, status: .cancelled)
            return .cancelled
        }
    }
    public var successorCommitError: Error?
    public var successorFailureAfterCommit: Error?
    public var successorAccountID: String?
    public var successorHasPendingProgramWrites = false
    public var beforeSuccessorCommit: (() -> Void)?
    public var successorReceipts: [String: WorkoutProgramSuccessorReceipt] = [:]
    public var createdSuccessorIDs: [String] = []

    public func createProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand) async throws -> WorkoutProgram? {
        try correctionLock.withLock {
            guard command.userID == userID, successorAccountID == nil || successorAccountID == userID else { throw WorkoutSuccessorError.accountChanged }
            try WorkoutProgramSuccessorRules.validate(command)
            beforeSuccessorCommit?()
            if let successorCommitError { throw successorCommitError }
            let key = "\(userID):\(command.operationID.uuidString)"
            if let receipt = successorReceipts[key] {
                try receipt.validate(command)
                guard receipt.status == .accepted else { throw WorkoutSuccessorError.cancelled }
                return deletedProgramIDs.contains(command.destinationProgramID) ? nil : committedBlockPrograms.first { $0.id == command.destinationProgramID }
            }
            guard !successorHasPendingProgramWrites else { throw WorkoutSuccessorError.pendingSync }
            let expected = try command.source()
            let latest = deletedProgramIDs.contains(command.sourceProgramID) ? nil
                : committedBlockPrograms.first { $0.id == command.sourceProgramID } ?? mockSaveProgramResult ?? expected
            try WorkoutProgramSuccessorRules.verifySource(latest, for: command)
            guard !deletedProgramIDs.contains(command.destinationProgramID),
                  !committedBlockPrograms.contains(where: { $0.id == command.destinationProgramID }) else { throw WorkoutSuccessorError.changed }
            let destination = try command.destination()
            let receipt = try WorkoutProgramSuccessorReceipt(command: command, status: .accepted)
            committedBlockPrograms.append(destination)
            createdSuccessorIDs.append(command.destinationProgramID)
            successorReceipts[key] = receipt
            if let successorFailureAfterCommit { throw successorFailureAfterCommit }
            return try command.destination()
        }
    }

    public func resolveProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand,
                                        cancelPending: Bool) async throws -> WorkoutProgramSuccessorResolution {
        try correctionLock.withLock {
            guard command.userID == userID, successorAccountID == nil || successorAccountID == userID else { throw WorkoutSuccessorError.accountChanged }
            try WorkoutProgramSuccessorRules.validate(command)
            if let successorCommitError { throw successorCommitError }
            let key = "\(userID):\(command.operationID.uuidString)"
            if let receipt = successorReceipts[key] {
                try receipt.validate(command)
                if receipt.status == .cancelled { return .cancelled }
                return .accepted(deletedProgramIDs.contains(command.destinationProgramID) ? nil
                    : committedBlockPrograms.first { $0.id == command.destinationProgramID })
            }
            guard cancelPending else { return .pending }
            successorReceipts[key] = try WorkoutProgramSuccessorReceipt(command: command, status: .cancelled)
            return .cancelled
        }
    }

    public var archiveSavedPrograms: [WorkoutProgram] = []
    public func saveProgramArchive(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram {
        if let saveProgramError { throw saveProgramError }
        guard program.userID == userID else { throw WorkoutLibraryEditError.changed }
        archiveSavedPrograms.append(program)
        return program
    }
    public func saveProgram(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram {
        if let saveProgramError {
            throw saveProgramError
        }
        return mockSaveProgramResult ?? program
    }

    public var deletedProgramIDs: [String] = []
    public var deleteProgramError: Error?
    public func deleteProgram(userID: String, programID: String) async throws {
        if let deleteProgramError {
            throw deleteProgramError
        }
        deletedProgramIDs.append(programID)
    }

    public func saveRoutine(userID: String, routine: WorkoutRoutine) async throws {
        savedRoutines.append(routine)
    }

    public var deletedRoutineIDs: [String] = []
    public func deleteRoutine(userID: String, routineID: String) async throws {
        deletedRoutineIDs.append(routineID)
    }

    public var saveWorkoutSessionLogError: Error?
    public func commitWorkoutCorrection(userID: String, expected: WorkoutSessionLog, updated: WorkoutSessionLog) async throws {
        try correctionLock.withLock {
            beforeCorrectionCommit?()
            guard let id = expected.id else { throw WorkoutCorrectionError.invalid }
            let latest = try session(userID: userID, id: id)
            if latest.correctionRevisionID == updated.correctionRevisionID, updated.correctionRevisionID != nil { return }
            guard latest.id == expected.id, expected.id == updated.id,
                  try WorkoutCorrectionRevisionRules.fingerprint(latest) == WorkoutCorrectionRevisionRules.fingerprint(expected) else {
                throw WorkoutCorrectionError.conflict
            }
            if let saveWorkoutSessionLogError { throw saveWorkoutSessionLogError }
            savedSessionLogs.append(updated)
            storedSessionsByOwner[userID, default: [:]][id] = updated
            if mockFetchSessionLogResult != nil { mockFetchSessionLogResult = .success(updated) }
        }
    }
    public func saveWorkoutSessionLog(userID: String, log: WorkoutSessionLog) async throws {
        if let saveWorkoutSessionLogError {
            throw saveWorkoutSessionLogError
        }
        correctionLock.withLock {
            savedSessionLogs.append(log)
            if let id = log.id, storedSessionsByOwner[userID]?[id] == nil {
                storedSessionsByOwner[userID, default: [:]][id] = log
            }
        }
    }
    public func fetchHistory(userID: String, exerciseName: String) async throws -> [WorkoutSessionLog] { return mockFetchHistoryResult }
    public func fetchPreviousPerformance(userID: String, exerciseName: String) async throws -> CompletedExercise? { return mockFetchPreviousPerformanceResult }
    public func saveWorkoutInsights(userID: String, sessionID: String, insights: [[String: Any]]) async throws {
        savedInsights = insights
    }
    public var historyPageError: Error?
    public var historyPagesFromCache = false
    public var historyPageRequests = 0
    public func fetchWorkoutHistoryPage(userID: String, cursor: WorkoutHistoryCursor?, pageSize: Int) async throws -> WorkoutHistoryPage {
        if let historyPageError { throw historyPageError }
        if let cursor { try cursor.validate(userID: userID) }
        guard (1...200).contains(pageSize) else { throw WorkoutHistoryReadError.invalidCursor }
        historyPageRequests += 1
        let upperBound = cursor?.upperBound ?? Date.distantFuture
        let ordered = WorkoutSetMath.uniqueSessions(storedSessions(userID: userID) + mockFetchHistoryResult).filter { log in
            guard log.date <= upperBound else { return false }
            guard let cursor else { return true }
            return log.date < cursor.lastDate || (log.date == cursor.lastDate && (log.id ?? "") < cursor.lastDocumentID)
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return ($0.id ?? "") > ($1.id ?? "")
        }
        let page = Array(ordered.prefix(pageSize))
        var next: WorkoutHistoryCursor?
        if ordered.count > pageSize, let last = page.last, let id = last.id {
            let timestamp = last.date.timeIntervalSince1970
            var seconds = Int64(floor(timestamp)); var nanos = Int64(((timestamp - Double(seconds)) * 1_000_000_000).rounded())
            if nanos >= 1_000_000_000 { seconds += 1; nanos = 0 }
            next = try WorkoutHistoryCursor(userID: userID, upperBound: upperBound,
                lastSeconds: seconds, lastNanoseconds: Int32(nanos), lastDocumentID: id)
        }
        return WorkoutHistoryPage(logs: page, nextCursor: next, isFromCache: historyPagesFromCache)
    }
    public func fetchWorkoutHistory(userID: String, limit: Int) async throws -> [WorkoutSessionLog] { return mockFetchHistoryResult }
    public func fetchWorkoutHistory(userID: String, routineID: String, limit: Int) async throws -> [WorkoutSessionLog] { return mockFetchHistoryResult }
}
#endif
