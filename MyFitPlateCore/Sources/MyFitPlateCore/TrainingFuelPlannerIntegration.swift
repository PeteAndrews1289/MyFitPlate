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
    public let identity: TrainingFuelSessionIdentity?

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
        assumptions: [Assumption],
        identity: TrainingFuelSessionIdentity? = nil
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
        self.identity = identity
    }
}

public enum TrainingFuelSessionAdapter {
    public static func activeStrengthCandidate(
        from program: WorkoutProgram,
        calendar: Calendar = .current
    ) -> TrainingFuelSessionCandidate? {
        guard !program.routines.isEmpty else { return nil }

        let index = max(program.currentProgressIndex ?? 0, 0)
        let totalSlots = program.totalSlots
        guard index < totalSlots else { return nil }

        guard let routine = program.routine(forSlot: index) else { return nil }
        let position = program.weekAndDay(forSlot: index)
        let week = position.week
        let day = position.day
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
            scheduledDay: program.date(forSlot: index, calendar: calendar),
            suggestedDurationMinutes: duration,
            suggestedIntensity: .moderate,
            suggestedStrengthFocus: focus,
            assumptions: [.durationEstimated, .intensityEstimated, .focusEstimated, .sessionTimeRequired],
            identity: TrainingFuelSessionIdentity(programID: program.id, programSlot: index,
                blockID: program.trainingBlock?.id, revisionID: program.trainingBlock?.revisionID)
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
    public var identity: TrainingFuelSessionIdentity?
    public var assumptions: [TrainingFuelSessionCandidate.Assumption]?

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
        self.identity = candidate.identity
        self.assumptions = candidate.assumptions
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
    public var ownerID: String?
    public var revisionID: String?
    public var calculation: TrainingFuelCalculationEvidence?
    public var foodLinks: [TrainingFuelFoodLink]?
    public var feedback: TrainingFuelFeedback?

    public init(
        draft: TrainingFuelPlanDraft,
        plannerPlan: TrainingFuelPlannerPlan,
        goals: TodayFuelPlanGoals,
        today: DailyLog?,
        existingPlan: TrainingFuelConfirmedPlan? = nil,
        confirmedAt: Date = Date(),
        calendar: Calendar = .current
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
        ownerID = matchingPlan?.ownerID; revisionID = matchingPlan?.revisionID
        calculation = TrainingFuelCalculationEvidence(plan: plannerPlan, draft: draft, at: confirmedAt, calendar: calendar)
        foodLinks = matchingPlan?.foodLinks ?? []; feedback = matchingPlan?.feedback
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
        let recoveryLimits = confirmedPlan.calculation?.individualEstimate.map { original in
            let earlier = confirmedPlan.allocations.filter { $0.phase != .afterTraining }
            return TrainingFuelRecoveryLimits(
                protein: max(0, original.appEstimatedProteinTotal - Double(earlier.reduce(0) { $0 + $1.proteinGrams })),
                carbs: max(0, original.appEstimatedCarbTotal - Double(earlier.reduce(0) { $0 + $1.carbGrams })))
        }
        return TrainingFuelPlannerRules.makePlan(
            session: session,
            today: today,
            goals: goals,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: false,
                wantsPostSessionFuel: true,
                personalInputs: confirmedPlan.draft.preference.personalInputs.map { input in
                    TrainingFuelPersonalInputs(adultConfirmed: input.adultConfirmed, bodyMass: input.bodyMass,
                        reviewedProteinGrams: input.reviewedProteinGrams, lastMealAt: input.lastMealAt, tolerance: input.tolerance)
                }
            ),
            now: planningAnchor,
            calendar: calendar,
            recoveryLimits: recoveryLimits
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
    public let context: TrainingFuelHandoffContext?

    public init(
        id: String = UUID().uuidString,
        planID: String,
        sessionTitle: String,
        phase: TrainingFuelAllocation.Phase,
        proteinGrams: Int,
        carbGrams: Int,
        context: TrainingFuelHandoffContext? = nil
    ) {
        self.id = id
        self.context = context
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
        let minimum = allocation.effectiveMinimumActionCalories
        return (protein + carbs) * 4 >= minimum && (protein >= (minimum == 60 ? 10 : 1) || carbs >= (minimum == 60 ? 10 : 1))
    }

    public var hasActionableTarget: Bool {
        (actionableProteinGrams + actionableCarbGrams) * 4 >= (allocation.effectiveMinimumActionCalories)
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
            guard phase == .duringTraining else { return nil }
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
        let links: [TrainingFuelFoodLink]
        let personalized: Bool
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
            now: now,
            calendar: calendar
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
                sessionEnd: actualEnd,
                links: plan.foodLinks ?? [], personalized: plan.calculation?.individualEstimate != nil
            )
        }

        let actualEnd = plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        let actualStart = plan.outcome?.actualStartAt ?? min(plan.draft.scheduledAt, actualEnd)
        return ReconciliationContext(
            allocations: plan.allocations,
            baseline: plan.diaryAtConfirmation,
            attributionBeganAt: plan.confirmedAt,
            sessionStart: actualStart,
            sessionEnd: actualEnd,
                links: plan.foodLinks ?? [], personalized: plan.calculation?.individualEstimate != nil
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
        now: Date,
        calendar: Calendar
    ) -> [TrainingFuelPhaseProgress] {
        let items = today?.meals.flatMap(\.foodItems) ?? []
        var proteinByPhase: [TrainingFuelAllocation.Phase: Double] = [:]
        var carbsByPhase: [TrainingFuelAllocation.Phase: Double] = [:]
        var seen = Set<String>()
        for link in context.links {
            guard let today, link.day == TrainingCalendarDay(today.date, calendar: calendar), seen.insert(link.foodID).inserted,
                  let item = items.first(where: { $0.id == link.foodID }),
                  [item.protein, item.carbs].allSatisfy({ $0.isFinite && $0 >= 0 }) else { continue }
            // Exact accepted diary identity only. Editing a portion updates progress; deleting it removes progress.
            proteinByPhase[link.phase, default: 0] += item.protein
            carbsByPhase[link.phase, default: 0] += item.carbs
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
            sessionEnd: context.sessionEnd,
            personalized: context.personalized,
            today: today,
            goals: goals,
            now: now
        )
    }

    private static func cappedProgress(
        _ progress: [TrainingFuelPhaseProgress],
        sessionStart: Date,
        sessionEnd: Date,
        personalized: Bool,
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
            if phase.allocation.phase == .duringTraining && now >= sessionEnd { return 0 }
            return Double(max(0, phase.allocation.proteinGrams - phase.loggedProteinGrams))
        }
        var carbs = progress.map { phase -> Double in
            if phase.allocation.phase == .beforeTraining && now >= sessionStart { return 0 }
            if phase.allocation.phase == .duringTraining && now >= sessionEnd { return 0 }
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
            let minimum = personalized ? 1 : 10
            if availableProtein < minimum { availableProtein = 0 }
            if availableCarbs < minimum { availableCarbs = 0 }
            if (availableProtein + availableCarbs) * 4 < (progress[index].allocation.effectiveMinimumActionCalories) {
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
        plan: TrainingFuelConfirmedPlan, routineID: String, routineName: String,
        completedAt: Date, session: WorkoutSessionLog? = nil
    ) -> Bool {
        guard plan.outcome == nil, plan.draft.kind == .strength,
              plan.draft.source == .activeStrengthProgram,
              let identity = plan.draft.identity, let programID = identity.programID,
              let slot = identity.programSlot, let session, session.id != nil,
              session.programContext?.programID == programID, session.programContext?.slotIndex == slot,
              plan.draft.sessionReferenceID == routineID, session.routineID == routineID else { return false }
        if let blockID = identity.blockID, session.programContext?.blockSession?.blockID != blockID { return false }
        // A later prescription revision remains the same session. History retains both snapshots.
        return completionIsNearPlan(plan, start: completedAt, end: completedAt)
    }

    public static func matchesRunCompletion(plan: TrainingFuelConfirmedPlan, run: Run, selectedPlanID: String?) -> Bool {
        guard plan.outcome == nil, plan.draft.kind == .run, plan.draft.source == .selectedRunPlan,
              let identity = plan.draft.identity, let commitmentID = identity.commitmentID,
              let context = run.scheduledContext, context.commitmentID == commitmentID,
              context.blockID == identity.blockID, context.plan.id == identity.runPlanID else { return false }
        return completionIsNearPlan(plan, start: run.startDate, end: run.endDate)
    }

    public static func matchesProgramSkip(plan: TrainingFuelConfirmedPlan, programID: String?, routineID: String, slotIndex: Int? = nil) -> Bool {
        guard plan.outcome == nil, plan.draft.source == .activeStrengthProgram, let identity = plan.draft.identity,
              let programID, let slotIndex else { return false }
        return identity.programID == programID && identity.programSlot == slotIndex && plan.draft.sessionReferenceID == routineID
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
