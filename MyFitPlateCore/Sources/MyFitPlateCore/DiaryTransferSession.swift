import Combine
import Foundation

/// A transfer has no optimistic diary overlay. A failed/offline transaction keeps
/// this account-scoped command for retry while its source remains in the diary.
@MainActor
public final class DiaryTransferSession: ObservableObject {
    public struct Checkpoint: Codable {
        public var draft: DiaryTransferDraft
        public var command: DiaryTransferCommand?
        public var receipt: DiaryTransferReceipt?
        public var undoSubmitted = false
    }

    @Published public private(set) var checkpoint: Checkpoint?
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastVerifiedResult: DiaryTransferResult?
    public let userID: String
    public var draft: DiaryTransferDraft? { checkpoint?.draft }
    public var command: DiaryTransferCommand? { checkpoint?.command }
    public var receipt: DiaryTransferReceipt? { checkpoint?.receipt }
    public var isFrozen: Bool { command != nil }
    public private(set) var isUnreadable = false
    private let store: EditorDraftStore
    private let scope: String
    private let currentUserID: () -> String?

    public init(userID: String, draft: DiaryTransferDraft? = nil, store: EditorDraftStore = EditorDraftStore(),
                scope: String = "diary-transfer", currentUserID: (() -> String?)? = nil) {
        self.userID = userID; self.store = store; self.scope = scope
        self.currentUserID = currentUserID ?? { DIContainer.shared.authService.currentUserID }
        do {
            if let existing = try store.load(Checkpoint.self, userID: userID, scope: scope)?.value {
                guard existing.draft.source.userID == userID, existing.draft.destination.userID == userID,
                      existing.command?.userID == nil || existing.command?.userID == userID,
                      existing.receipt == nil || existing.command != nil,
                      !existing.undoSubmitted || existing.receipt != nil else { throw DiaryTransferError.receiptMismatch }
                try existing.command?.validate()
                try existing.receipt?.validate()
                if let command = existing.command {
                    guard existing.draft.id == command.id, existing.draft.source == command.source,
                          existing.draft.destination == command.destination, existing.draft.mode == command.mode else {
                        throw DiaryTransferError.receiptMismatch
                    }
                }
                if let command = existing.command, let receipt = existing.receipt,
                   try command.fingerprint() != receipt.commandFingerprint { throw DiaryTransferError.receiptMismatch }
                checkpoint = existing
            } else if let draft {
                guard draft.source.userID == userID, draft.destination.userID == userID else { throw DiaryTransferError.accountChanged }
                _ = persist(Checkpoint(draft: draft))
            }
        } catch {
            isUnreadable = true
            errorMessage = "The previous transfer could not be opened. It has been kept unchanged on this device."
        }
    }

    @discardableResult
    public func updateDraft(_ update: (inout DiaryTransferDraft) -> Void) -> Bool {
        guard usable, !isSaving, var next = checkpoint, next.command == nil else { return false }
        update(&next.draft)
        guard next.draft.source.userID == userID, next.draft.destination.userID == userID else { return false }
        return persist(next)
    }

