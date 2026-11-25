import Foundation
import Combine

public struct FoodDetailSaveCheckpoint: Codable {
    public let original: FoodItem
    public let entryID: String
    public let date: Date
    public let mealName: String
    public let source: String
    public let isEditing: Bool
    public var food: FoodItem
    public var isSubmitted: Bool
    public var operationID: String?
    public var dayContext: DiaryDayContext?
    public var trainingFuelTarget: TrainingFuelTarget?
}

/// A detail editor owns its original account/day and freezes one logical consumption on
/// submission. A reopened editor retries that exact payload, including after cleanup failure.
@MainActor
public final class FoodDetailSaveSession: ObservableObject {
    @Published public private(set) var checkpoint: FoodDetailSaveCheckpoint
    @Published public private(set) var isSaving = false
    @Published public private(set) var isAccepted = false
    @Published public private(set) var restoredReview = false
    @Published public private(set) var errorMessage: String?
    public let userID: String?
    private let store: EditorDraftStore
    private let scope: String
    private var unreadable = false
    private var expectedFingerprint: String?

    public init(food: FoodItem, userID: String?, date: Date, mealName: String, source: String,
                isEditing: Bool, restoresExisting: Bool = true, dayContext: DiaryDayContext? = nil,
                store: EditorDraftStore = EditorDraftStore(), trainingFuelTarget: TrainingFuelTarget? = nil, draftScope: String? = nil) {
        self.userID = userID; self.store = store
        scope = draftScope ?? "food-detail-\(isEditing ? "edit" : "add")-\(source)-\(food.id)"
        let capturedDay = dayContext ?? userID.flatMap {
            DiaryDayContext(userID: $0, date: Calendar.current.startOfDay(for: date))
        }
        checkpoint = FoodDetailSaveCheckpoint(original: food, entryID: isEditing ? food.id : UUID().uuidString,
            date: capturedDay?.originalDate ?? Calendar.current.startOfDay(for: date), mealName: mealName, source: source,
            isEditing: isEditing, food: food, isSubmitted: false, dayContext: capturedDay)
        checkpoint.trainingFuelTarget = trainingFuelTarget
        checkpoint.operationID = UUID().uuidString
        guard restoresExisting, let userID else { return }
        do {
            if let saved = try store.load(FoodDetailSaveCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = saved.value; restoredReview = true
                expectedFingerprint = try PlanFingerprint.make(saved.value)
            }
        } catch { unreadable = true; errorMessage = "The previous food save could not be opened. It is kept on this device; nothing new has been logged." }
    }

    public func save(food: FoodItem, using service: DailyLogService, completion: @escaping (Bool) -> Void) {
        guard !isSaving, !isAccepted, canUseAccount, let userID, service.isActiveAccount(userID) else { completion(false); return }
        if checkpoint.operationID == nil {
            var next = checkpoint; next.operationID = UUID().uuidString
            guard persist(next) else { completion(false); return }
        }
        if !checkpoint.isSubmitted {
            guard [food.calories, food.protein, food.carbs, food.fats, food.servingWeight].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                errorMessage = "Review the food amounts before saving."; completion(false); return
            }
            var next = checkpoint; var item = food
            item.id = checkpoint.entryID
            item.timestamp = checkpoint.isEditing ? checkpoint.original.timestamp : Date()
            if let target = checkpoint.trainingFuelTarget {
                do {
                    guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                    try fuel.stageFoodLink(target: target, foods: [item], date: checkpoint.date, using: service, userID: userID)
                } catch { errorMessage = error.localizedDescription; completion(false); return }
            }
            next.food = item; next.isSubmitted = true
            guard persist(next) else { completion(false); return }
        }
        if let target = checkpoint.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.authorizeFoodLink(target: target, foods: [checkpoint.food], userID: userID)
            } catch { errorMessage = "Could not prepare the saved fuel link. Retry this review; no new food was sent."; completion(false); return }
        }
        isSaving = true
        let finish: (Bool) -> Void = { [weak self] accepted in
            guard let self else { completion(false); return }
            self.isSaving = false
            guard self.canUseAccount else { self.errorMessage = "Sign back into the account that opened this food."; completion(false); return }
            guard accepted else {
                self.errorMessage = "Could not save this food, or the original entry changed. Your reviewed amount and destination are kept for retry."
                completion(false); return
            }
            if let target = self.checkpoint.trainingFuelTarget {
                _ = service.trainingFuelPlanStore?.acceptFoodLink(target: target, foods: [self.checkpoint.food], userID: userID)
            }
            do {
                guard let fingerprint = self.expectedFingerprint,
                      try self.store.removeIfUnchanged(FoodDetailSaveCheckpoint.self, userID: userID, scope: self.scope, fingerprint: fingerprint) else { throw TrainingFuelLibraryError.changed }
                self.isAccepted = true; completion(true)
            } catch {
                self.errorMessage = "Your food was accepted. Retry to clear this review without adding it again."; completion(false)
            }
        }
        if checkpoint.isEditing {
            service.updateFood(for: userID, date: checkpoint.date, original: checkpoint.original, updated: checkpoint.food,
                               operationID: checkpoint.operationID, dayContext: checkpoint.dayContext, completion: finish)
        } else {
            service.addMealGroupsToLog(for: userID, date: checkpoint.date,
                mealGroups: [(mealName: checkpoint.mealName, foodItems: [checkpoint.food])],
                source: checkpoint.source, deduplicateFoodIDs: true, dayContext: checkpoint.dayContext, completion: finish)
        }
    }

    @discardableResult public func removeFuelContext() -> Bool {
        guard canUseAccount, !isSaving, !isAccepted, !checkpoint.isSubmitted else { return false }
        var next = checkpoint; next.trainingFuelTarget = nil
        return persist(next)
    }

    private var canUseAccount: Bool {
        !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID
            && (checkpoint.dayContext?.isOwned(by: userID) ?? true)
    }
    private func persist(_ next: FoodDetailSaveCheckpoint) -> Bool {
        guard canUseAccount, let userID else { return false }
        do {
            let current = try store.load(FoodDetailSaveCheckpoint.self, userID: userID, scope: scope)?.value
            guard try current.map(PlanFingerprint.make) == expectedFingerprint else { throw TrainingFuelLibraryError.changed }
            try store.save(next, userID: userID, scope: scope)
            checkpoint = next; expectedFingerprint = try PlanFingerprint.make(next); errorMessage = nil; return true
        } catch {
            errorMessage = "Could not keep your food save on this device. Keep this editor open and retry."; return false
        }
    }
}
