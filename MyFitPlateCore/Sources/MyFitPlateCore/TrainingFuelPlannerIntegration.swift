import Combine
import Foundation

public struct TrainingFuelSessionCandidate: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case activeStrengthProgram = "active_strength_program"
        case selectedRunPlan = "selected_run_plan"
        case manualStrength = "manual_strength"
        case manualRun = "manual_run"
    }

    public enum Assumption: String, Codable, Equatable, Sendable {
        case durationEstimated = "duration_estimated"
        case durationNeedsReview = "duration_needs_review"
        case intensityEstimated = "intensity_estimated"
        case focusEstimated = "focus_estimated"
        case sessionTimeRequired = "session_time_required"
    }

    public let id: String
    public let source: Source
    public let sourceID: String?
    public let sessionReferenceID: String?
    public let title: String
    public let detail: String
    public let kind: TrainingFuelSession.Kind
    public let scheduledDay: Date?
    public let suggestedDurationMinutes: Int?
    public let suggestedIntensity: TrainingFuelSession.Intensity
    public let suggestedStrengthFocus: TrainingFuelSession.StrengthFocus
    public let assumptions: [Assumption]

    public init(
        id: String,
        source: Source,
        sourceID: String?,
        sessionReferenceID: String? = nil,
        title: String,
        detail: String,
        kind: TrainingFuelSession.Kind,
        scheduledDay: Date?,
        suggestedDurationMinutes: Int?,
        suggestedIntensity: TrainingFuelSession.Intensity,
        suggestedStrengthFocus: TrainingFuelSession.StrengthFocus,
        assumptions: [Assumption]
    ) {
        self.id = id
        self.source = source
        self.sourceID = sourceID
        self.sessionReferenceID = sessionReferenceID
        self.title = title
        self.detail = detail
        self.kind = kind
        self.scheduledDay = scheduledDay
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.suggestedIntensity = suggestedIntensity
        self.suggestedStrengthFocus = suggestedStrengthFocus
        self.assumptions = assumptions
    }
}

public enum TrainingFuelSessionAdapter {
    public static func activeStrengthCandidate(
        from program: WorkoutProgram,
        calendar: Calendar = .current
    ) -> TrainingFuelSessionCandidate? {
        guard !program.routines.isEmpty else { return nil }

        let index = max(program.currentProgressIndex ?? 0, 0)
        let totalSlots = max((program.daysOfWeek?.count ?? 0) * 12, program.routines.count)
        guard index < totalSlots else { return nil }

        let routine = program.routines[index % program.routines.count]
        let daysPerWeek = max(program.daysOfWeek?.count ?? 0, 1)
        let week = index / daysPerWeek + 1
        let day = index % daysPerWeek + 1
        let duration = estimatedStrengthDuration(for: routine)
        let focus = inferredStrengthFocus(for: routine)

        return TrainingFuelSessionCandidate(
            id: "strength:\(program.id ?? program.name):\(routine.id):\(index)",
            source: .activeStrengthProgram,
            sourceID: program.id,
            sessionReferenceID: routine.id,
            title: routine.name,
            detail: "\(program.name) - Week \(week), Day \(day)",
            kind: .strength,
            scheduledDay: scheduledDay(forSlot: index, in: program, calendar: calendar),
            suggestedDurationMinutes: duration,
            suggestedIntensity: .moderate,
            suggestedStrengthFocus: focus,
            assumptions: [.durationEstimated, .intensityEstimated, .focusEstimated, .sessionTimeRequired]
        )
    }

    public static func runCandidate(from plan: RunWorkoutPlan) -> TrainingFuelSessionCandidate {
        let containsDistanceStep = plan.steps.contains { step in
            if case .distance = step.goal { return true }
            return false
        }
        let duration: Int?
        if containsDistanceStep {
            duration = nil
        } else {
            let minutes = Int(ceil(plan.estimatedDurationSeconds / 60))
            duration = minutes > 0 ? minutes : nil
        }
        let hasHardWork = plan.steps.contains { $0.kind == .hard }

        return TrainingFuelSessionCandidate(
            id: "run:\(plan.id)",
            source: .selectedRunPlan,
            sourceID: plan.id,
            sessionReferenceID: plan.id,
            title: plan.name,
            detail: plan.subtitle,
            kind: .run,
            scheduledDay: nil,
            suggestedDurationMinutes: duration,
            suggestedIntensity: hasHardWork ? .hard : .easy,
            suggestedStrengthFocus: .unknown,
            assumptions: [
                duration == nil ? .durationNeedsReview : .durationEstimated,
                .intensityEstimated,
                .sessionTimeRequired
            ]
        )
    }

    public static func manualCandidate(
        kind: TrainingFuelSession.Kind
    ) -> TrainingFuelSessionCandidate {
        let isStrength = kind == .strength
        return TrainingFuelSessionCandidate(
            id: isStrength ? "manual:strength" : "manual:run",
            source: isStrength ? .manualStrength : .manualRun,
            sourceID: nil,
            title: isStrength ? "Strength workout" : "Run",
            detail: "Set today's session details",
            kind: kind,
            scheduledDay: nil,
            suggestedDurationMinutes: nil,
            suggestedIntensity: .moderate,
            suggestedStrengthFocus: .unknown,
            assumptions: [.durationNeedsReview, .intensityEstimated, .sessionTimeRequired]
        )
    }

