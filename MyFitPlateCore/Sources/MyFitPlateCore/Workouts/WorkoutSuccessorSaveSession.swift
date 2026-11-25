import Combine
import Foundation

public struct WorkoutSuccessorDraft: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let userID: String
    public let sourceProgramID: String
    public let sourcePayload: Data
    public var destinationPayload: Data
    public var command: WorkoutProgramSuccessorCommand?

    public init(source: WorkoutProgram, destination: WorkoutProgram) throws {
        guard let id = source.id else { throw WorkoutSuccessorError.invalid }
        schemaVersion = 1; userID = source.userID; sourceProgramID = id
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        sourcePayload = try encoder.encode(source); destinationPayload = try encoder.encode(destination)
    }
    public func source() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: sourcePayload) }
    public func destination() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: destinationPayload) }
}

/// The exact pending successor is durable before transmission. Accepted creation is
/// separate from choosing it as active; closing the sheet never changes the plan.
@MainActor
public final class WorkoutSuccessorSaveSession: ObservableObject {
    @Published public private(set) var draft: WorkoutSuccessorDraft
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var wasAccepted = false
    @Published public private(set) var wasCancelled = false
    @Published public private(set) var acceptedProgram: WorkoutProgram?
    @Published public private(set) var didActivate = false
    @Published public private(set) var isFinished = false
    public let restored: Bool
    private let store: EditorDraftStore
    private let currentUserID: () -> String?
    public static func scope(sourceProgramID: String) -> String { "workout-successor-\(sourceProgramID)" }
    public var isSubmitted: Bool { draft.command != nil }
    public var isResolved: Bool { wasAccepted || wasCancelled }

    public init(source: WorkoutProgram, store: EditorDraftStore = EditorDraftStore(),
                currentUserID: (() -> String?)? = nil) throws {
        self.store = store
        self.currentUserID = currentUserID ?? { DIContainer.shared.authService.currentUserID }
        guard let sourceID = source.id, self.currentUserID() == source.userID else { throw WorkoutSuccessorError.accountChanged }
        let scope = Self.scope(sourceProgramID: sourceID)
        if let saved = try store.load(WorkoutSuccessorDraft.self, userID: source.userID, scope: scope) {
            guard saved.value.schemaVersion == 1, saved.value.userID == source.userID, saved.value.sourceProgramID == sourceID,
                  try saved.value.source().id == sourceID, try saved.value.destination().id != sourceID else {
                throw WorkoutSuccessorError.invalid
            }
            if let command = saved.value.command {
                try WorkoutProgramSuccessorRules.validate(command)
                guard command.userID == source.userID, command.sourceProgramID == sourceID,
                      try WorkoutBlockRules.fingerprint(command.source()) == WorkoutBlockRules.fingerprint(saved.value.source()),
                      try WorkoutBlockRules.fingerprint(command.destination()) == WorkoutBlockRules.fingerprint(saved.value.destination()) else {
                    throw WorkoutSuccessorError.invalid
                }
            }
            draft = saved.value; restored = true
        } else {
            let today = Calendar.current.startOfDay(for: Date())
            let afterLast = source.date(forSlot: max(source.totalSlots - 1, 0)).flatMap {
                Calendar.current.date(byAdding: .day, value: 1, to: $0)
            }
            let destination = try WorkoutProgramSuccessorRules.prepare(from: source, startDate: max(today, afterLast ?? today))
            let created = try WorkoutSuccessorDraft(source: source, destination: destination)
            try store.save(created, userID: source.userID, scope: scope)
            draft = created; restored = false
        }
    }

    public func update(_ mutation: (inout WorkoutProgram) throws -> Void) throws {
        guard canWork, !isSubmitted else { throw WorkoutSuccessorError.changed }
        var destination = try draft.destination()
        try mutation(&destination)
        guard destination.id == (try draft.destination().id), destination.userID == draft.userID else { throw WorkoutSuccessorError.invalid }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var updated = draft; updated.destinationPayload = try encoder.encode(destination)
        try persist(updated)
        errorMessage = nil
    }

    public func updateTargets(_ destination: WorkoutProgram) throws {
        try update { value in
            guard value.id == destination.id else { throw WorkoutSuccessorError.invalid }
            value = destination
            value.lineage?.mode = .adjusted
            _ = try WorkoutProgramSuccessorCommand(source: draft.source(), destination: value)
        }
    }

    public func submit(using service: WorkoutService) async -> Bool {
        guard canWork, !isResolved else { return false }
        do {
            if draft.command == nil {
                var updated = draft
                updated.command = try WorkoutProgramSuccessorCommand(source: draft.source(), destination: draft.destination())
                try persist(updated)
            }
            guard let command = draft.command else { return false }
            isWorking = true; errorMessage = nil
            defer { isWorking = false }
            let current = try await service.createProgramSuccessor(command)
            guard currentUserID() == draft.userID else { return false }
            acceptedProgram = current; wasAccepted = true
            return true
        } catch {
            if currentUserID() == draft.userID { errorMessage = error.localizedDescription }
            return false
        }
    }

    public func resolve(using service: WorkoutService, cancelPending: Bool = false) async -> Bool {
        guard canWork, let command = draft.command, !isResolved else { return false }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await service.resolveProgramSuccessor(command, cancelPending: cancelPending)
            guard currentUserID() == draft.userID else { return false }
            switch result {
            case .pending:
                errorMessage = "No accepted receipt is available yet. Retry this fixed proposal or cancel it safely."
                return false
            case .cancelled: wasCancelled = true
            case .accepted(let current): acceptedProgram = current; wasAccepted = true
            }
            return true
        } catch {
            if currentUserID() == draft.userID { errorMessage = error.localizedDescription }
            return false
        }
    }

    public func activate(using service: WorkoutService) async -> Bool {
        guard canWork, wasAccepted, acceptedProgram != nil, let command = draft.command else { return false }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let current = try await service.activateProgramSuccessor(command)
            guard currentUserID() == draft.userID else { return false }
            acceptedProgram = current; didActivate = true
            return true
        } catch {
            if currentUserID() == draft.userID { errorMessage = error.localizedDescription }
            return false
        }
    }

    /// Before submission this discards only an editing proposal. After submission a
    /// permanent remote resolution is required before its checkpoint can be cleared.
    @discardableResult public func finish() -> Bool {
        guard canWork, !isSubmitted || isResolved else { return false }
        do {
            try verifyCurrentCheckpoint()
            try store.remove(userID: draft.userID, scope: Self.scope(sourceProgramID: draft.sourceProgramID))
            isFinished = true; errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    public func showError(_ error: Error) { errorMessage = error.localizedDescription }

    private var canWork: Bool { !isWorking && !isFinished && currentUserID() == draft.userID }

    private func verifyCurrentCheckpoint() throws {
        guard let current = try store.load(WorkoutSuccessorDraft.self, userID: draft.userID,
            scope: Self.scope(sourceProgramID: draft.sourceProgramID)), current.value == draft else {
            throw WorkoutSuccessorError.changed
        }
    }

    private func persist(_ value: WorkoutSuccessorDraft) throws {
        try verifyCurrentCheckpoint()
        try store.save(value, userID: draft.userID, scope: Self.scope(sourceProgramID: draft.sourceProgramID))
        draft = value
    }
}
