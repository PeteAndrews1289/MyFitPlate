import SwiftUI
import Charts
import FirebaseAuth
import HealthKit
import FirebaseFirestore

// Defines the structure for the daily meal score.
struct MealScore {
    let grade: String
    let summary: String
    let color: Color
    let calorieScore: Int
    let macroScore: Int
    let qualityScore: Int
    let overallScore: Int
    let personalizedAISummary: String
    let improvementTips: [ImprovementTip]
    let actualCalories: Double
    let goalCalories: Double
    let actualProtein: Double
    let goalProtein: Double
    let actualCarbs: Double
    let goalCarbs: Double
    let actualFats: Double
    let goalFats: Double
    let actualFiber: Double
    let goalFiber: Double
    let actualSaturatedFat: Double
    let goalSaturatedFat: Double
    let actualSodium: Double
    let goalSodium: Double
    static let noScore = MealScore(grade: "N/A", summary: "Log a full day of meals to get your score.", color: .gray, calorieScore: 0, macroScore: 0, qualityScore: 0, overallScore: 0, personalizedAISummary: "No data available.", improvementTips: [], actualCalories: 0, goalCalories: 2000, actualProtein: 0, goalProtein: 150, actualCarbs: 0, goalCarbs: 250, actualFats: 0, goalFats: 70, actualFiber: 0, goalFiber: 25, actualSaturatedFat: 0, goalSaturatedFat: 20, actualSodium: 0, goalSodium: 2300)
}

// Defines the structure for improvement tips within the meal score.
struct ImprovementTip: Identifiable {
    let id = UUID()
    let category: String
    let advice: String
    let icon: String
    let color: Color
}

// Defines the structure for the overall report summary.
struct ReportSummary: Identifiable {
    let id = UUID()
    let timeframe: String
    let averageCalories: Double
    let averageProtein: Double
    let averageCarbs: Double
    let averageFats: Double
    let daysLogged: Int
}

// Represents a single data point for charts with a date.
struct DateValuePoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
}

// Represents data for micronutrient averages compared to goals.
struct MicroAverageDataPoint: Identifiable {
    let id = UUID()
    let name: String
    let unit: String
    let averageValue: Double
    let goalValue: Double
    var percentageMet: Double { guard goalValue > 0 else { return 0 }; return (averageValue / goalValue) * 100 }
    var progressViewValue: Double { guard goalValue > 0 else { return 0.0 }; return max(0.0, min(1.0, averageValue / goalValue)) }
}

// Represents data for calorie distribution across meals.
struct MealDistributionDataPoint: Identifiable {
    let id = UUID()
    let mealName: String
    let totalCalories: Double
}

// Represents detailed sleep report data.
struct EnhancedSleepReport: Identifiable {
    let id = UUID()
    let dateRange: String
    let averageSleepScore: Int
    let averageTimeInBed: TimeInterval
    let averageTimeAsleep: TimeInterval
    let averageTimeInCore: TimeInterval
    let averageTimeInDeep: TimeInterval
    let averageTimeInREM: TimeInterval
    let averageTimeAwake: TimeInterval
    let sleepConsistencyScore: Int
    let sleepConsistencyMessage: String
    let dailySleepData: [DailySleepStageData]

    struct DailySleepStageData: Identifiable {
        let id = UUID()
        let date: Date
        let timeInBed: TimeInterval
        let timeAsleep: TimeInterval
        let timeCore: TimeInterval
        let timeDeep: TimeInterval
        let timeREM: TimeInterval
        let timeAwake: TimeInterval
        var weekday: String {
            let formatter = DateFormatter(); formatter.dateFormat = "EEE"
            let calendar = Calendar.current
            // Adjust date slightly to ensure correct weekday display across timezones/midnight boundaries
            let displayDate = calendar.date(byAdding: .hour, value: 12, to: date) ?? date
            return formatter.string(from: displayDate)
        }
    }
}


// Manages fetching and processing data for the reports view.
@MainActor
class ReportsViewModel: ObservableObject {
    @Published var summary: ReportSummary? = nil
    @Published var mealScore: MealScore? = nil
    @Published var mealScoreHistory: [DateValuePoint] = []
    @Published var calorieTrend: [DateValuePoint] = []
    @Published var proteinTrend: [DateValuePoint] = []
    @Published var carbTrend: [DateValuePoint] = []
    @Published var fatTrend: [DateValuePoint] = []
    @Published var micronutrientAverages: [MicroAverageDataPoint] = []
    @Published var mealDistributionData: [MealDistributionDataPoint] = []
    @Published var reportSpecificInsight: UserInsight? = nil
    @Published var enhancedSleepReport: EnhancedSleepReport? = nil
    @Published var weeklyWorkoutReport: WorkoutReport? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var wellnessScore: WellnessScore? = nil
    @Published var lastNightSleepScore: Int? = nil

