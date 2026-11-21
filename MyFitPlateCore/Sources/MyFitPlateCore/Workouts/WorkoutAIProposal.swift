import Foundation

public struct WorkoutAIGenerationProvenance: Codable, Equatable, Sendable {
    public var requestID: String
    public var requestedModel: String
    public var acceptedRequestIDs: [String]
    public var requestFingerprint: String
    public var requestedAt: Date
    public var gymProfileID: String?
    public var gymRevisionID: String?
}

public struct WorkoutAIRequestSnapshot: Codable {
    public var id: String
    public var createdAt: Date
    public var goal: String
    public var daysPerWeek: Int
    public var maximumSessionMinutes: Int
    public var experience: String
    public var equipmentClass: String
    public var details: String
    public var gym: StrengthGymProfile?
    /// User-confirmed exercise name → implement ID; no guessed bench or machine availability.
    public var movementMappings: [String: String]
    public var startDate: Date
    public var weekdays: [Int]
    public var preferredMovements: [String]?
    public var avoidedMovements: [String]?
    public init(goal: String, daysPerWeek: Int, maximumSessionMinutes: Int, experience: String, equipmentClass: String,
                details: String, gym: StrengthGymProfile?, movementMappings: [String: String], startDate: Date, weekdays: [Int], preferredMovements: [String] = [], avoidedMovements: [String] = []) {
        id = UUID().uuidString; createdAt = Date(); self.goal = goal; self.daysPerWeek = daysPerWeek
        self.maximumSessionMinutes = maximumSessionMinutes; self.experience = experience; self.equipmentClass = equipmentClass
        self.details = details; self.gym = gym; self.movementMappings = movementMappings; self.startDate = startDate; self.weekdays = weekdays
        self.preferredMovements = Array(Set(preferredMovements)).sorted(); self.avoidedMovements = Array(Set(avoidedMovements)).sorted()
    }
    public var inventoryPrompt: String {
        guard let gym else { return "" }
        let rows = movementMappings.keys.sorted().map { name in
            "\(name):equipmentProfileID=\(gym.id),equipmentImplementID=\(movementMappings[name] ?? "")"
        }.joined(separator: "; ")
        return "\nActual gym: \(gym.name), revision \(gym.revisionID). Only use these user-confirmed loaded movements and echo their exact typed IDs: "
            + rows
            + ". Floor-only bodyweight movements are also allowed. Do not assume any other bench, machine, bar or attachment. Use only supported numeric targets; progression policy is conservativeDouble v1."
    }
}
public struct WorkoutAIProposal: Codable {
    public var schemaVersion = 1
    public var ownerID: String
    public var request: WorkoutAIRequestSnapshot
    public var pendingRequest: WorkoutAIRequestSnapshot?
    public var requestedModel: String
    public var program: WorkoutProgram?
    public var acceptedRequestIDs: [String]
    public init(ownerID: String, request: WorkoutAIRequestSnapshot, program: WorkoutProgram? = nil) {
        self.ownerID = ownerID; self.request = request; self.program = program
        requestedModel = "gpt-6-astra"; acceptedRequestIDs = []
    }
    public func validatedProgram(_ source: WorkoutProgram, daysPerWeek: Int? = nil) throws -> WorkoutProgram {
        guard schemaVersion == 1, source.userID == ownerID, let equipment = WorkoutPlanningEquipment(request: request.equipmentClass) else { throw WorkoutBlockError.accountChanged }
        var copy = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(source))
        copy.generationProvenance = WorkoutAIGenerationProvenance(requestID: request.id, requestedModel: requestedModel,
            acceptedRequestIDs: acceptedRequestIDs, requestFingerprint: try PlanFingerprint.make(request), requestedAt: request.createdAt,
            gymProfileID: request.gym?.id, gymRevisionID: request.gym?.revisionID)
        try WorkoutAIContract.validateMovementChoices(preferred: request.preferredMovements ?? [], avoided: request.avoidedMovements ?? [])
        guard !copy.routines.flatMap(\.exercises).contains(where: { exercise in
            (request.avoidedMovements ?? []).contains(exercise.name) || (exercise.alternatives ?? []).contains(where: { (request.avoidedMovements ?? []).contains($0) })
        }) else { throw WorkoutAIContractError.constraints("This proposal includes a movement you chose to avoid. Regenerate or remove that movement before saving.") }
        try WorkoutPlanningEligibility.validate(copy, daysPerWeek: daysPerWeek ?? request.daysPerWeek, equipment: equipment,
            maximumSessionMinutes: request.maximumSessionMinutes)
        for routine in copy.routines {
            for index in routine.exercises.indices {
                let name = routine.exercises[index].name
                guard let identity = WorkoutMovementCatalog.identity(for: name) else { throw WorkoutPlanningEligibilityError.unsupportedExercise(name) }
                routine.exercises[index].movementIdentity = identity
                if let gym = request.gym {
                    guard gym.isValid else { throw WorkoutBlockError.invalid }
                    if let implementID = request.movementMappings[name], let setup = gym.equipment(for: implementID) {
                        routine.exercises[index].loadEquipment = setup
                        let policy: WorkoutProgressionPolicy.Kind = setup.loadingMeaning == .assistance ? .assistance : setup.loadingMeaning == .bodyweightOnly ? .bodyweight : .conservativeDouble
                        if routine.exercises[index].progressionPolicy == nil { routine.exercises[index].progressionPolicy = WorkoutProgressionPolicy(kind: policy) }
                        if let message = routine.exercises[index].progressionPolicy?.validationMessage(for: routine.exercises[index]) { throw WorkoutAIContractError.policy(message) }
                    } else if WorkoutPlanningEligibility.isEligible(name, for: .floorOnly) {
                        if routine.exercises[index].type == .strength {
                            routine.exercises[index].loadEquipment = StrengthEquipment(loadingMeaning: .bodyweightOnly, availableWeights: [0])
                            if routine.exercises[index].progressionPolicy == nil { routine.exercises[index].progressionPolicy = WorkoutProgressionPolicy(kind: .bodyweight) }
                            if let message = routine.exercises[index].progressionPolicy?.validationMessage(for: routine.exercises[index]) { throw WorkoutAIContractError.policy(message) }
                        }
                    } else { throw WorkoutPlanningEligibilityError.unavailableEquipment(name) }
                    // Never silently remove an approved alternative to make a proposal fit.
                    for alternative in routine.exercises[index].alternatives ?? [] {
                        guard request.movementMappings[alternative].flatMap({ gym.equipment(for: $0) }) != nil
                                || WorkoutPlanningEligibility.isEligible(alternative, for: .floorOnly) else { throw WorkoutAIContractError.equipment(alternative) }
                    }
                }
            }
        }
        return copy
    }
    public func replacingRoutine(id: String, with routine: WorkoutRoutine) throws -> WorkoutProgram {
        guard let program, program.trainingBlock == nil, let index = program.routines.firstIndex(where: { $0.id == id }), routine.userID == ownerID else { throw WorkoutBlockError.changed }
        var result = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(program))
        result.routines[index] = routine
        return try validatedProgram(result)
    }

    /// The ordinary editor returns a local proposal, never a second publish action.
    /// A submitted block freezes its identities and cannot be revised during retry.
    public func replacingOutline(with edited: WorkoutProgram) throws -> WorkoutAIProposal {
        guard let original = program, original.trainingBlock == nil,
              (original.currentProgressIndex ?? 0) == 0, (original.skippedIndices ?? []).isEmpty,
              edited.userID == ownerID, edited.routines.allSatisfy({ $0.userID == ownerID }),
              Set(edited.routines.map(\.id)).count == edited.routines.count,
              let weekdays = edited.daysOfWeek, weekdays.count == request.daysPerWeek,
              Set(weekdays).count == weekdays.count, weekdays.allSatisfy({ (1...7).contains($0) }),
              let start = edited.startDate, start.timeIntervalSinceReferenceDate.isFinite else { throw WorkoutBlockError.changed }
        var replacement = edited
        replacement.id = original.id
        replacement.progressEpoch = original.progressEpoch
        replacement.currentProgressIndex = original.currentProgressIndex
        replacement.skippedIndices = original.skippedIndices
        replacement.trainingBlock = nil
        var result = self
        result.program = try validatedProgram(replacement)
        result.pendingRequest = nil
        return result
    }
}
@MainActor public final class WorkoutAIProposalStore {
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func load(userID: String) throws -> WorkoutAIProposal? {
        guard !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        let result = try store.load(WorkoutAIProposal.self, userID: userID, scope: "ai-workout-proposal-v1")?.value
        guard result == nil || (result?.ownerID == userID && result?.schemaVersion == 1) else { throw WorkoutBlockError.invalid }
        return result
    }
    public func save(_ proposal: WorkoutAIProposal) throws {
        guard DIContainer.shared.authService.currentUserID == proposal.ownerID, !proposal.ownerID.isEmpty, proposal.schemaVersion == 1 else { throw WorkoutBlockError.accountChanged }
        try store.save(proposal, userID: proposal.ownerID, scope: "ai-workout-proposal-v1")
    }
    public func remove(userID: String) throws {
        _ = try load(userID: userID)
        try store.remove(userID: userID, scope: "ai-workout-proposal-v1")
    }
}
