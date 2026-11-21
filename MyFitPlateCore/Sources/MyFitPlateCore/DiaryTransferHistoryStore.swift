import Combine
import Foundation

/// A bounded account-local index of acknowledged, operation-specific reversals.
/// Permanent server receipts remain authoritative; this is not a second diary.
@MainActor
public final class DiaryTransferHistoryStore: ObservableObject {
    @Published public private(set) var receipts: [DiaryTransferReceipt] = []
    @Published public private(set) var errorMessage: String?
    public let userID: String
    private let store: EditorDraftStore
    private let scope = "diary-transfer-history"
    private let currentUserID: () -> String?
    private var unreadable = false

    public init(userID: String, store: EditorDraftStore = EditorDraftStore(), currentUserID: (() -> String?)? = nil) {
        self.userID = userID; self.store = store
        self.currentUserID = currentUserID ?? { DIContainer.shared.authService.currentUserID }
        reload()
    }

    public func reload() {
        guard requireAccount() else { return }
        do {
            let saved = try store.load([DiaryTransferReceipt].self, userID: userID, scope: scope)?.value ?? []
            for receipt in saved {
                try receipt.validate()
                guard receipt.command.userID == userID else { throw DiaryTransferError.accountChanged }
            }
            receipts = saved; errorMessage = nil; unreadable = false
        } catch {
            unreadable = true
            errorMessage = "Food-change history could not be opened. Its saved receipts have been kept unchanged."
        }
    }

    @discardableResult
    public func record(_ receipt: DiaryTransferReceipt) -> Bool {
        guard requireAccount(), receipt.command.userID == userID else { return false }
        // Review and history screens can own separate instances. Merge against the
        // latest durable index rather than overwriting another instance's receipts.
        reload()
        guard !unreadable else { return false }
        do {
            try receipt.validate()
            let existing = receipts.first { $0.id == receipt.id }
            if let existing, existing.commandFingerprint != receipt.commandFingerprint {
                throw DiaryTransferError.receiptMismatch
            }
            // A delayed accepted response cannot erase an already acknowledged Undo.
            let merged: DiaryTransferReceipt
            if let existing, existing.undoneAt != nil { merged = existing } else { merged = receipt }
            var next = receipts.filter { $0.id != receipt.id }
            next.append(merged)
            next.sort { $0.acceptedAt > $1.acceptedAt }
            next = Array(next.prefix(20))
            try store.save(next, userID: userID, scope: scope)
            receipts = next; errorMessage = nil
            return true
        } catch {
            errorMessage = "The change was accepted, but its history receipt could not be kept. Retry before finishing."
            return false
        }
    }

    private func requireAccount() -> Bool {
        guard currentUserID() == userID else {
            receipts = []
            errorMessage = "Sign back into the account that owns this food-change history."
            return false
        }
        return true
    }
}
