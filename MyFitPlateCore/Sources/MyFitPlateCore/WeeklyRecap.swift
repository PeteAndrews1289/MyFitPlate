import Foundation

public struct WeeklyRecapProgress: Equatable {
    public let completed: Int
    public let eligible: Int

    public init(completed: Int, eligible: Int) {
        self.completed = max(0, min(completed, eligible))
        self.eligible = max(0, eligible)
    }

    public var fraction: Double? {
        guard eligible > 0 else { return nil }
        return Double(completed) / Double(eligible)
    }
}

public struct WeeklyRecapShoeContext: Equatable {
    public let name: String
    public let weeklyMeters: Double
    public let totalMeters: Double
    public let wearFraction: Double
    public let isWornOut: Bool

    public init(
        name: String,
        weeklyMeters: Double,
        totalMeters: Double,
        wearFraction: Double,
        isWornOut: Bool
    ) {
        self.name = name
        self.weeklyMeters = weeklyMeters
        self.totalMeters = totalMeters
        self.wearFraction = wearFraction
        self.isWornOut = isWornOut
    }
}

public struct WeeklyRecapStory: Equatable {
    public let headline: String
    public let training: String
    public let fueling: String
    public let change: String

    public init(headline: String, training: String, fueling: String, change: String) {
        self.headline = headline
        self.training = training
        self.fueling = fueling
        self.change = change
    }
}

/// One week of nutrition and training, computed from data the app already stores. Every
/// rate carries its denominator so missing data stays visibly missing instead of becoming
/// an invented failure or an opaque composite score.
public struct WeeklyRecap: Equatable {
    public let weekStart: Date
    public let weekEnd: Date

    /// Days in the window with at least one food item logged.
    public let daysLogged: Int
    /// Average intake over logged days only (nil when nothing was logged).
    public let averageCalories: Double?
    public let averageProtein: Double?
    public let calorieGoal: Double?
    public let proteinGoal: Double?
    public let calorieAdherence: WeeklyRecapProgress
    public let proteinAdherence: WeeklyRecapProgress
    public let trustReview: WeeklyRecapProgress

    /// Distinct days containing a strength session or run.
    public let trainingDays: Int
    /// Training days with at least one food item in the diary.
    public let trainingDaysLogged: Int

    public let workoutsCompleted: Int
    public let workingSetCount: Int
    /// Total weight moved across working sets only (lbs x reps).
    public let totalVolume: Double
    /// Exercises where this week's best estimated 1RM beat everything before the week.
    public let personalRecords: Int
    public let averageEffortRPE: Double?
    public let priorAverageEffortRPE: Double?
    public let demandingStrengthDays: Int
    public let demandingStrengthDaysLogged: Int
    /// Days that logged both calorie and protein consistency among all demanding days.
    public let demandingStrengthFuelAdherence: WeeklyRecapProgress

    /// Runs in the window, recorded in-app or imported from any watch.
    public let runCount: Int
    public let runMeters: Double
    public let priorRunMeters: Double
    public let runMovingSeconds: Double
    public let averageRunPaceSecondsPerKm: Double?
    public let runRecordCount: Int
    public let paceRecordCount: Int
    public let routeRunCount: Int
    public let outdoorRunCount: Int
    /// Aggregated seconds in Z1...Z5. Nil means no real HR series was available.
    public let heartRateZoneSeconds: [Double]?
    public let guidedRunCount: Int
    public let guidedCompletedSteps: Int
    public let guidedRecordedSteps: Int
    public let recoveryFuelLoggedRuns: Int
    /// Runs whose recovery window is still open and therefore cannot be scored yet.
    public let recoveryFuelPendingRuns: Int
    public let recoveryFuelAdherence: WeeklyRecapProgress
    public let shoeContext: WeeklyRecapShoeContext?

    /// Raw change retained for compatibility with the original recap.
    public let weightChange: Double?
    /// EMA-smoothed change (alpha 0.4), used by the report UI.
    public let smoothedWeightChange: Double?

    public let story: WeeklyRecapStory

