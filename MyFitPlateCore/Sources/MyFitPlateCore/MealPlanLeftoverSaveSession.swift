import Combine
import Foundation

public struct MealPlanLeftoverCheckpoint: Codable {
    public var change: MealPlanChange
    public var sourceMealID: String
    public var destinationDate: Date
    public var mealType: String
    public var portions: Double
    public var submitted = false
    public var accepted = false
    public var cancelled = false

    public init(change: MealPlanChange, sourceMealID: String, destinationDate: Date, mealType: String, portions: Double) {
        self.change = change; self.sourceMealID = sourceMealID; self.destinationDate = destinationDate
        self.mealType = mealType; self.portions = portions
    }
}

/// Frozen payloads and permanent repository receipts prevent a lost acknowledgement,
/// later edit or app restart from adding another logical leftover allocation.
@MainActor
public final class MealPlanLeftoverSaveSession: ObservableObject {
    @Published public private(set) var checkpoint: MealPlanLeftoverCheckpoint?
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var restored = false
    public let userID: String?
    private let store: EditorDraftStore
    public static let scope = "meal-leftover-review"
    private var scope: String { Self.scope }
    private var unreadable = false

    public init(userID: String?, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.store = store
        guard let userID, DIContainer.shared.authService.currentUserID == userID else { return }
        do {
            if let saved = try store.load(MealPlanLeftoverCheckpoint.self, userID: userID, scope: scope) {
                try MealPlanEditingRules.validate(saved.value.change)
                checkpoint = saved.value; restored = true
            }
        } catch {
            unreadable = true; errorMessage = "Your previous leftover review couldn't be opened. It has been kept on this device."
        }
    }

    @discardableResult
    public func prepare(_ value: MealPlanLeftoverCheckpoint) -> Bool {
        guard checkpoint == nil, !isSaving else { return false }
        var frozen = value
        frozen.change.after = value.change.after.map { day in
            var updated = day; updated.id = MealPlanEditingRules.dayID(day.date)
            updated.meals = MealPlanEditingRules.sorted(day.meals); return updated
        }
        do {
            try MealPlanEditingRules.validate(frozen.change)
            if let userID, let existing = try store.load(MealPlanLeftoverCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = existing.value
                restored = true
                errorMessage = "A previous leftover review is ready to resume. Finish it before creating another."
                return false
            }
        } catch { errorMessage = "Couldn't open this leftover review. Your previous choices are kept."; return false }
        return persist(frozen)
    }

    @discardableResult
    public func changeUnsubmittedReview() -> Bool {
        guard !isSaving, checkpoint?.submitted == false, canUseAccount, let userID else { return false }
        do {
            guard try store.load(MealPlanLeftoverCheckpoint.self, userID: userID, scope: scope)?.value.change.id == checkpoint?.change.id else { return false }
            try store.remove(userID: userID, scope: scope); checkpoint = nil; errorMessage = nil; return true
        } catch { errorMessage = "Couldn't change this review. Your previous choices are still kept."; return false }
    }

    public func save(using planner: MealPlannerService) async -> Bool {
        guard !isSaving, canUseAccount, let userID, var value = checkpoint else { return false }
        if value.accepted { return true }
        guard !value.cancelled else { errorMessage = "This reviewed save was cancelled. Close its receipt before creating another review."; return false }
        isSaving = true; defer { isSaving = false }
        value.submitted = true
        guard persist(value) else { return false }
        do {
            try await planner.applyPlanChange(value.change, for: userID)
            guard canUseAccount else { throw MealPlanEditError.accountChanged }
            value.accepted = true
            return persist(value)
        } catch {
            errorMessage = "Your exact leftover review is kept. Check its status or retry the same save."
            return false
        }
    }

    public func checkStatus(using repository: NutritionRepositoryProtocol, cancelPending: Bool = false) async {
        guard !isSaving, canUseAccount, let userID, var value = checkpoint else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let resolution = try await repository.resolveMealPlanChange(userID: userID, change: value.change, cancelPending: cancelPending)
            guard canUseAccount else { throw MealPlanEditError.accountChanged }
            switch resolution {
            case .accepted:
                value.accepted = true; value.cancelled = false
                _ = persist(value)
            case .cancelled:
                value.accepted = false; value.cancelled = true
                _ = persist(value)
            case .pending:
                errorMessage = "No saved receipt yet. Retry this exact review, or cancel its pending save before making another one."
            }
        } catch {
            errorMessage = "Couldn't confirm the leftover save yet. This review is kept; try checking again."
        }
    }

    @discardableResult
    public func finishAcceptedReview() -> Bool {
        guard !isSaving, checkpoint?.accepted == true || checkpoint?.cancelled == true,
              canUseAccount, let userID else { return false }
        do {
            guard try store.load(MealPlanLeftoverCheckpoint.self, userID: userID, scope: scope)?.value.change.id == checkpoint?.change.id else { return false }
            try store.remove(userID: userID, scope: scope); checkpoint = nil; return true
        } catch { errorMessage = "This save is resolved. Its receipt is kept on this device until it can be closed."; return false }
    }

    private var canUseAccount: Bool {
        !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID
    }

    private func persist(_ value: MealPlanLeftoverCheckpoint) -> Bool {
        guard canUseAccount, let userID else {
            if !unreadable { errorMessage = MealPlanEditError.accountChanged.localizedDescription }
            return false
        }
        do {
            if let existing = try store.load(MealPlanLeftoverCheckpoint.self, userID: userID, scope: scope),
               existing.value.change.id != value.change.id {
                errorMessage = "Another leftover review is already kept. Reopen it before making another change."
                return false
            }
            try store.save(value, userID: userID, scope: scope)
            checkpoint = value; errorMessage = nil; return true
        } catch { errorMessage = "Couldn't keep this leftover review on the device. Your previous choices are still here."; return false }
    }
}