    private static func estimatedStrengthDuration(for routine: WorkoutRoutine) -> Int {
        let seconds = routine.exercises.reduce(8 * 60) { total, exercise in
            let setCount = max(max(exercise.targetSets, exercise.sets.count), 1)
            let workSeconds = setCount * 45
            let restSeconds = max(0, setCount - 1) * max(0, exercise.restTimeInSeconds)
            return total + workSeconds + restSeconds
        }
        return min(120, max(20, Int(ceil(Double(seconds) / 60))))
    }

    private static func inferredStrengthFocus(
        for routine: WorkoutRoutine
    ) -> TrainingFuelSession.StrengthFocus {
        var hasUpper = false
        var hasLower = false
        var hasFullBody = false
        var hasOther = false

        for exercise in routine.exercises where exercise.type == .strength {
            let category = ExerciseList.category(for: exercise.name)
            switch category {
            case "Legs", "Glutes", "Calves":
                hasLower = true
            case "Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms":
                hasUpper = true
            case "Full Body":
                hasFullBody = true
            case .none:
                let name = exercise.name.lowercased()
                if name.contains("squat") || name.contains("lunge") || name.contains("leg") ||
                    name.contains("glute") || name.contains("calf") || name.contains("deadlift") {
                    hasLower = true
                } else if name.contains("press") || name.contains("row") || name.contains("pull") ||
                    name.contains("curl") || name.contains("shoulder") || name.contains("chest") {
                    hasUpper = true
                } else {
                    hasOther = true
                }
            default:
                hasOther = true
            }
        }

        if hasFullBody || (hasUpper && hasLower) { return .fullBody }
        if hasLower && !hasUpper { return .lowerBody }
        if hasUpper && !hasLower { return .upperBody }
        if hasOther { return .mixed }
        return .unknown
    }

    private static func scheduledDay(
        forSlot index: Int,
        in program: WorkoutProgram,
        calendar: Calendar
    ) -> Date? {
        guard let startDate = program.startDate,
              let days = program.daysOfWeek,
              !days.isEmpty else { return nil }

        let allowedDays = Set(days.filter { (1...7).contains($0) })
        guard !allowedDays.isEmpty else { return nil }

        let start = calendar.startOfDay(for: startDate)
        var matchedSlot = 0
        for offset in 0..<(7 * 13) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  allowedDays.contains(calendar.component(.weekday, from: date)) else { continue }
            if matchedSlot == index { return calendar.startOfDay(for: date) }
            matchedSlot += 1
        }
        return nil
    }
}

public struct TrainingFuelPlanDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var source: TrainingFuelSessionCandidate.Source
    public var sourceID: String?
    public var sessionReferenceID: String?
    public var sessionTitle: String
    public var scheduledAt: Date
    public var durationMinutes: Int
    public var intensity: TrainingFuelSession.Intensity
    public var strengthFocus: TrainingFuelSession.StrengthFocus
    public var preference: TrainingFuelPreference

    public init(
        id: String = UUID().uuidString,
        candidate: TrainingFuelSessionCandidate,
        scheduledAt: Date,
        durationMinutes: Int? = nil,
        intensity: TrainingFuelSession.Intensity? = nil,
        strengthFocus: TrainingFuelSession.StrengthFocus? = nil,
        preference: TrainingFuelPreference = TrainingFuelPreference()
    ) {
        self.id = id
        self.source = candidate.source
        self.sourceID = candidate.sourceID
        self.sessionReferenceID = candidate.sessionReferenceID
        self.sessionTitle = candidate.title
        self.scheduledAt = scheduledAt
        self.durationMinutes = durationMinutes ?? candidate.suggestedDurationMinutes ?? 45
        self.intensity = intensity ?? candidate.suggestedIntensity
        self.strengthFocus = strengthFocus ?? candidate.suggestedStrengthFocus
        self.preference = preference
    }

    public var kind: TrainingFuelSession.Kind {
        switch source {
        case .activeStrengthProgram, .manualStrength:
            return .strength
        case .selectedRunPlan, .manualRun:
            return .run
        }
    }

    public var session: TrainingFuelSession {
        TrainingFuelSession(
            kind: kind,
            scheduledAt: scheduledAt,
            expectedDurationMinutes: durationMinutes,
            intensity: intensity,
            strengthFocus: kind == .strength ? strengthFocus : .unknown
        )
    }
}

public struct TrainingFuelDiarySnapshot: Codable, Equatable, Sendable {
    public let calories: Double
    public let proteinGrams: Double
    public let carbGrams: Double

    public init(log: DailyLog?) {
        let macros = log?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        calories = log?.totalCalories() ?? 0
        proteinGrams = macros.protein
        carbGrams = macros.carbs
    }
}

