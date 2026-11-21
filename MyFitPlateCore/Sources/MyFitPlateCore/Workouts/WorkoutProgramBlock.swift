import CryptoKit
import Foundation

public struct WorkoutBlockWeek: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isDeload: Bool
    /// Schema 2 links only the session targets; names and lighter-week labels remain local.
    public var linkedSourceWeekID: String?
    public var deloadAdjustment: WorkoutDeloadReceipt?

    public init(id: String = UUID().uuidString, name: String, isDeload: Bool = false, linkedSourceWeekID: String? = nil) {
        self.id = id
        self.name = name
        self.isDeload = isDeload
        self.linkedSourceWeekID = linkedSourceWeekID
    }
}

public struct WorkoutBlockSlotOverride: Identifiable, Codable {
    public var id: String
    public var slotIndex: Int
    public var routine: WorkoutRoutine

    public init(id: String = UUID().uuidString, slotIndex: Int, routine: WorkoutRoutine) {
        self.id = id
        self.slotIndex = slotIndex
        self.routine = routine
    }
}

/// Unchanged sessions refer to the original rotation. Only authored variations carry
/// a snapshot, keeping ordinary twelve-week programs comfortably below document limits.
public struct WorkoutProgramBlock: Identifiable, Codable {
    public var schemaVersion: Int
    public var id: String
    public var revisionID: String
    public var name: String
    public var sessionsPerWeek: Int
    public var rotationRoutineIDs: [String]
    public var weeks: [WorkoutBlockWeek]
    public var overrides: [WorkoutBlockSlotOverride]
    public var scheduleExceptions: [WorkoutScheduleException]?

    public var totalSlots: Int {
        guard (1...7).contains(sessionsPerWeek), (1...24).contains(weeks.count) else { return 0 }
        return weeks.count * sessionsPerWeek
    }

    public init(id: String = UUID().uuidString, revisionID: String = UUID().uuidString,
                name: String = "Training block", sessionsPerWeek: Int, rotationRoutineIDs: [String],
                weeks: [WorkoutBlockWeek], overrides: [WorkoutBlockSlotOverride] = []) {
        schemaVersion = 1
        self.id = id
        self.revisionID = revisionID
        self.name = name
        self.sessionsPerWeek = sessionsPerWeek
        self.rotationRoutineIDs = rotationRoutineIDs
        self.weeks = weeks
        self.overrides = overrides
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, revisionID, name, sessionsPerWeek, rotationRoutineIDs, weeks, overridesPayload, schedulePayload
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard (1...2).contains(schemaVersion) else { throw WorkoutBlockError.unsupported }
        id = try values.decode(String.self, forKey: .id)
        revisionID = try values.decode(String.self, forKey: .revisionID)
        name = try values.decode(String.self, forKey: .name)
        sessionsPerWeek = try values.decode(Int.self, forKey: .sessionsPerWeek)
        rotationRoutineIDs = try values.decode([String].self, forKey: .rotationRoutineIDs)
        weeks = try values.decode([WorkoutBlockWeek].self, forKey: .weeks)
        // Firestore must not recast authored reference/snapshot dates through Timestamp.
        // The opaque payload retains the exact reviewed JSON representation for replay.
        let payload = try values.decode(Data.self, forKey: .overridesPayload)
        guard payload.count <= 500_000 else { throw WorkoutBlockError.tooLarge }
        overrides = try JSONDecoder().decode([WorkoutBlockSlotOverride].self, from: payload)
        scheduleExceptions = try values.decodeIfPresent(Data.self, forKey: .schedulePayload).map { try JSONDecoder().decode([WorkoutScheduleException].self, from: $0) }
        if let moves = scheduleExceptions, Set(moves.map(\.slotIndex)).count != moves.count || moves.contains(where: { !(0..<totalSlots).contains($0.slotIndex) || $0.proposedDay.date() == nil || $0.originalDay.date() == nil }) { throw WorkoutBlockError.invalid }
        guard (1...7).contains(sessionsPerWeek), (1...24).contains(weeks.count),
              !id.isEmpty, !revisionID.isEmpty, !rotationRoutineIDs.isEmpty,
              Set(weeks.map(\.id)).count == weeks.count,
              Set(overrides.map(\.slotIndex)).count == overrides.count,
              overrides.allSatisfy({ (0..<totalSlots).contains($0.slotIndex) }) else { throw WorkoutBlockError.invalid }
        try WorkoutWeekLinkRules.validate(self)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(revisionID, forKey: .revisionID)
        try values.encode(name, forKey: .name)
        try values.encode(sessionsPerWeek, forKey: .sessionsPerWeek)
        try values.encode(rotationRoutineIDs, forKey: .rotationRoutineIDs)
        try values.encode(weeks, forKey: .weeks)
        let payloadEncoder = JSONEncoder(); payloadEncoder.outputFormatting = .sortedKeys
        try values.encode(payloadEncoder.encode(overrides), forKey: .overridesPayload)
        if let scheduleExceptions { try values.encode(payloadEncoder.encode(scheduleExceptions), forKey: .schedulePayload) }
    }
}

