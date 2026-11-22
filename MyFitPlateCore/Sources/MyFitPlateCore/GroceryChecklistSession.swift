import Foundation
import Combine

/// A compare-and-set patch: unrelated grocery rows are never replaced by a checklist tap.
public struct GroceryListMutation: Codable, Equatable {
    public var id: UUID
    public var before: [GroceryListItem]
    public var upserts: [GroceryListItem]
    public var removedIDs: Set<UUID>
    public var title: String?
    public var shoppingStartDate: Date?
    public var undoingID: UUID?

    public init(id: UUID = UUID(), before: [GroceryListItem], upserts: [GroceryListItem], removedIDs: Set<UUID>,
                title: String? = nil, shoppingStartDate: Date? = nil, undoingID: UUID? = nil) {
        self.id = id; self.before = before
        self.upserts = upserts.map { item in
            var updated = item; updated.revisionID = Self.revisionID(operationID: id, itemID: item.id); return updated
        }
        self.removedIDs = removedIDs
        self.title = title; self.shoppingStartDate = shoppingStartDate; self.undoingID = undoingID
    }
    private enum CodingKeys: String, CodingKey { case id, before, upserts, removedIDs, title, shoppingStartDate, undoingID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        before = try values.decode([GroceryListItem].self, forKey: .before)
        upserts = try values.decode([GroceryListItem].self, forKey: .upserts)
        removedIDs = try values.decode(Set<UUID>.self, forKey: .removedIDs)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        shoppingStartDate = try values.decodeIfPresent(Date.self, forKey: .shoppingStartDate)
        undoingID = try values.decodeIfPresent(UUID.self, forKey: .undoingID)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(before, forKey: .before); try values.encode(upserts, forKey: .upserts)
        try values.encode(removedIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .removedIDs)
        try values.encodeIfPresent(title, forKey: .title); try values.encodeIfPresent(shoppingStartDate, forKey: .shoppingStartDate)
        try values.encodeIfPresent(undoingID, forKey: .undoingID)
    }

    public var itemIDs: Set<UUID> { Set(upserts.map(\.id)).union(removedIDs) }
    public var savedShoppingDays: Set<String> {
        var days = Set((before + upserts).compactMap(\.savedShoppingDay))
        // A 2.3 device can put a previously parked ID back in the visible list. Its
        // latest visible choice wins when that row is removed or moved again.
        for item in before where removedIDs.contains(item.id) && (item.source == "mealPlan" || item.source == "retainedPurchase") {
            if let start = item.sourcePlanStart { days.insert(MealPlanEditingRules.dayID(start)) }
        }
        return days
    }
    public var fingerprint: String { get throws { try PlanFingerprint.make(self) } }
    public static func revisionID(operationID: UUID, itemID: UUID) -> String {
        "\(operationID.uuidString.lowercased())-\(itemID.uuidString.lowercased())"
    }

    public func applying(to items: [GroceryListItem], checkingConflicts: Bool = true) throws -> [GroceryListItem] {
        guard Set(items.map(\.id)).count == items.count, Set(upserts.map(\.id)).count == upserts.count,
              Set(before.map(\.id)).count == before.count, Set(before.map(\.id)).isSubset(of: itemIDs),
              removedIDs.isDisjoint(with: upserts.map(\.id)), undoingID != id,
              (try JSONEncoder().encode(self)).count <= 350_000,
              upserts.allSatisfy({ $0.quantity.isFinite && $0.quantity >= 0 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.productSnapshot?.isValid != false && $0.quantityOverride?.isValid != false
                  && ($0.revisionID == nil || $0.revisionID == Self.revisionID(operationID: id, itemID: $0.id)) }) else {
            throw GroceryChecklistError.invalid
        }
        if checkingConflicts {
            for itemID in itemIDs {
                let actual = items.first { $0.id == itemID }
                let expected = before.first { $0.id == itemID }
                let desired = upserts.first { $0.id == itemID }
                guard actual == expected || actual == desired else { throw GroceryChecklistError.changed }
            }
        }
        var result = items.filter { !removedIDs.contains($0.id) }
        for item in upserts {
            if let index = result.firstIndex(where: { $0.id == item.id }) { result[index] = item } else { result.append(item) }
        }
        return result
    }
    public func inverse() -> GroceryListMutation {
        GroceryListMutation(before: upserts, upserts: before,
            removedIDs: Set(upserts.map(\.id)).subtracting(before.map(\.id)),
            title: "Undo \(title ?? "shopping change")", shoppingStartDate: shoppingStartDate, undoingID: id)
    }
    public func validateInverse(of original: GroceryListMutation) throws {
        guard undoingID == original.id, id != original.id,
              title == "Undo \(original.title ?? "shopping change")", shoppingStartDate == original.shoppingStartDate,
              removedIDs == Set(original.upserts.map(\.id)).subtracting(original.before.map(\.id)),
              Set(before.map(\.id)) == Set(original.upserts.map(\.id)),
              upserts.count == original.before.count,
              before.allSatisfy({ row in original.upserts.first(where: { $0.id == row.id }) == row }) else { throw GroceryChecklistError.changed }
        for restored in upserts {
            guard var expected = original.before.first(where: { $0.id == restored.id }) else { throw GroceryChecklistError.changed }
            expected.revisionID = Self.revisionID(operationID: id, itemID: expected.id)
            guard expected == restored else { throw GroceryChecklistError.changed }
        }
    }
}

