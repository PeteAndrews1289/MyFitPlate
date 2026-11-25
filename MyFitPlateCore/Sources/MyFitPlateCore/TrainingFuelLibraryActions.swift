import Foundation

public struct TrainingFuelPendingLink: Codable, Equatable {
    public let id: String
    public let target: TrainingFuelTarget
    public let foods: [FoodItem]
    public let day: TrainingCalendarDay
    public var diaryAccepted: Bool
    public var submissionAuthorized: Bool?
}

@MainActor public extension TrainingFuelPlanStore {
    func select(planID: String, for userID: String) throws {
        try requireOwner(userID)
        guard let value = history.first(where: { $0.plan.id == planID }) else { throw TrainingFuelLibraryError.changed }
        explicitSelection = planID
        var next = checkpoint; next.selectedID = planID; next.editingNew = false
        try persist(next, userID: userID); confirmedPlan = value.plan
    }
    func beginNewPlan(for userID: String) throws {
        try requireOwner(userID)
        explicitSelection = nil
        var next = checkpoint; next.selectedID = nil; next.draft = nil; next.editingNew = true
        try persist(next, userID: userID); confirmedPlan = nil
    }
    func saveDraft(_ draft: TrainingFuelPlanDraft, for userID: String) throws {
        try requireOwner(userID)
        var next = checkpoint; next.draft = draft
        try persist(next, userID: userID)
    }
    func revisions(planID: String) -> [TrainingFuelRevision] { checkpoint.state.heads(planID: planID) }
    func resolve(planID: String, choosing revisionID: String, for userID: String) throws {
        try requireOwner(userID)
        let heads = checkpoint.state.heads(planID: planID)
        guard heads.count > 1, let chosen = heads.first(where: { $0.id == revisionID }) else { throw TrainingFuelLibraryError.changed }
        try append(chosen.plan, userID: userID, reason: "Reviewed conflicting versions; alternatives retained",
                   archivedAt: chosen.archivedAt, resolving: heads.map(\.id))
    }
    func undoManualOutcome(planID: String, revisionID: String, for userID: String) throws {
        try requireOwner(userID)
        guard var plan = history.first(where: { $0.plan.id == planID && $0.id == revisionID })?.plan,
              plan.outcome?.source == .manualConfirmation else { throw TrainingFuelLibraryError.changed }
        plan.outcome = nil
        try append(plan, userID: userID, reason: "Undid manual outcome; linked foods unchanged")
    }
    func saveFeedback(_ feedback: TrainingFuelFeedback, planID: String, for userID: String) throws {
        try requireOwner(userID)
        guard var plan = history.first(where: { $0.plan.id == planID })?.plan, plan.outcome != nil else { throw TrainingFuelLibraryError.changed }
        plan.feedback = feedback
        try append(plan, userID: userID, reason: "Personal energy, comfort and practicality observation")
    }

    /// Use this only after confirmation; preview UI targets deliberately have no executable context.
    func makeTarget(planID: String, phase: TrainingFuelAllocation.Phase, today: DailyLog?, goals: TodayFuelPlanGoals,
                    now: Date = Date(), calendar: Calendar = .current) throws -> TrainingFuelTarget {
        guard let owner = currentUserID else { throw TrainingFuelLibraryError.accountChanged }
        try requireOwner(owner)
        guard let revision = history.first(where: { $0.plan.id == planID && $0.archivedAt == nil }) else { throw TrainingFuelLibraryError.changed }
        let plan = revision.plan
        let progress = self.progress(for: plan, today: today, goals: goals, now: now, calendar: calendar)
        guard let base = progress.target(for: phase, plan: plan) else { throw TrainingFuelLibraryError.budgetChanged }
        let day = phase != .afterTraining ? plan.draft.scheduledAt : plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        return TrainingFuelTarget(planID: planID, sessionTitle: base.sessionTitle, phase: phase,
            proteinGrams: base.proteinGrams, carbGrams: base.carbGrams,
            context: TrainingFuelHandoffContext(ownerID: owner, planRevisionID: revision.id, session: plan.draft.identity,
                day: TrainingCalendarDay(day, calendar: calendar), ruleset: plan.calculation?.ruleset ?? "legacy-unversioned", createdAt: now, timeZone: calendar.timeZone, foodTolerance: plan.draft.preference.personalInputs?.tolerance))
    }

