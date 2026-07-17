import Foundation

/// Immutable presentation data for the Living Day experience. The app layer gathers account-
/// scoped repository values once, builds this snapshot, and renders it without per-node reads.
public struct LivingDaySnapshot: Equatable, Sendable {
    public enum NutrientKind: String, CaseIterable, Hashable, Sendable {
        case calories
        case protein
        case carbs
        case fats
    }

    public struct NutrientBudget: Equatable, Sendable {
        public let kind: NutrientKind
        public let consumed: Double?
        public let planned: Double?
        public let target: Double?

        public init(kind: NutrientKind, consumed: Double?, planned: Double?, target: Double?) {
            self.kind = kind
            self.consumed = Self.usable(consumed)
            self.planned = Self.usable(planned)
            self.target = Self.positive(target)
        }

        public var isAvailable: Bool {
            consumed != nil && planned != nil && target != nil
        }

        public var remaining: Double? {
            guard let consumed, let planned, let target else { return nil }
            return target - consumed - planned
        }

        public var consumedFraction: Double? {
            guard let consumed, let target, target > 0 else { return nil }
            return max(0, consumed / target)
        }

        public var plannedFraction: Double? {
            guard let planned, let target, target > 0 else { return nil }
            return max(0, planned / target)
        }

        private static func usable(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }

        private static func positive(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
    }

    public struct Budget: Equatable, Sendable {
        public let calories: NutrientBudget
        public let protein: NutrientBudget
        public let carbs: NutrientBudget
        public let fats: NutrientBudget

        public init(
            calories: NutrientBudget,
            protein: NutrientBudget,
            carbs: NutrientBudget,
            fats: NutrientBudget
        ) {
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fats = fats
        }

        public var nutrients: [NutrientBudget] {
            [calories, protein, carbs, fats]
        }

        public var isFullyAvailable: Bool {
            nutrients.allSatisfy(\.isAvailable)
        }
    }

    public struct Nutrition: Equatable, Sendable {
        public let calories: Double
        public let protein: Double
        public let carbs: Double
        public let fats: Double

        public init(calories: Double, protein: Double, carbs: Double, fats: Double) {
            self.calories = Self.clean(calories)
            self.protein = Self.clean(protein)
            self.carbs = Self.clean(carbs)
            self.fats = Self.clean(fats)
        }

        private static func clean(_ value: Double) -> Double {
            value.isFinite ? max(0, value) : 0
        }
    }

    public enum EventKind: String, CaseIterable, Sendable {
        case meal
        case plannedMeal
        case strength
        case run
        case walk
        case recovery
        case activity
    }

    public enum EventState: String, CaseIterable, Sendable {
        case completed
        case planned
        case active
        case skipped
    }

    public enum TimingConfidence: String, Sendable {
        case exact
        case approximate
    }

    public enum Evidence: String, CaseIterable, Sendable {
        case excellent
        case supported
        case review
        case correction
        case unavailable
        case notApplicable
    }

    public enum Destination: Equatable, Sendable {
        case diary(mealID: String)
        case mealPlan
        case workouts
        case runs
        case trainingFuel
        case none
    }

    public struct Event: Equatable, Identifiable, Sendable {
        public let id: String
        public let kind: EventKind
        public let state: EventState
        public let title: String
        public let detail: String
        public let startDate: Date
        public let endDate: Date?
        public let timing: TimingConfidence
        public let evidence: Evidence
        public let nutrition: Nutrition?
        public let destination: Destination

        public init(
            id: String,
            kind: EventKind,
            state: EventState,
            title: String,
            detail: String,
            startDate: Date,
            endDate: Date? = nil,
            timing: TimingConfidence,
            evidence: Evidence,
            nutrition: Nutrition? = nil,
            destination: Destination
        ) {
            self.id = id
            self.kind = kind
            self.state = state
            self.title = title
            self.detail = detail
            self.startDate = startDate
            self.endDate = endDate
            self.timing = timing
            self.evidence = evidence
            self.nutrition = nutrition
            self.destination = destination
        }
    }

    public struct TrainingWindow: Equatable, Sendable {
        public let planID: String
        public let title: String
        public let sessionStart: Date
        public let sessionEnd: Date
        public let windowStart: Date
        public let windowEnd: Date
        public let status: TrainingFuelPlanProgress.Status