    @Published var workoutAnalytics: WorkoutAnalytics? = nil

    private let wellnessScoreService = WellnessScoreService()
    private let workoutAnalyticsService = WorkoutAnalyticsService()

    let dailyLogService: DailyLogService
    let healthKitManager = HealthKitManager.shared // Direct access for fetching

    // *** This is the weak reference to the HealthKitViewModel ***
    private weak var healthKitViewModel: HealthKitViewModel?

    private var currentGoals: GoalSettings?
    private var currentUserID: String? { Auth.auth().currentUser?.uid }
    private let db = Firestore.firestore()
    private var yesterdaysLog: DailyLog? = nil
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
            self.enhancedSleepReport = nil // Clear report if no data
            self.lastNightSleepScore = nil // Clear last night's score
            // Trigger wellness score recalculation as sleep data is now nil
            Task { await calculateWellnessScoreIfNeeded() }
            return
        }

        let calendar = Calendar.current
        var dailyData: [Date: EnhancedSleepReport.DailySleepStageData] = [:]
        var allBedtimes: [Date] = [] // Collect all start times for consistency calculation

        // Group samples by the start day
        let sleepByStartDate = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.startDate) }
        var mostRecentSleepDay: Date? = nil // Track the latest day with sleep data

        // Iterate through each day's samples
        for (day, samplesForDay) in sleepByStartDate {
            var timeInBed: TimeInterval = 0; var timeAsleep: TimeInterval = 0; var timeCore: TimeInterval = 0
            var timeDeep: TimeInterval = 0; var timeREM: TimeInterval = 0; var timeAwake: TimeInterval = 0
            // Note: relevantSamples is just samplesForDay here, can simplify later if needed
            let relevantSamples = samplesForDay

            // Sum durations for each sleep stage
            for sample in relevantSamples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .inBed: timeInBed += duration
                case .asleepCore: timeCore += duration; timeAsleep += duration
                case .asleepDeep: timeDeep += duration; timeAsleep += duration
                case .asleepREM: timeREM += duration; timeAsleep += duration
                case .awake: timeAwake += duration; timeInBed += duration // Awake counts towards timeInBed
                default: break // Ignore other stages like .asleepUnspecified
                }
            }

            // Estimate timeInBed if HealthKit didn't provide it directly but provided asleep/awake times
            if timeInBed == 0 && (timeAsleep > 0 || timeAwake > 0) {
                 let firstStart = relevantSamples.map{$0.startDate}.min() ?? day
                 let lastEnd = relevantSamples.map{$0.endDate}.max() ?? calendar.date(byAdding: .day, value: 1, to: day)!
                 timeInBed = lastEnd.timeIntervalSince(firstStart) // Use span from first start to last end
            }

            // Only store data if there was actual sleep recorded
            if timeAsleep > 0 {
                dailyData[day] = EnhancedSleepReport.DailySleepStageData(
                    date: day, timeInBed: timeInBed, timeAsleep: timeAsleep, timeCore: timeCore,
                    timeDeep: timeDeep, timeREM: timeREM, timeAwake: timeAwake
                )
                // Store the earliest start time for this sleep session for consistency calculation
                if let bedtime = relevantSamples.map({$0.startDate}).min() { allBedtimes.append(bedtime) }
                // Update the most recent sleep day found so far
                 if mostRecentSleepDay == nil || day > mostRecentSleepDay! { mostRecentSleepDay = day }
            }
        }

        // Get the valid daily sleep data entries, sorted by date
        let validDays = dailyData.values.sorted { $0.date < $1.date }
        guard !validDays.isEmpty else {
            self.enhancedSleepReport = nil; self.lastNightSleepScore = nil
            Task { await calculateWellnessScoreIfNeeded() } // Recalculate wellness score
            return
        }

        // Calculate the score specifically for the most recent night of sleep
        if let lastSleepDay = mostRecentSleepDay, let lastNightData = dailyData[lastSleepDay] {
            // Need consistency score for *all* bedtimes for the last night calculation
            let lastNightConsistencyScore = calculateBedtimeConsistencyScore(bedtimes: allBedtimes)
            self.lastNightSleepScore = calculateComprehensiveSleepScore(
                avgTimeAsleep: lastNightData.timeAsleep, avgTimeDeep: lastNightData.timeDeep,
                avgTimeREM: lastNightData.timeREM, avgTimeAwake: lastNightData.timeAwake,
                consistencyScore: lastNightConsistencyScore // Use overall consistency
            )
        } else {
            self.lastNightSleepScore = nil // No score if last night's data is missing
        }

        // Calculate weekly averages
        let numDays = Double(validDays.count)
        let avgInBed=validDays.reduce(0){$0 + $1.timeInBed}/numDays; let avgAsleep=validDays.reduce(0){$0 + $1.timeAsleep}/numDays
        let avgCore=validDays.reduce(0){$0 + $1.timeCore}/numDays; let avgDeep=validDays.reduce(0){$0 + $1.timeDeep}/numDays
        let avgREM=validDays.reduce(0){$0 + $1.timeREM}/numDays; let avgAwake=validDays.reduce(0){$0 + $1.timeAwake}/numDays
        // Calculate overall consistency score and message for the period
        let (consistencyScore, consistencyMessage) = calculateBedtimeConsistency(bedtimes: allBedtimes)
        // Calculate the average weekly sleep score based on average durations and consistency
        let weeklyAverageScore = calculateComprehensiveSleepScore(avgTimeAsleep: avgAsleep, avgTimeDeep: avgDeep, avgTimeREM: avgREM, avgTimeAwake: avgAwake, consistencyScore: consistencyScore)
        // Format the date range string for display
        let firstDate = validDays.first!.date; let lastDate = validDays.last!.date
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "MMM d"
        let dateRangeString = "\(dateFormatter.string(from: firstDate)) - \(dateFormatter.string(from: lastDate))"

        // Create the final EnhancedSleepReport object
        self.enhancedSleepReport = EnhancedSleepReport(
            dateRange: dateRangeString, averageSleepScore: weeklyAverageScore, averageTimeInBed: avgInBed,
            averageTimeAsleep: avgAsleep, averageTimeInCore: avgCore, averageTimeInDeep: avgDeep,
            averageTimeInREM: avgREM, averageTimeAwake: avgAwake, sleepConsistencyScore: consistencyScore,
            sleepConsistencyMessage: consistencyMessage, dailySleepData: validDays
        )

        // Trigger wellness score calculation now that sleep data (or lack thereof) is processed
         Task {
              await self.calculateWellnessScoreIfNeeded()
         }
    }


    // Calculates bedtime consistency score and provides a descriptive message.
    private func calculateBedtimeConsistency(bedtimes: [Date]) -> (score: Int, message: String) {
        guard bedtimes.count > 1 else { return (75, "Need 2+ nights for consistency analysis.") } // Need at least 2 points
        let calendar = Calendar.current
        // Convert bedtimes to minutes past midnight (adjusting for crossing midnight)
        let bedtimeMinutes = bedtimes.map { date -> Double in let c = calendar.dateComponents([.hour, .minute], from: date); let h=Double(c.hour ?? 0); let m=Double(c.minute ?? 0); return h < 12 ? (h+24)*60+m : h*60+m } // Handle times after midnight
        let stdDev = calculateStdDev(for: bedtimeMinutes) // Calculate standard deviation
        // Assign score and message based on standard deviation
        let score: Int; let message: String
        if stdDev <= 15 { score = 100; message = "Excellent! Bedtime varies by only \(Int(round(stdDev))) mins." }
        else if stdDev <= 30 { score = 85; message = "Good. Bedtime varies by ~\(Int(round(stdDev))) mins." }
        else if stdDev <= 60 { score = 65; message = "Fair. Bedtime varies by ~\(Int(round(stdDev))) mins. Aim for more regularity." }
        else { score = 40; message = "Inconsistent. Bedtime varies by over an hour (\(Int(round(stdDev))) mins)." }
        return (score, message)
    }

    // Helper to get just the consistency score.
     private func calculateBedtimeConsistencyScore(bedtimes: [Date]) -> Int { return calculateBedtimeConsistency(bedtimes: bedtimes).score }

    // Calculates a comprehensive sleep score based on durations, stages, and consistency.
    private func calculateComprehensiveSleepScore(avgTimeAsleep: TimeInterval, avgTimeDeep: TimeInterval, avgTimeREM: TimeInterval, avgTimeAwake: TimeInterval, consistencyScore: Int) -> Int {
        let totalHoursAsleep = avgTimeAsleep / 3600.0; guard totalHoursAsleep > 0 else { return 0 } // Need sleep to score
        var durationScore: Double = 0; var deepScore: Double = 0; var remScore: Double = 0; var awakePenalty: Double = 0
        let consistencyBonus: Double = Double(consistencyScore) * 0.2 // Consistency contributes up to 20 points

        // Score based on total sleep duration (aiming for 7-9 hours)
        if totalHoursAsleep >= 7 && totalHoursAsleep <= 9 { durationScore = 40 } // Max score in ideal range
        else if totalHoursAsleep > 9 { durationScore = max(20, 40 - (totalHoursAsleep - 9) * 10) } // Penalize oversleeping
        else if totalHoursAsleep >= 6 { durationScore = 20 + (totalHoursAsleep - 6) * 20 } // Scale up score between 6-7 hours
        else { durationScore = max(0, totalHoursAsleep * 3.33) }; durationScore = max(0, min(40, durationScore)) // Score for <6 hours, capped at 40

        // Score based on deep sleep percentage (aiming for 13-23%)
        let deepPercentage = (avgTimeDeep / avgTimeAsleep) * 100
        if deepPercentage >= 13 && deepPercentage <= 23 { deepScore = 20 } // Max score in ideal range
        else if deepPercentage > 23 { deepScore = max(10, 20 - (deepPercentage - 23)) } // Penalize slightly too much deep sleep
        else { deepScore = max(0, deepPercentage * (20.0 / 13.0)) }; deepScore = max(0, min(20, deepScore)) // Scale up score below 13%, capped at 20

        // Score based on REM sleep percentage (aiming for 20-25%)
        let remPercentage = (avgTimeREM / avgTimeAsleep) * 100
        if remPercentage >= 20 && remPercentage <= 25 { remScore = 20 } // Max score in ideal range
        else if remPercentage > 25 { remScore = max(10, 20 - (remPercentage - 25)) } // Penalize slightly too much REM
        else { remScore = max(0, remPercentage * (20.0 / 20.0)) }; remScore = max(0, min(20, remScore)) // Scale up score below 20%, capped at 20

        // Penalty for excessive time awake during the sleep period (more than 15% is penalized)
        // Use total time (asleep + awake) if available, otherwise just asleep time, as base for percentage.
        let totalTimeForAwakeCalc = max(avgTimeAsleep, avgTimeAsleep + avgTimeAwake) // Ensure non-zero denominator
        let awakePercentage = totalTimeForAwakeCalc > 0 ? (avgTimeAwake / totalTimeForAwakeCalc) * 100 : 0
        if awakePercentage > 15 { awakePenalty = min(10, (awakePercentage - 15) * 0.67) } // Penalty up to 10 points

        // Combine scores and clamp between 0 and 100
        let totalScore = durationScore + deepScore + remScore + consistencyBonus - awakePenalty
        return Int(max(0, min(100, round(totalScore))))
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
        guard let userID = currentUserID, let goals = currentGoals else { errorMessage = "User or goals not loaded."; isLoading = false; return }
        // Reset state before fetching
        isLoading = true; errorMessage = nil; summary = nil
        calorieTrend = []; proteinTrend = []; carbTrend = []; fatTrend = []
        micronutrientAverages = []; mealDistributionData = []
        reportSpecificInsight = nil; weeklyWorkoutReport = nil; workoutAnalytics = nil;
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
            effectiveStartDate = Calendar.current.date(byAdding: .day, value: daysToSubtract, to: effectiveEndDate)!
            daysInPeriodForSummary = (timeframe == .week) ? 7 : 30
        }

        // Use Task to perform asynchronous operations
        Task {
             // Fetch logs for the main period and just for yesterday concurrently
             async let logResult = dailyLogService.fetchDailyHistory(for: userID, startDate: effectiveStartDate, endDate: effectiveEndDate)
             async let yesterdayLogResult = dailyLogService.fetchDailyHistory(for: userID, startDate: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!, endDate: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!)

             // *** Use HealthKitViewModel's authorization status ***
             if healthKitViewModel?.isAuthorized ?? false {
                 // Fetch sleep data if authorized (adjust start date for sleep queries)
                 let sleepStartDate = Calendar.current.date(byAdding: .day, value: -1, to: effectiveStartDate)! // Fetch from day before start to catch overnight sleep
                 
                 // Use the shared HealthKitManager instance to perform the fetch
                 healthKitManager.fetchSleepAnalysis(startDate: sleepStartDate, endDate: effectiveEndDate) { [weak self] samples, error in
                     // Process results on main thread
                     Task { @MainActor in
                         if let samples = samples {
                             // Filter samples to ensure they start within the *intended* report period or slightly before
                             let filteredSamples = samples.filter { $0.startDate >= effectiveStartDate && $0.startDate <= Calendar.current.date(byAdding: .day, value: 1, to: effectiveEndDate)! }
                             self?.processAndScoreSleepData(samples: filteredSamples)
                         } else {
                             // Handle fetch errors or no data
                             self?.enhancedSleepReport = nil; self?.lastNightSleepScore = nil
                             await self?.calculateWellnessScoreIfNeeded() // Recalculate wellness without sleep
                         }
                     }
                 }
             } else {
                 // Handle case where HealthKit sleep data is not authorized
                 self.enhancedSleepReport = nil; self.lastNightSleepScore = nil
                 // Still need to attempt wellness score calculation, passing potential yesterday log result
                 await self.calculateWellnessScoreIfNeeded(yesterdayLogResult: await yesterdayLogResult)
             }

            // Await log fetching results
            isLoading = false // Set loading to false after fetches start
            switch await logResult {
            case .success(let logs):
                // Process fetched logs to calculate summaries, trends, etc.
                self.processLogs(logs: logs, timeframeName: timeframeNameForSummary, totalDaysInPeriod: daysInPeriodForSummary)
            case .failure(let e):
                // Handle errors fetching logs
                self.errorMessage = "Error fetching report data: \(e.localizedDescription)"
            }

            // Store yesterday's log result if successful
            if case .success(let yesterdayLogs) = await yesterdayLogResult { self.yesterdaysLog = yesterdayLogs.first; }
            else { self.yesterdaysLog = nil; }

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

        // Process workouts first (if any)
        let allExercises = validLogs.flatMap { $0.exercises ?? [] }
        if !allExercises.isEmpty {
            let totalWorkouts = allExercises.count; let totalCaloriesBurned = allExercises.reduce(0){$0 + $1.caloriesBurned}
            // Find most frequent workout type
            let frequency = Dictionary(grouping: allExercises, by: {$0.name}).mapValues{$0.count}
            let mostFrequent = frequency.max{$0.value < $1.value}?.key ?? "N/A"
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
             self.calorieTrend=tmpCalT.sorted{$0.date<$1.date}; self.proteinTrend=tmpProtT.sorted{$0.date<$1.date}; self.carbTrend=tmpCarbT.sorted{$0.date<$1.date}; self.fatTrend=tmpFatT.sorted{$0.date<$1.date}
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
             if totCals > 0 { var tmpMealDist: [MealDistributionDataPoint] = []; for (n, c) in mealCals { tmpMealDist.append(MealDistributionDataPoint(mealName: n, totalCalories: c / divisor)) }; self.mealDistributionData = tmpMealDist.sorted { $0.mealName < $1.mealName } }
             else { self.mealDistributionData = [] } // Clear distribution if no calories logged
             // Generate a simple insight based on the logs
             self.reportSpecificInsight = generateReportInsight(from: validLogs)
         } else {
             // If no valid logs, but sleep or workout data exists, create a zeroed summary
             if enhancedSleepReport != nil || weeklyWorkoutReport != nil { self.summary = ReportSummary(timeframe: timeframeName, averageCalories: 0, averageProtein: 0, averageCarbs: 0, averageFats: 0, daysLogged: 0) }
         }
         // If still no summary, no sleep, no workout, no analytics, and no error message, set the error message.
         if summary == nil && enhancedSleepReport == nil && weeklyWorkoutReport == nil && workoutAnalytics == nil && errorMessage == nil { self.errorMessage = "No data available for the selected period." }
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
        // Reference to the dailySummaries collection for the user
        let ref = db.collection("users").document(userID).collection("dailySummaries").order(by: "date", descending: true).limit(to: 30) // Get last 30 summaries
        ref.getDocuments { [weak self] snapshot, error in
            guard let self = self, let documents = snapshot?.documents else { return } // Ensure self and documents exist
            // Map Firestore documents to DateValuePoint objects
            let history = documents.compactMap { doc -> DateValuePoint? in
                // Try decoding modern 'mealOverallScore' (Double) first
                guard let timestamp = doc.data()["date"] as? Timestamp, let scoreValue = doc.data()["mealOverallScore"] as? Double else {
                    // Fallback for older 'mealScore' (String grade)
                    if let timestamp = doc.data()["date"] as? Timestamp, let scoreString = doc.data()["mealScore"] as? String {
                        let fallbackScoreValue: Double
                         switch scoreString { case "A+": fallbackScoreValue = 95; case "A-": fallbackScoreValue = 85; case "B": fallbackScoreValue = 75; case "C": fallbackScoreValue = 65; case "D": fallbackScoreValue = 55; default: fallbackScoreValue = 0 } // Convert grade to approximate score
                         return DateValuePoint(date: timestamp.dateValue(), value: fallbackScoreValue)
                    }
                    return nil // Skip if neither format is found
                }
                // Return point with modern score format
                return DateValuePoint(date: timestamp.dateValue(), value: scoreValue)
            }
            // Update the published history property on the main thread, sorted by date
            DispatchQueue.main.async { self.mealScoreHistory = history.sorted { $0.date < $1.date } }
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
                self.yesterdaysLog = log; // Store it for future use within this cycle
                calculatedMealScore = await calculateMealScore(for: log, goals: goals)
                 if !didCalculateYesterdaysMealScore { saveMealScore(for: userID, date: log.date, score: calculatedMealScore); didCalculateYesterdaysMealScore = true }
                 logsAvailableForMealScore = true;
            }
        } else {
             // If neither is available, attempt one final fetch for yesterday's log
             let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
             let logResult = await dailyLogService.fetchDailyHistory(for: userID, startDate: yesterday, endDate: yesterday)
             if case .success(let logs) = logResult, let log = logs.first {
                 self.yesterdaysLog = log; calculatedMealScore = await calculateMealScore(for: log, goals: goals)
                 if !didCalculateYesterdaysMealScore { saveMealScore(for: userID, date: yesterday, score: calculatedMealScore); didCalculateYesterdaysMealScore = true }
                 logsAvailableForMealScore = true;
             }
        }

        // Fetch latest RHR and HRV concurrently
        async let restingHeartRateSample = fetchLatestRHR()
        async let hrvSample = fetchLatestHRV()
        // Use the last calculated sleep score (could be nil or 0)
        let sleepScoreForWellness = self.lastNightSleepScore ?? 0
        // Extract values from HealthKit samples
        let rhrValue = (await restingHeartRateSample)?.quantity.doubleValue(for: HKUnit(from: "count/min"))
        let hrvValue = (await hrvSample)?.quantity.doubleValue(for: HKUnit(from: "ms"))

        // Calculate the final wellness score using the service
        let finalWellnessScore = wellnessScoreService.calculateWellnessScore(
            mealScore: calculatedMealScore.overallScore > 0 ? calculatedMealScore : nil, // Pass meal score only if calculated
            lastNightSleepScore: sleepScoreForWellness > 0 ? sleepScoreForWellness : nil, // Pass sleep score only if > 0
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
    
    // Saves the calculated meal score to Firestore.
    // *** This is the correct "live" version that saves the numeric score ***
    private func saveMealScore(for userID: String, date: Date, score: MealScore) {
        let dateString = dailyLogService.dateFormatter.string(from: date)
        let ref = db.collection("users").document(userID).collection("dailySummaries").document(dateString)
        let data: [String: Any] = [
            "date": Timestamp(date: date),
            "mealScore": score.grade, // Save grade for quick display
            "mealOverallScore": score.overallScore, // *** SAVE THE NUMERIC SCORE ***
            "calorieScore": score.calorieScore,
            "macroScore": score.macroScore,
            "qualityScore": score.qualityScore
        ]
        ref.setData(data, merge: true) { e in
             if let e = e {print("❌ Error saving meal score: \(e.localizedDescription)")}
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
        if finalScore >= 80 { summary = "Excellent work!" }
        else if finalScore >= 60 { summary = "Good effort!" }
        else { summary = "Focus on consistency." }
        
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