public struct TrainingFuelSessionOutcome: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case completed
        case skipped
    }

    public enum Source: String, Codable, Equatable, Sendable {
        case strengthWorkout = "strength_workout"
        case recordedRun = "recorded_run"
        case treadmillRun = "treadmill_run"
        case programSkip = "program_skip"
        case manualConfirmation = "manual_confirmation"
    }

    public let status: Status
    public let source: Source
    public let recordedAt: Date
    public let actualStartAt: Date?
    public let actualEndAt: Date?
    public let referenceID: String?
    public let diaryAtOutcome: TrainingFuelDiarySnapshot
    public let recoveryPlan: TrainingFuelPlannerPlan?
    public let recoveryDiaryIsAuthoritative: Bool?

    public init(
        status: Status,
        source: Source,
        recordedAt: Date,
        actualStartAt: Date? = nil,
        actualEndAt: Date? = nil,
        referenceID: String? = nil,
        diaryAtOutcome: TrainingFuelDiarySnapshot = TrainingFuelDiarySnapshot(log: nil),
        recoveryPlan: TrainingFuelPlannerPlan? = nil,
        recoveryDiaryIsAuthoritative: Bool? = nil
    ) {
        self.status = status
        self.source = source
        self.recordedAt = recordedAt
        self.actualStartAt = actualStartAt
        self.actualEndAt = actualEndAt
        self.referenceID = referenceID
        self.diaryAtOutcome = diaryAtOutcome
        self.recoveryPlan = recoveryPlan
        self.recoveryDiaryIsAuthoritative = recoveryDiaryIsAuthoritative
    }

    public var hasAuthoritativeRecoveryDiary: Bool {
        recoveryDiaryIsAuthoritative ?? (recoveryPlan != nil)
    }
}

public struct TrainingFuelConfirmedPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String { draft.id }
    public let draft: TrainingFuelPlanDraft
    public let confirmedAt: Date
    public let allocations: [TrainingFuelAllocation]
    public let goalsAtConfirmation: TodayFuelPlanGoals
    public let diaryAtConfirmation: TrainingFuelDiarySnapshot
    public var outcome: TrainingFuelSessionOutcome?

    public init(
        draft: TrainingFuelPlanDraft,
        plannerPlan: TrainingFuelPlannerPlan,
        goals: TodayFuelPlanGoals,
        today: DailyLog?,
        existingPlan: TrainingFuelConfirmedPlan? = nil,
        confirmedAt: Date = Date()
    ) {
        let diary = TrainingFuelDiarySnapshot(log: today)
        let matchingPlan = existingPlan?.id == draft.id ? existingPlan : nil
        self.draft = draft
        self.confirmedAt = matchingPlan?.confirmedAt ?? confirmedAt
        self.allocations = plannerPlan.allocations
        self.goalsAtConfirmation = matchingPlan?.goalsAtConfirmation ?? TodayFuelPlanGoals(
            calories: goals.calories,
            protein: diary.proteinGrams + Double(plannerPlan.remainingProteinGrams),
            carbs: diary.carbGrams + Double(plannerPlan.remainingCarbGrams),
            fats: goals.fats.isFinite && goals.fats >= 0 ? goals.fats : 0
        )
        self.diaryAtConfirmation = matchingPlan?.diaryAtConfirmation ?? diary
        self.outcome = matchingPlan?.outcome
    }

    public var estimatedEndAt: Date {
        draft.scheduledAt.addingTimeInterval(Double(draft.durationMinutes * 60))
    }

    public func defersPostSession(toNextDay calendar: Calendar = .current) -> Bool {
        draft.preference.wantsPostSessionFuel &&
            !calendar.isDate(estimatedEndAt, inSameDayAs: draft.scheduledAt)
    }

    public func requiresRecoveryDiaryRefresh(
        calendar: Calendar = .current
    ) -> Bool {
        guard let outcome,
              outcome.status == .completed,
              draft.preference.wantsPostSessionFuel else { return false }
        let actualEnd = outcome.actualEndAt ?? outcome.recordedAt
        let needsFreshRecovery = !allocations.contains { $0.phase == .afterTraining } ||
            !calendar.isDate(actualEnd, inSameDayAs: draft.scheduledAt)
        return needsFreshRecovery && !outcome.hasAuthoritativeRecoveryDiary
    }
}

public enum TrainingFuelDeferredRecoveryRules {
    public static func makePlan(
        for confirmedPlan: TrainingFuelConfirmedPlan,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        completedAt: Date,
        calendar: Calendar = .current
    ) -> TrainingFuelPlannerPlan {
        let planningAnchor = calendar.date(
            byAdding: .hour,
            value: 12,
            to: calendar.startOfDay(for: completedAt)
        ) ?? completedAt
        let session = TrainingFuelSession(
            kind: confirmedPlan.draft.kind,
            scheduledAt: planningAnchor,
            expectedDurationMinutes: confirmedPlan.draft.durationMinutes,
            intensity: confirmedPlan.draft.intensity,
            strengthFocus: confirmedPlan.draft.strengthFocus
        )
        return TrainingFuelPlannerRules.makePlan(
            session: session,
            today: today,
            goals: goals,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: false,
                wantsPostSessionFuel: true
            ),
            now: planningAnchor,
            calendar: calendar
        )
    }
}

public struct TrainingFuelTarget: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let planID: String
    public let sessionTitle: String
    public let phase: TrainingFuelAllocation.Phase
    public let proteinGrams: Int
    public let carbGrams: Int

    public init(
        id: String = UUID().uuidString,
        planID: String,
        sessionTitle: String,
        phase: TrainingFuelAllocation.Phase,
        proteinGrams: Int,
        carbGrams: Int
    ) {
        self.id = id
        self.planID = planID
        self.sessionTitle = sessionTitle
        self.phase = phase
        self.proteinGrams = max(0, proteinGrams)
        self.carbGrams = max(0, carbGrams)
    }

    public var calories: Int { (proteinGrams + carbGrams) * 4 }
}

