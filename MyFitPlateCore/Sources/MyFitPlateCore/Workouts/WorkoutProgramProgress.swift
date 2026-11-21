import Foundation
import CryptoKit

public struct WorkoutSlotCompletionProof: Codable, Equatable, Sendable {
    public var slotIndex: Int
    public var sessionID: String
}
public struct WorkoutProgramSkipReceipt: Codable, Equatable, Sendable {
    public var operationID: String
    public var originalProgress: Int
    public var originalSkips: [Int]
    public var targetProgress: Int
    public var addedSkips: [Int]
    public var postEpoch: String
    public var structureFingerprint: String
}
public struct WorkoutProgramProgressCommand: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case skip, undoSkip, completion }
    public let id: String
    public let ownerID: String
    public let programID: String
    public let kind: Kind
    public let targetIndex: Int?
    public let sessionID: String?
    public let proofSessionIDs: [String]
    public let expectedData: Data
    public let createdAt: Date
    public init(program: WorkoutProgram, kind: Kind, targetIndex: Int? = nil, sessionID: String? = nil,
                proofSessionIDs: [String] = [], id: String = UUID().uuidString, now: Date = Date()) throws {
        guard let programID = program.id, !programID.isEmpty, !programID.contains("/"), !program.userID.isEmpty,
              !id.isEmpty, !id.contains("/"), id.count <= 128 else { throw WorkoutBlockError.invalid }
        if kind == .completion {
            guard let sessionID, !sessionID.isEmpty, targetIndex == nil else { throw WorkoutBlockError.invalid }
            self.id = "completion-" + SHA256.hash(data: Data("\(program.userID)|\(programID)|\(sessionID)".utf8)).map { String(format: "%02x", $0) }.joined()
        } else { self.id = id }
        ownerID = program.userID; self.programID = programID; self.kind = kind
        self.targetIndex = targetIndex; self.sessionID = sessionID; createdAt = now
        self.proofSessionIDs = Array(Set(proofSessionIDs + (program.slotCompletionProofs ?? []).map(\.sessionID) + (sessionID.map { [$0] } ?? []))).sorted()
        guard self.proofSessionIDs.count <= 200, self.proofSessionIDs.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0.utf8.count <= 1_500 }), now.timeIntervalSinceReferenceDate.isFinite else { throw WorkoutBlockError.invalid }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; expectedData = try encoder.encode(program)
    }
    public func validateIdentity() throws {
        guard !ownerID.isEmpty, !programID.isEmpty, !programID.contains("/"), programID.utf8.count <= 1_500,
              !id.isEmpty, !id.contains("/"), id.count <= 128, expectedData.count <= 750_000,
              createdAt.timeIntervalSinceReferenceDate.isFinite, proofSessionIDs.count <= 200,
              Set(proofSessionIDs).count == proofSessionIDs.count,
              proofSessionIDs.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0.utf8.count <= 1_500 }) else { throw WorkoutBlockError.invalid }
        if kind == .completion {
            guard let sessionID, proofSessionIDs.contains(sessionID), targetIndex == nil else { throw WorkoutBlockError.invalid }
            let expectedID = "completion-" + SHA256.hash(data: Data("\(ownerID)|\(programID)|\(sessionID)".utf8)).map { String(format: "%02x", $0) }.joined()
            guard id == expectedID else { throw WorkoutBlockError.invalid }
        }
        let source = try expected()
        guard source.id == programID, source.userID == ownerID else { throw WorkoutBlockError.accountChanged }
    }
    public func expected() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: expectedData) }
    /// The history write can reach listeners before its paired progress command.
    public static func historySaveEpoch(ownerID: String, sessionID: String) throws -> String {
        "saved-" + (try PlanFingerprint.make(["owner": ownerID, "session": sessionID]))
    }
    public func fingerprint() throws -> String {
        try validateIdentity()
        if kind == .completion {
            // A completion is a reference to one durable session, not a template overwrite.
            // Expected projection/history IDs are read hints; the event identity never changes.
            return try PlanFingerprint.make(["owner": ownerID, "program": programID, "kind": kind.rawValue, "session": sessionID ?? ""])
        }
        return try PlanFingerprint.make(self)
    }
    public func applying(to latest: WorkoutProgram, verifiedLogs: [WorkoutSessionLog], now: Date = Date(), trustStoredProofsForLocalProjection: Bool = false) throws -> WorkoutProgram {
        try validateIdentity()
        guard latest.id == programID, latest.userID == ownerID else { throw WorkoutBlockError.accountChanged }
        let expected = try expected()
        var result = latest
        let verified = WorkoutSetMath.uniqueSessions(verifiedLogs).filter {
            $0.programLinkDecision != .standalone && $0.programContext?.programID == programID
                && $0.date <= now && $0.date.timeIntervalSinceReferenceDate.isFinite
                && $0.programContext.map { (0..<latest.totalSlots).contains($0.slotIndex) } == true
        }
        var allProofs = verified.compactMap { log -> WorkoutSlotCompletionProof? in
            guard let id = log.id, let context = log.programContext else { return nil }
            return WorkoutSlotCompletionProof(slotIndex: context.slotIndex, sessionID: id)
        }
        if trustStoredProofsForLocalProjection && kind == .completion {
            let newSlots = Set(allProofs.map(\.slotIndex))
            allProofs += (latest.slotCompletionProofs ?? []).filter { !newSlots.contains($0.slotIndex) }
        }
        let proofs = Dictionary(allProofs.map { ($0.slotIndex, $0) }, uniquingKeysWith: { _, last in last }).values.sorted { $0.slotIndex < $1.slotIndex }
        let completed = Set(proofs.map(\.slotIndex))
        let current = min(latest.totalSlots, max(0, latest.currentProgressIndex ?? 0))
        func nextUnfinished(from start: Int, skipping skipped: Set<Int>) -> Int {
            var position = start
            while position < latest.totalSlots && (completed.contains(position) || skipped.contains(position)) { position += 1 }
            return position
        }
        switch kind {
        case .completion:
            guard let sessionID, verified.contains(where: { $0.id == sessionID }) else { throw WorkoutBlockError.unavailable }
            let pointer = nextUnfinished(from: current, skipping: Set(latest.skippedIndices ?? []))
            if pointer == current, (latest.slotCompletionProofs ?? []).contains(where: { $0.sessionID == sessionID }) { return latest }
            result.currentProgressIndex = pointer
        case .skip:
            guard latest.archivedAt == nil, expected.progressEpoch == latest.progressEpoch,
                  expected.currentProgressIndex == latest.currentProgressIndex,
                  try Self.structure(latest) == Self.structure(expected),
                  let targetIndex, (current + 1...max(current + 1, latest.totalSlots)).contains(targetIndex), targetIndex <= latest.totalSlots else { throw WorkoutBlockError.changed }
            let added = (current..<targetIndex).filter { !completed.contains($0) }
            let skipped = Set((latest.skippedIndices ?? []) + added)
            let pointer = nextUnfinished(from: targetIndex, skipping: skipped)
            result.skippedIndices = skipped.sorted()
            result.currentProgressIndex = pointer
            result.lastSkipReceipt = WorkoutProgramSkipReceipt(operationID: id, originalProgress: current,
                originalSkips: latest.skippedIndices ?? [], targetProgress: pointer, addedSkips: added,
                postEpoch: id, structureFingerprint: try Self.structure(latest))
        case .undoSkip:
            guard let receipt = latest.lastSkipReceipt, latest.progressEpoch == receipt.postEpoch,
                  expected.progressEpoch == latest.progressEpoch, current == receipt.targetProgress,
                  try Self.structure(latest) == receipt.structureFingerprint else { throw WorkoutBlockError.progressChanged }
            let beforeIDs = Set(latest.slotCompletionProofs?.map(\.sessionID) ?? [])
            guard !verified.contains(where: { log in
                guard let slot = log.programContext?.slotIndex, let id = log.id else { return false }
                return slot >= receipt.originalProgress && !beforeIDs.contains(id)
            }) else { throw WorkoutBlockError.progressChanged }
            result.currentProgressIndex = nextUnfinished(from: receipt.originalProgress, skipping: Set(receipt.originalSkips))
            result.skippedIndices = receipt.originalSkips.isEmpty ? nil : receipt.originalSkips
            result.lastSkipReceipt = nil
        }
        result.progressEpoch = id
        let proofFloor = kind == .skip ? current : result.currentProgressIndex ?? 0
        result.slotCompletionProofs = proofs.filter { $0.slotIndex >= proofFloor }
        return result
    }
    public static func structure(_ program: WorkoutProgram) throws -> String {
        var value = program; value.currentProgressIndex = nil; value.skippedIndices = nil
        value.progressEpoch = nil; value.lastSkipReceipt = nil; value.slotCompletionProofs = nil
        return try PlanFingerprint.make(value)
    }
    /// Cached local publication is optimistic and explicitly retained in the workout outbox.
    /// A canonical different epoch wins over an older queued skip/undo.
    public func overlay(proposed: WorkoutProgram, on latest: WorkoutProgram) throws -> WorkoutProgram {
        let expected = try expected()
        guard latest.id == programID, latest.userID == ownerID else { throw WorkoutBlockError.accountChanged }
        if latest.progressEpoch == id { return latest }
        if latest.progressEpoch != expected.progressEpoch {
            guard kind == .completion, let sessionID, proposed.progressEpoch == id,
                  latest.progressEpoch == (try Self.historySaveEpoch(ownerID: ownerID, sessionID: sessionID)),
                  latest.currentProgressIndex == expected.currentProgressIndex,
                  latest.skippedIndices == expected.skippedIndices,
                  latest.slotCompletionProofs == expected.slotCompletionProofs,
                  latest.lastSkipReceipt == expected.lastSkipReceipt,
                  latest.totalSlots == expected.totalSlots else { return latest }
        }
        var result = latest
        result.currentProgressIndex = proposed.currentProgressIndex; result.skippedIndices = proposed.skippedIndices
        result.progressEpoch = proposed.progressEpoch; result.lastSkipReceipt = proposed.lastSkipReceipt
        result.slotCompletionProofs = proposed.slotCompletionProofs
        return result
    }
}
public struct WorkoutProgramProgressOperationReceipt: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case accepted, cancelled }
    public var id: String
    public var fingerprint: String
    public var programID: String
    public var status: Status
    public init(id: String, fingerprint: String, programID: String, status: Status) {
        self.id = id; self.fingerprint = fingerprint; self.programID = programID; self.status = status
    }
}
public enum WorkoutProgramProgressResolution { case pending, accepted(WorkoutProgram?), cancelled(WorkoutProgram?) }