public struct WorkoutPrescribedSetSnapshot: Codable, Equatable, Sendable {
    public let exerciseID: String
    public let setID: String
    public let originalText: String?
    public let prescription: WorkoutPrescription?
}

public struct WorkoutBlockSessionSnapshot: Codable, Equatable, Sendable {
    public let blockID: String
    public let revisionID: String
    public let weekID: String
    public let weekIndex: Int
    public let weekName: String
    public let isDeload: Bool
    public let slotID: String
    public let targets: [WorkoutPrescribedSetSnapshot]
}

public enum WorkoutBlockError: Error, LocalizedError {
    case invalid, unsupported, changed, progressChanged, pendingSync, accountChanged, unavailable, tooLarge, cancelled, authoredRotationChanged

    public var errorDescription: String? {
        switch self {
        case .invalid: "Each week needs valid sessions and supported targets."
        case .unsupported: "This block needs a newer app version. Its saved data has been kept."
        case .changed: "Your program changed. Close and reopen the block to review the latest version. Your draft is kept."
        case .progressChanged: "A session was completed or started while editing. Keep its targets unchanged and review again."
        case .pendingSync: "Let this program finish syncing, then try saving the block again. Your draft is kept."
        case .accountChanged: "Return to the account that opened this block before saving."
        case .unavailable: "This program is unavailable. Your block draft is kept."
        case .tooLarge: "This block has too many detailed variations. Use fewer weeks or edited sessions."
        case .cancelled: "This block proposal was cancelled. Its saved program was kept."
        case .authoredRotationChanged: "This program now has authored weeks. Your routine edits are kept in this draft. Review the latest training block before changing its sessions."
        }
    }
}

public enum WorkoutBlockResolution {
    case accepted(WorkoutProgram?)
    case cancelled
}

public struct WorkoutBlockOperationReceipt: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case accepted, cancelled }
    public let schemaVersion: Int
    public let userID: String
    public let programID: String
    public let operationID: String
    public let fingerprint: String
    public let status: Status
    public let legacyMigration: WorkoutLegacyMigrationRecord?

    public init(expected: WorkoutProgram, block: WorkoutProgramBlock, status: Status) throws {
        guard let programID = expected.id else { throw WorkoutBlockError.invalid }
        schemaVersion = 1; userID = expected.userID; self.programID = programID
        operationID = block.revisionID; fingerprint = try WorkoutBlockRules.commandFingerprint(expected: expected, block: block)
        self.status = status
        legacyMigration = status == .accepted && expected.trainingBlock == nil
            ? try WorkoutLegacyMigrationRecord(original: expected, block: block) : nil
    }

    public func validate(expected: WorkoutProgram, block: WorkoutProgramBlock) throws {
        guard schemaVersion == 1 else { throw WorkoutBlockError.unsupported }
        guard userID == expected.userID, programID == expected.id, operationID == block.revisionID,
              try fingerprint == WorkoutBlockRules.commandFingerprint(expected: expected, block: block) else {
            throw WorkoutBlockError.changed
        }
    }
}