public struct GroceryMutationHistoryEntry: Codable, Identifiable {
    public let mutation: GroceryListMutation
    public let acceptedAt: Date
    public var undoneBy: UUID?
    public var id: UUID { mutation.id }
}

public enum GroceryChecklistError: Int, Error, LocalizedError, CustomNSError {
    case invalid = 400, accountChanged = 401, changed = 409, cancelled = 410, unavailable = 503
    public static var errorDomain: String { "MyFitPlate.GroceryChecklist" }
    public var errorCode: Int { rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "The shopping change could not be confirmed."] }
    public var errorDescription: String? {
        switch self {
        case .changed: "This grocery item changed elsewhere. Your local change is kept. Reload the account list to use its current version."
        case .invalid: "Review the grocery item before saving."
        case .accountChanged: "Sign back into the account that opened this grocery list."
        case .cancelled: "This shopping operation was cancelled. Its reviewed values are kept; resolve dependent reviews before preparing a fresh change."
        case .unavailable: "The account has not confirmed this shopping change. Its exact operation is kept for retry or status checking."
        }
    }
}

public struct GroceryCancelledDraft: Codable, Identifiable {
    public let mutation: GroceryListMutation
    public let cancelledAt: Date
    public var reviewOperationID: UUID?
    public var restoredBy: UUID?
    public var id: UUID { mutation.id }
}

public struct GroceryChecklistCheckpoint: Codable {
    public var items: [GroceryListItem]
    public var operations: [GroceryListMutation]
    public var history: [GroceryMutationHistoryEntry]?
    public var hideCompleted: Bool?
    public var cancelledDrafts: [GroceryCancelledDraft]?
    public var cancellingOperationIDs: [UUID]?
    public var operationResolutions: [String: String]?
}

@MainActor
public final class GroceryChecklistSession: ObservableObject {
    @Published public private(set) var checkpoint = GroceryChecklistCheckpoint(items: [], operations: [])
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    public let userID: String?
    private let store: EditorDraftStore
    private let scope = "grocery-checklist"
    private var unreadable = false
    private var expectedFingerprint: String?
    public var items: [GroceryListItem] { checkpoint.items }
    public var pendingCount: Int { checkpoint.operations.count }
    public var pendingItemIDs: Set<UUID> { checkpoint.operations.reduce(into: []) { $0.formUnion($1.itemIDs) } }
    public var history: [GroceryMutationHistoryEntry] { checkpoint.history ?? [] }
    public var cancelledDrafts: [GroceryCancelledDraft] { checkpoint.cancelledDrafts ?? [] }
    public var isCancelling: Bool { checkpoint.cancellingOperationIDs != nil }

    public init(userID: String?, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.store = store
        guard let userID else { return }
        do {
            if let saved = try store.load(GroceryChecklistCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = saved.value; expectedFingerprint = try PlanFingerprint.make(saved.value)
            }
        } catch {
            unreadable = true
            errorMessage = "The previous grocery changes could not be opened. They have been kept on this device."
        }
    }