public struct TrainingFuelPhaseProgress: Equatable, Identifiable, Sendable {
    public var id: String { allocation.phase.rawValue }
    public let allocation: TrainingFuelAllocation
    public let loggedProteinGrams: Int
    public let loggedCarbGrams: Int
    public let actionableProteinGrams: Int
    public let actionableCarbGrams: Int

    public init(
        allocation: TrainingFuelAllocation,
        loggedProteinGrams: Int,
        loggedCarbGrams: Int,
        actionableProteinGrams: Int? = nil,
        actionableCarbGrams: Int? = nil
    ) {
        self.allocation = allocation
        self.loggedProteinGrams = max(0, loggedProteinGrams)
        self.loggedCarbGrams = max(0, loggedCarbGrams)
        self.actionableProteinGrams = max(
            0,
            actionableProteinGrams ?? (allocation.proteinGrams - loggedProteinGrams)
        )
        self.actionableCarbGrams = max(
            0,
            actionableCarbGrams ?? (allocation.carbGrams - loggedCarbGrams)
        )
    }

    public var remainingProteinGrams: Int {
        actionableProteinGrams
    }

    public var remainingCarbGrams: Int {
        actionableCarbGrams
    }

    public var isComplete: Bool {
        loggedProteinGrams >= allocation.proteinGrams &&
            loggedCarbGrams >= allocation.carbGrams
    }

    public var hasMeaningfulUnloggedTarget: Bool {
        let protein = max(0, allocation.proteinGrams - loggedProteinGrams)
        let carbs = max(0, allocation.carbGrams - loggedCarbGrams)
        return (protein + carbs) * 4 >= 60 && (protein >= 10 || carbs >= 10)
    }

    public var hasActionableTarget: Bool {
        (actionableProteinGrams + actionableCarbGrams) * 4 >= 60
    }
}

public struct TrainingFuelPlanProgress: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case upcoming
        case inSession = "in_session"
        case awaitingOutcome = "awaiting_outcome"
        case awaitingRecoveryData = "awaiting_recovery_data"
        case recovery
        case complete
        case skipped
        case stale
        case overTarget = "over_target"
        case invalidDiary = "invalid_diary"
        case invalidTargets = "invalid_targets"
        case budgetUsedElsewhere = "budget_used_elsewhere"
    }

    public let status: Status
    public let phases: [TrainingFuelPhaseProgress]

    public func target(
        for phase: TrainingFuelAllocation.Phase,
        plan: TrainingFuelConfirmedPlan
    ) -> TrainingFuelTarget? {
        switch status {
        case .upcoming:
            guard phase == .beforeTraining else { return nil }
        case .inSession:
            return nil
        case .recovery:
            guard phase == .afterTraining else { return nil }
        case .awaitingOutcome, .awaitingRecoveryData, .complete, .skipped, .stale, .overTarget,
             .invalidDiary, .invalidTargets, .budgetUsedElsewhere:
            return nil
        }
        guard let progress = phases.first(where: { $0.allocation.phase == phase }),
              !progress.isComplete,
              progress.hasActionableTarget else { return nil }
        return TrainingFuelTarget(
            id: "\(plan.id):\(phase.rawValue)",
            planID: plan.id,
            sessionTitle: plan.draft.sessionTitle,
            phase: phase,
            proteinGrams: progress.remainingProteinGrams,
            carbGrams: progress.remainingCarbGrams
        )
    }
}

public enum TrainingFuelPlanProgressRules {
    private static let recoveryWindow: TimeInterval = 2 * 60 * 60

    private struct ReconciliationContext {
        let allocations: [TrainingFuelAllocation]
        let baseline: TrainingFuelDiarySnapshot
        let attributionBeganAt: Date
        let sessionStart: Date
        let sessionEnd: Date
    }

    public static func makeProgress(
        plan: TrainingFuelConfirmedPlan,
        today: DailyLog?,
        goals: TodayFuelPlanGoals? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingFuelPlanProgress {
        if plan.outcome?.status == .skipped {
            return TrainingFuelPlanProgress(
                status: .skipped,
                phases: inactiveProgress(for: plan.allocations)
            )
        }

        if plan.requiresRecoveryDiaryRefresh(calendar: calendar) {
            let actualEnd = plan.outcome?.actualEndAt ?? plan.outcome?.recordedAt ?? plan.estimatedEndAt
            if now > actualEnd.addingTimeInterval(recoveryWindow) {
                return TrainingFuelPlanProgress(status: .stale, phases: [])
            }
            return TrainingFuelPlanProgress(
                status: .awaitingRecoveryData,
                phases: inactiveProgress(for: [])
            )
        }

        let context = reconciliationContext(for: plan)
        let loggedMacros = today?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        let values: [Double] = [
            today?.totalCalories() ?? 0,
            loggedMacros.protein,
            loggedMacros.carbs
        ]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return TrainingFuelPlanProgress(
                status: .invalidDiary,
                phases: inactiveProgress(for: context.allocations)
            )
        }
        let effectiveGoals = goals ?? plan.goalsAtConfirmation
        guard effectiveGoals.calories.isFinite,
              effectiveGoals.calories > 0,
              effectiveGoals.protein.isFinite,
              effectiveGoals.protein >= 0,
              effectiveGoals.carbs.isFinite,
              effectiveGoals.carbs >= 0 else {
            return TrainingFuelPlanProgress(
                status: .invalidTargets,
                phases: inactiveProgress(for: context.allocations)
            )
        }
        let phaseProgress = progressByPhase(
            context: context,
            today: today,
            goals: effectiveGoals,
            now: now
        )

        guard isRelevantDay(plan: plan, now: now, calendar: calendar) else {
            return TrainingFuelPlanProgress(status: .stale, phases: phaseProgress)
        }

        if plan.outcome?.status == .completed {
            return completedProgress(
                plan: plan,
                context: context,
                phases: phaseProgress,
                today: today,
                goals: effectiveGoals,
                now: now
            )
        }

        return pendingProgress(
            context: context,
            phases: phaseProgress,
            today: today,
            goals: effectiveGoals,
            now: now
        )
    }