public enum WorkoutBlockRules {
    public static func commandFingerprint(expected: WorkoutProgram, block: WorkoutProgramBlock) throws -> String {
        struct Identity: Encodable {
            let userID: String
            let programID: String?
            let baseline: String
            let block: String
        }
        return try fingerprint(Identity(userID: expected.userID, programID: expected.id,
            baseline: structureFingerprint(expected), block: fingerprint(block)))
    }
    public static func createRepeatingBlock(for program: WorkoutProgram, weekCount: Int = 12) throws -> WorkoutProgramBlock {
        guard let days = program.daysOfWeek, !days.isEmpty, (1...24).contains(weekCount),
              Set(days).count == days.count, days.allSatisfy({ (1...7).contains($0) }),
              !program.routines.isEmpty else { throw WorkoutBlockError.invalid }
        return WorkoutProgramBlock(sessionsPerWeek: days.count, rotationRoutineIDs: program.routines.map(\.id),
                                   weeks: (1...weekCount).map { WorkoutBlockWeek(name: "Week \($0)") })
    }

    public static func baseRoutine(for program: WorkoutProgram, slot: Int) -> WorkoutRoutine? {
        guard slot >= 0 else { return nil }
        if let block = program.trainingBlock {
            guard (1...2).contains(block.schemaVersion), slot < block.totalSlots, !block.rotationRoutineIDs.isEmpty else { return nil }
            return resolveRoutine(for: program, slot: slot, visitedWeeks: [])
        }
        guard !program.routines.isEmpty else { return nil }
        return program.routines[slot % program.routines.count]
    }

    private static func resolveRoutine(for program: WorkoutProgram, slot: Int, visitedWeeks: Set<Int>) -> WorkoutRoutine? {
        guard let block = program.trainingBlock, block.sessionsPerWeek > 0,
              (0..<block.totalSlots).contains(slot) else { return nil }
        let weekIndex = slot / block.sessionsPerWeek
        guard block.weeks.indices.contains(weekIndex), !visitedWeeks.contains(weekIndex) else { return nil }
        if let sourceID = block.weeks[weekIndex].linkedSourceWeekID {
            guard let sourceIndex = block.weeks.firstIndex(where: { $0.id == sourceID }) else { return nil }
            return resolveRoutine(for: program, slot: sourceIndex * block.sessionsPerWeek + slot % block.sessionsPerWeek,
                visitedWeeks: visitedWeeks.union([weekIndex]))
        }
        if let variation = block.overrides.first(where: { $0.slotIndex == slot }) { return variation.routine }
        let routineID = block.rotationRoutineIDs[slot % block.rotationRoutineIDs.count]
        return program.routines.first { $0.id == routineID }
    }

    public static func snapshot(for program: WorkoutProgram, slot: Int) -> WorkoutBlockSessionSnapshot? {
        guard let block = program.trainingBlock, block.sessionsPerWeek > 0,
              (0..<block.totalSlots).contains(slot), let routine = program.routine(forSlot: slot) else { return nil }
        let weekIndex = slot / block.sessionsPerWeek
        let week = block.weeks[weekIndex]
        return WorkoutBlockSessionSnapshot(blockID: block.id, revisionID: block.revisionID, weekID: week.id,
            weekIndex: weekIndex, weekName: week.name, isDeload: week.isDeload,
            slotID: "\(week.id)-day-\(slot % block.sessionsPerWeek)",
            targets: routine.exercises.flatMap { exercise in
                exercise.sets.map { WorkoutPrescribedSetSnapshot(exerciseID: exercise.id, setID: $0.id,
                                                                 originalText: $0.target, prescription: $0.prescription) }
            })
    }