    public var hasAnyActivity: Bool {
        daysLogged > 0 || workoutsCompleted > 0 || runCount > 0
    }

    public var effortChange: Double? {
        guard let averageEffortRPE, let priorAverageEffortRPE else { return nil }
        return averageEffortRPE - priorAverageEffortRPE
    }

    public var runDistanceChangeFraction: Double? {
        guard priorRunMeters > 0 else { return nil }
        return (runMeters - priorRunMeters) / priorRunMeters
    }
}

public enum WeeklyRecapBuilder {
    public static let calorieToleranceFraction = 0.10
    public static let proteinTargetFraction = 0.90
    public static let demandingWorkingSetThreshold = 8
    public static let demandingEffortThreshold = 8.0
    public static let weightSmoothingAlpha = 0.4

    private struct NutritionDay {
        let date: Date
        let calories: Double?
        let protein: Double?
        let foods: [FoodItem]
    }

    /// Builds the report for the 7 days ending at `weekEnding` (inclusive).
    /// `runs` and `priorSessionLogs` may include older history; the builder owns all
    /// windowing so callers cannot accidentally mix report periods.
    public static func build(
        weekEnding: Date = Date(),
        calendar: Calendar = .current,
        dailyLogs: [DailyLog],
        sessionLogs: [WorkoutSessionLog],
        priorSessionLogs: [WorkoutSessionLog],
        weightHistory: [(id: String, date: Date, weight: Double)],
        runs: [Run] = [],
        calorieGoal: Double?,
        proteinGoal: Double? = nil,
        bodyWeightLbs: Double = 165,
        heartRateZoneSeconds: [Double]? = nil,
        runWorkoutResults: [RunWorkoutResult] = [],
        shoes: [RunningShoe] = []
    ) -> WeeklyRecap {
        let startOfEndingDay = calendar.startOfDay(for: weekEnding)
        let weekEnd = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: startOfEndingDay
        ) ?? weekEnding
        let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfEndingDay) ?? weekEnding
        let priorWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart

        func inWindow(_ date: Date) -> Bool {
            date >= weekStart && date <= weekEnd
        }

        let validCalorieGoal = validGoal(calorieGoal)
        let validProteinGoal = validGoal(proteinGoal)
        let nutritionDays = nutritionDays(
            from: dailyLogs,
            weekStart: weekStart,
            weekEnd: weekEnd,
            calendar: calendar
        )
        let daysLogged = nutritionDays.count
        let assessableCalories = nutritionDays.compactMap(\.calories)
        let assessableProtein = nutritionDays.compactMap(\.protein)
        let averageCalories = average(assessableCalories)
        let averageProtein = average(assessableProtein)

        let calorieAdherentDays = validCalorieGoal.map { goal in
            assessableCalories.filter { abs($0 - goal) / goal <= calorieToleranceFraction }.count
        } ?? 0
        let proteinAdherentDays = validProteinGoal.map { goal in
            assessableProtein.filter { $0 >= goal * proteinTargetFraction }.count
        } ?? 0
        let calorieAdherence = WeeklyRecapProgress(
            completed: calorieAdherentDays,
            eligible: validCalorieGoal == nil ? 0 : assessableCalories.count
        )
        let proteinAdherence = WeeklyRecapProgress(
            completed: proteinAdherentDays,
            eligible: validProteinGoal == nil ? 0 : assessableProtein.count
        )

        let reviewedFoods = nutritionDays.flatMap(\.foods).compactMap(\.sourceMetadata).filter {
            $0.reviewStatus != .notRequired
        }
        let trustReview = WeeklyRecapProgress(
            completed: reviewedFoods.filter {
                $0.reviewStatus == .userConfirmed || $0.reviewStatus == .userEdited
            }.count,
            eligible: reviewedFoods.count
        )

        let weekSessions = sessionLogs.filter { inWindow($0.date) }
        let workingSets = weekSessions.flatMap { session in
            session.completedExercises.flatMap(\.sets).filter(\.isWorkingSet)
        }
        let totalVolume = workingSets.reduce(0.0) { total, set in
            guard set.weight.isFinite, set.weight > 0, set.reps > 0 else { return total }
            return total + set.weight * Double(set.reps)
        }
        let personalRecords = personalRecordCount(
            weekSessions: weekSessions,
            priorSessions: priorSessionLogs.filter { $0.date < weekStart }
        )
        let currentEfforts = workingSets.compactMap(\.effort?.normalizedRPE)
        let priorWeekSessions = priorSessionLogs.filter {
            $0.date >= priorWeekStart && $0.date < weekStart
        }
        let priorEfforts = priorWeekSessions.flatMap { session in
            session.completedExercises.flatMap(\.sets)
                .filter(\.isWorkingSet)
                .compactMap(\.effort?.normalizedRPE)
        }

        let hardStrengthDates = demandingStrengthDates(
            sessions: weekSessions,
            calendar: calendar
        )
        let loggedDates = Set(nutritionDays.map(\.date))
        let demandingStrengthDaysLogged = hardStrengthDates.intersection(loggedDates).count
        let nutritionByDate = Dictionary(uniqueKeysWithValues: nutritionDays.map { ($0.date, $0) })
        let canAssessHardDayFuel = validCalorieGoal != nil && validProteinGoal != nil
        let assessableHardStrengthDates = canAssessHardDayFuel ? hardStrengthDates.filter { date in
            guard let day = nutritionByDate[date] else { return true }
            return day.calories != nil && day.protein != nil
        } : []
        let demandingStrengthFuelDays = assessableHardStrengthDates.filter { date in
            guard let day = nutritionByDate[date],
                  let calories = day.calories,
                  let protein = day.protein,
                  let calorieGoal = validCalorieGoal,
                  let proteinGoal = validProteinGoal else { return false }
            let caloriesMet = abs(calories - calorieGoal) / calorieGoal <= calorieToleranceFraction
            let proteinMet = protein >= proteinGoal * proteinTargetFraction
            return caloriesMet && proteinMet
        }.count

        let sortedRuns = runs.sorted { $0.startDate < $1.startDate }
        let weekRuns = sortedRuns.filter { inWindow($0.startDate) }
        let priorWeekRuns = sortedRuns.filter {
            $0.startDate >= priorWeekStart && $0.startDate < weekStart
        }
        let runMeters = weekRuns.reduce(0.0) { $0 + safePositive($1.distanceMeters) }
        let priorRunMeters = priorWeekRuns.reduce(0.0) { $0 + safePositive($1.distanceMeters) }
        let validPacedRuns = weekRuns.filter {
            $0.distanceMeters >= 100 && $0.distanceMeters.isFinite &&
                $0.movingSeconds > 0 && $0.movingSeconds.isFinite
        }
        let pacedMeters = validPacedRuns.reduce(0.0) { $0 + $1.distanceMeters }
        let runMovingSeconds = validPacedRuns.reduce(0.0) { $0 + $1.movingSeconds }
        let averageRunPace = pacedMeters > 0 ? runMovingSeconds / (pacedMeters / 1000) : nil
        let runRecords = runRecordCounts(
            weekRuns: weekRuns,
            priorRuns: sortedRuns.filter { $0.startDate < weekStart }
        )

        let normalizedZoneSeconds = normalizedHeartRateZones(heartRateZoneSeconds)
        let weekRunIDs = Set(weekRuns.map(\.id))
        let guidedResults = runWorkoutResults.filter { weekRunIDs.contains($0.runID) }
        let guidedRecordedSteps = guidedResults.reduce(0) { $0 + $1.steps.count }
        let guidedCompletedSteps = guidedResults.reduce(0) { total, result in
            total + result.steps.filter(\.isComplete).count
        }

        let recovery = recoveryProgress(
            weekRuns: weekRuns,
            foods: dailyLogs.flatMap { $0.meals.flatMap(\.foodItems) },
            bodyWeightLbs: bodyWeightLbs,
            evaluatedAt: weekEnding
        )
        let shoeContext = primaryShoeContext(
            weekRuns: weekRuns,
            allRuns: sortedRuns,
            shoes: shoes
        )

        let strengthDates = Set(weekSessions.map { calendar.startOfDay(for: $0.date) })
        let runDates = Set(weekRuns.map { calendar.startOfDay(for: $0.startDate) })
        let trainingDates = strengthDates.union(runDates)
        let trainingDaysLogged = trainingDates.intersection(loggedDates).count

        let rawWeightChange = rawWeightChange(
            history: weightHistory,
            weekStart: weekStart,
            weekEnd: weekEnd
        )
        let smoothedWeightChange = smoothedWeightChange(
            history: weightHistory,
            weekStart: weekStart,
            weekEnd: weekEnd
        )

        let story = story(
            daysLogged: daysLogged,
            trainingDays: trainingDates.count,
            trainingDaysLogged: trainingDaysLogged,
            workouts: weekSessions.count,
            workingSets: workingSets.count,
            runs: weekRuns.count,
            runMeters: runMeters,
            priorRunMeters: priorRunMeters,
            personalRecords: personalRecords,
            runRecords: runRecords.records,
            calorieAdherence: calorieAdherence,
            proteinAdherence: proteinAdherence,
            smoothedWeightChange: smoothedWeightChange
        )

        return WeeklyRecap(
            weekStart: weekStart,
            weekEnd: weekEnd,
            daysLogged: daysLogged,
            averageCalories: averageCalories,
            averageProtein: averageProtein,
            calorieGoal: validCalorieGoal,
            proteinGoal: validProteinGoal,
            calorieAdherence: calorieAdherence,
            proteinAdherence: proteinAdherence,
            trustReview: trustReview,
            trainingDays: trainingDates.count,
            trainingDaysLogged: trainingDaysLogged,
            workoutsCompleted: weekSessions.count,
            workingSetCount: workingSets.count,
            totalVolume: totalVolume,
            personalRecords: personalRecords,
            averageEffortRPE: average(currentEfforts),
            priorAverageEffortRPE: average(priorEfforts),
            demandingStrengthDays: hardStrengthDates.count,
            demandingStrengthDaysLogged: demandingStrengthDaysLogged,
            demandingStrengthFuelAdherence: WeeklyRecapProgress(
                completed: demandingStrengthFuelDays,
                eligible: assessableHardStrengthDates.count
            ),
            runCount: weekRuns.count,
            runMeters: runMeters,
            priorRunMeters: priorRunMeters,
            runMovingSeconds: runMovingSeconds,
            averageRunPaceSecondsPerKm: averageRunPace,
            runRecordCount: runRecords.records,
            paceRecordCount: runRecords.paceRecords,
            routeRunCount: weekRuns.filter { !$0.isIndoor && $0.hasRoute }.count,
            outdoorRunCount: weekRuns.filter { !$0.isIndoor }.count,
            heartRateZoneSeconds: normalizedZoneSeconds,
            guidedRunCount: guidedResults.count,
            guidedCompletedSteps: guidedCompletedSteps,
            guidedRecordedSteps: guidedRecordedSteps,
            recoveryFuelLoggedRuns: recovery.logged,
            recoveryFuelPendingRuns: recovery.pending,
            recoveryFuelAdherence: WeeklyRecapProgress(
                completed: recovery.targetsMet,
                eligible: recovery.eligible
            ),
            shoeContext: shoeContext,
            weightChange: rawWeightChange,
            smoothedWeightChange: smoothedWeightChange,
            story: story
        )
    }

    /// Epley estimated 1RM, the same yardstick Workout History uses for top sets.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight.isFinite, weight > 0, reps > 0 else { return 0 }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// Number of exercises whose best set this week beats their best in all prior history.
    /// New movements do not count; a first attempt is a baseline, not improvement evidence.
    static func personalRecordCount(
        weekSessions: [WorkoutSessionLog],
        priorSessions: [WorkoutSessionLog]
    ) -> Int {
        func bestByExercise(_ sessions: [WorkoutSessionLog]) -> [String: Double] {
            var best: [String: Double] = [:]
            for session in sessions {
                for exercise in session.completedExercises {
                    let name = exercise.exerciseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    let sessionBest = exercise.sets
                        .filter(\.isWorkingSet)
                        .map { estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }
                        .max() ?? 0
                    best[name] = max(best[name] ?? 0, sessionBest)
                }
            }
            return best
        }

        let weekBest = bestByExercise(weekSessions)
        let priorBest = bestByExercise(priorSessions)

        return weekBest.filter { name, best in
            guard best > 0, let prior = priorBest[name], prior > 0 else { return false }
            return best > prior
        }.count
    }

    public static func smoothedWeightChange(
        history: [(id: String, date: Date, weight: Double)],
        weekStart: Date,
        weekEnd: Date,
        alpha: Double = weightSmoothingAlpha
    ) -> Double? {
        let safeAlpha = min(1, max(0.01, alpha))
        let sorted = history
            .filter { $0.date <= weekEnd && $0.weight.isFinite && $0.weight > 0 }
            .sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return nil }

        var ema: Double?
        var baselineEMA: Double?
        var firstWindowEMA: Double?
        var latestWindowEMA: Double?

        for entry in sorted {
            ema = ema.map { safeAlpha * entry.weight + (1 - safeAlpha) * $0 } ?? entry.weight
            guard let ema else { continue }
            if entry.date < weekStart {
                baselineEMA = ema
            } else {
                firstWindowEMA = firstWindowEMA ?? ema
                latestWindowEMA = ema
            }
        }

        guard let latestWindowEMA else { return nil }
        if let baselineEMA {
            return latestWindowEMA - baselineEMA
        }
        guard let firstWindowEMA,
              sorted.filter({ $0.date >= weekStart && $0.date <= weekEnd }).count >= 2 else { return nil }
        return latestWindowEMA - firstWindowEMA
    }

    private static func nutritionDays(
        from logs: [DailyLog],
        weekStart: Date,
        weekEnd: Date,
        calendar: Calendar
    ) -> [NutritionDay] {
        var seenDays = Set<Date>()
        var days: [NutritionDay] = []
        for log in logs.sorted(by: { $0.date < $1.date }) where log.date >= weekStart && log.date <= weekEnd {
            let day = calendar.startOfDay(for: log.date)
            guard !seenDays.contains(day) else { continue }
            let foods = log.meals.flatMap(\.foodItems)
            guard !foods.isEmpty else { continue }
            seenDays.insert(day)
            days.append(NutritionDay(
                date: day,
                calories: validNutritionValue(log.totalCalories()),
                protein: validNutritionValue(log.totalMacros().protein),
                foods: foods
            ))
        }
        return days
    }

    private static func demandingStrengthDates(
        sessions: [WorkoutSessionLog],
        calendar: Calendar
    ) -> Set<Date> {
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return Set(byDay.compactMap { date, sessions in
            let sets = sessions.flatMap { $0.completedExercises.flatMap(\.sets) }.filter(\.isWorkingSet)
            let efforts = sets.compactMap(\.effort?.normalizedRPE)
            let averageEffort = average(efforts)
            let isDemanding = sets.count >= demandingWorkingSetThreshold ||
                (averageEffort.map { $0 >= demandingEffortThreshold } ?? false)
            return isDemanding ? date : nil
        })
    }

    private static func runRecordCounts(
        weekRuns: [Run],
        priorRuns: [Run]
    ) -> (records: Int, paceRecords: Int) {
        var history = priorRuns
        var records = 0
        var paceRecords = 0
        for run in weekRuns.sorted(by: { $0.startDate < $1.startDate }) {
            if RunStats.setsRecord(run, against: history) {
                records += 1
            }
            if RunStats.ghostPaceComparison(for: run, against: history)?.isPR == true {
                paceRecords += 1
            }
            history.append(run)
        }
        return (records, paceRecords)
    }

    private static func recoveryProgress(
        weekRuns: [Run],
        foods: [FoodItem],
        bodyWeightLbs: Double,
        evaluatedAt: Date
    ) -> (eligible: Int, logged: Int, targetsMet: Int, pending: Int) {
        let timestampedFoods = foods.compactMap { food -> (food: FoodItem, timestamp: Date)? in
            guard let timestamp = food.timestamp else { return nil }
            return (food, timestamp)
        }

        var eligible = 0
        var logged = 0
        var targetsMet = 0
        var pending = 0
        for run in weekRuns {
            let safeBodyWeight = bodyWeightLbs.isFinite && bodyWeightLbs > 0 ? bodyWeightLbs : 165
            guard let target = RunRecoveryRules.calculateTarget(for: run, weightLbs: safeBodyWeight) else { continue }
            guard evaluatedAt >= run.endDate else { continue }
            let windowEnd = run.endDate.addingTimeInterval(Double(target.windowMinutes * 60))
            let observationEnd = min(windowEnd, evaluatedAt)
            let recoveryFoods = timestampedFoods.filter {
                $0.timestamp >= run.endDate && $0.timestamp <= observationEnd
            }.map(\.food)
            let protein = recoveryFoods.reduce(0.0) { $0 + safePositive($1.protein) }
            let carbs = recoveryFoods.reduce(0.0) { $0 + safePositive($1.carbs) }
            let targetMet = protein >= Double(target.targetProteinGrams) &&
                carbs >= Double(target.targetCarbGrams)

            if !targetMet && evaluatedAt < windowEnd {
                pending += 1
                continue
            }

            eligible += 1
            if !recoveryFoods.isEmpty { logged += 1 }
            if targetMet { targetsMet += 1 }
        }
        return (eligible, logged, targetsMet, pending)
    }

    private static func primaryShoeContext(
        weekRuns: [Run],
        allRuns: [Run],
        shoes: [RunningShoe]
    ) -> WeeklyRecapShoeContext? {
        let weeklyByShoe = Dictionary(grouping: weekRuns.compactMap { run -> Run? in
            run.shoeID == nil ? nil : run
        }, by: { $0.shoeID! })
        guard let primary = weeklyByShoe.max(by: {
            $0.value.reduce(0) { $0 + safePositive($1.distanceMeters) } <
                $1.value.reduce(0) { $0 + safePositive($1.distanceMeters) }
        }), let shoe = shoes.first(where: { $0.id == primary.key }) else { return nil }

        let weeklyMeters = primary.value.reduce(0.0) { $0 + safePositive($1.distanceMeters) }
        let totalMeters = safePositive(shoe.initialMeters) + allRuns
            .filter { $0.shoeID == shoe.id }
            .reduce(0.0) { $0 + safePositive($1.distanceMeters) }
        let wear = shoe.maxMeters > 0 ? totalMeters / shoe.maxMeters : 0
        return WeeklyRecapShoeContext(
            name: shoe.name,
            weeklyMeters: weeklyMeters,
            totalMeters: totalMeters,
            wearFraction: max(0, wear),
            isWornOut: shoe.maxMeters > 0 && totalMeters >= shoe.maxMeters
        )
    }

    private static func rawWeightChange(
        history: [(id: String, date: Date, weight: Double)],
        weekStart: Date,
        weekEnd: Date
    ) -> Double? {
        let sorted = history
            .filter { $0.weight.isFinite && $0.weight > 0 }
            .sorted { $0.date < $1.date }
        let inWindow = sorted.filter { $0.date >= weekStart && $0.date <= weekEnd }
        guard let latest = inWindow.last else { return nil }
        if let baseline = sorted.last(where: { $0.date < weekStart }) {
            return latest.weight - baseline.weight
        }
        guard let first = inWindow.first, first.id != latest.id else { return nil }
        return latest.weight - first.weight
    }

    private static func story(
        daysLogged: Int,
        trainingDays: Int,
        trainingDaysLogged: Int,
        workouts: Int,
        workingSets: Int,
        runs: Int,
        runMeters: Double,
        priorRunMeters: Double,
        personalRecords: Int,
        runRecords: Int,
        calorieAdherence: WeeklyRecapProgress,
        proteinAdherence: WeeklyRecapProgress,
        smoothedWeightChange: Double?
    ) -> WeeklyRecapStory {
        let headline: String
        if trainingDays > 0 {
            headline = "You trained \(trainingDays) \(trainingDays == 1 ? "day" : "days") and logged food on \(trainingDaysLogged) of them"
        } else if daysLogged > 0 {
            headline = "You logged fuel on \(daysLogged) of 7 days"
        } else {
            headline = "A quiet week, honestly reported"
        }

        var trainingParts: [String] = []
        if workouts > 0 {
            trainingParts.append("\(workouts) strength \(workouts == 1 ? "session" : "sessions") with \(workingSets) working sets")
        }
        if runs > 0 {
            trainingParts.append("\(runs) \(runs == 1 ? "run" : "runs")")
        }
        let training = trainingParts.isEmpty
            ? "No strength sessions or runs were recorded."
            : trainingParts.joined(separator: "; ") + "."

        var fuelingParts = ["Food was logged on \(daysLogged) of 7 days"]
        if proteinAdherence.eligible > 0 {
            fuelingParts.append("protein reached at least 90% of goal on \(proteinAdherence.completed) of \(proteinAdherence.eligible)")
        }
        if calorieAdherence.eligible > 0 {
            fuelingParts.append("calories landed within 10% of goal on \(calorieAdherence.completed) of \(calorieAdherence.eligible)")
        }
        let fueling = fuelingParts.joined(separator: "; ") + "."

        let change: String
        if personalRecords > 0 && runRecords > 0 {
            let liftText = personalRecords == 1 ? "1 lift beat prior history" : "\(personalRecords) lifts beat prior history"
            let runText = runRecords == 1 ? "1 run set a personal record" : "\(runRecords) runs set personal records"
            change = "\(liftText); \(runText)."
        } else if personalRecords > 0 {
            change = "\(personalRecords) \(personalRecords == 1 ? "lift beat" : "lifts beat") prior history."
        } else if runRecords > 0 {
            change = runRecords == 1
                ? "1 run set a personal record this week."
                : "\(runRecords) runs set personal records this week."
        } else if priorRunMeters > 0 && runs > 0 {
            let percentage = Int((((runMeters - priorRunMeters) / priorRunMeters) * 100).rounded())
            change = "Running distance changed \(signedPercent(percentage)) from the prior seven days."
        } else if let smoothedWeightChange {
            if abs(smoothedWeightChange) < 0.05 {
                change = "The smoothed weight trend held steady across the week."
            } else {
                change = "The smoothed weight trend moved \(smoothedWeightChange < 0 ? "down" : "up") across the week."
            }
        } else {
            change = "There is not enough comparable history to call a change yet."
        }

        return WeeklyRecapStory(
            headline: headline,
            training: training,
            fueling: fueling,
            change: change
        )
    }

    private static func normalizedHeartRateZones(_ values: [Double]?) -> [Double]? {
        guard let values, values.count == HeartRateZones.zones.count else { return nil }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return values.reduce(0, +) > 0 ? values : nil
    }

    private static func validGoal(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func validNutritionValue(_ value: Double) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func average(_ values: [Double]) -> Double? {
        let valid = values.filter(\.isFinite)
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private static func safePositive(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func signedPercent(_ value: Int) -> String {
        value > 0 ? "+\(value)%" : "\(value)%"
    }
}

/// Aggregate-only CSV for explicit user sharing. It intentionally excludes account IDs,
/// food/routine names, routes, coordinates, and raw heart-rate samples.
public enum WeeklyRecapCSVExporter {
    public static func csvString(for recap: WeeklyRecap, metric: Bool) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weightUnit = metric ? "kg" : "lb"
        let volumeUnit = metric ? "kg-reps" : "lb-reps"
        let volume = metric ? recap.totalVolume / BodyUnits.lbsPerKg : recap.totalVolume
        let weightChange = recap.smoothedWeightChange.map {
            metric ? $0 / BodyUnits.lbsPerKg : $0
        }

        var rows: [[String]] = [
            ["Category", "Metric", "Value", "Unit", "Notes"],
            ["Period", "Start", dateFormatter.string(from: recap.weekStart), "date", "Rolling seven-day report"],
            ["Period", "End", dateFormatter.string(from: recap.weekEnd), "date", "Rolling seven-day report"],
            ["Nutrition", "Days logged", "\(recap.daysLogged)", "days", "Out of 7"],
            ["Nutrition", "Average calories", decimal(recap.averageCalories), "kcal/day", "Assessable logged days only"],
            ["Nutrition", "Average protein", decimal(recap.averageProtein), "g/day", "Assessable logged days only"],
            ["Nutrition", "Calorie-consistent days", "\(recap.calorieAdherence.completed)/\(recap.calorieAdherence.eligible)", "days", "Within 10% of goal"],
            ["Nutrition", "Protein-consistent days", "\(recap.proteinAdherence.completed)/\(recap.proteinAdherence.eligible)", "days", "At least 90% of goal"],
            ["Nutrition", "Trust reviews", "\(recap.trustReview.completed)/\(recap.trustReview.eligible)", "entries", "Only foods requiring review"],
            ["Training", "Training days with food logged", "\(recap.trainingDaysLogged)/\(recap.trainingDays)", "days", "Strength or running days"],
            ["Strength", "Sessions", "\(recap.workoutsCompleted)", "sessions", ""],
            ["Strength", "Working sets", "\(recap.workingSetCount)", "sets", "Warmups excluded"],
            ["Strength", "Working-set volume", decimal(volume), volumeUnit, "Warmups excluded"],
            ["Strength", "Personal records", "\(recap.personalRecords)", "exercises", "Compared with prior history"],
            ["Strength", "Average effort", decimal(recap.averageEffortRPE), "RPE", "Logged working sets only"],
            ["Strength", "Hard-day fuel consistency", "\(recap.demandingStrengthFuelAdherence.completed)/\(recap.demandingStrengthFuelAdherence.eligible)", "days", "8+ working sets or average RPE 8+; both nutrition targets logged"],
            ["Running", "Runs", "\(recap.runCount)", "runs", ""],
            ["Running", "Distance", decimal(metric ? recap.runMeters / 1000 : recap.runMeters / RunFormat.metersPerMile), metric ? "km" : "mi", ""],
            ["Running", "Average pace", decimal(recap.averageRunPaceSecondsPerKm.map { metric ? $0 : $0 * RunFormat.metersPerMile / 1000 }), metric ? "sec/km" : "sec/mi", "Distance-weighted"],
            ["Running", "Records", "\(recap.runRecordCount)", "runs", "Longest, 5K, or 10K bests"],
            ["Running", "Pace records", "\(recap.paceRecordCount)", "runs", "Compared with similar-distance history"],
            ["Running", "Outdoor runs with routes", "\(recap.routeRunCount)/\(recap.outdoorRunCount)", "runs", "Aggregate count; no route data exported"],
            ["Running", "Guided steps completed", "\(recap.guidedCompletedSteps)/\(recap.guidedRecordedSteps)", "steps", "Recorded guided steps only"],
            ["Running", "Recovery food logged", "\(recap.recoveryFuelLoggedRuns)/\(recap.recoveryFuelAdherence.eligible)", "runs", "Timestamped inside the recovery window"],
            ["Running", "Recovery targets logged", "\(recap.recoveryFuelAdherence.completed)/\(recap.recoveryFuelAdherence.eligible)", "runs", "Both carb and protein targets"],
            ["Running", "Recovery windows pending", "\(recap.recoveryFuelPendingRuns)", "runs", "Still open and excluded from adherence"],
            ["Outcome", "Smoothed weight change", decimal(weightChange), weightUnit, "EMA alpha 0.4"],
        ]

        if let zoneSeconds = recap.heartRateZoneSeconds {
            for (index, seconds) in zoneSeconds.enumerated() {
                rows.append(["Running", "Heart-rate zone \(index + 1)", decimal(seconds / 60), "minutes", "Aggregated; no raw samples exported"])
            }
        }
        if let shoe = recap.shoeContext {
            rows.append(["Running", "Primary shoe", shoe.name, "", "Most distance this week"])
            rows.append(["Running", "Primary shoe wear", decimal(shoe.wearFraction * 100), "%", "Based on configured replacement distance"])
        }

        return rows.map { $0.map(escaped).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func decimal(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func escaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
