import MyFitPlateCore

import SwiftUI
import Charts
import HealthKit

// Manages fetching and processing data for the reports view.
@MainActor
class ReportsViewModel: ObservableObject {
    @Published var summary: ReportSummary?
    @Published var mealScore: MealScore?
    @Published var mealScoreHistory: [DateValuePoint] = []
    @Published var calorieTrend: [DateValuePoint] = []
    @Published var proteinTrend: [DateValuePoint] = []
    @Published var carbTrend: [DateValuePoint] = []
    @Published var fatTrend: [DateValuePoint] = []
    @Published var micronutrientAverages: [MicroAverageDataPoint] = []
    @Published var mealDistributionData: [MealDistributionDataPoint] = []
    @Published var reportSpecificInsight: UserInsight?
    @Published var enhancedSleepReport: EnhancedSleepReport?
    @Published var weeklyWorkoutReport: WorkoutReport?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var wellnessScore: WellnessScore?
    @Published var lastNightSleepScore: Int?

    @Published var workoutAnalytics: WorkoutAnalytics?

    private let wellnessScoreService = WellnessScoreService()
    private let workoutAnalyticsService = WorkoutAnalyticsService()

    let dailyLogService: DailyLogService
    let healthKitManager = HealthKitManager.shared // Direct access for fetching

    // *** This is the weak reference to the HealthKitViewModel ***
    private weak var healthKitViewModel: HealthKitViewModel?

    private var currentGoals: GoalSettings?
    private var currentUserID: String? { DIContainer.shared.authService.currentUserID }
    private var yesterdaysLog: DailyLog?
    private var didCalculateYesterdaysMealScore = false // Prevents duplicate score saving