    public func submit(using repository: NutritionRepositoryProtocol) async -> DiaryTransferResult? {
        lastVerifiedResult = nil
        guard usable, !isSaving, var next = checkpoint else { return nil }
        if next.receipt?.undoneAt != nil { errorMessage = DiaryTransferError.alreadyUndone.localizedDescription; return nil }
        do {
            if next.command == nil { next.command = try next.draft.freeze() }
            guard persist(next), let command = next.command else { return nil }
            isSaving = true; defer { isSaving = false }
            let result = try await repository.applyDiaryTransfer(userID: userID, command: command)
            guard usable else { return nil }
            try result.receipt.validate()
            guard result.receipt.commandFingerprint == (try command.fingerprint()) else { throw DiaryTransferError.receiptMismatch }
            next.receipt = result.receipt
            guard persist(next) else {
                errorMessage = "The transfer was saved. Its retry receipt is kept; retry to finish without duplicates."
                return nil
            }
            lastVerifiedResult = result
            return result
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    public func undo(using repository: NutritionRepositoryProtocol) async -> DiaryTransferResult? {
        lastVerifiedResult = nil
        guard usable, !isSaving, var next = checkpoint, let receipt = next.receipt else { return nil }
        next.undoSubmitted = true
        guard persist(next) else { return nil }
        isSaving = true; defer { isSaving = false }
        do {
            let result = try await repository.undoDiaryTransfer(userID: userID, receipt: receipt)
            guard usable else { return nil }
            try result.receipt.validate()
            guard result.receipt.commandFingerprint == receipt.commandFingerprint,
                  result.receipt.undoneAt != nil else { throw DiaryTransferError.receiptMismatch }
            next.receipt = result.receipt
            next.undoSubmitted = false
            guard persist(next) else {
                errorMessage = "Undo was saved. Retry to finish its receipt; it will not run twice."
                return nil
            }
            lastVerifiedResult = result
            return result
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    /// Cancellation is a server transaction at the operation's permanent receipt,
    /// never a local assumption based on an absent receipt or a failed request.
    public func cancelUnaccepted(using repository: NutritionRepositoryProtocol) async -> Bool {
        lastVerifiedResult = nil
        guard usable, !isSaving, var next = checkpoint, let command = next.command, next.receipt == nil else { return false }
        isSaving = true; defer { isSaving = false }
        do {
            if let result = try await repository.cancelDiaryTransfer(userID: userID, command: command) {
                guard usable else { return false }
                try result.receipt.validate()
                guard result.receipt.commandFingerprint == (try command.fingerprint()) else { throw DiaryTransferError.receiptMismatch }
                next.receipt = result.receipt; next.undoSubmitted = false
                guard persist(next) else { return false }
                lastVerifiedResult = result
                return false
            }
            guard usable else { return false }
            lastVerifiedResult = nil
            return clear()
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// A canonical remote read settles an interrupted/conflicted Undo without
    /// repeating it. Verification failure keeps the submitted intent untouched.
    public func refresh(using repository: NutritionRepositoryProtocol) async -> DiaryTransferResult? {
        lastVerifiedResult = nil
        guard usable, !isSaving, var next = checkpoint, let command = next.command else { return nil }
        isSaving = true; defer { isSaving = false }
        do {
            let result = try await repository.fetchDiaryTransfer(userID: userID, command: command)
            guard usable else { return nil }
            try result.receipt.validate()
            guard result.receipt.commandFingerprint == (try command.fingerprint()) else { throw DiaryTransferError.receiptMismatch }
            next.receipt = result.receipt; next.undoSubmitted = false
            guard persist(next) else { return nil }
            lastVerifiedResult = result
            return result
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    /// History Undo shares the same durable command/ack path without replacing any
    /// unrelated proposal or unresolved submission already kept on this device.
    @discardableResult
    public func prepareUndo(of receipt: DiaryTransferReceipt) -> Bool {
        guard usable, !isSaving, receipt.command.userID == userID else { return false }
        do {
            try receipt.validate()
            if let existing = checkpoint {
                guard let command = existing.command, command.id == receipt.id,
                      try command.fingerprint() == receipt.commandFingerprint else { return false }
            }
            let next = Checkpoint(draft: try DiaryTransferDraft(resuming: receipt.command), command: receipt.command,
                                  receipt: receipt, undoSubmitted: receipt.undoneAt == nil && checkpoint?.undoSubmitted == true)
            return persist(next)
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// Call after the acknowledged receipt has been consumed/stored for any Undo UI.
    @discardableResult
    public func finish() -> Bool {
        guard usable, !isSaving, checkpoint?.receipt != nil, checkpoint?.undoSubmitted != true else { return false }
        return clear()
    }

    /// Submitted commands cannot be discarded while their remote outcome is unknown.
    @discardableResult
    public func discardProposal() -> Bool {
        guard usable, !isSaving, checkpoint?.command == nil else { return false }
        return clear()
    }

    private var usable: Bool {
        guard !isUnreadable, currentUserID() == userID else {
            if !isUnreadable { errorMessage = DiaryTransferError.accountChanged.localizedDescription }
            return false
        }
        return true
    }

    private func persist(_ next: Checkpoint) -> Bool {
        guard usable else { return false }
        do {
            try store.save(next, userID: userID, scope: scope)
            checkpoint = next; errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not keep this transfer on the device. Keep this screen open and retry."
            return false
        }
    }

    private func clear() -> Bool {
        do { try store.remove(userID: userID, scope: scope); checkpoint = nil; errorMessage = nil; return true } catch {
            errorMessage = "The saved transfer receipt could not be cleared. Retry safely."
            return false
        }
    }
}
