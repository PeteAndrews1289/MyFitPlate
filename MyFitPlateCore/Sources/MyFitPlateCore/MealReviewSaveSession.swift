import Foundation
import Combine

/// An account-scoped review checkpoint. Logging IDs are independent of provider IDs and
/// remain stable after submission, including a retry after an ambiguous save outcome.
public struct MealReviewCheckpoint: Codable {
    public var draft: FoodLoggingDraft
    public var selectedItemIDs: Set<String>
    public let source: String
    public var trainingFuelTarget: TrainingFuelTarget?
    public var mealSuggestion: MealSuggestion?
    public var ingredientReview: MealIngredientReview?
    public var portionQuestion: MealPortionQuestionState?
    public var suggestionBudget: MealSuggestionBudgetReceipt?
    public var requestedAlternative: MealSuggestionAlternativeReason?
    public var alternativeHistory: [MealSuggestionAlternativeReceipt]?
}

@MainActor
public final class MealReviewSaveSession: ObservableObject {
    @Published public private(set) var checkpoint: MealReviewCheckpoint
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var restoredReview = false
    @Published public private(set) var isAccepted = false
    @Published public private(set) var isDiscarded = false
    @Published public private(set) var pendingBudgetReview: MealSuggestionBudgetReceipt?

    public let userID: String?
    private let store: EditorDraftStore
    private let scope: String
    private let confirmingSourceType: FoodSourceType?
    private var unreadableCheckpoint = false

    public var items: [FoodItem] { checkpoint.draft.entries.map(\.food) }
    public var selectedItemIDs: Set<String> { checkpoint.selectedItemIDs }
    public var selectedItems: [FoodItem] { items.filter { selectedItemIDs.contains($0.id) } }
    public var date: Date { checkpoint.draft.date }
    public var mealName: String { checkpoint.draft.mealName }
    public var isSubmitted: Bool { checkpoint.draft.isSubmitted }
    public var isLocked: Bool { isSaving || isSubmitted || isAccepted || isDiscarded }

    public static func scope(for source: String) -> String { "meal-review-\(source)" }

    public static func pendingReview(source: String, userID: String?, store: EditorDraftStore = EditorDraftStore()) -> MealReviewCheckpoint? {
        guard let userID else { return nil }
        return try? store.load(MealReviewCheckpoint.self, userID: userID, scope: scope(for: source))?.value
    }

    public init(
        items: [FoodItem], userID: String?, date: Date, mealName: String,
        source: String, selectsAllItems: Bool = true, draftScope: String? = nil,
        confirmingSourceType: FoodSourceType? = nil, dayContext: DiaryDayContext? = nil,
        store: EditorDraftStore = EditorDraftStore(), trainingFuelTarget: TrainingFuelTarget? = nil, mealSuggestion: MealSuggestion? = nil
    ) {
        self.userID = userID
        self.store = store
        scope = draftScope ?? Self.scope(for: source)
        self.confirmingSourceType = confirmingSourceType
        let capturedDay = dayContext ?? userID.flatMap {
            DiaryDayContext(userID: $0, date: Calendar.current.startOfDay(for: date))
        }
        var draft = FoodLoggingDraft(date: date, mealName: mealName, dayContext: capturedDay)
        draft.entries = items.map { FoodLoggingDraft.Entry(food: $0) }
        checkpoint = MealReviewCheckpoint(
            draft: draft, selectedItemIDs: selectsAllItems ? Set(items.map(\.id)) : [], source: source, trainingFuelTarget: trainingFuelTarget, mealSuggestion: mealSuggestion
        )
        guard let userID else {
            errorMessage = "Sign in to save this review. Your foods have not been logged."
            return
        }
        do {
            if let saved = try store.load(MealReviewCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = saved.value
                restoredReview = true
                return
            }
        } catch {
            unreadableCheckpoint = true
            errorMessage = "The previous review could not be opened. It has been kept on this device; nothing new has been logged."
            return
        }
        if !items.isEmpty {
            _ = persist(checkpoint)
        }
    }

