import Foundation
import Combine

/// A single account-scoped frozen save, separate from editable recipe content.
/// Possibly submitted work can only be cleared after a canonical receipt or cancellation fence.
@MainActor
public final class RecipeRevisionSaveSession: ObservableObject {
    public static let scope = "recipe-revision-save"
    public let userID: String?
    @Published public private(set) var proposal: RecipeRevisionSaveProposal?
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isUnreadable = false
    @Published public private(set) var isFinished = false
    @Published public private(set) var acceptedRecipe: Recipe?
    @Published public private(set) var wasAccepted = false
    private let store: EditorDraftStore
    private let currentUserID: () -> String?

    public init(userID: String?, store: EditorDraftStore = EditorDraftStore(), currentUserID: (() -> String?)? = nil) {
        self.userID = userID; self.store = store
        self.currentUserID = currentUserID ?? { DIContainer.shared.authService.currentUserID }
        guard let userID, self.currentUserID() == userID else { return }
        do {
            if let saved = try store.load(RecipeRevisionSaveProposal.self, userID: userID, scope: Self.scope) {
                guard saved.value.schemaVersion == 1, saved.value.userID == userID,
                      saved.value.updated.id?.isEmpty == false else { throw CocoaError(.coderReadCorrupt) }
                proposal = saved.value
            }
        } catch {
            isUnreadable = true
            errorMessage = "The pending recipe save cannot be read. It is still kept on this device; close this screen and use a compatible version to recover it."
        }
    }

    public func prepare(_ value: RecipeRevisionSaveProposal) -> Bool {
        guard !isWorking, !isUnreadable, !isFinished, let userID,
              currentUserID() == userID, value.userID == userID, value.schemaVersion == 1 else {
            errorMessage = "Reopen recipe editing for the signed-in account."
            return false
        }
        do {
            if let proposal {
                guard try PlanFingerprint.make(proposal) == PlanFingerprint.make(value) else {
                    errorMessage = "Finish the pending recipe save before starting another."
                    return false
                }
                return true
            }
            // Another editor cannot overwrite an already durable account-level proposal.
            if let existing = try store.load(RecipeRevisionSaveProposal.self, userID: userID, scope: Self.scope) {
                guard existing.value.schemaVersion == 1, existing.value.userID == userID,
                      existing.value.updated.id?.isEmpty == false else { throw CocoaError(.coderReadCorrupt) }
                proposal = existing.value
                errorMessage = "A pending recipe save is ready to resume. Finish it before starting another."
                return false
            }
            try store.save(value, userID: userID, scope: Self.scope)
            proposal = value; errorMessage = nil
            return true
        } catch {
            errorMessage = "The recipe could not be checkpointed on this device. Your fields are still here; try again."
            return false
        }
    }

    public func submit(using service: RecipeService) async -> Bool {
        guard beginWork(), let proposal, let userID else { return false }
        defer { isWorking = false }
        do {
            let saved = try await service.saveRecipeRevision(proposal.updated, for: userID,
                expected: proposal.expected, operationID: proposal.operationID)
            guard currentUserID() == userID else { return false }
            acceptedRecipe = saved; wasAccepted = true
            return finish(proposal)
        } catch {
            guard currentUserID() == userID else { return false }
            errorMessage = error.localizedDescription + " Your submitted version is kept unchanged. Retry, check its saved status, or cancel the pending save."
            return false
        }
    }

    public func resolve(using service: RecipeService, cancelIfUnaccepted: Bool) async -> Bool {
        guard beginWork(), let proposal, let userID else { return false }
        defer { isWorking = false }
        do {
            let resolution = try await service.resolveRecipeRevision(proposal, cancelIfUnaccepted: cancelIfUnaccepted)
            guard currentUserID() == userID else { return false }
            switch resolution {
            case .pending:
                errorMessage = "No accepted receipt is available yet. Retry this exact save, or cancel it safely before making a new proposal."
                return false
            case .cancelled:
                return finish(proposal)
            case .accepted(let current):
                acceptedRecipe = current; wasAccepted = true
                return finish(proposal)
            }
        } catch {
            guard currentUserID() == userID else { return false }
            errorMessage = error.localizedDescription + " The pending recipe save remains on this device."
            return false
        }
    }

    private func beginWork() -> Bool {
        guard !isWorking, !isFinished, !isUnreadable, proposal != nil, let userID, currentUserID() == userID else {
            return false
        }
        errorMessage = nil; isWorking = true
        return true
    }

    private func finish(_ accepted: RecipeRevisionSaveProposal) -> Bool {
        guard let userID, currentUserID() == userID else { return false }
        do {
            if let saved = try store.load(RecipeRevisionSaveProposal.self, userID: userID, scope: Self.scope) {
                guard try PlanFingerprint.make(saved.value) == PlanFingerprint.make(accepted) else {
                    errorMessage = "A newer pending recipe save is kept on this device. Close and reopen it."
                    return false
                }
                try store.remove(userID: userID, scope: Self.scope)
            }
            proposal = nil; isFinished = true
            return true
        } catch {
            errorMessage = "The saved status was confirmed, but its local recovery record could not be cleared. Retry to finish safely."
            return false
        }
    }
}
