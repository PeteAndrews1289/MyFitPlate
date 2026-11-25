import Combine
import Foundation

public struct MealPlanWeekDraft: Identifiable, Codable {
    public var id: UUID
    public var days: [MealPlanDay]
    public var title: String
    public var constraints: MealPlanConstraints?
    public var preserveCookingBatches: Bool
    public var lockedMealIDs: Set<String>?
    public var existingLockedMealIDs: Set<String>?
    public var timeZoneIdentifier: String?
    public init(days: [MealPlanDay], title: String, constraints: MealPlanConstraints? = nil, preserveCookingBatches: Bool = false) {
        id = UUID(); self.days = days; self.title = title; self.constraints = constraints
        self.preserveCookingBatches = preserveCookingBatches
        existingLockedMealIDs = []; timeZoneIdentifier = Calendar.current.timeZone.identifier
    }
    private enum CodingKeys: String, CodingKey {
        case id, days, title, constraints, preserveCookingBatches, lockedMealIDs, existingLockedMealIDs, timeZoneIdentifier
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id); try box.encode(days, forKey: .days); try box.encode(title, forKey: .title)
        try box.encodeIfPresent(constraints, forKey: .constraints); try box.encode(preserveCookingBatches, forKey: .preserveCookingBatches)
        try box.encodeIfPresent(lockedMealIDs?.sorted(), forKey: .lockedMealIDs)
        try box.encodeIfPresent(existingLockedMealIDs?.sorted(), forKey: .existingLockedMealIDs)
        try box.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
    }
}

public enum MealPlanWeekReviewRules {
    /// A generated cooking graph is accepted as a whole. An independent reused week
    /// retains the existing explicit copy semantics, including separate cooking stock.
    public static func merging(_ draft: MealPlanWeekDraft, existing: [MealPlanDay], replace: Bool) throws -> MealPlanChange {
        guard !replace || draft.lockedMealIDs?.isEmpty != false else { throw MealPlanEditError.invalid }
        guard draft.preserveCookingBatches else {
            return MealPlanEditingRules.mergingDraft(draft.days, into: existing, replacingExisting: replace)
        }
        let locked = draft.lockedMealIDs ?? []
        for id in locked {
            guard let day = draft.days.first(where: { $0.meals.contains { $0.id == id } }), let meal = day.meals.first(where: { $0.id == id }) else { throw MealPlanEditError.invalid }
            let old = existing.first { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) }
            let saved = old?.meals.first { $0.id == id }
            if draft.existingLockedMealIDs?.contains(id) == true {
                guard let saved, try PlanFingerprint.make(saved) == PlanFingerprint.make(meal) else { throw MealPlanEditError.changed }
            } else if let saved {
                guard try PlanFingerprint.make(saved) == PlanFingerprint.make(meal) else { throw MealPlanEditError.changed }
            } else if old?.meals.contains(where: { MealPlanEditingRules.canonicalSlot($0.mealType) == MealPlanEditingRules.canonicalSlot(meal.mealType) }) == true {
                throw MealPlanEditError.changed
            }
        }
        var selected: [(MealPlanDay, [PlannedMeal])] = []
        for day in draft.days {
            let old = existing.first { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) }
                ?? MealPlanEditingRules.emptyDay(day.date)
            let occupied = Set(old.meals.map { MealPlanEditingRules.canonicalSlot($0.mealType) })
            selected.append((old, day.meals.filter { replace || !occupied.contains(MealPlanEditingRules.canonicalSlot($0.mealType)) }))
        }
        let meals = selected.flatMap(\.1)
        let ids = Set(meals.map(\.id))
        var mealIDs: [String: String] = [:], batchIDs: [String: String] = [:]
        for meal in meals {
            mealIDs[meal.id] = UUID().uuidString
            if let batch = meal.cookingBatch {
                guard Set(batch.allocations.map(\.mealID)).isSubset(of: ids), ids.contains(batch.sourceMealID) else { throw MealCookingError.linkedBatch }
                batchIDs[batch.id] = batchIDs[batch.id] ?? UUID().uuidString
            }
        }
        var before: [MealPlanDay] = [], after: [MealPlanDay] = []
        for (old, additions) in selected where !additions.isEmpty || draft.constraints != nil {
            var changed = old
            changed.meals = replace ? [] : old.meals
            for original in additions {
                var meal = original
                meal.id = mealIDs[original.id]!
                meal.foodItem?.id = "plan-food-\(meal.id)"
                if var batch = original.cookingBatch {
                    batch.id = batchIDs[batch.id]!
                    batch.revisionID = batch.id
                    batch.sourceMealID = mealIDs[batch.sourceMealID]!
                    batch.allocations = batch.allocations.map { .init(mealID: mealIDs[$0.mealID]!, date: $0.date, portions: $0.portions) }
                    meal.cookingBatch = batch
                }
                if let evidence = original.planningEvidence, evidence.isCurrent(for: original) {
                    meal.planningEvidence = try PlannedMealEvidence(profile: evidence.profile, meal: meal)
                }
                changed.meals.append(meal)
            }
            changed.meals = MealPlanEditingRules.sorted(changed.meals)
            before.append(old); after.append(changed)
        }
        let change = MealPlanChange(title: "Week planned", before: before, after: after)
        if !after.isEmpty { try MealPlanEditingRules.validate(change) }
        return change
    }
}