    @discardableResult public func replaceMealSuggestion(_ suggestion: MealSuggestion) -> Bool {
        guard !isLocked, !unreadableCheckpoint, checkpoint.mealSuggestion != nil else { return false }
        guard var food = suggestion.reviewFood, !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, food.calories > 0,
              [food.calories, food.protein, food.carbs, food.fats].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        let previous = checkpoint
        var next = checkpoint
        if let prior = checkpoint.mealSuggestion {
            next.alternativeHistory = Array(((checkpoint.alternativeHistory ?? []) + [MealSuggestionAlternativeReceipt(previous: prior,
                reason: checkpoint.requestedAlternative ?? .anotherIdea, replacedAt: Date())]).suffix(5))
        }
        next.requestedAlternative = nil
        next.suggestionBudget = nil
        next.mealSuggestion = suggestion
        next.ingredientReview = nil
        food.sourceMetadata?.mealSuggestionRejections = next.alternativeHistory?.map { rejected in
            MealSuggestionRejectionEvidence(suggestionID: rejected.previous.id, name: rejected.previous.mealName,
                reason: rejected.reason, recordedAt: rejected.replacedAt)
        }
        next.draft.entries = [FoodLoggingDraft.Entry(food: food)]
        next.selectedItemIDs = [food.id]
        guard persist(next) else { checkpoint = previous; return false }
        return true
    }

    @discardableResult public func requestAlternative(_ reason: MealSuggestionAlternativeReason) -> Bool {
        guard !isLocked, checkpoint.mealSuggestion != nil else { return false }
        var next = checkpoint; next.requestedAlternative = reason
        return persist(next)
    }

    @discardableResult public func restorePreviousSuggestion() -> Bool {
        guard !isLocked, let previous = checkpoint.alternativeHistory?.last?.previous else { return false }
        return replaceMealSuggestion(previous)
    }

    @discardableResult public func acceptChangedSuggestionBudget() -> Bool {
        guard !isLocked, var receipt = pendingBudgetReview else { return false }
        receipt.acceptsAboveBudget = true
        var next = checkpoint; next.suggestionBudget = receipt
        return persist(next)
    }

    public func ingredientAssessment(profile: MealConstraintProfile?) -> MealConstraintAssessment? {
        guard let suggestion = checkpoint.mealSuggestion else { return nil }
        return MealConstraintRules.report(candidate: suggestion.constraintCandidate, profile: profile,
            personalReview: checkpoint.ingredientReview)
    }

    @discardableResult public func confirmIngredientReview(profile: MealConstraintProfile?) -> Bool {
        guard !isLocked, !unreadableCheckpoint, let profile, let suggestion = checkpoint.mealSuggestion,
              ingredientAssessment(profile: profile)?.needsPersonalReview == true else { return false }
        var next = checkpoint
        next.ingredientReview = MealIngredientReview(candidate: suggestion.constraintCandidate, profile: profile)
        return persist(next)
    }

    @discardableResult public func offerPortionQuestion(_ question: UsefulMealQuestion) -> Bool {
        guard !isLocked, !unreadableCheckpoint, checkpoint.portionQuestion == nil,
              let item = items.first(where: { $0.id == question.itemID }),
              UsefulMealQuestionRules.preview(answer: .skip, question: question, item: item) != nil else { return false }
        let previous = checkpoint
        var next = checkpoint; next.portionQuestion = MealPortionQuestionState(question: question)
        guard persist(next) else { checkpoint = previous; return false }
        return true
    }

    @discardableResult public func answerPortionQuestion(_ answer: MealQuestionAnswer) -> Bool {
        guard !isLocked, !unreadableCheckpoint, let question = checkpoint.portionQuestion?.question,
              checkpoint.portionQuestion?.receipt == nil,
              let index = checkpoint.draft.entries.firstIndex(where: { $0.food.id == question.itemID }),
              let preview = UsefulMealQuestionRules.preview(answer: answer, question: question,
                  item: checkpoint.draft.entries[index].food) else { return false }
        let previous = checkpoint
        var next = checkpoint
        next.draft.entries[index].food = preview.food
        next.portionQuestion?.receipt = preview.receipt
        guard persist(next) else { checkpoint = previous; return false }
        return true
    }

    @discardableResult public func removeFuelContext() -> Bool {
        guard !isLocked, !unreadableCheckpoint else { return false }
        var next = checkpoint; next.trainingFuelTarget = nil
        return persist(next)
    }

    @discardableResult
    public func updateDestination(date: Date, mealName: String, dayContext: DiaryDayContext? = nil) -> Bool {
        guard !isLocked, !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var changed = checkpoint
        if date != checkpoint.draft.date || dayContext != nil {
            let capturedDay = dayContext ?? userID.flatMap {
                DiaryDayContext(userID: $0, date: Calendar.current.startOfDay(for: date))
            }
            guard capturedDay?.isOwned(by: userID) == true else { return false }
            changed.draft.date = capturedDay?.originalDate ?? date
            changed.draft.dayContext = capturedDay
        }
        changed.draft.mealName = mealName
        return persist(changed)
    }

