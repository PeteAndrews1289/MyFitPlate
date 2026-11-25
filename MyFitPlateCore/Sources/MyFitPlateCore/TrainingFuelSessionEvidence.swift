import Foundation

public extension TrainingFuelSessionAdapter {
    static func scheduledRunCandidate(from commitment: TrainingRunCommitment, role: RunBlockRole? = nil) -> TrainingFuelSessionCandidate {
        let template = runCandidate(from: commitment.plan)
        // A step named "work" is used for easy continuous running too. Ask for effort unless the block role establishes it.
        let intensity: TrainingFuelSession.Intensity = role == .quality ? .hard : role == nil ? .moderate : .easy
        return TrainingFuelSessionCandidate(id: "commitment:" + commitment.id, source: .selectedRunPlan,
            sourceID: commitment.plan.id, sessionReferenceID: commitment.plan.id, title: commitment.plan.name,
            detail: commitment.blockID == nil ? "Scheduled run" : "Scheduled running block session", kind: .run,
            scheduledDay: commitment.day.date(), suggestedDurationMinutes: template.suggestedDurationMinutes,
            suggestedIntensity: intensity, suggestedStrengthFocus: .unknown,
            assumptions: template.assumptions,
            identity: TrainingFuelSessionIdentity(blockID: commitment.blockID, revisionID: commitment.revisionID,
                commitmentID: commitment.id, runPlanID: commitment.plan.id))
    }
}

@MainActor public extension TrainingFuelPlanStore {
    /// Pending session allocations share one remaining daily budget; no training calories are added to goals.
    func availableGoals(for draft: TrainingFuelPlanDraft, today: DailyLog?, goals: TodayFuelPlanGoals,
                        now: Date = Date(), calendar: Calendar = .current) -> TodayFuelPlanGoals {
        var reservedProtein = 0.0
        var reservedCarbs = 0.0
        for record in history where record.archivedAt == nil && record.plan.id != draft.id {
            // Earlier sessions get first use of the remaining budget. A stable ID breaks
            // ties; later plans cannot make an earlier plan wait on itself indirectly.
            guard record.plan.draft.scheduledAt < draft.scheduledAt ||
                    record.plan.draft.scheduledAt == draft.scheduledAt && record.plan.id < draft.id else { continue }
            let plan = record.plan
            guard calendar.isDate(plan.draft.scheduledAt, inSameDayAs: draft.scheduledAt), plan.outcome?.status != .skipped else { continue }
            let progress = TrainingFuelPlanProgressRules.makeProgress(plan: plan, today: today, goals: goals, now: now, calendar: calendar)
            guard [.upcoming, .inSession, .recovery, .awaitingOutcome].contains(progress.status) else { continue }
            for phase in progress.phases {
                if phase.allocation.phase == .beforeTraining && now >= plan.draft.scheduledAt { continue }
                if phase.allocation.phase == .duringTraining && now >= plan.estimatedEndAt { continue }
                reservedProtein += Double(phase.remainingProteinGrams)
                reservedCarbs += Double(phase.remainingCarbGrams)
            }
        }
        return TodayFuelPlanGoals(calories: max(0, goals.calories - (reservedProtein + reservedCarbs) * 4),
            protein: max(0, goals.protein - reservedProtein), carbs: max(0, goals.carbs - reservedCarbs), fats: goals.fats)
    }

    func progress(for plan: TrainingFuelConfirmedPlan, today: DailyLog?, goals: TodayFuelPlanGoals,
                  now: Date = Date(), calendar: Calendar = .current) -> TrainingFuelPlanProgress {
        let available = availableGoals(for: plan.draft, today: today, goals: goals, now: now, calendar: calendar)
        return TrainingFuelPlanProgressRules.makeProgress(plan: plan, today: today, goals: available, now: now, calendar: calendar)
    }

    /// Used by the existing durable food editors. Validation runs once before submission;
    /// uncertain retries continue their original reviewed diary command.
    func stageFoodLink(target: TrainingFuelTarget, foods: [FoodItem], date: Date, using service: DailyLogService,
                       userID: String) throws {
        guard let settings = service.goalSettings else { throw TrainingFuelLibraryError.budgetChanged }
        try stageFoodLink(target: target, foods: foods, date: date, today: service.currentDailyLog,
            goals: TodayFuelPlanGoals(calories: settings.calories ?? 0, protein: settings.protein, carbs: settings.carbs, fats: settings.fats), userID: userID, requiresSubmissionAuthorization: true)
    }
}
