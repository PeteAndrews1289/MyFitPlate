import Foundation
import Combine

public struct PlannedMealSaveCheckpoint: Codable {
    public let id: UUID
    public let date: Date
    public var meals: [Meal]
    public var isSubmitted: Bool
    public var trainingFuelTarget: TrainingFuelTarget?
}

/// A day-scoped receipt freezes reviewed planned occurrences independently of later plan edits.
@MainActor
public final class PlannedMealSaveSession: ObservableObject, Identifiable {
    @Published public private(set) var checkpoint: PlannedMealSaveCheckpoint
    @Published public private(set) var isSaving = false
    @Published public private(set) var isAccepted = false
    @Published public private(set) var restoredReview = false
    @Published public private(set) var errorMessage: String?
    public var id: UUID { checkpoint.id }
    public let userID: String?
    private let scope: String
    private let store: EditorDraftStore
    private var unreadable = false
    private var expectedFingerprint: String?

    public init(userID: String?, date: Date, meals: [Meal], trainingFuelTarget: TrainingFuelTarget? = nil, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.store = store
        scope = "planned-meal-save-\(MealPlanEditingRules.dayID(date))"
        checkpoint = PlannedMealSaveCheckpoint(id: UUID(), date: Calendar.current.startOfDay(for: date), meals: meals,
                                              isSubmitted: false, trainingFuelTarget: trainingFuelTarget)
        guard let userID else { return }
        do {
            if let saved = try store.load(PlannedMealSaveCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = saved.value; restoredReview = true
                expectedFingerprint = try PlanFingerprint.make(saved.value)
            }
        } catch { unreadable = true; errorMessage = "The previous planned-meal review could not be opened. It has been kept on this device." }
    }

    @discardableResult public func updateFood(_ food: FoodItem, entryID: String) -> Bool {
        guard !checkpoint.isSubmitted, !isSaving, !isAccepted, !unreadable, let userID,
              DIContainer.shared.authService.currentUserID == userID,
              food.id == entryID, [food.calories, food.protein, food.carbs, food.fats].allSatisfy({ $0.isFinite && $0 >= 0 }),
              let group = checkpoint.meals.firstIndex(where: { $0.foodItems.contains { $0.id == entryID } }),
              let index = checkpoint.meals[group].foodItems.firstIndex(where: { $0.id == entryID }) else { return false }
        var updated = checkpoint; updated.meals[group].foodItems[index] = food
        do { try persist(updated); return true } catch { errorMessage = "A newer review was kept. Close and reopen it before changing foods."; return false }
    }

    @discardableResult public func omitFood(entryID: String) -> Bool {
        guard !checkpoint.isSubmitted, !isSaving, !isAccepted, !unreadable else { return false }
        var updated = checkpoint
        updated.meals = updated.meals.compactMap { group in
            var value = group; value.foodItems.removeAll { $0.id == entryID }; return value.foodItems.isEmpty ? nil : value
        }
        do { try persist(updated); return true } catch { errorMessage = "The saved review changed. Close and reopen before changing selection."; return false }
    }

    @discardableResult public func discardUnsubmitted() -> Bool {
        guard !checkpoint.isSubmitted, !isSaving, let userID, DIContainer.shared.authService.currentUserID == userID else { return false }
        do {
            let current = try store.load(PlannedMealSaveCheckpoint.self, userID: userID, scope: scope)?.value
            guard try current.map(PlanFingerprint.make) == expectedFingerprint else { throw MealPlanEditError.changed }
            try store.remove(userID: userID, scope: scope); expectedFingerprint = nil; return true
        } catch { errorMessage = "This review could not be closed safely. Try again."; return false }
    }

    private func persist(_ value: PlannedMealSaveCheckpoint) throws {
        guard let userID, DIContainer.shared.authService.currentUserID == userID else { throw MealPlanEditError.accountChanged }
        let stored = try store.load(PlannedMealSaveCheckpoint.self, userID: userID, scope: scope)?.value
        guard try stored.map(PlanFingerprint.make) == expectedFingerprint else { throw MealPlanEditError.changed }
        try store.save(value, userID: userID, scope: scope); checkpoint = value; expectedFingerprint = try PlanFingerprint.make(value)
    }

    @discardableResult public func removeFuelContext() -> Bool {
        guard !checkpoint.isSubmitted, !isSaving, !isAccepted, !unreadable else { return false }
        var updated = checkpoint; updated.trainingFuelTarget = nil
        do { try persist(updated); return true } catch { errorMessage = "This review changed. Reopen it before changing the fuel link."; return false }
    }

    public func save(using service: DailyLogService, fuelStore: TrainingFuelPlanStore? = nil, now: Date = Date(), completion: @escaping (Bool) -> Void) {
        guard !isSaving, !isAccepted, !unreadable, let userID,
              DIContainer.shared.authService.currentUserID == userID, service.isActiveAccount(userID) else { completion(false); return }
        let foods = checkpoint.meals.flatMap(\.foodItems)
        guard !foods.isEmpty, Set(foods.map(\.id)).count == foods.count,
              foods.allSatisfy({ [$0.calories, $0.protein, $0.carbs, $0.fats].allSatisfy { $0.isFinite && $0 >= 0 } }) else {
            errorMessage = "Review every planned meal's nutrition before logging. Nothing has been logged."; completion(false); return
        }
        if !checkpoint.isSubmitted, let target = checkpoint.trainingFuelTarget {
            do {
                guard let fuelStore, let goals = service.goalSettings else { throw TrainingFuelLibraryError.changed }
                try fuelStore.stageFoodLink(target: target, foods: foods, date: checkpoint.date, today: service.currentDailyLog,
                    goals: TodayFuelPlanGoals(calories: goals.calories ?? 0, protein: goals.protein, carbs: goals.carbs, fats: goals.fats),
                    userID: userID, now: now, requiresSubmissionAuthorization: true)
            } catch { errorMessage = error.localizedDescription; completion(false); return }
        }
        var submitted = checkpoint; submitted.isSubmitted = true
        do { try persist(submitted) } catch {
            errorMessage = "Could not keep this plan review on the device. Keep it open and retry."; completion(false); return
        }
        if let target = checkpoint.trainingFuelTarget {
            do {
                guard let fuelStore else { throw TrainingFuelLibraryError.changed }
                try fuelStore.authorizeFoodLink(target: target, foods: foods, userID: userID)
            } catch { errorMessage = "Could not prepare the saved fuel link. Retry this review; no new food was sent."; completion(false); return }
        }
        isSaving = true; errorMessage = nil
        service.addMealGroupsToLog(for: userID, date: checkpoint.date,
            mealGroups: checkpoint.meals.map { (mealName: $0.name, foodItems: $0.foodItems) },
            source: "meal_plan", deduplicateFoodIDs: true) { [weak self] accepted in
            guard let self else { completion(false); return }
            self.isSaving = false
            guard DIContainer.shared.authService.currentUserID == userID else {
                self.errorMessage = "Sign back into the account that opened this plan review."; completion(false); return
            }
            guard accepted else {
                self.errorMessage = "Could not log these meals. This exact food, date and occurrence receipt is kept for retry."; completion(false); return
            }
            if let target = self.checkpoint.trainingFuelTarget {
                _ = fuelStore?.acceptFoodLink(target: target, foods: foods, userID: userID)
            }
            do { try self.store.remove(userID: userID, scope: self.scope); self.isAccepted = true; completion(true) } catch {
                self.errorMessage = "The meals were accepted. Retry to clear this review without logging them twice."; completion(false)
            }
        }
    }
}