    @discardableResult
    public func updateItem(_ food: FoodItem) -> Bool {
        guard !isLocked, let index = checkpoint.draft.entries.firstIndex(where: { $0.food.id == food.id }) else { return false }
        var changed = checkpoint
        changed.draft.entries[index].food = food
        return persist(changed)
    }

    @discardableResult
    public func replaceItems(_ foods: [FoodItem]) -> Bool {
        guard !isLocked else { return false }
        var changed = checkpoint
        changed.draft.entries = foods.map { food in
            if var existing = checkpoint.draft.entries.first(where: { $0.food.id == food.id }) {
                existing.food = food
                return existing
            }
            return FoodLoggingDraft.Entry(food: food)
        }
        changed.selectedItemIDs = Set(foods.map(\.id))
        return persist(changed)
    }

    @discardableResult
    public func removeItem(id: String) -> Bool {
        guard !isLocked else { return false }
        var changed = checkpoint
        changed.draft.entries.removeAll { $0.food.id == id }
        changed.selectedItemIDs.remove(id)
        return persist(changed)
    }

    @discardableResult
    public func toggleSelection(id: String) -> Bool {
        guard !isLocked, items.contains(where: { $0.id == id }) else { return false }
        var changed = checkpoint
        if changed.selectedItemIDs.contains(id) {
            changed.selectedItemIDs.remove(id)
        } else {
            changed.selectedItemIDs.insert(id)
        }
        return persist(changed)
    }

    /// Transfer reviewed portions to an existing meal selection in one local write.
    /// The caller can safely repeat the handoff if checkpoint cleanup is interrupted.
    public func moveToMeal(_ accept: ([FoodItem]) -> Bool) -> Bool {
        guard !isLocked, !unreadableCheckpoint, let userID,
              userID == DIContainer.shared.authService.currentUserID else { return false }
        let entries = checkpoint.draft.entries.filter { selectedItemIDs.contains($0.food.id) }
        let foods = entries.compactMap { entry -> FoodItem? in
            guard let food = entry.preparedFood else { return nil }
            guard let confirmingSourceType else { return food }
            return food.markedUserConfirmed(sourceType: food.sourceMetadata?.sourceType ?? confirmingSourceType)
        }
        guard !foods.isEmpty, foods.count == entries.count, accept(foods) else {
            errorMessage = "Couldn’t add these portions to the selected meal. Your photo review is saved."
            return false
        }
        return discard()
    }

    /// Discard is available only before submission. A submitted review stays recoverable
    /// because a timeout may hide an already accepted server write.
    @discardableResult
    public func discard() -> Bool {
        guard !isLocked, !unreadableCheckpoint, let userID,
              DIContainer.shared.authService.currentUserID == userID else { return false }
        do {
            try store.remove(userID: userID, scope: scope)
            isDiscarded = true
            return true
        } catch {
            errorMessage = "Could not discard this review. It is still kept on this device."
            return false
        }
    }

    public func save(using service: DailyLogService, completion: @escaping (Bool) -> Void) {
        guard !isSaving, !isAccepted, !isDiscarded, !unreadableCheckpoint, let userID,
              DIContainer.shared.authService.currentUserID == userID, service.isActiveAccount(userID) else {
            if !isSaving { errorMessage = "Sign back into the account that opened this review to finish saving." }
            completion(false)
            return
        }
        guard checkpoint.draft.dayContext?.isOwned(by: userID) ?? true else {
            errorMessage = "This review is kept with its original account. Sign back in to finish saving."
            completion(false); return
        }
        if !isSubmitted, let assessment = ingredientAssessment(profile: service.goalSettings?.effectiveMealConstraintProfile), !assessment.canAccept {
            errorMessage = assessment.issues.first?.message; completion(false); return
        }
        if !isSubmitted, checkpoint.mealSuggestion != nil {
            guard let day = checkpoint.draft.dayContext else {
                errorMessage = "Reopen this estimate to confirm its original diary day."; completion(false); return
            }
            isSaving = true
            service.fetchLogInternal(for: userID, day: day) { [weak self] result in
                guard let self else { completion(false); return }
                self.isSaving = false
                guard DIContainer.shared.authService.currentUserID == userID, service.isActiveAccount(userID),
                      let goals = service.goalSettings, let calorieGoal = goals.calories, calorieGoal > 0,
                      case .success(let log) = result,
                      let receipt = MealSuggestionBudgetReceipt(day: day, log: log,
                        goals: .init(calories: calorieGoal, protein: goals.protein, carbs: goals.carbs, fats: goals.fats), foods: self.selectedItems) else {
                    self.errorMessage = "Could not verify this day's remaining targets. Your estimate is kept; try again."; completion(false); return
                }
                if let assessment = self.ingredientAssessment(profile: goals.effectiveMealConstraintProfile), !assessment.canAccept {
                    self.errorMessage = assessment.issues.first?.message; completion(false); return
                }
                let previous = self.checkpoint.suggestionBudget
                let acknowledged = previous?.acceptsAboveBudget == true && previous?.sameEvidence(as: receipt) == true
                guard receipt.remaining.fits(self.selectedItems) || acknowledged else {
                    self.pendingBudgetReview = receipt
                    self.errorMessage = "This estimate exceeds the current remaining targets for \(day.dayKey). Review the changed budget before logging."; completion(false); return
                }
                var next = self.checkpoint; var acceptedReceipt = receipt; acceptedReceipt.acceptsAboveBudget = acknowledged
                next.suggestionBudget = acceptedReceipt
                guard self.persist(next) else { completion(false); return }
                self.pendingBudgetReview = nil
                self.submitVerified(using: service, userID: userID, completion: completion)
            }
            return
        }
        submitVerified(using: service, userID: userID, completion: completion)
    }