    private static func reconciliationContext(
        for plan: TrainingFuelConfirmedPlan
    ) -> ReconciliationContext {
        if let outcome = plan.outcome,
           outcome.status == .completed,
           let recoveryPlan = outcome.recoveryPlan {
            let actualEnd = outcome.actualEndAt ?? outcome.recordedAt
            return ReconciliationContext(
                allocations: recoveryPlan.allocations,
                baseline: outcome.diaryAtOutcome,
                attributionBeganAt: outcome.recordedAt,
                sessionStart: actualEnd,
                sessionEnd: actualEnd
            )
        }

        let actualEnd = plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        let actualStart = plan.outcome?.actualStartAt ?? min(plan.draft.scheduledAt, actualEnd)
        return ReconciliationContext(
            allocations: plan.allocations,
            baseline: plan.diaryAtConfirmation,
            attributionBeganAt: plan.confirmedAt,
            sessionStart: actualStart,
            sessionEnd: actualEnd
        )
    }

    private static func completedProgress(
        plan: TrainingFuelConfirmedPlan,
        context: ReconciliationContext,
        phases: [TrainingFuelPhaseProgress],
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date
    ) -> TrainingFuelPlanProgress {
        if now < context.sessionEnd {
            return TrainingFuelPlanProgress(status: .inSession, phases: phases)
        }
        if now > context.sessionEnd.addingTimeInterval(recoveryWindow) {
            return TrainingFuelPlanProgress(status: .stale, phases: phases)
        }
        guard plan.draft.preference.wantsPostSessionFuel else {
            return TrainingFuelPlanProgress(status: .complete, phases: phases)
        }

        if let recoveryStatus = plan.outcome?.recoveryPlan?.status,
           let blockedStatus = blockedStatus(for: recoveryStatus) {
            return TrainingFuelPlanProgress(status: blockedStatus, phases: phases)
        }

        let recoveryPhases = phases.filter { $0.allocation.phase == .afterTraining }
        guard !recoveryPhases.isEmpty else {
            return TrainingFuelPlanProgress(status: .budgetUsedElsewhere, phases: phases)
        }
        if recoveryPhases.allSatisfy(\.isComplete) {
            return TrainingFuelPlanProgress(status: .complete, phases: phases)
        }
        if (today?.totalCalories() ?? 0) >= goals.calories {
            return TrainingFuelPlanProgress(status: .overTarget, phases: phases)
        }
        if hasUnmetTargetWithoutAction(recoveryPhases) {
            return TrainingFuelPlanProgress(status: .budgetUsedElsewhere, phases: phases)
        }
        return TrainingFuelPlanProgress(status: .recovery, phases: phases)
    }

    private static func pendingProgress(
        context: ReconciliationContext,
        phases: [TrainingFuelPhaseProgress],
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date
    ) -> TrainingFuelPlanProgress {
        if now < context.sessionStart {
            let preTraining = phases.filter { $0.allocation.phase == .beforeTraining }
            if (today?.totalCalories() ?? 0) >= goals.calories {
                return TrainingFuelPlanProgress(status: .overTarget, phases: phases)
            }
            if hasUnmetTargetWithoutAction(preTraining) {
                return TrainingFuelPlanProgress(status: .budgetUsedElsewhere, phases: phases)
            }
            return TrainingFuelPlanProgress(status: .upcoming, phases: phases)
        }
        if now < context.sessionEnd {
            return TrainingFuelPlanProgress(status: .inSession, phases: phases)
        }
        if now <= context.sessionEnd.addingTimeInterval(recoveryWindow) {
            return TrainingFuelPlanProgress(status: .awaitingOutcome, phases: phases)
        }
        return TrainingFuelPlanProgress(status: .stale, phases: phases)
    }

    private static func blockedStatus(
        for plannerStatus: TrainingFuelPlannerPlan.Status
    ) -> TrainingFuelPlanProgress.Status? {
        switch plannerStatus {
        case .ready:
            return nil
        case .deferredRecovery:
            return .budgetUsedElsewhere
        case .invalidDiaryData:
            return .invalidDiary
        case .invalidCalorieTarget:
            return .invalidTargets
        case .overTargetReview:
            return .overTarget
        case .insufficientBudget, .outsideToday, .needsSessionTime,
             .noFuelRequested, .staleSession:
            return .budgetUsedElsewhere
        }
    }

    private static func hasUnmetTargetWithoutAction(
        _ phases: [TrainingFuelPhaseProgress]
    ) -> Bool {
        phases.contains { !$0.isComplete && $0.hasMeaningfulUnloggedTarget } &&
            !phases.contains(where: \.hasActionableTarget)
    }