    func validateTarget(_ target: TrainingFuelTarget, day: Date, today: DailyLog?, goals: TodayFuelPlanGoals,
                        userID: String, now: Date = Date(), calendar: Calendar = .current) throws {
        try requireOwner(userID)
        guard let context = target.context, context.ownerID == userID else { throw TrainingFuelLibraryError.accountChanged }
        guard context.day == TrainingCalendarDay(day, calendar: calendar),
              context.day == TrainingCalendarDay(now, calendar: calendar), let today,
              context.day == TrainingCalendarDay(today.date, calendar: calendar) else { throw TrainingFuelLibraryError.wrongDay }
        let current = try makeTarget(planID: target.planID, phase: target.phase, today: today, goals: goals, now: now, calendar: calendar)
        guard current.context?.planRevisionID == context.planRevisionID, current.context?.foodTolerance == context.foodTolerance else { throw TrainingFuelLibraryError.changed }
        guard current.proteinGrams >= target.proteinGrams, current.carbGrams >= target.carbGrams else { throw TrainingFuelLibraryError.budgetChanged }
    }

    /// Durable before diary submission. A later receipt attaches only these exact logging IDs.
    func stageFoodLink(target: TrainingFuelTarget, foods: [FoodItem], date: Date, today: DailyLog?, goals: TodayFuelPlanGoals,
                       userID: String, now: Date = Date(), requiresSubmissionAuthorization: Bool = false) throws {
        try validateTarget(target, day: date, today: today, goals: goals, userID: userID, now: now, calendar: target.context?.calendar ?? .current)
        guard let context = target.context, !foods.isEmpty,
              foods.allSatisfy({ [$0.calories, $0.protein, $0.carbs].allSatisfy { $0.isFinite && $0 >= 0 } }) else { throw TrainingFuelLibraryError.unverifiedFood }
        let id = try pendingLinkID(target: target, foods: foods)
        var next = checkpoint
        var pending = next.pendingLinks ?? [:]
        if let existing = pending[id], existing.submissionAuthorized != false {
            guard existing.target == target, try PlanFingerprint.make(existing.foods) == PlanFingerprint.make(foods) else {
                throw TrainingFuelLibraryError.changed
            }
            return
        }
        pending[id] = TrainingFuelPendingLink(id: id, target: target, foods: foods, day: context.day, diaryAccepted: false, submissionAuthorized: !requiresSubmissionAuthorization)
        next.pendingLinks = pending
        try persist(next, userID: userID)
    }

    /// Called only after the exact food command is durable. An abandoned preflight must
    /// never acquire attribution just because the same foods are later logged independently.
    func authorizeFoodLink(target: TrainingFuelTarget, foods: [FoodItem], userID: String) throws {
        try requireOwner(userID)
        let id = try pendingLinkID(target: target, foods: foods)
        guard var pending = checkpoint.pendingLinks?[id] else {
            let ids = Set(foods.map(\.id))
            guard history.contains(where: { revision in
                revision.plan.id == target.planID && ids.isSubset(of: Set((revision.plan.foodLinks ?? [])
                    .filter { $0.requestID == target.context?.requestID }.map(\.foodID)))
            }) else { throw TrainingFuelLibraryError.changed }
            return
        }
        guard pending.target == target, try PlanFingerprint.make(pending.foods) == PlanFingerprint.make(foods) else { throw TrainingFuelLibraryError.changed }
        guard pending.submissionAuthorized == false else { return }
        pending.submissionAuthorized = true
        var next = checkpoint; next.pendingLinks?[id] = pending
        try persist(next, userID: userID)
    }

    /// Diary success is independent of this bookkeeping. Failed linkage remains a separate retry.
    @discardableResult func acceptFoodLink(target: TrainingFuelTarget, foods: [FoodItem], userID: String) -> Bool {
        do {
            try requireOwner(userID)
            let id = try pendingLinkID(target: target, foods: foods)
            guard var pending = checkpoint.pendingLinks?[id] else {
                let ids = Set(foods.map(\.id))
                return history.contains { revision in
                    revision.plan.id == target.planID && ids.isSubset(of: Set((revision.plan.foodLinks ?? [])
                        .filter { $0.requestID == target.context?.requestID }.map(\.foodID)))
                }
            }
            guard pending.target == target, try PlanFingerprint.make(pending.foods) == PlanFingerprint.make(foods) else {
                throw TrainingFuelLibraryError.changed
            }
            pending.diaryAccepted = true
            var next = checkpoint; next.pendingLinks?[id] = pending
            try persist(next, userID: userID)
            try completeLink(pending, userID: userID)
            return true
        } catch { errorMessage = "Food saved. Its Training Fuel link is waiting to retry; your food will not be added again."; return false }
    }