    private func submitVerified(using service: DailyLogService, userID: String, completion: @escaping (Bool) -> Void) {
        // The first-submit snapshot is durable. An uncertain submitted retry never reopens it.
        var submitted = checkpoint
        if !submitted.draft.isSubmitted, let confirmingSourceType {
            for index in submitted.draft.entries.indices
            where submitted.selectedItemIDs.contains(submitted.draft.entries[index].food.id) {
                let food = submitted.draft.entries[index].food
                submitted.draft.entries[index].food = food.markedUserConfirmed(
                    sourceType: food.sourceMetadata?.sourceType ?? confirmingSourceType
                )
            }
        }
        let entries = submitted.draft.entries.filter { submitted.selectedItemIDs.contains($0.food.id) }
        let foods = entries.compactMap(\.preparedFood)
        guard !foods.isEmpty, foods.count == entries.count else {
            errorMessage = "Review the food portions before saving. Nothing has been logged."
            completion(false)
            return
        }
        if !submitted.draft.isSubmitted, let target = submitted.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.stageFoodLink(target: target, foods: foods, date: date, using: service, userID: userID)
            } catch { errorMessage = error.localizedDescription; completion(false); return }
        }
        submitted.draft.isSubmitted = true
        guard persist(submitted) else { completion(false); return }
        if let target = checkpoint.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.authorizeFoodLink(target: target, foods: foods, userID: userID)
            } catch { errorMessage = "Could not prepare the saved fuel link. Retry this review; no new food was sent."; completion(false); return }
        }
        isSaving = true
        errorMessage = nil
        service.addMealGroupsToLog(
            for: userID, date: date, mealGroups: [(mealName: mealName, foodItems: foods)],
            source: checkpoint.source, deduplicateFoodIDs: true, dayContext: checkpoint.draft.dayContext
        ) { [weak self] accepted in
            guard let self else { completion(false); return }
            self.isSaving = false
            guard DIContainer.shared.authService.currentUserID == userID, service.isActiveAccount(userID) else {
                self.errorMessage = "This review is kept with its original account. Sign back in to finish saving."
                completion(false)
                return
            }
            guard accepted else {
                self.errorMessage = "Could not save this meal. Your reviewed foods and destination are kept; retry safely."
                completion(false)
                return
            }
            if let target = self.checkpoint.trainingFuelTarget {
                _ = service.trainingFuelPlanStore?.acceptFoodLink(target: target, foods: foods, userID: userID)
            }
            do {
                try self.store.remove(userID: userID, scope: self.scope)
                self.isAccepted = true
                completion(true)
            } catch {
                self.errorMessage = "Your meal was saved. Retry to clear the review; it will not be added twice."
                completion(false)
            }
        }
    }

    private func persist(_ changed: MealReviewCheckpoint) -> Bool {
        guard !unreadableCheckpoint, let userID,
              DIContainer.shared.authService.currentUserID == userID,
              changed.draft.dayContext?.isOwned(by: userID) ?? true else { return false }
        // Keep the user's latest input in memory even when the local checkpoint cannot
        // be written. No diary mutation is sent until that same payload is durable.
        checkpoint = changed
        do {
            try store.save(changed, userID: userID, scope: scope)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not keep this review on the device. Keep it open and try again."
            return false
        }
    }
}