    private static func isRelevantDay(
        plan: TrainingFuelConfirmedPlan,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if calendar.isDate(plan.draft.scheduledAt, inSameDayAs: now) {
            return true
        }
        let end = plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        guard !calendar.isDate(end, inSameDayAs: plan.draft.scheduledAt) else {
            return false
        }
        return now >= plan.draft.scheduledAt &&
            now <= end.addingTimeInterval(recoveryWindow)
    }

    private static func inactiveProgress(
        for allocations: [TrainingFuelAllocation]
    ) -> [TrainingFuelPhaseProgress] {
        allocations.map {
            TrainingFuelPhaseProgress(
                allocation: $0,
                loggedProteinGrams: 0,
                loggedCarbGrams: 0,
                actionableProteinGrams: 0,
                actionableCarbGrams: 0
            )
        }
    }

    private static func progressByPhase(
        context: ReconciliationContext,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date
    ) -> [TrainingFuelPhaseProgress] {
        let items = today?.meals.flatMap(\.foodItems) ?? []
        var proteinByPhase: [TrainingFuelAllocation.Phase: Double] = [:]
        var carbsByPhase: [TrainingFuelAllocation.Phase: Double] = [:]
        var timestampedProtein = 0.0
        var timestampedCarbs = 0.0

        for item in items {
            guard let timestamp = item.timestamp,
                  timestamp > context.attributionBeganAt else { continue }
            let protein = max(0, item.protein)
            let carbs = max(0, item.carbs)
            timestampedProtein += protein
            timestampedCarbs += carbs
            guard timestamp <= now else { continue }

            let phase: TrainingFuelAllocation.Phase
            if timestamp < context.sessionStart {
                phase = .beforeTraining
            } else if timestamp >= context.sessionEnd {
                phase = .afterTraining
            } else {
                continue
            }
            proteinByPhase[phase, default: 0] += protein
            carbsByPhase[phase, default: 0] += carbs
        }

        let total = TrainingFuelDiarySnapshot(log: today)
        let unassignedProtein = max(
            0,
            total.proteinGrams - context.baseline.proteinGrams - timestampedProtein
        )
        let unassignedCarbs = max(
            0,
            total.carbGrams - context.baseline.carbGrams - timestampedCarbs
        )
        let fallbackPhase: TrainingFuelAllocation.Phase?
        if now < context.sessionStart {
            fallbackPhase = .beforeTraining
        } else if now >= context.sessionEnd {
            fallbackPhase = .afterTraining
        } else {
            fallbackPhase = nil
        }
        if let fallbackPhase {
            proteinByPhase[fallbackPhase, default: 0] += unassignedProtein
            carbsByPhase[fallbackPhase, default: 0] += unassignedCarbs
        }

        let rawProgress = context.allocations.map { allocation in
            TrainingFuelPhaseProgress(
                allocation: allocation,
                loggedProteinGrams: min(
                    allocation.proteinGrams,
                    Int(floor(proteinByPhase[allocation.phase, default: 0]))
                ),
                loggedCarbGrams: min(
                    allocation.carbGrams,
                    Int(floor(carbsByPhase[allocation.phase, default: 0]))
                )
            )
        }
        return cappedProgress(
            rawProgress,
            sessionStart: context.sessionStart,
            today: today,
            goals: goals,
            now: now
        )
    }

    private static func cappedProgress(
        _ progress: [TrainingFuelPhaseProgress],
        sessionStart: Date,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date
    ) -> [TrainingFuelPhaseProgress] {
        let macros = today?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        let remainingCalories = max(
            0,
            goals.calories - (today?.totalCalories() ?? 0)
        )
        let remainingProtein = max(0, goals.protein - macros.protein)
        let remainingCarbs = max(0, goals.carbs - macros.carbs)

        var protein = progress.map { phase -> Double in
            if phase.allocation.phase == .beforeTraining && now >= sessionStart { return 0 }
            return Double(max(0, phase.allocation.proteinGrams - phase.loggedProteinGrams))
        }
        var carbs = progress.map { phase -> Double in
            if phase.allocation.phase == .beforeTraining && now >= sessionStart { return 0 }
            return Double(max(0, phase.allocation.carbGrams - phase.loggedCarbGrams))
        }

        scale(&protein, toTotalAtMost: remainingProtein)
        scale(&carbs, toTotalAtMost: remainingCarbs)
        let requestedCalories = (protein.reduce(0, +) + carbs.reduce(0, +)) * 4
        if requestedCalories > remainingCalories, requestedCalories > 0 {
            let factor = remainingCalories / requestedCalories
            protein = protein.map { $0 * factor }
            carbs = carbs.map { $0 * factor }
        }

        return progress.indices.map { index in
            var availableProtein = Int(floor(protein[index]))
            var availableCarbs = Int(floor(carbs[index]))
            if availableProtein < 10 { availableProtein = 0 }
            if availableCarbs < 10 { availableCarbs = 0 }
            if (availableProtein + availableCarbs) * 4 < 60 {
                availableProtein = 0
                availableCarbs = 0
            }
            return TrainingFuelPhaseProgress(
                allocation: progress[index].allocation,
                loggedProteinGrams: progress[index].loggedProteinGrams,
                loggedCarbGrams: progress[index].loggedCarbGrams,
                actionableProteinGrams: availableProtein,
                actionableCarbGrams: availableCarbs
            )
        }
    }