    init(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    // *** This setup method is correct ***
    func setup(goals: GoalSettings, healthKitViewModel: HealthKitViewModel) {
        self.currentGoals = goals
        self.healthKitViewModel = healthKitViewModel
    }

    // Processes sleep samples from HealthKit to generate scores and reports.
    func processAndScoreSleepData(samples: [HKCategorySample]) {
        guard !samples.isEmpty else {
            self.enhancedSleepReport = nil
            self.lastNightSleepScore = nil
            self.wellnessScore = nil
            Task { await calculateWellnessScoreIfNeeded() }
            return
        }

        let calendar = Calendar.current
        var dailyData: [Date: EnhancedSleepReport.DailySleepStageData] = [:]
        var allBedtimes: [Date] = []
        var bedtimesByDay: [Date: Date] = [:]

        let sleepByNight = Dictionary(grouping: samples) { sleepNightKey(for: $0, calendar: calendar) }
        var mostRecentSleepDay: Date?

        for (day, samplesForDay) in sleepByNight {
            let relevantSamples = samplesForDay

            let inBedSamples = relevantSamples.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value) == .inBed }
            let asleepSamples = relevantSamples.filter { 
                guard let value = HKCategoryValueSleepAnalysis(rawValue: $0.value) else { return false }
                return value == .asleepCore || value == .asleepDeep || value == .asleepREM || value == .asleepUnspecified
            }
            
            let coreSamples = relevantSamples.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value) == .asleepCore }
            let deepSamples = relevantSamples.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value) == .asleepDeep }
            let remSamples = relevantSamples.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value) == .asleepREM }
            let awakeSamples = relevantSamples.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value) == .awake }

            let timeCore = calculateTotalDuration(from: coreSamples)
            let timeDeep = calculateTotalDuration(from: deepSamples)
            let timeREM = calculateTotalDuration(from: remSamples)
            let timeAwake = calculateTotalDuration(from: awakeSamples)

            var timeInBed = calculateTotalDuration(from: inBedSamples)
            let timeAsleep = calculateTotalDuration(from: asleepSamples)

            if timeInBed == 0 && (timeAsleep > 0 || timeAwake > 0) {
                 let firstStart = relevantSamples.map {$0.startDate}.min() ?? day
                 let lastEnd = relevantSamples.map {$0.endDate}.max() ?? calendar.date(byAdding: .day, value: 1, to: day) ?? day
                 timeInBed = lastEnd.timeIntervalSince(firstStart)
            }

            if timeAsleep > 0 {
                dailyData[day] = EnhancedSleepReport.DailySleepStageData(
                    date: day, timeInBed: timeInBed, timeAsleep: timeAsleep, timeCore: timeCore,
                    timeDeep: timeDeep, timeREM: timeREM, timeAwake: timeAwake
                )
                if let bedtime = relevantSamples.map({$0.startDate}).min() {
                    allBedtimes.append(bedtime)
                    bedtimesByDay[day] = bedtime
                }
                if mostRecentSleepDay.map({ day > $0 }) ?? true { mostRecentSleepDay = day }
            }
        }

        let validDays = dailyData.values.sorted { $0.date < $1.date }
        guard !validDays.isEmpty else {
            self.enhancedSleepReport = nil; self.lastNightSleepScore = nil
            self.wellnessScore = nil
            Task { await calculateWellnessScoreIfNeeded() }
            return
        }

        let usualBedtimeMinutes = averageBedtimeMinutes(from: allBedtimes)

        if let lastSleepDay = mostRecentSleepDay, let lastNightData = dailyData[lastSleepDay] {
            self.lastNightSleepScore = calculateSleepScore(
                timeAsleep: lastNightData.timeAsleep,
                timeAwake: lastNightData.timeAwake,
                bedtimeComponent: bedtimeScore(for: bedtimesByDay[lastSleepDay], usualBedtimeMinutes: usualBedtimeMinutes)
            )
        } else {
            self.lastNightSleepScore = nil
        }

        let numDays = Double(validDays.count)
        let avgInBed=validDays.reduce(0) {$0 + $1.timeInBed}/numDays; let avgAsleep=validDays.reduce(0) {$0 + $1.timeAsleep}/numDays
        let avgCore=validDays.reduce(0) {$0 + $1.timeCore}/numDays; let avgDeep=validDays.reduce(0) {$0 + $1.timeDeep}/numDays
        let avgREM=validDays.reduce(0) {$0 + $1.timeREM}/numDays; let avgAwake=validDays.reduce(0) {$0 + $1.timeAwake}/numDays
        let (consistencyScore, consistencyMessage) = calculateBedtimeConsistency(bedtimes: allBedtimes)
        let dailyScores = validDays.map { dayData in
            calculateSleepScore(
                timeAsleep: dayData.timeAsleep,
                timeAwake: dayData.timeAwake,
                bedtimeComponent: bedtimeScore(for: bedtimesByDay[dayData.date], usualBedtimeMinutes: usualBedtimeMinutes)
            )
        }
        let weeklyAverageScore = dailyScores.reduce(0, +) / max(dailyScores.count, 1)
        guard let firstDate = validDays.first?.date, let lastDate = validDays.last?.date else { return }
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "MMM d"
        let dateRangeString = "\(dateFormatter.string(from: firstDate)) - \(dateFormatter.string(from: lastDate))"

        self.enhancedSleepReport = EnhancedSleepReport(
            dateRange: dateRangeString, averageSleepScore: weeklyAverageScore, averageTimeInBed: avgInBed,
            averageTimeAsleep: avgAsleep, averageTimeInCore: avgCore, averageTimeInDeep: avgDeep,
            averageTimeInREM: avgREM, averageTimeAwake: avgAwake, sleepConsistencyScore: consistencyScore,
            sleepConsistencyMessage: consistencyMessage, dailySleepData: validDays
        )

        if errorMessage == "No data available for the selected timeframe." {
            errorMessage = nil
        }
        self.wellnessScore = nil
        Task {
            await self.calculateWellnessScoreIfNeeded()
        }
    }

    private func sleepNightKey(for sample: HKCategorySample, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: sample.startDate)
        let normalizedDate = hour < 18 ? calendar.date(byAdding: .day, value: -1, to: sample.startDate) ?? sample.startDate : sample.startDate
        return calendar.startOfDay(for: normalizedDate)
    }

    private func calculateTotalDuration(from samples: [HKCategorySample]) -> TimeInterval {
        let intervals = samples.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = [sorted[0]]
        for interval in sorted.dropFirst() {
            let lastIndex = merged.count - 1
            let last = merged[lastIndex]
            if interval.start <= last.end {
                if interval.end > last.end {
                    merged[lastIndex] = DateInterval(start: last.start, end: interval.end)
                }
            } else {
                merged.append(interval)
            }
        }
        return merged.reduce(0) { $0 + $1.duration }
    }

    // Calculates bedtime consistency score and provides a descriptive message.
    private func calculateBedtimeConsistency(bedtimes: [Date]) -> (score: Int, message: String) {
        guard bedtimes.count > 1 else { return (75, "Need 2+ nights for consistency analysis.") } // Need at least 2 points
        let bedtimeMinuteValues = bedtimes.map { bedtimeMinutes(from: $0) }
        let stdDev = calculateStdDev(for: bedtimeMinuteValues) // Calculate standard deviation
        // Assign score and message based on standard deviation
        let score: Int; let message: String
        if stdDev <= 15 { score = 100; message = "Excellent! Bedtime varies by only \(Int(round(stdDev))) mins." } else if stdDev <= 30 { score = 88; message = "Good. Bedtime varies by ~\(Int(round(stdDev))) mins." } else if stdDev <= 60 { score = 70; message = "Fair. Bedtime varies by ~\(Int(round(stdDev))) mins. Aim for more regularity." } else if stdDev <= 90 { score = 55; message = "Bedtime was off by ~\(Int(round(stdDev))) mins. Keep nudging it earlier." } else { score = 40; message = "Inconsistent. Bedtime varies by over an hour and a half (\(Int(round(stdDev))) mins)." }
        return (score, message)
    }

    private func averageBedtimeMinutes(from bedtimes: [Date]) -> Double? {
        guard bedtimes.count > 1 else { return nil }
        let minutes = bedtimes.map { bedtimeMinutes(from: $0) }
        return minutes.reduce(0, +) / Double(minutes.count)
    }

    private func bedtimeMinutes(from date: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        return hour < 12 ? (hour + 24) * 60 + minute : hour * 60 + minute
    }

    private func bedtimeScore(for bedtime: Date?, usualBedtimeMinutes: Double?) -> Double {
        guard let bedtime, let usualBedtimeMinutes else { return 22.5 }

        let deviation = abs(bedtimeMinutes(from: bedtime) - usualBedtimeMinutes)
        if deviation <= 15 { return 30 }
        if deviation <= 30 { return 26 }
        if deviation <= 60 { return 21 }
        if deviation <= 90 { return 16 }
        if deviation <= 120 { return 11 }
        return 6
    }

    private func calculateSleepScore(timeAsleep: TimeInterval, timeAwake: TimeInterval, bedtimeComponent: Double) -> Int {
        let totalHoursAsleep = timeAsleep / 3600.0; guard totalHoursAsleep > 0 else { return 0 }
        let totalScore = durationScore(hours: totalHoursAsleep)
            + bedtimeComponent
            + interruptionScore(asleep: timeAsleep, awake: timeAwake)
        return Int(max(0, min(100, round(totalScore))))
    }

    private func durationScore(hours: Double) -> Double {
        if hours >= 7 && hours <= 9 { return 50 }
        if hours > 9 { return max(30, 50 - ((hours - 9) * 5)) }
        if hours >= 6 { return min(50, 30 + ((hours - 6) * 25)) }
        return max(0, (hours / 6) * 30)
    }

    private func interruptionScore(asleep: TimeInterval, awake: TimeInterval) -> Double {
        let totalTime = max(asleep, asleep + awake)
        guard totalTime > 0 else { return 0 }

        let awakePercentage = (awake / totalTime) * 100
        if awakePercentage <= 8 { return 20 }
        if awakePercentage <= 20 { return max(10, 20 - ((awakePercentage - 8) * 0.8)) }
        return max(0, 10 - ((awakePercentage - 20) * 0.6))
    }

    // Helper to format time intervals into "Xh Ym" string.
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0h 0m" }; let totalMinutes = Int(round(interval / 60.0)); let hours = totalMinutes / 60; let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    // Helper to calculate standard deviation for a list of doubles.
    private func calculateStdDev(for values: [Double]) -> Double {
        let n = Double(values.count); guard n > 1 else { return 0 } // Need >1 value
        let mean = values.reduce(0, +) / n; let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / (n - 1) // Sample variance
        return sqrt(variance)
    }

    // Fetches all necessary data for the selected timeframe.
    func fetchData(for timeframe: ReportTimeframe, startDate: Date? = nil, endDate: Date? = nil) {
        // Ensure user and goals are loaded
        guard let userID = currentUserID, currentGoals != nil else { errorMessage = "User or goals not loaded."; isLoading = false; return }
        // Reset state before fetching
        isLoading = true; errorMessage = nil; summary = nil
        calorieTrend = []; proteinTrend = []; carbTrend = []; fatTrend = []
        micronutrientAverages = []; mealDistributionData = []
        reportSpecificInsight = nil; weeklyWorkoutReport = nil; workoutAnalytics = nil
        enhancedSleepReport = nil; lastNightSleepScore = nil; wellnessScore = nil
        didCalculateYesterdaysMealScore = false; yesterdaysLog = nil // Reset yesterday's log flag

        // Determine date range based on timeframe selection
        var effectiveStartDate: Date; var effectiveEndDate: Date = Calendar.current.startOfDay(for: Date()) // Default end date is today
        var timeframeNameForSummary: String = timeframe.rawValue; var daysInPeriodForSummary: Int

        if timeframe == .custom {
            guard let start = startDate, let end = endDate else { errorMessage = "Custom date range not provided."; isLoading = false; return }
            effectiveStartDate = Calendar.current.startOfDay(for: start); effectiveEndDate = Calendar.current.startOfDay(for: end)
            // Calculate days in custom range
            let components = Calendar.current.dateComponents([.day], from: effectiveStartDate, to: effectiveEndDate)
            daysInPeriodForSummary = (components.day ?? 0) + 1
            // Format custom timeframe name
            let formatter = DateFormatter(); formatter.dateStyle = .short
            timeframeNameForSummary = "\(formatter.string(from: effectiveStartDate)) - \(formatter.string(from: effectiveEndDate))"
        } else {
            // Calculate start date for week or month
            let daysToSubtract = (timeframe == .week) ? -6 : -29
            effectiveStartDate = Calendar.current.date(byAdding: .day, value: daysToSubtract, to: effectiveEndDate) ?? effectiveEndDate
            daysInPeriodForSummary = (timeframe == .week) ? 7 : 30
        }

        let reportStartDate = effectiveStartDate
        let reportEndDate = effectiveEndDate
        let reportTimeframeName = timeframeNameForSummary
        let reportDaysInPeriod = daysInPeriodForSummary

        // Use Task to perform asynchronous operations
        Task {
             // Fetch logs for the main period and just for yesterday concurrently
             let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Calendar.current.startOfDay(for: Date())
             async let logResult = dailyLogService.fetchDailyHistory(for: userID, startDate: reportStartDate, endDate: reportEndDate)
             async let yesterdayLogResult = dailyLogService.fetchDailyHistory(for: userID, startDate: yesterday, endDate: yesterday)

             // *** Use HealthKitViewModel's authorization status ***
             if healthKitViewModel?.isAuthorized ?? false {
                 // Fetch sleep data if authorized (adjust start date for sleep queries)
                 let sleepStartDate = Calendar.current.date(byAdding: .day, value: -1, to: reportStartDate) ?? reportStartDate // Fetch from day before start to catch overnight sleep
                 
                 // Use the shared HealthKitManager instance to perform the fetch
                 healthKitManager.fetchSleepAnalysis(startDate: sleepStartDate, endDate: reportEndDate) { [weak self] samples, _ in
                     // Process results on main thread
                     Task { @MainActor in
                         guard let self else { return }
                         if let samples = samples {
                             let reportEndBoundary = Calendar.current.date(byAdding: .day, value: 1, to: reportEndDate) ?? reportEndDate
                             let filteredSamples = samples.filter {
                                 let night = self.sleepNightKey(for: $0, calendar: Calendar.current)
                                 return night >= reportStartDate && night < reportEndBoundary
                             }
                             self.processAndScoreSleepData(samples: filteredSamples)
                         } else {
                             // Handle fetch errors or no data
                             self.enhancedSleepReport = nil; self.lastNightSleepScore = nil; self.wellnessScore = nil
                             await self.calculateWellnessScoreIfNeeded() // Recalculate wellness without sleep
                         }
                     }
                 }
             } else {
                 // Handle case where HealthKit sleep data is not authorized
                 self.enhancedSleepReport = nil; self.lastNightSleepScore = nil; self.wellnessScore = nil
                 // Still need to attempt wellness score calculation, passing potential yesterday log result
                 await self.calculateWellnessScoreIfNeeded(yesterdayLogResult: await yesterdayLogResult)
             }

            // Await log fetching results
            isLoading = false // Set loading to false after fetches start
            switch await logResult {
            case .success(let logs):
                // Process fetched logs to calculate summaries, trends, etc.
                self.processLogs(logs: logs, timeframeName: reportTimeframeName, totalDaysInPeriod: reportDaysInPeriod)
            case .failure(let e):
                // Handle errors fetching logs
                self.errorMessage = "Error fetching report data: \(e.localizedDescription)"
            }

            // Store yesterday's log result if successful
            if case .success(let yesterdayLogs) = await yesterdayLogResult { self.yesterdaysLog = yesterdayLogs.first; } else { self.yesterdaysLog = nil; }

            // Final check to calculate wellness score if sleep wasn't authorized or calculation hasn't happened yet
             if !(healthKitViewModel?.isAuthorized ?? false) {
                 await self.calculateWellnessScoreIfNeeded() // Calculate without sleep data
             } else if self.wellnessScore == nil {
                 // If sleep *was* authorized but wellness score is still nil (e.g., fetchSleepAnalysis callback race condition)
                  await self.calculateWellnessScoreIfNeeded() // Attempt calculation again
             }
        }
    }

    // Processes fetched logs to populate published report data properties.
    private func processLogs(logs: [DailyLog], timeframeName: String, totalDaysInPeriod: Int) {
        guard let goals = currentGoals else { return } // Need goals for comparisons
        // Filter out logs that have no meals AND no exercises (empty days)
        let validLogs = logs.filter { !$0.meals.isEmpty || !($0.exercises?.isEmpty ?? true) }
        let daysWithActualLogEntries = validLogs.count

        // Reset all data arrays and summary before processing
         calorieTrend = []; proteinTrend = []; carbTrend = []; fatTrend = []
         micronutrientAverages = []; mealDistributionData = []
         summary = nil; weeklyWorkoutReport = nil; workoutAnalytics = nil; reportSpecificInsight = nil

        // Accumulators for totals
        var totCals=0.0, totProt=0.0, totCarb=0.0, totFat=0.0 // Macros
        var totCa=0.0, totFe=0.0, totK=0.0, totNa=0.0, totVa=0.0, totVc=0.0, totVd=0.0, totFib = 0.0 // Micros + Fiber
        var mealCals: [String: Double] = [:] // Calories per meal type
        // Temporary arrays for chart data points
        var tmpCalT=[DateValuePoint](), tmpProtT=[DateValuePoint](), tmpCarbT=[DateValuePoint](), tmpFatT=[DateValuePoint]()

        // Process workouts first (if any). Dedupe per-day so a routine also recorded on
        // Apple Health isn't counted twice in the workout count or calories burned.
        let allExercises = validLogs.flatMap { ($0.exercises ?? []).dedupedAgainstHealthKit() }
        if !allExercises.isEmpty {
            let totalWorkouts = allExercises.count; let totalCaloriesBurned = allExercises.reduce(0) {$0 + $1.caloriesBurned}
            // Find most frequent workout type
            let frequency = Dictionary(grouping: allExercises, by: {$0.name}).mapValues {$0.count}
            let mostFrequent = frequency.max {$0.value < $1.value}?.key ?? "N/A"
            // Create the workout report summary
            self.weeklyWorkoutReport = WorkoutReport(totalWorkouts: totalWorkouts, totalCaloriesBurned: totalCaloriesBurned, mostFrequentWorkout: mostFrequent)
        }

        // Calculate detailed workout analytics (volume, PRs) in a background task
        Task { if !validLogs.isEmpty { self.workoutAnalytics = await workoutAnalyticsService.calculateAnalytics(for: validLogs, program: nil) } }

        // Process nutrition data if there are valid logs
        if daysWithActualLogEntries > 0 {
             // Iterate through each valid daily log
             for log in validLogs {
                 let c=log.totalCalories(); let mac=log.totalMacros(); let mic=log.totalMicronutrients()
                 // Accumulate totals
                 totCals+=c; totProt+=mac.protein; totCarb+=mac.carbs; totFat+=mac.fats
                 totCa+=mic.calcium; totFe+=mic.iron; totK+=mic.potassium; totNa+=mic.sodium; totVa+=mic.vitaminA; totVc+=mic.vitaminC; totVd+=mic.vitaminD; totFib+=mic.fiber
                 // Create data points for trends
                 let date=Calendar.current.startOfDay(for: log.date) // Use start of day for consistency
                 tmpCalT.append(DateValuePoint(date: date, value: c)); tmpProtT.append(DateValuePoint(date: date, value: mac.protein)); tmpCarbT.append(DateValuePoint(date: date, value: mac.carbs)); tmpFatT.append(DateValuePoint(date: date, value: mac.fats))
                 // Accumulate calories per meal type
                 for meal in log.meals { mealCals[meal.name, default: 0.0] += meal.foodItems.reduce(0) { $0 + $1.calories } }
             }
             // Calculate averages
             let divisor = Double(daysWithActualLogEntries)
             let avgCals=totCals/divisor; let avgProt=totProt/divisor; let avgCarb=totCarb/divisor; let avgFat=totFat/divisor
             // Create the overall summary report
             self.summary = ReportSummary(timeframe: timeframeName, averageCalories: avgCals, averageProtein: avgProt, averageCarbs: avgCarb, averageFats: avgFat, daysLogged: daysWithActualLogEntries)
             // Set the trend data, sorted by date
             self.calorieTrend=tmpCalT.sorted {$0.date<$1.date}; self.proteinTrend=tmpProtT.sorted {$0.date<$1.date}; self.carbTrend=tmpCarbT.sorted {$0.date<$1.date}; self.fatTrend=tmpFatT.sorted {$0.date<$1.date}
             // Create micronutrient average data points
             var tmpMicros: [MicroAverageDataPoint] = []
             tmpMicros.append(MicroAverageDataPoint(name: "Fiber", unit: "g", averageValue: totFib/divisor, goalValue: 25)) // Standard fiber goal
             tmpMicros.append(MicroAverageDataPoint(name: "Calcium", unit: "mg", averageValue: totCa/divisor, goalValue: goals.calciumGoal ?? 1)) // Use goal or 1 if nil
             tmpMicros.append(MicroAverageDataPoint(name: "Iron", unit: "mg", averageValue: totFe/divisor, goalValue: goals.ironGoal ?? 1))
             tmpMicros.append(MicroAverageDataPoint(name: "Potassium", unit: "mg", averageValue: totK/divisor, goalValue: goals.potassiumGoal ?? 1))
             tmpMicros.append(MicroAverageDataPoint(name: "Sodium", unit: "mg", averageValue: totNa/divisor, goalValue: goals.sodiumGoal ?? 2300)) // Standard sodium goal or user goal
             tmpMicros.append(MicroAverageDataPoint(name: "Vitamin A", unit: "mcg", averageValue: totVa/divisor, goalValue: goals.vitaminAGoal ?? 1))
             tmpMicros.append(MicroAverageDataPoint(name: "Vitamin C", unit: "mg", averageValue: totVc/divisor, goalValue: goals.vitaminCGoal ?? 1))
             tmpMicros.append(MicroAverageDataPoint(name: "Vitamin D", unit: "mcg", averageValue: totVd/divisor, goalValue: goals.vitaminDGoal ?? 1))
             // Filter out micros with no goal set (goalValue <= 0)
             self.micronutrientAverages = tmpMicros.filter { $0.goalValue > 0 }
             // Calculate meal distribution if total calories > 0
             if totCals > 0 { var tmpMealDist: [MealDistributionDataPoint] = []; for (n, c) in mealCals { tmpMealDist.append(MealDistributionDataPoint(mealName: n, totalCalories: c / divisor)) }; self.mealDistributionData = tmpMealDist.sorted { $0.mealName < $1.mealName } } else { self.mealDistributionData = [] } // Clear distribution if no calories logged
             // Generate a simple insight based on the logs
             self.reportSpecificInsight = generateReportInsight(from: validLogs)
         } else {
             // If no valid logs, but sleep or workout data exists, create a zeroed summary
             if enhancedSleepReport != nil || weeklyWorkoutReport != nil { self.summary = ReportSummary(timeframe: timeframeName, averageCalories: 0, averageProtein: 0, averageCarbs: 0, averageFats: 0, daysLogged: 0) }
         }
         // If still no summary, no sleep, no workout, no analytics, and no error message, set the error message.
         if summary == nil && enhancedSleepReport == nil && weeklyWorkoutReport == nil && workoutAnalytics == nil && errorMessage == nil { self.errorMessage = "No data available for the selected timeframe." }
    }

    // Generates a simple insight based on the highest calorie day.
    private func generateReportInsight(from logs: [DailyLog]) -> UserInsight? {
        // Find the log with the maximum total calories
        guard !logs.isEmpty, let highestCalorieLog = logs.max(by: { $0.totalCalories() < $1.totalCalories() }) else { return nil }
        // Format the date for display
        let formatter = DateFormatter(); formatter.dateStyle = .medium; let dateString = formatter.string(from: highestCalorieLog.date)
        // Create the insight object
        return UserInsight(title: "Highest Calorie Day", message: "Your highest calorie day was \(dateString), with \(String(format: "%.0f", highestCalorieLog.totalCalories())) calories.", category: .smartSuggestion)
    }

    // Fetches historical meal scores from Firestore.
    func fetchMealScoreHistory(for userID: String) {
        Task {
            do {
                let history = try await DIContainer.shared.reportsRepository.fetchMealScoreHistory(userID: userID)
                DispatchQueue.main.async { self.mealScoreHistory = history }
            } catch {
                AppLog.data.error("Failed to fetch meal score history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Calculates the wellness score, ensuring dependencies (meal score, sleep) are handled.
    private func calculateWellnessScoreIfNeeded(yesterdayLogResult: Result<[DailyLog], Error>? = nil) async {
         // Only calculate if score isn't already present
         guard wellnessScore == nil else { return }
        // Ensure user and goals are available
        guard let userID = currentUserID, let goals = currentGoals else { return }

        var calculatedMealScore: MealScore = .noScore // Default to no score
        var logsAvailableForMealScore = self.yesterdaysLog != nil // Check if yesterday's log is already loaded

        // Try using the already loaded yesterday's log first
        if let log = self.yesterdaysLog {
            calculatedMealScore = await calculateMealScore(for: log, goals: goals)
            // Save score only once per fetch cycle
            if !didCalculateYesterdaysMealScore { saveMealScore(for: userID, date: log.date, score: calculatedMealScore); didCalculateYesterdaysMealScore = true }
        } else if let result = yesterdayLogResult { // If not loaded, try using the passed-in fetch result
            if case .success(let logs) = result, let log = logs.first {
                self.yesterdaysLog = log // Store it for future use within this cycle
                calculatedMealScore = await calculateMealScore(for: log, goals: goals)
                 if !didCalculateYesterdaysMealScore { saveMealScore(for: userID, date: log.date, score: calculatedMealScore); didCalculateYesterdaysMealScore = true }
                 logsAvailableForMealScore = true
            }
        } else {
             // If neither is available, attempt one final fetch for yesterday's log
             let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Calendar.current.startOfDay(for: Date())
             let logResult = await dailyLogService.fetchDailyHistory(for: userID, startDate: yesterday, endDate: yesterday)
             if case .success(let logs) = logResult, let log = logs.first {
                 self.yesterdaysLog = log; calculatedMealScore = await calculateMealScore(for: log, goals: goals)
                 if !didCalculateYesterdaysMealScore { saveMealScore(for: userID, date: yesterday, score: calculatedMealScore); didCalculateYesterdaysMealScore = true }
                 logsAvailableForMealScore = true
             }
        }

        // Fetch latest RHR and HRV concurrently
        async let restingHeartRateSample = fetchLatestRHR()
        async let hrvSample = fetchLatestHRV()
        // Extract values from HealthKit samples
        let rhrValue = (await restingHeartRateSample)?.quantity.doubleValue(for: HKUnit(from: "count/min"))
        let hrvValue = (await hrvSample)?.quantity.doubleValue(for: HKUnit(from: "ms"))

        // Calculate the final wellness score using the service
        let finalWellnessScore = wellnessScoreService.calculateWellnessScore(
            mealScore: calculatedMealScore.overallScore > 0 ? calculatedMealScore : nil, // Pass meal score only if calculated
            lastNightSleepScore: lastNightSleepScore,
            restingHeartRate: rhrValue, hrv: hrvValue
        )

        // Update published properties on the main thread
        DispatchQueue.main.async {
            // Only update mealScore if logs were actually available for scoring
            if logsAvailableForMealScore || calculatedMealScore.overallScore > 0 { self.mealScore = calculatedMealScore }
            self.wellnessScore = finalWellnessScore
        }
    }

    // Async wrappers for HealthKit fetches using continuations.
    private func fetchLatestRHR() async -> HKQuantitySample? { await withCheckedContinuation { c in healthKitManager.fetchLatestRestingHeartRate { c.resume(returning: $0) } } }
    private func fetchLatestHRV() async -> HKQuantitySample? { await withCheckedContinuation { c in healthKitManager.fetchLatestHRV { c.resume(returning: $0) } } }
    
    private func saveMealScore(for userID: String, date: Date, score: MealScore) {
        Task {
            do {
                try await DIContainer.shared.reportsRepository.saveMealScore(userID: userID, date: date, score: score)
            } catch {
                AppLog.data.error("Failed to save meal score: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    // Calculates the meal score based on calorie, macro, and quality adherence.
    // This is the correct "live" version.
    private func calculateMealScore(for log: DailyLog, goals: GoalSettings) async -> MealScore {
        guard let calorieGoal = goals.calories, calorieGoal > 0 else { return .noScore }
        
        // Calorie Control Score (40%)
        let calorieDiff = abs(log.totalCalories() - calorieGoal)
        let calorieScore = max(0, 100 - (calorieDiff / calorieGoal) * 200)

        // Macro Balance Score (30%)
        let macros = log.totalMacros()
        let pD = goals.protein > 0 ? abs(macros.protein - goals.protein) / goals.protein : 0
        let cD = goals.carbs > 0 ? abs(macros.carbs - goals.carbs) / goals.carbs : 0
        let fD = goals.fats > 0 ? abs(macros.fats - goals.fats) / goals.fats : 0
        let macroScore = max(0, 100 - (pD + cD + fD) / 3 * 100)

        // Food Quality Score (30%)
        let micros = log.totalMicronutrients()
        var qualityScore = 50.0 // Start with a base score
        let fiberGoal = 25.0 // Standard fiber goal
        qualityScore += min(25, (micros.fiber / fiberGoal) * 25) // Fiber bonus
        let sodiumGoal = goals.sodiumGoal ?? 2300.0 // Sodium penalty
        if micros.sodium > sodiumGoal { qualityScore -= min(25, (micros.sodium - sodiumGoal) / sodiumGoal * 25) }
        let ironGoal = goals.ironGoal ?? 18; let calciumGoal = goals.calciumGoal ?? 1000 // Micro bonus
        if micros.iron >= ironGoal { qualityScore += 12.5 }
        if micros.calcium >= calciumGoal { qualityScore += 12.5 }
        qualityScore = max(0, min(100, qualityScore))

        // Final weighted score
        let finalScore = (calorieScore * 0.4) + (macroScore * 0.3) + (qualityScore * 0.3)
        
        let grade: String; let color: Color
        switch finalScore {
        case 90...: grade = "A+"; color = .accentPositive
        case 80..<90: grade = "A-"; color = .accentPositive
        case 70..<80: grade = "B"; color = .yellow
        case 60..<70: grade = "C"; color = .orange
        default: grade = "D"; color = .red
        }
        
        let summary: String
        if finalScore >= 80 { summary = "Excellent work!" } else if finalScore >= 60 { summary = "Good effort!" } else { summary = "Focus on consistency." }
        
        // This data is all needed for the MealScoreDetailView
        return MealScore(
            grade: grade, summary: summary, color: color,
            calorieScore: Int(calorieScore), macroScore: Int(macroScore), qualityScore: Int(qualityScore), overallScore: Int(finalScore),
            personalizedAISummary: "AI summary generation is handled by InsightsService.", // Placeholder, as InsightsService handles this
            improvementTips: [], // Placeholder, as InsightsService handles this
            actualCalories: log.totalCalories(), goalCalories: calorieGoal,
            actualProtein: macros.protein, goalProtein: goals.protein,
            actualCarbs: macros.carbs, goalCarbs: goals.carbs,
            actualFats: macros.fats, goalFats: goals.fats,
            actualFiber: micros.fiber, goalFiber: fiberGoal,
            actualSaturatedFat: log.totalSaturatedFat(), goalSaturatedFat: 20, // 20g is a general guideline
            actualSodium: micros.sodium, goalSodium: sodiumGoal
        )
    }
}
