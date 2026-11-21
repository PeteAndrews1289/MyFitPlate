import Foundation

public enum WorkoutSuccessorMode: String, Codable, CaseIterable, Sendable {
    case repeatBlock, adjusted
    public var title: String { self == .repeatBlock ? "Repeat block" : "Adjust next block" }
}

public struct WorkoutProgramLineage: Codable, Equatable, Sendable {
    public let sourceProgramID: String
    public let sourceBlockID: String?
    public let sourceBlockRevisionID: String?
    public let sourceProgramName: String
    public let sourceFingerprint: String
    public let sourceProgressIndex: Int
    public var mode: WorkoutSuccessorMode
}

public enum WorkoutSuccessorError: Int, Error, LocalizedError, CustomNSError {
    case invalid = 400, accountChanged = 401, changed = 409, cancelled = 410, pendingSync = 412, activeWorkout = 423, unavailable = 503
    public static var errorDomain: String { "MyFitPlate.ProgramSuccessor" }
    public var errorCode: Int { rawValue }
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review the new block's name, schedule and targets before saving."
        case .accountChanged: "Return to the account that opened this block. Its proposal is kept."
        case .changed: "The source program or new block changed. Your proposal is kept; cancel it and review the current program before trying again."
        case .cancelled: "This next-block proposal was cancelled. A late retry cannot save it."
        case .pendingSync: "Let this program finish syncing before creating the next block. Its proposal is kept."
        case .activeWorkout: "Finish or discard your current workout before activating another block. The new block stays saved."
        case .unavailable: "The new block could not be confirmed. Retry, check its status, or cancel the pending proposal."
        }
    }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "Could not save the next block."] }
}

/// Serialized snapshots prevent mutable routine references from changing a reviewed
/// source or destination during retry, interruption, or a nested editor callback.
public struct WorkoutProgramSuccessorCommand: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let operationID: UUID
    public let userID: String
    public let sourceProgramID: String
    public let destinationProgramID: String
    private let sourcePayload: Data
    private let destinationPayload: Data

    public init(source: WorkoutProgram, destination: WorkoutProgram, operationID: UUID = UUID()) throws {
        guard let sourceID = source.id, let destinationID = destination.id else { throw WorkoutSuccessorError.invalid }
        schemaVersion = 1; self.operationID = operationID; userID = source.userID
        sourceProgramID = sourceID; destinationProgramID = destinationID
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        sourcePayload = try encoder.encode(source); destinationPayload = try encoder.encode(destination)
        try WorkoutProgramSuccessorRules.validate(self)
    }

    public func source() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: sourcePayload) }
    public func destination() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: destinationPayload) }
    public var fingerprint: String { get throws { try WorkoutBlockRules.fingerprint(self) } }
}

public enum WorkoutProgramSuccessorResolution {
    case pending
    case cancelled
    /// The current destination may be newer, or absent after deliberate deletion.
    case accepted(WorkoutProgram?)
}

public struct WorkoutProgramSuccessorReceipt: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case accepted, cancelled }
    public let schemaVersion: Int
    public let userID: String
    public let operationID: UUID
    public let sourceProgramID: String
    public let destinationProgramID: String
    public let fingerprint: String
    public let status: Status

    public init(command: WorkoutProgramSuccessorCommand, status: Status) throws {
        schemaVersion = 1; userID = command.userID; operationID = command.operationID
        sourceProgramID = command.sourceProgramID; destinationProgramID = command.destinationProgramID
        fingerprint = try command.fingerprint; self.status = status
    }
    public func validate(_ command: WorkoutProgramSuccessorCommand) throws {
        guard schemaVersion == 1, userID == command.userID, operationID == command.operationID,
              sourceProgramID == command.sourceProgramID, destinationProgramID == command.destinationProgramID,
              try fingerprint == command.fingerprint else { throw WorkoutSuccessorError.changed }
    }
}