    private static func scale(_ values: inout [Double], toTotalAtMost limit: Double) {
        let total = values.reduce(0, +)
        guard total > limit, total > 0 else { return }
        let factor = max(0, limit) / total
        values = values.map { $0 * factor }
    }
}

public enum TrainingFuelSessionOutcomeRules {
    private static let matchingTolerance: TimeInterval = 6 * 60 * 60

    public static func matchesStrengthCompletion(
        plan: TrainingFuelConfirmedPlan,
        routineID: String,
        routineName: String,
        completedAt: Date
    ) -> Bool {
        guard plan.outcome == nil, plan.draft.kind == .strength else { return false }
        switch plan.draft.source {
        case .activeStrengthProgram:
            if let reference = plan.draft.sessionReferenceID {
                guard reference == routineID else { return false }
            } else {
                guard normalized(plan.draft.sessionTitle) == normalized(routineName) else { return false }
            }
        case .manualStrength:
            break
        case .selectedRunPlan, .manualRun:
            return false
        }
        return completionIsNearPlan(plan, start: completedAt, end: completedAt)
    }

    public static func matchesRunCompletion(
        plan: TrainingFuelConfirmedPlan,
        run: Run,
        selectedPlanID: String?
    ) -> Bool {
        guard plan.outcome == nil, plan.draft.kind == .run else { return false }
        switch plan.draft.source {
        case .selectedRunPlan:
            guard let selectedPlanID,
                  selectedPlanID == (plan.draft.sessionReferenceID ?? plan.draft.sourceID) else {
                return false
            }
        case .manualRun:
            break
        case .activeStrengthProgram, .manualStrength:
            return false
        }
        return completionIsNearPlan(plan, start: run.startDate, end: run.endDate)
    }

    public static func matchesProgramSkip(
        plan: TrainingFuelConfirmedPlan,
        programID: String?,
        routineID: String
    ) -> Bool {
        guard plan.outcome == nil,
              plan.draft.source == .activeStrengthProgram,
              plan.draft.kind == .strength else { return false }
        if let sourceID = plan.draft.sourceID {
            guard sourceID == programID else { return false }
        }
        if let referenceID = plan.draft.sessionReferenceID {
            return referenceID == routineID
        }
        return true
    }

    private static func completionIsNearPlan(
        _ plan: TrainingFuelConfirmedPlan,
        start: Date,
        end: Date
    ) -> Bool {
        let earliest = plan.draft.scheduledAt.addingTimeInterval(-matchingTolerance)
        let latest = plan.estimatedEndAt.addingTimeInterval(matchingTolerance)
        return end >= earliest && start <= latest
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
public final class TrainingFuelPlanStore: ObservableObject {
    @Published public private(set) var confirmedPlan: TrainingFuelConfirmedPlan?

    private let userDefaults: UserDefaults
    private let keyPrefix = "myfitplate.training_fuel_plan."
    private var currentUserID: String?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load(
        for userID: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        currentUserID = userID
        guard let key = storageKey(for: userID) else {
            confirmedPlan = nil
            return
        }
        guard let data = userDefaults.data(forKey: key) else {
            confirmedPlan = nil
            return
        }
        guard let plan = try? JSONDecoder().decode(TrainingFuelConfirmedPlan.self, from: data) else {
            userDefaults.removeObject(forKey: key)
            confirmedPlan = nil
            return
        }

        guard shouldRetain(plan, at: now, calendar: calendar) else {
            userDefaults.removeObject(forKey: key)
            confirmedPlan = nil
            return
        }
        confirmedPlan = plan
    }

    public func confirm(_ plan: TrainingFuelConfirmedPlan, for userID: String?) {
        currentUserID = userID
        confirmedPlan = plan
        guard let key = storageKey(for: userID),
              let data = try? JSONEncoder().encode(plan) else { return }
        userDefaults.set(data, forKey: key)
    }

    @discardableResult
    public func recordStrengthCompletion(
        routineID: String,
        routineName: String,
        completedAt: Date,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let plan = planForOutcome(userID: userID, at: completedAt, calendar: calendar),
              TrainingFuelSessionOutcomeRules.matchesStrengthCompletion(
                plan: plan,
                routineID: routineID,
                routineName: routineName,
                completedAt: completedAt
              ) else { return false }
        return recordCompletion(
            plan: plan,
            source: .strengthWorkout,
            referenceID: routineID,
            actualStartAt: nil,
            actualEndAt: completedAt,
            today: today,
            goals: goals,
            userID: userID,
            calendar: calendar
        )
    }

    @discardableResult
    public func recordRunCompletion(
        _ run: Run,
        selectedPlanID: String?,
        source: TrainingFuelSessionOutcome.Source = .recordedRun,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let plan = planForOutcome(userID: userID, at: run.endDate, calendar: calendar),
              TrainingFuelSessionOutcomeRules.matchesRunCompletion(
                plan: plan,
                run: run,
                selectedPlanID: selectedPlanID
              ) else { return false }
        return recordCompletion(
            plan: plan,
            source: source,
            referenceID: run.id,
            actualStartAt: run.startDate,
            actualEndAt: run.endDate,
            today: today,
            goals: goals,
            userID: userID,
            calendar: calendar
        )
    }

    @discardableResult
    public func recordProgramSkip(
        programID: String?,
        routineID: String,
        at date: Date = Date(),
        today: DailyLog?,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard var plan = planForOutcome(userID: userID, at: date, calendar: calendar),
              TrainingFuelSessionOutcomeRules.matchesProgramSkip(
                plan: plan,
                programID: programID,
                routineID: routineID
              ) else { return false }
        plan.outcome = TrainingFuelSessionOutcome(
            status: .skipped,
            source: .programSkip,
            recordedAt: date,
            referenceID: routineID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: today)
        )
        confirm(plan, for: userID)
        return true
    }

    @discardableResult
    public func markCurrentPlanCompleted(
        at date: Date = Date(),
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let plan = planForOutcome(userID: userID, at: date, calendar: calendar),
              plan.outcome == nil else { return false }
        return recordCompletion(
            plan: plan,
            source: .manualConfirmation,
            referenceID: plan.draft.sessionReferenceID,
            actualStartAt: nil,
            actualEndAt: date,
            today: today,
            goals: goals,
            userID: userID,
            calendar: calendar
        )
    }

    @discardableResult
    public func markCurrentPlanSkipped(
        at date: Date = Date(),
        today: DailyLog?,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard var plan = planForOutcome(userID: userID, at: date, calendar: calendar),
              plan.outcome == nil else { return false }
        plan.outcome = TrainingFuelSessionOutcome(
            status: .skipped,
            source: .manualConfirmation,
            recordedAt: date,
            referenceID: plan.draft.sessionReferenceID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: today)
        )
        confirm(plan, for: userID)
        return true
    }