    public static func structureFingerprint(_ program: WorkoutProgram) throws -> String {
        var structure = program
        structure.currentProgressIndex = nil
        structure.skippedIndices = nil
        structure.progressEpoch = nil; structure.slotCompletionProofs = nil; structure.lastSkipReceipt = nil
        return try fingerprint(structure)
    }

    public static func fingerprint<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    public static func applying(_ block: WorkoutProgramBlock, to latest: WorkoutProgram,
                                expected: WorkoutProgram, protectedSlots: Set<Int> = []) throws -> WorkoutProgram {
        guard latest.id == expected.id, latest.userID == expected.userID else { throw WorkoutBlockError.accountChanged }
        // Only a durable repository receipt can prove a prior acceptance. Matching
        // current field values alone cannot bypass the original compare-and-set.
        if latest.trainingBlock?.revisionID == block.revisionID { throw WorkoutBlockError.changed }
        if let existingID = expected.trainingBlock?.id, block.id != existingID { throw WorkoutBlockError.changed }
        guard try structureFingerprint(latest) == structureFingerprint(expected) else { throw WorkoutBlockError.changed }
        var updated = latest; updated.trainingBlock = block
        try validate(updated)
        let protected = Set(0..<max(latest.currentProgressIndex ?? 0, 0)).union(protectedSlots)
        for slot in protected {
            guard slot < updated.totalSlots,
                  let old = baseRoutine(for: latest, slot: slot), let new = baseRoutine(for: updated, slot: slot),
                  try fingerprint(old) == fingerprint(new),
                  latest.date(forSlot: slot) == updated.date(forSlot: slot) else { throw WorkoutBlockError.progressChanged }
        }
        return updated
    }

    public static func validate(_ program: WorkoutProgram) throws {
        guard let block = program.trainingBlock, (1...2).contains(block.schemaVersion) else { throw WorkoutBlockError.unsupported }
        try WorkoutWeekLinkRules.validate(block)
        guard (1...24).contains(block.weeks.count), (1...7).contains(block.sessionsPerWeek),
              !block.id.isEmpty, !block.revisionID.isEmpty, !block.revisionID.contains("/"), block.revisionID.count <= 128,
              program.daysOfWeek?.count == block.sessionsPerWeek,
              !block.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              block.name.count <= 200, block.weeks.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 }),
              Set(block.weeks.map(\.id)).count == block.weeks.count,
              Set(block.overrides.map(\.slotIndex)).count == block.overrides.count,
              Set(block.rotationRoutineIDs).count == block.rotationRoutineIDs.count,
              block.rotationRoutineIDs.allSatisfy({ id in program.routines.contains { $0.id == id } }),
              block.totalSlots >= max(program.currentProgressIndex ?? 0, 0),
              block.overrides.allSatisfy({ (0..<block.totalSlots).contains($0.slotIndex) }) else { throw WorkoutBlockError.invalid }
        if let moves = block.scheduleExceptions {
            guard Set(moves.map(\.slotIndex)).count == moves.count,
                  moves.allSatisfy({ (0..<block.totalSlots).contains($0.slotIndex) && $0.originalDay.date() != nil && $0.proposedDay.date() != nil && $0.revision > 0 }) else { throw WorkoutBlockError.invalid }
        }
        for slot in 0..<block.totalSlots {
            guard let routine = baseRoutine(for: program, slot: slot), routine.userID == program.userID,
                  !routine.exercises.isEmpty, !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkoutBlockError.invalid
            }
            for exercise in routine.exercises {
                guard !exercise.sets.isEmpty else { throw WorkoutBlockError.invalid }
                for set in exercise.sets {
                    if let target = set.prescription,
                       target.validationMessage != nil || !target.isSupported(for: exercise.type) { throw WorkoutBlockError.invalid }
                }
            }
        }
        let encoder = JSONEncoder()
        guard try encoder.encode(block).count <= 500_000, try encoder.encode(program).count <= 750_000 else { throw WorkoutBlockError.tooLarge }
    }
}
