import Foundation

public struct TrainingFuelSession: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case strength
        case run
    }

    public enum Intensity: String, Equatable, Sendable {
        case easy
        case moderate
        case hard
    }

    public enum StrengthFocus: String, Equatable, Sendable {
        case upperBody = "upper_body"
        case lowerBody = "lower_body"
        case fullBody = "full_body"
        case mixed
        case unknown
    }

    public let kind: Kind
    public let scheduledAt: Date?
    public let expectedDurationMinutes: Int?
    public let intensity: Intensity?
    public let strengthFocus: StrengthFocus

    public init(
        kind: Kind,
        scheduledAt: Date?,
        expectedDurationMinutes: Int?,
        intensity: Intensity?,
        strengthFocus: StrengthFocus = .unknown
    ) {
        self.kind = kind
        self.scheduledAt = scheduledAt
        self.expectedDurationMinutes = expectedDurationMinutes
        self.intensity = intensity
        self.strengthFocus = strengthFocus
    }
}

public struct TrainingFuelPreference: Equatable, Sendable {
    public let wantsPreSessionFuel: Bool
    public let wantsPostSessionFuel: Bool

    public init(wantsPreSessionFuel: Bool = true, wantsPostSessionFuel: Bool = true) {
        self.wantsPreSessionFuel = wantsPreSessionFuel
        self.wantsPostSessionFuel = wantsPostSessionFuel
    }
}

public struct TrainingFuelAllocation: Equatable, Sendable {
    static let maximumSupportedMacroGrams = 100_000

    public enum Phase: String, Equatable, Sendable {
        case beforeTraining = "before_training"
        case afterTraining = "after_training"
    }

    public enum Timing: String, Equatable, Sendable {
        case within30Minutes = "within_30_minutes"
        case thirtyTo120Minutes = "30_to_120_minutes"
        case overTwoHours = "over_two_hours"
        case afterSession = "after_session"
    }

    public let phase: Phase
    public let timing: Timing
    public let proteinGrams: Int
    public let carbGrams: Int

    public init(phase: Phase, timing: Timing, proteinGrams: Int, carbGrams: Int) {
        self.phase = phase
        self.timing = timing
        self.proteinGrams = min(Self.maximumSupportedMacroGrams, max(0, proteinGrams))
        self.carbGrams = min(Self.maximumSupportedMacroGrams, max(0, carbGrams))
    }

    public var calories: Int {
        (proteinGrams + carbGrams) * 4
    }
}