    /// Call only for an accepted or server-synced diary, never an optimistic mutation projection.
    func reconcileFoodLinks(with diary: DailyLog, for userID: String) {
        guard currentUserID == userID else { return }
        let foodIDs = Set(diary.meals.flatMap(\.foodItems).map(\.id))
        for pending in (checkpoint.pendingLinks ?? [:]).values {
            guard pending.submissionAuthorized != false,
                  let context = pending.target.context, context.ownerID == userID,
                  pending.day == TrainingCalendarDay(diary.date, calendar: context.calendar),
                  Set(pending.foods.map(\.id)).isSubset(of: foodIDs) else { continue }
            _ = acceptFoodLink(target: pending.target, foods: pending.foods, userID: userID)
        }
    }

    func retryFoodLinks(for userID: String) {
        do {
            try requireOwner(userID)
            for pending in (checkpoint.pendingLinks ?? [:]).values where pending.diaryAccepted {
                try completeLink(pending, userID: userID)
            }
        } catch { errorMessage = error.localizedDescription }
    }
    var pendingFoodLinkCount: Int { (checkpoint.pendingLinks ?? [:]).values.filter(\.diaryAccepted).count }

    /// Explicitly reviewed correction, never inferred from timestamp or macro coincidence.
    func linkExistingFoods(planID: String, phase: TrainingFuelAllocation.Phase, foodIDs: Set<String>,
                           diary: DailyLog, for userID: String, now: Date = Date()) throws {
        try requireOwner(userID)
        guard var plan = history.first(where: { $0.plan.id == planID })?.plan else { throw TrainingFuelLibraryError.changed }
        let targetDay = phase != .afterTraining ? plan.draft.scheduledAt : plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        let day = TrainingCalendarDay(diary.date)
        guard day == TrainingCalendarDay(targetDay) else { throw TrainingFuelLibraryError.wrongDay }
        let foods = diary.meals.flatMap(\.foodItems).filter { foodIDs.contains($0.id) }
        guard foods.count == foodIDs.count, !foods.isEmpty else { throw TrainingFuelLibraryError.unverifiedFood }
        try ensureNotLinkedElsewhere(foodIDs: foodIDs, planID: planID, phase: phase)
        let request = UUID().uuidString
        var links = (plan.foodLinks ?? []).filter { !foodIDs.contains($0.foodID) }
        links += foods.map { TrainingFuelFoodLink(requestID: request, food: $0, day: day, phase: phase, at: now) }
        plan.foodLinks = links
        try append(plan, userID: userID, reason: "Reviewed links to existing diary foods")
    }
    func unlinkFood(planID: String, linkID: String, for userID: String) throws {
        try requireOwner(userID)
        guard var plan = history.first(where: { $0.plan.id == planID })?.plan else { throw TrainingFuelLibraryError.changed }
        plan.foodLinks = (plan.foodLinks ?? []).filter { $0.id != linkID }
        try append(plan, userID: userID, reason: "Corrected fuel attribution; diary unchanged")
    }
}

@MainActor private extension TrainingFuelPlanStore {
    func pendingLinkID(target: TrainingFuelTarget, foods: [FoodItem]) throws -> String {
        guard let context = target.context else { throw TrainingFuelLibraryError.changed }
        return context.requestID + ":" + (try PlanFingerprint.make(foods.map(\.id).sorted()))
    }
    func ensureNotLinkedElsewhere(foodIDs: Set<String>, planID: String, phase: TrainingFuelAllocation.Phase) throws {
        guard !history.contains(where: { record in
            (record.plan.foodLinks ?? []).contains { foodIDs.contains($0.foodID) && (record.plan.id != planID || $0.phase != phase) }
        }) else { throw TrainingFuelLibraryError.changed }
    }
    func completeLink(_ pending: TrainingFuelPendingLink, userID: String) throws {
        guard pending.diaryAccepted, let context = pending.target.context, context.ownerID == userID,
              var plan = history.first(where: { $0.plan.id == pending.target.planID })?.plan else { throw TrainingFuelLibraryError.changed }
        let ids = Set(pending.foods.map(\.id))
        try ensureNotLinkedElsewhere(foodIDs: ids, planID: plan.id, phase: pending.target.phase)
        let additions = pending.foods.map { TrainingFuelFoodLink(requestID: context.requestID, food: $0, day: pending.day,
            phase: pending.target.phase, at: Date()) }
        var links = plan.foodLinks ?? []
        for link in additions where !links.contains(where: { $0.foodID == link.foodID }) { links.append(link) }
        if links != plan.foodLinks { plan.foodLinks = links; try append(plan, userID: userID, reason: "Accepted food receipt linked") }
        var next = checkpoint; next.pendingLinks?[pending.id] = nil
        try persist(next, userID: userID)
    }
}
