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

public struct TrainingFuelConfirmedPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String { draft.id }
    public let draft: TrainingFuelPlanDraft
    public let confirmedAt: Date
    public let allocations: [TrainingFuelAllocation]
    public let goalsAtConfirmation: TodayFuelPlanGoals
    public let diaryAtConfirmation: TrainingFuelDiarySnapshot

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
        case recovery
        case complete
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
        case .complete, .stale, .overTarget, .invalidDiary, .invalidTargets, .budgetUsedElsewhere:
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

    public static func makeProgress(
        plan: TrainingFuelConfirmedPlan,
        today: DailyLog?,
        goals: TodayFuelPlanGoals? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingFuelPlanProgress {
        let values = [
            today?.totalCalories() ?? 0,
            today?.totalMacros().protein ?? 0,
            today?.totalMacros().carbs ?? 0
        ]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return TrainingFuelPlanProgress(
                status: .invalidDiary,
                phases: plan.allocations.map {
                    TrainingFuelPhaseProgress(
                        allocation: $0,
                        loggedProteinGrams: 0,
                        loggedCarbGrams: 0,
                        actionableProteinGrams: 0,
                        actionableCarbGrams: 0
                    )
                }
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
                phases: plan.allocations.map {
                    TrainingFuelPhaseProgress(
                        allocation: $0,
                        loggedProteinGrams: 0,
                        loggedCarbGrams: 0,
                        actionableProteinGrams: 0,
                        actionableCarbGrams: 0
                    )
                }
            )
        }
        let phaseProgress = progressByPhase(
            plan: plan,
            today: today,
            goals: effectiveGoals,
            now: now
        )

        guard calendar.isDate(plan.draft.scheduledAt, inSameDayAs: now) else {
            return TrainingFuelPlanProgress(status: .stale, phases: phaseProgress)
        }
        if phaseProgress.allSatisfy(\.isComplete) {
            return TrainingFuelPlanProgress(status: .complete, phases: phaseProgress)
        }
        let end = plan.draft.scheduledAt.addingTimeInterval(Double(plan.draft.durationMinutes * 60))
        if now > end.addingTimeInterval(recoveryWindow) {
            return TrainingFuelPlanProgress(status: .stale, phases: phaseProgress)
        }
        if (today?.totalCalories() ?? 0) >= effectiveGoals.calories {
            return TrainingFuelPlanProgress(status: .overTarget, phases: phaseProgress)
        }

        let hasRelevantUnmetTarget = phaseProgress.contains { phase in
            guard !phase.isComplete, phase.hasMeaningfulUnloggedTarget else { return false }
            return phase.allocation.phase == .afterTraining || now < plan.draft.scheduledAt
        }
        if hasRelevantUnmetTarget && !phaseProgress.contains(where: \.hasActionableTarget) {
            return TrainingFuelPlanProgress(status: .budgetUsedElsewhere, phases: phaseProgress)
        }

        if now < plan.draft.scheduledAt {
            return TrainingFuelPlanProgress(status: .upcoming, phases: phaseProgress)
        }
        if now < end {
            return TrainingFuelPlanProgress(status: .inSession, phases: phaseProgress)
        }
        if now <= end.addingTimeInterval(recoveryWindow) {
            return TrainingFuelPlanProgress(status: .recovery, phases: phaseProgress)
        }
        return TrainingFuelPlanProgress(status: .stale, phases: phaseProgress)
    }

    private static func progressByPhase(
        plan: TrainingFuelConfirmedPlan,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date
    ) -> [TrainingFuelPhaseProgress] {
        let items = today?.meals.flatMap(\.foodItems) ?? []
        var proteinByPhase: [TrainingFuelAllocation.Phase: Double] = [:]
        var carbsByPhase: [TrainingFuelAllocation.Phase: Double] = [:]
        var timestampedProtein = 0.0
        var timestampedCarbs = 0.0
        let sessionEnd = plan.draft.scheduledAt.addingTimeInterval(
            Double(plan.draft.durationMinutes * 60)
        )

        for item in items {
            guard let timestamp = item.timestamp,
                  timestamp >= plan.confirmedAt else { continue }
            let protein = max(0, item.protein)
            let carbs = max(0, item.carbs)
            timestampedProtein += protein
            timestampedCarbs += carbs
            guard timestamp <= now else { continue }

            let phase: TrainingFuelAllocation.Phase
            if timestamp < plan.draft.scheduledAt {
                phase = .beforeTraining
            } else if timestamp >= sessionEnd {
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
            total.proteinGrams - plan.diaryAtConfirmation.proteinGrams - timestampedProtein
        )
        let unassignedCarbs = max(
            0,
            total.carbGrams - plan.diaryAtConfirmation.carbGrams - timestampedCarbs
        )
        let fallbackPhase: TrainingFuelAllocation.Phase?
        if now < plan.draft.scheduledAt {
            fallbackPhase = .beforeTraining
        } else if now >= sessionEnd {
            fallbackPhase = .afterTraining
        } else {
            fallbackPhase = nil
        }
        if let fallbackPhase {
            proteinByPhase[fallbackPhase, default: 0] += unassignedProtein
            carbsByPhase[fallbackPhase, default: 0] += unassignedCarbs
        }

        let rawProgress = plan.allocations.map { allocation in
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
        return cappedProgress(rawProgress, plan: plan, today: today, goals: goals, now: now)
    }

    private static func cappedProgress(
        _ progress: [TrainingFuelPhaseProgress],
        plan: TrainingFuelConfirmedPlan,
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
            if phase.allocation.phase == .beforeTraining && now >= plan.draft.scheduledAt { return 0 }
            return Double(max(0, phase.allocation.proteinGrams - phase.loggedProteinGrams))
        }
        var carbs = progress.map { phase -> Double in
            if phase.allocation.phase == .beforeTraining && now >= plan.draft.scheduledAt { return 0 }
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

        guard calendar.isDate(plan.draft.scheduledAt, inSameDayAs: now) else {
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
}