public struct TrainingFuelPlannerPlan: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case ready
        case needsSessionTime = "needs_session_time"
        case noFuelRequested = "no_fuel_requested"
        case outsideToday = "outside_today"
        case staleSession = "stale_session"
        case overTargetReview = "over_target_review"
        case insufficientBudget = "insufficient_budget"
        case invalidDiaryData = "invalid_diary_data"
        case invalidCalorieTarget = "invalid_calorie_target"
    }

    public enum Note: String, Equatable, Sendable {
        case durationDefaulted = "duration_defaulted"
        case durationClamped = "duration_clamped"
        case intensityDefaulted = "intensity_defaulted"
        case invalidGoalValueIgnored = "invalid_goal_value_ignored"
        case invalidLoggedValue = "invalid_logged_value"
        case nonTodayLogIgnored = "non_today_log_ignored"
        case sessionStartGrace = "session_start_grace"
        case postSessionFallsNextDay = "post_session_falls_next_day"
        case calorieBudgetLimited = "calorie_budget_limited"
        case proteinBudgetLimited = "protein_budget_limited"
        case carbBudgetLimited = "carb_budget_limited"
    }

    public let status: Status
    public let normalizedDurationMinutes: Int
    public let normalizedIntensity: TrainingFuelSession.Intensity
    public let minutesUntilSession: Int?
    public let remainingCalories: Int
    public let remainingProteinGrams: Int
    public let remainingCarbGrams: Int
    public let allocations: [TrainingFuelAllocation]
    public let notes: [Note]

    public init(
        status: Status,
        normalizedDurationMinutes: Int,
        normalizedIntensity: TrainingFuelSession.Intensity,
        minutesUntilSession: Int?,
        remainingCalories: Int,
        remainingProteinGrams: Int,
        remainingCarbGrams: Int,
        allocations: [TrainingFuelAllocation],
        notes: [Note]
    ) {
        self.status = status
        self.normalizedDurationMinutes = normalizedDurationMinutes
        self.normalizedIntensity = normalizedIntensity
        self.minutesUntilSession = minutesUntilSession
        self.remainingCalories = remainingCalories
        self.remainingProteinGrams = remainingProteinGrams
        self.remainingCarbGrams = remainingCarbGrams
        self.allocations = allocations
        self.notes = notes
    }

    public var allocatedCalories: Int {
        allocations.reduce(0) { $0 + $1.calories }
    }

    public var allocatedProteinGrams: Int {
        allocations.reduce(0) { $0 + $1.proteinGrams }
    }

    public var allocatedCarbGrams: Int {
        allocations.reduce(0) { $0 + $1.carbGrams }
    }

    public func allocation(for phase: TrainingFuelAllocation.Phase) -> TrainingFuelAllocation? {
        allocations.first { $0.phase == phase }
    }

    public var staysInsideDailyTargets: Bool {
        allocatedCalories <= max(0, remainingCalories) &&
            allocatedProteinGrams <= remainingProteinGrams &&
            allocatedCarbGrams <= remainingCarbGrams
    }
}

public enum TrainingFuelPlannerRules {
    private static let defaultDurationMinutes = 45
    private static let minimumDurationMinutes = 15
    private static let maximumDurationMinutes = 240
    private static let sessionStartGraceMinutes = 15
    private static let minimumActionCalories = 60
    private static let minimumMacroGrams = 10
    private static let maximumSupportedCalories = 1_000_000.0
    private static let maximumSupportedMacroGrams = Double(
        TrainingFuelAllocation.maximumSupportedMacroGrams
    )