        public init(
            planID: String,
            title: String,
            sessionStart: Date,
            sessionEnd: Date,
            windowStart: Date,
            windowEnd: Date,
            status: TrainingFuelPlanProgress.Status
        ) {
            self.planID = planID
            self.title = title
            self.sessionStart = sessionStart
            self.sessionEnd = sessionEnd
            self.windowStart = windowStart
            self.windowEnd = windowEnd
            self.status = status
        }
    }

    public enum Freshness: Equatable, Sendable {
        case current(updatedAt: Date?)
        case stale(lastUpdated: Date)
        case unavailable
    }

    public struct PathWindow: Equatable, Sendable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = max(end, start.addingTimeInterval(60))
        }

        public func position(for date: Date) -> Double {
            let duration = end.timeIntervalSince(start)
            guard duration > 0 else { return 0 }
            return min(1, max(0, date.timeIntervalSince(start) / duration))
        }
    }

    public let date: Date
    public let generatedAt: Date
    public let pathWindow: PathWindow
    public let budget: Budget
    public let events: [Event]
    public let trainingWindow: TrainingWindow?
    public let nextAction: DailyNextAction
    public let freshness: Freshness
    public let currentTime: Date?

    public init(
        date: Date,
        generatedAt: Date,
        pathWindow: PathWindow,
        budget: Budget,
        events: [Event],
        trainingWindow: TrainingWindow?,
        nextAction: DailyNextAction,
        freshness: Freshness,
        currentTime: Date?
    ) {
        self.date = date
        self.generatedAt = generatedAt
        self.pathWindow = pathWindow
        self.budget = budget
        self.events = events.sorted {
            if $0.startDate == $1.startDate { return $0.id < $1.id }
            return $0.startDate < $1.startDate
        }
        self.trainingWindow = trainingWindow
        self.nextAction = nextAction
        self.freshness = freshness
        self.currentTime = currentTime
    }
}

public struct LivingDayActivityInput: Equatable, Sendable {
    public let id: String
    public let kind: LivingDaySnapshot.EventKind
    public let title: String
    public let detail: String
    public let startDate: Date
    public let endDate: Date?
    public let state: LivingDaySnapshot.EventState
    public let timing: LivingDaySnapshot.TimingConfidence
    public let destination: LivingDaySnapshot.Destination

    public init(
        id: String,
        kind: LivingDaySnapshot.EventKind,
        title: String,
        detail: String,
        startDate: Date,
        endDate: Date? = nil,
        state: LivingDaySnapshot.EventState,
        timing: LivingDaySnapshot.TimingConfidence = .exact,
        destination: LivingDaySnapshot.Destination
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.startDate = startDate
        self.endDate = endDate
        self.state = state
        self.timing = timing
        self.destination = destination
    }
}

public extension LivingDayActivityInput {
    init(exercise: LoggedExercise) {
        let normalizedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = normalizedName.isEmpty ? "Activity" : normalizedName
        let kind = Self.kind(for: title)
        let durationMinutes = max(0, exercise.durationMinutes ?? 0)
        let duration = TimeInterval(durationMinutes * 60)
        let isHealthKit = exercise.source.localizedCaseInsensitiveContains("healthkit")
        let startDate = isHealthKit ? exercise.date : exercise.date.addingTimeInterval(-duration)
        let endDate = duration > 0 ? startDate.addingTimeInterval(duration) : nil

        self.init(
            id: exercise.id,
            kind: kind,
            title: title,
            detail: Self.detail(
                durationMinutes: exercise.durationMinutes,
                calories: exercise.caloriesBurned
            ),
            startDate: startDate,
            endDate: endDate,
            state: .completed,
            timing: .exact,
            destination: kind == .run || kind == .walk ? .runs : .workouts
        )
    }

    private static func kind(for name: String) -> LivingDaySnapshot.EventKind {
        let value = name.lowercased()
        if value.contains("run") || value.contains("jog") { return .run }
        if value.contains("walk") || value.contains("hike") { return .walk }
        let strengthTerms = ["strength", "lift", "weight", "resistance", "barbell", "dumbbell"]
        if strengthTerms.contains(where: value.contains) { return .strength }
        return .activity
    }