public struct MealPlanWeekCheckpoint: Codable {
    public var draft: MealPlanWeekDraft
    public var change: MealPlanChange?
    public var ingredientProfile: MealConstraintProfile?
    public var submitted = false
    public var accepted = false
    public var cancelled = false
    public init(draft: MealPlanWeekDraft) { self.draft = draft }
}

/// One account-scoped, immutable submitted proposal. Transport retries and status checks
/// keep its operation ID, preventing duplicate weeks after an uncertain acknowledgement.
@MainActor public final class MealPlanWeekSaveSession: ObservableObject {
    public static let scope = "meal-plan-week-review"
    @Published public private(set) var checkpoint: MealPlanWeekCheckpoint?
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?
    public let userID: String?
    private let store: EditorDraftStore
    private let currentScope: String
    private var unreadable = false
    private var expectedFingerprint: String?
    public init(userID: String?, draft: MealPlanWeekDraft? = nil, store: EditorDraftStore = EditorDraftStore(), scope: String = MealPlanWeekSaveSession.scope) {
        self.userID = userID; self.store = store; currentScope = scope
        guard active, let userID else { return }
        do {
            checkpoint = try store.load(MealPlanWeekCheckpoint.self, userID: userID, scope: currentScope)?.value
            expectedFingerprint = try checkpoint.map { try PlanFingerprint.make($0) }
            if checkpoint == nil, let draft { _ = persist(MealPlanWeekCheckpoint(draft: draft)) }
        } catch { unreadable = true; errorMessage = "The previous week review couldn't be opened. It has been preserved." }
    }
    public var canEdit: Bool { active && !isWorking && checkpoint?.submitted == false }
    public func updateDraft(_ draft: MealPlanWeekDraft) -> Bool {
        guard canEdit, var value = checkpoint, draft.id == value.draft.id else { return false }
        value.draft = draft; value.change = nil; return persist(value)
    }
    public func prepare(_ change: MealPlanChange, ingredientProfile: MealConstraintProfile? = nil) -> Bool {
        guard canEdit, var value = checkpoint else { return false }
        guard timeZoneMatches else { errorMessage = "Your time zone changed. Close this unsubmitted review and rebuild it for your current dates."; return false }
        do { try MealPlanEditingRules.validate(change) } catch { errorMessage = error.localizedDescription; return false }
        if let constraints = value.draft.constraints {
            let complete = value.draft.days.map { day in
                change.after.first { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) } ?? day
            }
            let report = MealPlanConstraintRules.report(days: complete, constraints: constraints)
            guard report.canSave else { errorMessage = report.issues.first(where: \.blocking)?.message; return false }
        }
        let selectedProfile = ingredientProfile.map { $0.adding(diet: value.draft.constraints?.effectiveIngredientProfile?.diet ?? .unrestricted,
            exclusions: value.draft.constraints?.effectiveIngredientProfile?.hardExclusions ?? []) } ?? value.draft.constraints?.effectiveIngredientProfile
        do { try validateIngredients(change: change, profile: selectedProfile) } catch { errorMessage = error.localizedDescription; return false }
        value.ingredientProfile = selectedProfile
        value.change = change; return persist(value)
    }
    public func save(using planner: MealPlannerService, goalSettings: GoalSettings? = nil) async -> Bool {
        guard active, !isWorking, let userID, var value = checkpoint, let change = value.change, !value.cancelled else { return false }
        if value.accepted { return true }
        guard timeZoneMatches else { errorMessage = "Your time zone changed. Cancel this pending save before creating a review for your current dates."; return false }
        isWorking = true; defer { isWorking = false }
        if !value.submitted, change.after.flatMap(\.meals).contains(where: { $0.preparedStock != nil }) {
            do {
                let repository = DIContainer.shared.nutritionRepository!
                async let stock = repository.fetchInventory(userID: userID)
                async let plans = repository.fetchMealPlansForStockReservations(userID: userID)
                let changedDates = Set(change.after.map(\.id))
                let allPlans = try await plans.filter { !changedDates.contains($0.id) } + change.after
                try await PreparedMealStockRules.validate(plans: allPlans, stock: stock)
                guard active else { throw MealPlanEditError.accountChanged }
            } catch { errorMessage = error.localizedDescription; return false }
        }
        if !value.submitted {
            let current = goalSettings?.effectiveMealConstraintProfile.map { $0.adding(diet: value.ingredientProfile?.diet ?? .unrestricted,
                exclusions: value.ingredientProfile?.hardExclusions ?? []) } ?? value.ingredientProfile
            do { try validateIngredients(change: change, profile: current) } catch { errorMessage = error.localizedDescription; return false }
            value.ingredientProfile = current
        }
        value.submitted = true
        guard persist(value) else { return false }
        do {
            try await planner.applyPlanChange(change, for: userID)
            guard active else { throw MealPlanEditError.accountChanged }
            value.accepted = true; return persist(value)
        } catch { errorMessage = "Your exact week review is kept. Check its status or retry the same save."; return false }
    }
    private func validateIngredients(change: MealPlanChange, profile: MealConstraintProfile?) throws {
        try profile?.validate()
        guard profile?.hasRestrictions == true else { return }
        let originals = Dictionary(change.before.flatMap(\.meals).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for meal in change.after.flatMap(\.meals) {
            if let original = originals[meal.id], try PlanFingerprint.make(original) == PlanFingerprint.make(meal) { continue }
            let review = meal.planningEvidence.flatMap { $0.isCurrent(for: meal) ? $0.profile : nil }
            let report = MealConstraintRules.report(candidate: meal.constraintCandidate, profile: profile, recipeReview: review)
            guard report.canAccept else { throw report.isBlocked ? MealConstraintError.blocked : MealConstraintError.reviewRequired }
        }
    }

    public func resolve(using repository: NutritionRepositoryProtocol, cancelPending: Bool = false) async {
        guard active, !isWorking, let userID, var value = checkpoint, let change = value.change else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let status = try await repository.resolveMealPlanChange(userID: userID, change: change, cancelPending: cancelPending)
            guard active else { throw MealPlanEditError.accountChanged }
            switch status {
            case .accepted: value.accepted = true; value.cancelled = false; _ = persist(value)
            case .cancelled: value.cancelled = true; _ = persist(value)
            case .pending: errorMessage = "No accepted receipt yet. Retry this exact review, or cancel it before changing the week."
            }
        } catch { errorMessage = "Couldn't confirm the save. This review is still kept." }
    }
    public func closeResolvedOrUnsubmitted() -> Bool {
        guard active, !isWorking, let userID, let value = checkpoint,
              !value.submitted || value.accepted || value.cancelled else { return false }
        do {
            let saved = try store.load(MealPlanWeekCheckpoint.self, userID: userID, scope: currentScope)?.value
            guard try saved.map({ try PlanFingerprint.make($0) }) == expectedFingerprint else {
                checkpoint = saved; expectedFingerprint = try saved.map { try PlanFingerprint.make($0) }
                errorMessage = "A newer review is kept. Reopen it before closing."; return false
            }
            try store.remove(userID: userID, scope: currentScope); checkpoint = nil; expectedFingerprint = nil; return true
        } catch { errorMessage = "Couldn't close this saved review yet."; return false }
    }
    private var timeZoneMatches: Bool { checkpoint?.draft.timeZoneIdentifier == nil || checkpoint?.draft.timeZoneIdentifier == Calendar.current.timeZone.identifier }
    private var active: Bool { !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID }
    private func persist(_ value: MealPlanWeekCheckpoint) -> Bool {
        guard active, let userID else { return false }
        do {
            let old = try store.load(MealPlanWeekCheckpoint.self, userID: userID, scope: currentScope)?.value
            guard try old.map({ try PlanFingerprint.make($0) }) == expectedFingerprint else {
                checkpoint = old; expectedFingerprint = try old.map { try PlanFingerprint.make($0) }
                errorMessage = "A newer week review is kept. Its submitted choices cannot be replaced by this editor."; return false
            }
            let fingerprint = try PlanFingerprint.make(value)
            try store.save(value, userID: userID, scope: currentScope); expectedFingerprint = fingerprint
            checkpoint = value; errorMessage = nil; return true
        } catch { errorMessage = "Couldn't keep this week review on the device. Nothing new was submitted."; return false }
    }
}