    public static func makePlan(
        session: TrainingFuelSession,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        preference: TrainingFuelPreference = TrainingFuelPreference(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingFuelPlannerPlan {
        var notes: [TrainingFuelPlannerPlan.Note] = []
        let duration = normalizedDuration(session.expectedDurationMinutes, notes: &notes)
        let intensity = normalizedIntensity(session.intensity, notes: &notes)

        guard goals.calories.isFinite,
              goals.calories > 0,
              goals.calories <= maximumSupportedCalories else {
            return emptyPlan(
                status: .invalidCalorieTarget,
                duration: duration,
                intensity: intensity,
                notes: notes
            )
        }

        let currentLog: DailyLog?
        if let today, !calendar.isDate(today.date, inSameDayAs: now) {
            currentLog = nil
            appendUnique(.nonTodayLogIgnored, to: &notes)
        } else {
            currentLog = today
        }

        let caloriesLogged = validatedLoggedValue(
            currentLog?.totalCalories() ?? 0,
            upperBound: maximumSupportedCalories,
            notes: &notes
        )
        let loggedMacros = currentLog?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        let proteinLogged = validatedLoggedValue(
            loggedMacros.protein,
            upperBound: maximumSupportedMacroGrams,
            notes: &notes
        )
        let carbsLogged = validatedLoggedValue(
            loggedMacros.carbs,
            upperBound: maximumSupportedMacroGrams,
            notes: &notes
        )
        guard let caloriesLogged, let proteinLogged, let carbsLogged else {
            return emptyPlan(
                status: .invalidDiaryData,
                duration: duration,
                intensity: intensity,
                notes: notes
            )
        }
        let proteinGoal = sanitizedGoalValue(
            goals.protein,
            upperBound: maximumSupportedMacroGrams,
            notes: &notes
        )
        let carbGoal = sanitizedGoalValue(
            goals.carbs,
            upperBound: maximumSupportedMacroGrams,
            notes: &notes
        )

        let rawRemainingCalories = goals.calories - caloriesLogged
        let remainingCalories = Int(floor(rawRemainingCalories))
        let remainingProtein = Int(floor(max(0, proteinGoal - proteinLogged)))
        let remainingCarbs = Int(floor(max(0, carbGoal - carbsLogged)))

        guard rawRemainingCalories > 0 else {
            return plan(
                status: .overTargetReview,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: nil,
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        guard preference.wantsPreSessionFuel || preference.wantsPostSessionFuel else {
            return plan(
                status: .noFuelRequested,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: nil,
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        guard let scheduledAt = session.scheduledAt else {
            return plan(
                status: .needsSessionTime,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: nil,
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        let secondsUntilSession = scheduledAt.timeIntervalSince(now)
        if secondsUntilSession < -Double(sessionStartGraceMinutes * 60) {
            return plan(
                status: .staleSession,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: Int(floor(secondsUntilSession / 60)),
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        guard calendar.isDate(scheduledAt, inSameDayAs: now) else {
            return plan(
                status: .outsideToday,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: Int(floor(secondsUntilSession / 60)),
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        let minutesUntilSession: Int
        if secondsUntilSession < 0 {
            appendUnique(.sessionStartGrace, to: &notes)
            minutesUntilSession = 0
        } else {
            minutesUntilSession = Int(floor(secondsUntilSession / 60))
        }

        let includePreSession = preference.wantsPreSessionFuel
        var includePostSession = preference.wantsPostSessionFuel
        let estimatedEnd = scheduledAt.addingTimeInterval(Double(duration * 60))
        if !calendar.isDate(estimatedEnd, inSameDayAs: scheduledAt) {
            includePostSession = false
            appendUnique(.postSessionFallsNextDay, to: &notes)
        }

        if !includePreSession && !includePostSession {
            return plan(
                status: .outsideToday,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: minutesUntilSession,
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        guard remainingCalories >= minimumActionCalories else {
            return plan(
                status: .insufficientBudget,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: minutesUntilSession,
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        let demand = desiredDemand(
            for: session,
            duration: duration,
            intensity: intensity
        )
        var slots = desiredSlots(
            demand: demand,
            includePreSession: includePreSession,
            includePostSession: includePostSession,
            minutesUntilSession: minutesUntilSession
        )
        constrain(
            slots: &slots,
            remainingCalories: Double(remainingCalories),
            remainingProtein: Double(remainingProtein),
            remainingCarbs: Double(remainingCarbs),
            notes: &notes
        )

        let allocations = slots.compactMap { slot -> TrainingFuelAllocation? in
            var protein = Int(floor(slot.proteinGrams))
            var carbs = Int(floor(slot.carbGrams))
            if protein < minimumMacroGrams { protein = 0 }
            if carbs < minimumMacroGrams { carbs = 0 }
            guard (protein + carbs) * 4 >= minimumActionCalories else { return nil }
            return TrainingFuelAllocation(
                phase: slot.phase,
                timing: slot.timing,
                proteinGrams: protein,
                carbGrams: carbs
            )
        }

        guard !allocations.isEmpty else {
            return plan(
                status: .insufficientBudget,
                duration: duration,
                intensity: intensity,
                minutesUntilSession: minutesUntilSession,
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                notes: notes
            )
        }

        return plan(
            status: .ready,
            duration: duration,
            intensity: intensity,
            minutesUntilSession: minutesUntilSession,
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein,
            remainingCarbs: remainingCarbs,
            allocations: allocations,
            notes: notes
        )
    }

    private struct Demand {
        let proteinGrams: Double
        let carbGrams: Double
    }

    private struct DesiredSlot {
        let phase: TrainingFuelAllocation.Phase
        let timing: TrainingFuelAllocation.Timing
        var proteinGrams: Double
        var carbGrams: Double
    }

    private static func desiredDemand(
        for session: TrainingFuelSession,
        duration: Int,
        intensity: TrainingFuelSession.Intensity
    ) -> Demand {
        let intensityFactor: Double
        switch intensity {
        case .easy: intensityFactor = 0.75
        case .moderate: intensityFactor = 1
        case .hard: intensityFactor = 1.25
        }

        switch session.kind {
        case .strength:
            let durationFactor = min(2, max(0.5, Double(duration) / 60))
            var carbs = 35 * durationFactor * intensityFactor
            if session.strengthFocus == .lowerBody || session.strengthFocus == .fullBody {
                switch intensity {
                case .easy: break
                case .moderate: carbs += 8
                case .hard: carbs += 15
                }
            }
            let protein: Double
            switch intensity {
            case .easy: protein = 20
            case .moderate: protein = 25
            case .hard: protein = 30
            }
            return Demand(
                proteinGrams: protein,
                carbGrams: min(110, max(20, carbs))
            )
        case .run:
            let durationFactor = min(3, max(0.5, Double(duration) / 60))
            let carbs = min(160, max(20, 45 * durationFactor * intensityFactor))
            let protein = duration >= 75 ? 25.0 : 20.0
            return Demand(proteinGrams: protein, carbGrams: carbs)
        }
    }

    private static func desiredSlots(
        demand: Demand,
        includePreSession: Bool,
        includePostSession: Bool,
        minutesUntilSession: Int
    ) -> [DesiredSlot] {
        let preCarbShare: Double
        switch (includePreSession, includePostSession) {
        case (true, true): preCarbShare = 0.55
        case (true, false): preCarbShare = 1
        case (false, true), (false, false): preCarbShare = 0
        }

        var preCarbs = demand.carbGrams * preCarbShare
        var postCarbs = demand.carbGrams - preCarbs
        if includePreSession {
            let preCarbCap: Double?
            if minutesUntilSession <= 30 {
                preCarbCap = 25
            } else if minutesUntilSession <= 60 {
                preCarbCap = 35
            } else {
                preCarbCap = nil
            }
            if let preCarbCap, preCarbs > preCarbCap {
                let overflow = preCarbs - preCarbCap
                preCarbs = preCarbCap
                if includePostSession { postCarbs += overflow }
            }
        }

        let preProtein: Double
        let postProtein: Double
        switch (includePreSession, includePostSession) {
        case (true, true):
            preProtein = minutesUntilSession >= 60 ? min(10, demand.proteinGrams) : 0
            postProtein = demand.proteinGrams - preProtein
        case (true, false):
            preProtein = minutesUntilSession >= 30 ? demand.proteinGrams : 0
            postProtein = 0
        case (false, true):
            preProtein = 0
            postProtein = demand.proteinGrams
        case (false, false):
            preProtein = 0
            postProtein = 0
        }

        var slots: [DesiredSlot] = []
        if includePreSession {
            slots.append(DesiredSlot(
                phase: .beforeTraining,
                timing: preSessionTiming(minutesUntilSession: minutesUntilSession),
                proteinGrams: preProtein,
                carbGrams: preCarbs
            ))
        }
        if includePostSession {
            slots.append(DesiredSlot(
                phase: .afterTraining,
                timing: .afterSession,
                proteinGrams: postProtein,
                carbGrams: postCarbs
            ))
        }
        return slots
    }

    private static func constrain(
        slots: inout [DesiredSlot],
        remainingCalories: Double,
        remainingProtein: Double,
        remainingCarbs: Double,
        notes: inout [TrainingFuelPlannerPlan.Note]
    ) {
        let desiredProtein = slots.reduce(0) { $0 + $1.proteinGrams }
        if desiredProtein > remainingProtein, desiredProtein > 0 {
            let scale = remainingProtein / desiredProtein
            for index in slots.indices { slots[index].proteinGrams *= scale }
            appendUnique(.proteinBudgetLimited, to: &notes)
        }

        let desiredCarbs = slots.reduce(0) { $0 + $1.carbGrams }
        if desiredCarbs > remainingCarbs, desiredCarbs > 0 {
            let scale = remainingCarbs / desiredCarbs
            for index in slots.indices { slots[index].carbGrams *= scale }
            appendUnique(.carbBudgetLimited, to: &notes)
        }

        let desiredCalories = slots.reduce(0) {
            $0 + ($1.proteinGrams + $1.carbGrams) * 4
        }
        if desiredCalories > remainingCalories, desiredCalories > 0 {
            let scale = remainingCalories / desiredCalories
            for index in slots.indices {
                slots[index].proteinGrams *= scale
                slots[index].carbGrams *= scale
            }
            appendUnique(.calorieBudgetLimited, to: &notes)
        }
    }

    private static func normalizedDuration(
        _ requested: Int?,
        notes: inout [TrainingFuelPlannerPlan.Note]
    ) -> Int {
        guard let requested else {
            appendUnique(.durationDefaulted, to: &notes)
            return defaultDurationMinutes
        }
        let clamped = min(maximumDurationMinutes, max(minimumDurationMinutes, requested))
        if clamped != requested { appendUnique(.durationClamped, to: &notes) }
        return clamped
    }

    private static func normalizedIntensity(
        _ requested: TrainingFuelSession.Intensity?,
        notes: inout [TrainingFuelPlannerPlan.Note]
    ) -> TrainingFuelSession.Intensity {
        guard let requested else {
            appendUnique(.intensityDefaulted, to: &notes)
            return .moderate
        }
        return requested
    }

    private static func validatedLoggedValue(
        _ value: Double,
        upperBound: Double,
        notes: inout [TrainingFuelPlannerPlan.Note]
    ) -> Double? {
        guard value.isFinite, value >= 0, value <= upperBound else {
            appendUnique(.invalidLoggedValue, to: &notes)
            return nil
        }
        return value
    }

    private static func sanitizedGoalValue(
        _ value: Double,
        upperBound: Double,
        notes: inout [TrainingFuelPlannerPlan.Note]
    ) -> Double {
        guard value.isFinite, value >= 0, value <= upperBound else {
            appendUnique(.invalidGoalValueIgnored, to: &notes)
            return 0
        }
        return value
    }

    private static func preSessionTiming(minutesUntilSession: Int) -> TrainingFuelAllocation.Timing {
        if minutesUntilSession <= 30 { return .within30Minutes }
        if minutesUntilSession <= 120 { return .thirtyTo120Minutes }
        return .overTwoHours
    }

    private static func appendUnique(
        _ note: TrainingFuelPlannerPlan.Note,
        to notes: inout [TrainingFuelPlannerPlan.Note]
    ) {
        if !notes.contains(note) { notes.append(note) }
    }

    private static func emptyPlan(
        status: TrainingFuelPlannerPlan.Status,
        duration: Int,
        intensity: TrainingFuelSession.Intensity,
        notes: [TrainingFuelPlannerPlan.Note]
    ) -> TrainingFuelPlannerPlan {
        plan(
            status: status,
            duration: duration,
            intensity: intensity,
            minutesUntilSession: nil,
            remainingCalories: 0,
            remainingProtein: 0,
            remainingCarbs: 0,
            notes: notes
        )
    }

    private static func plan(
        status: TrainingFuelPlannerPlan.Status,
        duration: Int,
        intensity: TrainingFuelSession.Intensity,
        minutesUntilSession: Int?,
        remainingCalories: Int,
        remainingProtein: Int,
        remainingCarbs: Int,
        allocations: [TrainingFuelAllocation] = [],
        notes: [TrainingFuelPlannerPlan.Note]
    ) -> TrainingFuelPlannerPlan {
        TrainingFuelPlannerPlan(
            status: status,
            normalizedDurationMinutes: duration,
            normalizedIntensity: intensity,
            minutesUntilSession: minutesUntilSession,
            remainingCalories: remainingCalories,
            remainingProteinGrams: remainingProtein,
            remainingCarbGrams: remainingCarbs,
            allocations: allocations,
            notes: notes
        )
    }
}