    private static func detail(durationMinutes: Int?, calories: Double) -> String {
        var parts: [String] = []
        if let durationMinutes, durationMinutes > 0 {
            parts.append("\(durationMinutes) min")
        }
        if calories.isFinite, calories > 0 {
            parts.append("\(Int(calories.rounded())) active cal")
        }
        return parts.isEmpty ? "Completed activity" : parts.joined(separator: " · ")
    }
}

public enum LivingDaySnapshotBuilder {
    public static func make(
        date: Date,
        now: Date = Date(),
        dailyLog: DailyLog?,
        goals: TodayFuelPlanGoals,
        plannedMeals: [PlannedMeal] = [],
        activities: [LivingDayActivityInput] = [],
        trainingPlan: TrainingFuelConfirmedPlan? = nil,
        freshness: LivingDaySnapshot.Freshness = .current(updatedAt: nil),
        calendar: Calendar = .current
    ) -> LivingDaySnapshot {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let log = dailyLog.flatMap {
            calendar.isDate($0.date, inSameDayAs: dayStart) ? $0 : nil
        }

        let mealEvents = (log?.meals ?? []).enumerated().map { index, meal in
            event(for: meal, index: index, dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
        }
        var loggedPlanMatches = Dictionary(
            grouping: (log?.meals ?? []).flatMap { meal in
                meal.foodItems.map { planMatchKey(mealName: meal.name, foodID: $0.id) }
            },
            by: { $0 }
        ).mapValues(\.count)
        let remainingPlannedMeals = plannedMeals.filter { plannedMeal in
            guard let foodID = plannedMeal.foodItem?.id else { return true }
            let key = planMatchKey(mealName: plannedMeal.mealType, foodID: foodID)
            guard let count = loggedPlanMatches[key], count > 0 else { return true }
            loggedPlanMatches[key] = count - 1
            return false
        }
        let plannedEvents = remainingPlannedMeals.enumerated().map { index, meal in
            event(for: meal, index: index, dayStart: dayStart, calendar: calendar)
        }
        let activityEvents = activities
            .filter { activity in
                calendar.isDate(activity.startDate, inSameDayAs: dayStart) ||
                    activity.endDate.map { calendar.isDate($0, inSameDayAs: dayStart) } == true
            }
            .map { LivingDaySnapshot.Event($0) }

        let progress = trainingPlan.map {
            TrainingFuelPlanProgressRules.makeProgress(
                plan: $0,
                today: log,
                goals: goals,
                now: now,
                calendar: calendar
            )
        }
        let training = trainingPlan.flatMap { plan in
            trainingWindow(
                plan: plan,
                progress: progress,
                selectedDay: dayStart,
                calendar: calendar
            )
        }
        let trainingPlanEvent = trainingPlan.flatMap { plan in
            Self.trainingEvent(
                plan: plan,
                progress: progress,
                selectedDay: dayStart,
                now: now,
                calendar: calendar
            )
        }

        let uniqueTrainingEvent = trainingPlanEvent.flatMap { candidate in
            activityEvents.contains(where: { representsSameSession($0, candidate) }) ? nil : candidate
        }
        let events = mealEvents + plannedEvents + activityEvents + [uniqueTrainingEvent].compactMap { $0 }
        let consumed = nutrition(for: log)
        let planned = nutrition(for: remainingPlannedMeals)
        let budget = makeBudget(consumed: consumed, planned: planned, goals: goals)
        let nextAction = reconcile(
            action: DailyNextActionRules.makeAction(
                plan: trainingPlan,
                today: log,
                goals: goals,
                now: now,
                calendar: calendar
            ),
            with: budget
        )
        let currentTime = calendar.isDate(now, inSameDayAs: dayStart) ? now : nil
        let pathWindow = makePathWindow(
            dayStart: dayStart,
            dayEnd: dayEnd,
            events: events,
            trainingWindow: training,
            currentTime: currentTime,
            calendar: calendar
        )

        return LivingDaySnapshot(
            date: dayStart,
            generatedAt: now,
            pathWindow: pathWindow,
            budget: budget,
            events: events,
            trainingWindow: training,
            nextAction: nextAction,
            freshness: freshness,
            currentTime: currentTime
        )
    }

    private struct Totals {
        let calories: Double?
        let protein: Double?
        let carbs: Double?
        let fats: Double?
    }

    private static func nutrition(for log: DailyLog?) -> Totals {
        guard let log else {
            return Totals(calories: 0, protein: 0, carbs: 0, fats: 0)
        }
        let macros = log.totalMacros()
        let values = [log.totalCalories(), macros.protein, macros.carbs, macros.fats]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return Totals(calories: nil, protein: nil, carbs: nil, fats: nil)
        }
        return Totals(
            calories: values[0],
            protein: values[1],
            carbs: values[2],
            fats: values[3]
        )
    }