public enum WorkoutProgramSuccessorRules {
    public static func prepare(from source: WorkoutProgram, mode: WorkoutSuccessorMode = .repeatBlock,
                               startDate: Date = Date(), weekCount: Int? = nil, now: Date = Date(),
                               calendar: Calendar = .current) throws -> WorkoutProgram {
        guard let sourceID = source.id, !sourceID.isEmpty, !source.userID.isEmpty,
              startDate.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkoutSuccessorError.invalid
        }
        var resolvedSource = source
        resolvedSource.trainingBlock = try source.trainingBlock ?? WorkoutBlockRules.createRepeatingBlock(for: source)
        try WorkoutBlockRules.validate(resolvedSource)
        guard let sourceBlock = resolvedSource.trainingBlock else { throw WorkoutSuccessorError.invalid }
        let count = weekCount ?? sourceBlock.weeks.count
        guard (1...24).contains(count) else { throw WorkoutSuccessorError.invalid }
        let data = try JSONEncoder().encode(source)
        var destination = try JSONDecoder().decode(WorkoutProgram.self, from: data)
        destination.id = UUID().uuidString
        destination.name = source.name
        destination.dateCreated = now; destination.startDate = calendar.startOfDay(for: startDate)
        destination.scheduleAnchorDay = TrainingCalendarDay(startDate, calendar: calendar)
        destination.progressEpoch = destination.id; destination.slotCompletionProofs = nil; destination.lastSkipReceipt = nil
        destination.currentProgressIndex = 0; destination.skippedIndices = nil; destination.weekRescue = nil
        destination.archivedAt = nil; destination.slotDateSnapshots = nil
        destination.lineage = WorkoutProgramLineage(sourceProgramID: sourceID, sourceBlockID: source.trainingBlock?.id,
            sourceBlockRevisionID: source.trainingBlock?.revisionID, sourceProgramName: source.name,
            sourceFingerprint: try WorkoutBlockRules.fingerprint(source), sourceProgressIndex: max(source.currentProgressIndex ?? 0, 0), mode: mode)
        let weeks = (0..<count).map { index in
            let original = sourceBlock.weeks[index % sourceBlock.weeks.count]
            return WorkoutBlockWeek(name: index < sourceBlock.weeks.count ? original.name : "Week \(index + 1)", isDeload: original.isDeload)
        }
        var block = WorkoutProgramBlock(name: sourceBlock.name, sessionsPerWeek: sourceBlock.sessionsPerWeek,
            rotationRoutineIDs: sourceBlock.rotationRoutineIDs, weeks: weeks)
        for routine in destination.routines { clearPerformedValues(routine) }
        destination.trainingBlock = block
        // Snapshot the resolved pattern when variations/odd rotations make it differ
        // from the new rotation. Repeating a source week never guesses its first day.
        for slot in 0..<block.totalSlots {
            let sourceSlot = (slot / block.sessionsPerWeek % sourceBlock.weeks.count) * block.sessionsPerWeek + slot % block.sessionsPerWeek
            guard let routine = WorkoutBlockRules.baseRoutine(for: resolvedSource, slot: sourceSlot)?.deepCopy(),
                  let ordinary = destination.routines.first(where: { $0.id == block.rotationRoutineIDs[slot % block.rotationRoutineIDs.count] }) else {
                throw WorkoutSuccessorError.invalid
            }
            clearPerformedValues(routine)
            if try WorkoutBlockRules.fingerprint(routine) != WorkoutBlockRules.fingerprint(ordinary) {
                block.overrides.append(WorkoutBlockSlotOverride(slotIndex: slot, routine: routine))
            }
        }
        destination.trainingBlock = block
        try validate(WorkoutProgramSuccessorCommand(uncheckedSource: source, destination: destination))
        return destination
    }

    public static func validate(_ command: WorkoutProgramSuccessorCommand) throws {
        guard command.schemaVersion == 1 else { throw WorkoutSuccessorError.invalid }
        let source = try command.source(); let destination = try command.destination()
        let validID: (String) -> Bool = { !$0.isEmpty && !$0.contains("/") && $0.utf8.count <= 128 }
        guard !command.userID.isEmpty, source.userID == command.userID, destination.userID == command.userID,
              source.id == command.sourceProgramID, destination.id == command.destinationProgramID,
              validID(command.sourceProgramID), validID(command.destinationProgramID), source.id != destination.id,
              let block = destination.trainingBlock, block.id != source.trainingBlock?.id,
              block.revisionID != source.trainingBlock?.revisionID,
              Set(block.weeks.map(\.id)).isDisjoint(with: Set(source.trainingBlock?.weeks.map(\.id) ?? [])),
              destination.currentProgressIndex == 0, (destination.skippedIndices ?? []).isEmpty, destination.weekRescue == nil,
              !destination.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, destination.name.count <= 200,
              destination.dateCreated.timeIntervalSinceReferenceDate.isFinite,
              destination.startDate?.timeIntervalSinceReferenceDate.isFinite == true,
              let lineage = destination.lineage,
              lineage.sourceProgramID == source.id, lineage.sourceBlockID == source.trainingBlock?.id,
              lineage.sourceBlockRevisionID == source.trainingBlock?.revisionID,
              lineage.sourceProgramName == source.name, lineage.sourceProgressIndex == max(source.currentProgressIndex ?? 0, 0),
              try lineage.sourceFingerprint == WorkoutBlockRules.fingerprint(source) else { throw WorkoutSuccessorError.invalid }
        try WorkoutBlockRules.validate(destination)
    }

    public static func verifySource(_ latest: WorkoutProgram?, for command: WorkoutProgramSuccessorCommand) throws {
        guard let latest, latest.userID == command.userID, latest.id == command.sourceProgramID,
              try WorkoutBlockRules.fingerprint(latest) == WorkoutBlockRules.fingerprint(command.source()) else {
            throw WorkoutSuccessorError.changed
        }
    }

    private static func clearPerformedValues(_ routine: WorkoutRoutine) {
        for exerciseIndex in routine.exercises.indices {
            for setIndex in routine.exercises[exerciseIndex].sets.indices {
                routine.exercises[exerciseIndex].sets[setIndex].isCompleted = false
                routine.exercises[exerciseIndex].sets[setIndex].effort = nil
                routine.exercises[exerciseIndex].sets[setIndex].previousPerformance = nil
                routine.exercises[exerciseIndex].sets[setIndex].generatedWarmup = nil
                routine.exercises[exerciseIndex].sets[setIndex].intervalTimer = nil
                routine.exercises[exerciseIndex].sets[setIndex].isDeferred = nil
                routine.exercises[exerciseIndex].sets[setIndex].reps = 0
                routine.exercises[exerciseIndex].sets[setIndex].weight = 0
                routine.exercises[exerciseIndex].sets[setIndex].distance = 0
                routine.exercises[exerciseIndex].sets[setIndex].durationInSeconds = 0
            }
        }
    }
}

private extension WorkoutProgramSuccessorCommand {
    init(uncheckedSource source: WorkoutProgram, destination: WorkoutProgram) throws {
        guard let sourceID = source.id, let destinationID = destination.id else { throw WorkoutSuccessorError.invalid }
        schemaVersion = 1; operationID = UUID(); userID = source.userID
        sourceProgramID = sourceID; destinationProgramID = destinationID
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        sourcePayload = try encoder.encode(source); destinationPayload = try encoder.encode(destination)
    }
}