    @discardableResult
    public func refreshDeferredRecovery(
        today: DailyLog,
        goals: TodayFuelPlanGoals,
        at date: Date = Date(),
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard var plan = planForOutcome(userID: userID, at: date, calendar: calendar),
              plan.requiresRecoveryDiaryRefresh(calendar: calendar),
              let outcome = plan.outcome,
              calendar.isDate(today.date, inSameDayAs: outcome.actualEndAt ?? outcome.recordedAt) else {
            return false
        }
        let recoveryPlan = TrainingFuelDeferredRecoveryRules.makePlan(
            for: plan,
            today: today,
            goals: goals,
            completedAt: outcome.actualEndAt ?? outcome.recordedAt,
            calendar: calendar
        )
        plan.outcome = TrainingFuelSessionOutcome(
            status: outcome.status,
            source: outcome.source,
            recordedAt: outcome.recordedAt,
            actualStartAt: outcome.actualStartAt,
            actualEndAt: outcome.actualEndAt,
            referenceID: outcome.referenceID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: today),
            recoveryPlan: recoveryPlan,
            recoveryDiaryIsAuthoritative: true
        )
        confirm(plan, for: userID)
        return true
    }

    public func clear(for userID: String? = nil) {
        let resolvedUserID = userID ?? currentUserID
        if let key = storageKey(for: resolvedUserID) {
            userDefaults.removeObject(forKey: key)
        }
        confirmedPlan = nil
    }

    private func storageKey(for userID: String?) -> String? {
        guard let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else { return nil }
        return keyPrefix + userID
    }

    private func planForOutcome(
        userID: String?,
        at date: Date,
        calendar: Calendar
    ) -> TrainingFuelConfirmedPlan? {
        load(for: userID, now: date, calendar: calendar)
        return confirmedPlan
    }

    private func recordCompletion(
        plan: TrainingFuelConfirmedPlan,
        source: TrainingFuelSessionOutcome.Source,
        referenceID: String?,
        actualStartAt: Date?,
        actualEndAt: Date,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        userID: String?,
        calendar: Calendar
    ) -> Bool {
        var updated = plan
        let needsFreshRecoveryPlan = plan.draft.preference.wantsPostSessionFuel &&
            (
                plan.allocations.contains(where: { $0.phase == .afterTraining }) == false ||
                !calendar.isDate(actualEndAt, inSameDayAs: plan.draft.scheduledAt)
            )
        let hasMatchingDiary = today.map {
            calendar.isDate($0.date, inSameDayAs: actualEndAt)
        } ?? false
        let recoveryPlan = needsFreshRecoveryPlan && hasMatchingDiary
            ? TrainingFuelDeferredRecoveryRules.makePlan(
                for: plan,
                today: today,
                goals: goals,
                completedAt: actualEndAt,
                calendar: calendar
            )
            : nil
        updated.outcome = TrainingFuelSessionOutcome(
            status: .completed,
            source: source,
            recordedAt: actualEndAt,
            actualStartAt: actualStartAt,
            actualEndAt: actualEndAt,
            referenceID: referenceID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: hasMatchingDiary ? today : nil),
            recoveryPlan: recoveryPlan,
            recoveryDiaryIsAuthoritative: needsFreshRecoveryPlan ? hasMatchingDiary : true
        )
        confirm(updated, for: userID)
        return true
    }

    private func shouldRetain(
        _ plan: TrainingFuelConfirmedPlan,
        at now: Date,
        calendar: Calendar
    ) -> Bool {
        if calendar.isDate(plan.draft.scheduledAt, inSameDayAs: now) {
            return true
        }
        let end = plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        return now >= plan.draft.scheduledAt && now <= end.addingTimeInterval(2 * 60 * 60)
    }
}