    private static func nutrition(for meals: [PlannedMeal]) -> Totals {
        let foods = meals.compactMap(\.foodItem)
        let values = foods.flatMap { [$0.calories, $0.protein, $0.carbs, $0.fats] }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return Totals(calories: nil, protein: nil, carbs: nil, fats: nil)
        }
        return Totals(
            calories: foods.reduce(0) { $0 + $1.calories },
            protein: foods.reduce(0) { $0 + $1.protein },
            carbs: foods.reduce(0) { $0 + $1.carbs },
            fats: foods.reduce(0) { $0 + $1.fats }
        )
    }

    private static func makeBudget(
        consumed: Totals,
        planned: Totals,
        goals: TodayFuelPlanGoals
    ) -> LivingDaySnapshot.Budget {
        LivingDaySnapshot.Budget(
            calories: .init(kind: .calories, consumed: consumed.calories, planned: planned.calories, target: goals.calories),
            protein: .init(kind: .protein, consumed: consumed.protein, planned: planned.protein, target: goals.protein),
            carbs: .init(kind: .carbs, consumed: consumed.carbs, planned: planned.carbs, target: goals.carbs),
            fats: .init(kind: .fats, consumed: consumed.fats, planned: planned.fats, target: goals.fats)
        )
    }

    private static func reconcile(
        action: DailyNextAction,
        with budget: LivingDaySnapshot.Budget
    ) -> DailyNextAction {
        guard action.kind == .proteinCatchUp,
              let caloriesRemaining = budget.calories.remaining,
              let proteinRemaining = budget.protein.remaining else { return action }

        if caloriesRemaining < Double(DailyNextActionRules.proteinCatchUpMinimumCalories) {
            return DailyNextAction(
                kind: .steadyDay,
                title: "Review Today's Plan",
                detail: "Planned meals use today's calorie budget",
                deepLink: "myfitplate://meal-plan"
            )
        }

        let adjustedProtein = Int(max(0, proteinRemaining).rounded())
        if adjustedProtein < DailyNextActionRules.proteinCatchUpMinimumGrams {
            return DailyNextAction(
                kind: .steadyDay,
                title: "Your Plan Covers Protein",
                detail: "No extra protein needed right now",
                deepLink: "myfitplate://meal-plan"
            )
        }

        return DailyNextAction(
            kind: .proteinCatchUp,
            title: action.title,
            detail: "\(adjustedProtein) g protein left today",
            deepLink: action.deepLink,
            proteinGrams: adjustedProtein
        )
    }

    private static func event(
        for meal: Meal,
        index: Int,
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> LivingDaySnapshot.Event {
        let validTimes = meal.foodItems.compactMap(\.timestamp).filter { $0 >= dayStart && $0 < dayEnd }
        let hasExactTiming = !validTimes.isEmpty && validTimes.count == meal.foodItems.count
        let start = validTimes.min() ?? approximateTime(
            mealName: meal.name,
            index: index,
            dayStart: dayStart,
            calendar: calendar
        )
        let nutrition = nutrition(for: meal.foodItems)
        let itemCount = meal.foodItems.count
        let detail = "\(itemCount) \(itemCount == 1 ? "item" : "items"), \(Int(nutrition.calories.rounded())) cal"

        return LivingDaySnapshot.Event(
            id: "meal:\(meal.id.uuidString)",
            kind: .meal,
            state: .completed,
            title: meal.name.isEmpty ? "Meal" : meal.name,
            detail: detail,
            startDate: start,
            timing: hasExactTiming ? .exact : .approximate,
            evidence: evidence(for: meal.foodItems),
            nutrition: nutrition,
            destination: .diary(mealID: meal.id.uuidString)
        )
    }

    private static func event(
        for meal: PlannedMeal,
        index: Int,
        dayStart: Date,
        calendar: Calendar
    ) -> LivingDaySnapshot.Event {
        let food = meal.foodItem
        let title = food?.name ?? meal.mealType
        let detail = food.map { "\(Int($0.calories.rounded())) cal planned" } ?? "Planned meal"
        return LivingDaySnapshot.Event(
            id: "planned:\(meal.id)",
            kind: .plannedMeal,
            state: .planned,
            title: title.isEmpty ? "Planned meal" : title,
            detail: detail,
            startDate: approximateTime(
                mealName: meal.mealType,
                index: index,
                dayStart: dayStart,
                calendar: calendar
            ),
            timing: .approximate,
            evidence: food.map { evidence(for: [$0]) } ?? .notApplicable,
            nutrition: food.map { nutrition(for: [$0]) },
            destination: .mealPlan
        )
    }

    private static func nutrition(for foods: [FoodItem]) -> LivingDaySnapshot.Nutrition {
        LivingDaySnapshot.Nutrition(
            calories: foods.reduce(0) { $0 + $1.calories },
            protein: foods.reduce(0) { $0 + $1.protein },
            carbs: foods.reduce(0) { $0 + $1.carbs },
            fats: foods.reduce(0) { $0 + $1.fats }
        )
    }

    private static func evidence(for foods: [FoodItem]) -> LivingDaySnapshot.Evidence {
        guard !foods.isEmpty else { return .unavailable }
        let evaluations = foods.map { food in
            let metadata = food.sourceMetadata
            let descriptor = FoodSourceClassifier.descriptor(
                for: metadata?.sourceName ?? "",
                foodID: food.id,
                metadata: metadata
            )
            return FoodTrustEvaluation.evaluate(item: food, descriptor: descriptor, metadata: metadata)
        }

        if evaluations.contains(where: \.requiresCorrection) { return .correction }
        if evaluations.contains(where: { $0.level == .low || $0.level == .review }) { return .review }
        if evaluations.allSatisfy({ $0.level == .excellent }) { return .excellent }
        return .supported
    }

    private static func approximateTime(
        mealName: String,
        index: Int,
        dayStart: Date,
        calendar: Calendar
    ) -> Date {
        let normalized = mealName.lowercased()
        let hour: Int
        let minute: Int
        if normalized.contains("breakfast") {
            hour = 8; minute = 0
        } else if normalized.contains("lunch") {
            hour = 12; minute = 30
        } else if normalized.contains("dinner") || normalized.contains("supper") {
            hour = 18; minute = 30
        } else if normalized.contains("snack") {
            hour = index < 2 ? 10 : 15; minute = 30
        } else {
            hour = min(21, 9 + index * 3); minute = 0
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? dayStart
    }

    private static func trainingWindow(
        plan: TrainingFuelConfirmedPlan,
        progress: TrainingFuelPlanProgress?,
        selectedDay: Date,
        calendar: Calendar
    ) -> LivingDaySnapshot.TrainingWindow? {
        let sessionStart = plan.outcome?.actualStartAt ?? plan.draft.scheduledAt
        guard calendar.isDate(sessionStart, inSameDayAs: selectedDay) else { return nil }
        let sessionEnd = plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        let preAllocation = plan.allocations.first { $0.phase == .beforeTraining }
        let postAllocation = plan.allocations.first { $0.phase == .afterTraining }
        let preSeconds: TimeInterval
        switch preAllocation?.timing {
        case .within30Minutes: preSeconds = 30 * 60
        case .thirtyTo120Minutes: preSeconds = 120 * 60
        case .overTwoHours: preSeconds = 180 * 60
        case .afterSession, .none: preSeconds = 0
        }
        let postSeconds: TimeInterval = postAllocation == nil ? 0 : 120 * 60
        return LivingDaySnapshot.TrainingWindow(
            planID: plan.id,
            title: plan.draft.sessionTitle,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            windowStart: sessionStart.addingTimeInterval(-preSeconds),
            windowEnd: sessionEnd.addingTimeInterval(postSeconds),
            status: progress?.status ?? .stale
        )
    }

    private static func trainingEvent(
        plan: TrainingFuelConfirmedPlan,
        progress: TrainingFuelPlanProgress?,
        selectedDay: Date,
        now: Date,
        calendar: Calendar
    ) -> LivingDaySnapshot.Event? {
        let start = plan.outcome?.actualStartAt ?? plan.draft.scheduledAt
        guard calendar.isDate(start, inSameDayAs: selectedDay) else { return nil }
        let end = plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        let state: LivingDaySnapshot.EventState
        if plan.outcome?.status == .skipped {
            state = .skipped
        } else if now >= start && now < end {
            state = .active
        } else if now >= end || plan.outcome?.status == .completed {
            state = .completed
        } else {
            state = .planned
        }
        let kind: LivingDaySnapshot.EventKind = plan.draft.kind == .strength ? .strength : .run
        let detail = progress.map { progressDetail(for: $0.status) } ?? "Training plan"
        return LivingDaySnapshot.Event(
            id: "training:\(plan.id)",
            kind: kind,
            state: state,
            title: plan.draft.sessionTitle,
            detail: detail,
            startDate: start,
            endDate: end,
            timing: .exact,
            evidence: .notApplicable,
            destination: .trainingFuel
        )
    }

    private static func progressDetail(for status: TrainingFuelPlanProgress.Status) -> String {
        switch status {
        case .upcoming: return "Fuel window open"
        case .inSession: return "Training in progress"
        case .awaitingOutcome: return "Confirm session outcome"
        case .awaitingRecoveryData: return "Refreshing recovery data"
        case .recovery: return "Recovery window open"
        case .complete: return "Fuel plan complete"
        case .skipped: return "Session skipped"
        case .stale: return "Plan needs review"
        case .overTarget: return "Review daily targets"
        case .invalidDiary, .invalidTargets: return "Data unavailable"
        case .budgetUsedElsewhere: return "Daily budget used elsewhere"
        }
    }

    private static func representsSameSession(
        _ first: LivingDaySnapshot.Event,
        _ second: LivingDaySnapshot.Event
    ) -> Bool {
        guard first.kind == second.kind else { return false }
        let buffer: TimeInterval = 15 * 60
        let firstEnd = first.endDate ?? first.startDate
        let secondEnd = second.endDate ?? second.startDate
        return first.startDate <= secondEnd.addingTimeInterval(buffer) &&
            second.startDate <= firstEnd.addingTimeInterval(buffer)
    }

    private static func planMatchKey(mealName: String, foodID: String) -> String {
        let normalizedMeal = mealName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedMeal):\(foodID)"
    }

    private static func makePathWindow(
        dayStart: Date,
        dayEnd: Date,
        events: [LivingDaySnapshot.Event],
        trainingWindow: LivingDaySnapshot.TrainingWindow?,
        currentTime: Date?,
        calendar: Calendar
    ) -> LivingDaySnapshot.PathWindow {
        let defaultStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: dayStart) ?? dayStart
        let defaultEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(22 * 60 * 60)
        let starts = events.map(\.startDate) + [trainingWindow?.windowStart, currentTime].compactMap { $0 }
        let ends = events.map { $0.endDate ?? $0.startDate } + [trainingWindow?.windowEnd, currentTime].compactMap { $0 }
        let earliest = starts.min().map { $0.addingTimeInterval(-60 * 60) } ?? defaultStart
        let latest = ends.max().map { $0.addingTimeInterval(60 * 60) } ?? defaultEnd
        let start = max(dayStart, min(defaultStart, earliest))
        let end = min(dayEnd, max(defaultEnd, latest))
        return LivingDaySnapshot.PathWindow(start: start, end: end)
    }
}

private extension LivingDaySnapshot.Event {
    init(_ input: LivingDayActivityInput) {
        self.init(
            id: "activity:\(input.id)",
            kind: input.kind,
            state: input.state,
            title: input.title,
            detail: input.detail,
            startDate: input.startDate,
            endDate: input.endDate,
            timing: input.timing,
            evidence: .notApplicable,
            destination: input.destination
        )
    }
}