    @discardableResult
    public func installRemote(_ items: [GroceryListItem]) -> Bool {
        var projected = items
        do {
            for operation in checkpoint.operations { projected = try operation.applying(to: projected, checkingConflicts: false) }
            var next = checkpoint; next.items = projected
            return persist(next)
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// Local acceptance happens only after the recoverable operation reaches disk.
    @discardableResult
    public func stage(_ items: [GroceryListItem], title: String? = nil, shoppingStartDate: Date? = nil) -> Bool {
        let changed = items.filter { item in checkpoint.items.first(where: { $0.id == item.id }) != item }
        let removed = Set(checkpoint.items.map(\.id)).subtracting(items.map(\.id))
        guard !changed.isEmpty || !removed.isEmpty else { return true }
        let ids = Set(changed.map(\.id)).union(removed)
        let operation = GroceryListMutation(before: checkpoint.items.filter { ids.contains($0.id) }, upserts: changed, removedIDs: removed,
            title: title, shoppingStartDate: shoppingStartDate)
        return stage(operation)
    }
    @discardableResult public func stage(_ operation: GroceryListMutation) -> Bool {
        do {
            guard !isCancelling else { throw GroceryChecklistError.cancelled }
            guard checkpoint.operations.count < 200 else { throw GroceryChecklistError.invalid }
            if let pending = checkpoint.operations.first(where: { $0.id == operation.id }) {
                guard pending == operation else { throw GroceryChecklistError.changed }
                return true
            }
            let projected = try operation.applying(to: checkpoint.items)
            var next = checkpoint; next.items = projected; next.operations.append(operation)
            return persist(next)
        } catch { errorMessage = error.localizedDescription; return false }
    }
    public func setHideCompleted(_ hide: Bool) -> Bool {
        var next = checkpoint; next.hideCompleted = hide; return persist(next)
    }
    public func undo(_ entry: GroceryMutationHistoryEntry, shoppingStartDate: Date? = nil) -> Bool {
        guard !isSaving, !isCancelling, let accepted = history.first(where: { $0.id == entry.id }), accepted.undoneBy == nil,
              !checkpoint.operations.contains(where: { !$0.itemIDs.isDisjoint(with: entry.mutation.itemIDs) }) else { return false }
        if let expected = entry.mutation.shoppingStartDate, let shoppingStartDate,
           !Calendar.current.isDate(expected, inSameDayAs: shoppingStartDate) {
            errorMessage = "Open the original shopping period to review this Undo."; return false
        }
        let inverse = accepted.mutation.inverse()
        do {
            let projected = try inverse.applying(to: checkpoint.items)
            var next = checkpoint; next.items = projected; next.operations.append(inverse)
            return persist(next)
        } catch { errorMessage = "This shopping item changed since that action. Later purchases and edits are kept. " + error.localizedDescription; return false }
    }

    public func retry(using repository: NutritionRepositoryProtocol) async {
        guard !isSaving, canUseAccount else { return }
        if isCancelling { _ = await cancelAllPending(using: repository); return }
        isSaving = true
        defer { isSaving = false }
        while let operation = checkpoint.operations.first {
            guard canUseAccount else { errorMessage = GroceryChecklistError.accountChanged.localizedDescription; return }
            do {
                guard checkpoint.operationResolutions?[operation.id.uuidString] != "cancelled" else { throw GroceryChecklistError.cancelled }
                let remote = try await repository.applyGroceryMutation(userID: userID!, mutation: operation)
                guard canUseAccount else { errorMessage = GroceryChecklistError.accountChanged.localizedDescription; return }
                var next = checkpoint
                next.operations.removeAll { $0.id == operation.id }
                recordAccepted(operation, in: &next)
                var projected = remote
                for pending in next.operations { projected = try pending.applying(to: projected, checkingConflicts: false) }
                next.items = projected
                guard persist(next) else { return } // Retain the same receipt if checkpoint cleanup failed.
            } catch {
                errorMessage = "Grocery changes are saved on this device and need retry. \(error.localizedDescription)"
                return
            }
        }
    }

    public func reloadDiscardingPending(using repository: NutritionRepositoryProtocol) async -> Bool {
        await cancelAllPending(using: repository)
    }

    public func checkSavedStatus(using repository: NutritionRepositoryProtocol) async {
        guard !isSaving, canUseAccount, let userID else { return }
        if isCancelling { _ = await cancelAllPending(using: repository); return }
        guard let operation = checkpoint.operations.first else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let resolution = try await repository.resolveGroceryMutation(userID: userID, mutation: operation, cancelPending: false)
            guard canUseAccount else { throw GroceryChecklistError.accountChanged }
            switch resolution {
            case .pending: errorMessage = "The first shopping change has not been accepted. Retry it, or review cancellation of all pending changes."
            case .cancelled:
                var next = checkpoint; next.operationResolutions = next.operationResolutions ?? [:]
                next.operationResolutions?[operation.id.uuidString] = "cancelled"
                if persist(next) { errorMessage = "The first change was cancelled. Later dependent reviews are kept; resolve all pending changes before creating a fresh review." }
            case .accepted:
                let remote = try await repository.fetchGroceryList(userID: userID)
                guard canUseAccount else { throw GroceryChecklistError.accountChanged }
                var next = checkpoint; next.operations.removeAll { $0.id == operation.id }; recordAccepted(operation, in: &next)
                var projected = remote
                for pending in next.operations { projected = try pending.applying(to: projected, checkingConflicts: false) }
                next.items = projected; _ = persist(next)
            }
        } catch { errorMessage = "Your shopping reviews are kept. " + error.localizedDescription }
    }

    @discardableResult public func cancelAllPending(using repository: NutritionRepositoryProtocol) async -> Bool {
        guard !isSaving, canUseAccount, let userID else { return false }
        isSaving = true; defer { isSaving = false }
        if !isCancelling {
            var next = checkpoint; next.cancellingOperationIDs = next.operations.map(\.id)
            guard persist(next) else { return false }
        }
        let frozenIDs = checkpoint.cancellingOperationIDs ?? []
        do {
            for id in frozenIDs {
                guard canUseAccount, let operation = checkpoint.operations.first(where: { $0.id == id }) else { throw GroceryChecklistError.changed }
                let cached = checkpoint.operationResolutions?[id.uuidString]
                let resolution: GroceryMutationResolution
                if cached == "accepted" { resolution = .accepted } else if cached == "cancelled" { resolution = .cancelled } else {
                    resolution = try await repository.resolveGroceryMutation(userID: userID, mutation: operation, cancelPending: true)
                }
                guard canUseAccount else { throw GroceryChecklistError.accountChanged }
                var next = checkpoint; next.operationResolutions = next.operationResolutions ?? [:]
                switch resolution {
                case .pending: throw GroceryChecklistError.unavailable
                case .accepted:
                    next.operationResolutions?[id.uuidString] = "accepted"; recordAccepted(operation, in: &next)
                case .cancelled:
                    next.operationResolutions?[id.uuidString] = "cancelled"
                    var drafts = next.cancelledDrafts ?? []
                    for index in drafts.indices where drafts[index].reviewOperationID == id { drafts[index].reviewOperationID = nil }
                    if !drafts.contains(where: { $0.id == id }) { drafts.append(GroceryCancelledDraft(mutation: operation, cancelledAt: Date())) }
                    next.cancelledDrafts = drafts
                }
                guard persist(next) else { return false }
            }
            let remote = try await repository.fetchGroceryList(userID: userID)
            guard canUseAccount else { throw GroceryChecklistError.accountChanged }
            var next = checkpoint; let ids = Set(frozenIDs)
            next.operations.removeAll { ids.contains($0.id) }; next.cancellingOperationIDs = nil
            var projected = remote
            for pending in next.operations { projected = try pending.applying(to: projected, checkingConflicts: false) }
            next.items = projected
            guard persist(next) else { return false }
            return true
        } catch { errorMessage = "Cancellation is unfinished. Every exact review and confirmed result is kept; retry resolution to finish safely. " + error.localizedDescription; return false }
    }

    public func stageReviewedCancelledDraft(_ draft: GroceryCancelledDraft, proposal: GroceryListMutation) -> Bool {
        guard !isCancelling, let index = cancelledDrafts.firstIndex(where: { $0.id == draft.id }),
              cancelledDrafts[index].restoredBy == nil, proposal.id != draft.id, proposal.undoingID == nil,
              !checkpoint.operations.contains(where: { $0.id == cancelledDrafts[index].reviewOperationID }) else { return false }
        do {
            let projected = try proposal.applying(to: checkpoint.items)
            var next = checkpoint; next.items = projected; next.operations.append(proposal)
            next.cancelledDrafts?[index].reviewOperationID = proposal.id
            return persist(next)
        } catch { errorMessage = "The current list changed while this new review was open. The cancelled draft is still kept. " + error.localizedDescription; return false }
    }

    public func discardCancelledDraft(_ draft: GroceryCancelledDraft) -> Bool {
        guard !isSaving, !checkpoint.operations.contains(where: { $0.id == draft.reviewOperationID }) else { return false }
        var next = checkpoint; next.cancelledDrafts?.removeAll { $0.id == draft.id }; return persist(next)
    }

    private func recordAccepted(_ operation: GroceryListMutation, in next: inout GroceryChecklistCheckpoint) {
        var history = next.history ?? []
        if !history.contains(where: { $0.id == operation.id }) { history.append(GroceryMutationHistoryEntry(mutation: operation, acceptedAt: Date())) }
        if let original = operation.undoingID, let index = history.firstIndex(where: { $0.id == original }) { history[index].undoneBy = operation.id }
        next.history = Array(history.suffix(100))
        if let index = next.cancelledDrafts?.firstIndex(where: { $0.reviewOperationID == operation.id }) { next.cancelledDrafts?[index].restoredBy = operation.id }
    }

    private var canUseAccount: Bool { !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID }
    private func persist(_ next: GroceryChecklistCheckpoint) -> Bool {
        guard canUseAccount, let userID else { return false }
        do {
            let previous = try store.load(GroceryChecklistCheckpoint.self, userID: userID, scope: scope)?.value
            guard try previous.map(PlanFingerprint.make) == expectedFingerprint else { throw GroceryChecklistError.changed }
            try store.save(next, userID: userID, scope: scope)
            checkpoint = next; expectedFingerprint = try PlanFingerprint.make(next); errorMessage = nil; return true
        } catch {
            errorMessage = "Could not keep this grocery change on the device. The last saved list is still shown."
            return false
        }
    }
}
