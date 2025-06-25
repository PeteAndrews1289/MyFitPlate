import SwiftUI
import Charts
import FirebaseAuth
import HealthKit

struct ReportSummary: Identifiable {
    let id = UUID()
    let timeframe: String
    let averageCalories: Double
    let averageProtein: Double
    let averageCarbs: Double
    let averageFats: Double
    let daysLogged: Int
}

struct DateValuePoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct MicroAverageDataPoint: Identifiable {
    let id = UUID()
    let name: String
    let unit: String
    let averageValue: Double
    let goalValue: Double
    var percentageMet: Double { guard goalValue > 0 else { return 0 }; return (averageValue / goalValue) * 100 }
    var progressViewValue: Double { guard goalValue > 0 else { return 0.0 }; return max(0.0, min(1.0, averageValue / goalValue)) }
}

struct MealDistributionDataPoint: Identifiable {
    let id = UUID()
    let mealName: String
    let totalCalories: Double
}

@MainActor
class ReportsViewModel: ObservableObject {
    @Published var summary: ReportSummary? = nil
    @Published var calorieTrend: [DateValuePoint] = []
    @Published var proteinTrend: [DateValuePoint] = []
    @Published var carbTrend: [DateValuePoint] = []
    @Published var fatTrend: [DateValuePoint] = []
    @Published var micronutrientAverages: [MicroAverageDataPoint] = []
    @Published var mealDistributionData: [MealDistributionDataPoint] = []
    @Published var reportSpecificInsight: UserInsight? = nil
    @Published var weeklySleepReport: WeeklySleepReport? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    let dailyLogService: DailyLogService
    private var currentGoals: GoalSettings?
    private var currentUserID: String? { Auth.auth().currentUser?.uid }

    init(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    func setup(goals: GoalSettings) {
        self.currentGoals = goals
    }

    func processSleepData(samples: [HKCategorySample]) {
        guard !samples.isEmpty else {
            self.weeklySleepReport = nil
            return
        }
        
        let asleepStates: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepREM, .asleep]
        let asleepRawValues = Set(asleepStates.map { $0.rawValue })

        var totalInBed: TimeInterval = 0
        var totalAsleep: TimeInterval = 0
        var daysWithSleep = 0
        var bedtimeVariability: [Double] = []
        var dailySleepData: [WeeklySleepReport.DailySleep] = []

        let calendar = Calendar.current
        
        let sleepByDay = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.startDate) }
        
        for (day, samplesForDay) in sleepByDay {
            let inBedForDay = samplesForDay.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            let asleepForDay = samplesForDay.filter { asleepRawValues.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            
            if asleepForDay > 0 {
                totalAsleep += asleepForDay
                totalInBed += (inBedForDay > 0) ? inBedForDay : asleepForDay
                daysWithSleep += 1
                
                if let bedtime = samplesForDay.map({$0.startDate}).min() {
                    let bedtimeInMinutes = Double(calendar.component(.hour, from: bedtime) * 60 + calendar.component(.minute, from: bedtime))
                    bedtimeVariability.append(bedtimeInMinutes)
                }
                
                dailySleepData.append(.init(date: day, timeAsleep: asleepForDay))
            }
        }
        
        guard daysWithSleep > 0 else {
            self.weeklySleepReport = nil
            return
        }

        let avgInBed = totalInBed / Double(daysWithSleep)
        let avgAsleep = totalAsleep / Double(daysWithSleep)
        
        let stdDev = bedtimeVariability.count > 1 ? calculateStdDev(for: bedtimeVariability) : 0
        let consistency: String
        if stdDev <= 30 {
            consistency = "Your bedtime is very consistent, varying by less than \(Int(stdDev)) minutes on average."
        } else if stdDev <= 60 {
            consistency = "Your bedtime is fairly consistent, varying by about \(Int(stdDev)) minutes on average."
        } else {
            consistency = "Your bedtime varies by more than an hour on average. A more regular schedule can improve sleep quality."
        }

        self.weeklySleepReport = WeeklySleepReport(
            averageTimeInBed: formatTimeInterval(avgInBed),
            averageTimeAsleep: formatTimeInterval(avgAsleep),
            sleepConsistency: consistency,
            dailySleep: dailySleepData.sorted(by: { $0.date < $1.date })
        )
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0h 0m" }

        // First, round the total seconds to the nearest minute.
        let totalMinutes = Int(round(interval / 60.0))
        
        // Then, calculate hours and the remaining minutes from the rounded total.
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        return "\(hours)h \(minutes)m"
    }

    private func calculateStdDev(for values: [Double]) -> Double {
        let n = Double(values.count)
        guard n > 0 else { return 0 }
        let mean = values.reduce(0, +) / n
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / n
        return sqrt(variance)
    }

    func fetchData(for timeframe: ReportTimeframe, startDate: Date? = nil, endDate: Date? = nil) {
        guard let userID = currentUserID, let goals = currentGoals else {
            errorMessage = "User or goals not loaded."
            isLoading = false
            return
        }
        isLoading = true; errorMessage = nil; summary = nil
        calorieTrend = []; proteinTrend = []; carbTrend = []; fatTrend = []
        micronutrientAverages = []; mealDistributionData = []
        reportSpecificInsight = nil
        
        var effectiveStartDate: Date
        var effectiveEndDate: Date = Calendar.current.startOfDay(for: Date())
        var timeframeNameForSummary: String = timeframe.rawValue
        var daysInPeriodForSummary: Int

        if timeframe == .custom {
            guard let start = startDate, let end = endDate else {
                errorMessage = "Custom date range not provided."
                isLoading = false
                return
            }
            effectiveStartDate = Calendar.current.startOfDay(for: start)
            effectiveEndDate = Calendar.current.startOfDay(for: end)
            let components = Calendar.current.dateComponents([.day], from: effectiveStartDate, to: effectiveEndDate)
            daysInPeriodForSummary = (components.day ?? 0) + 1
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            timeframeNameForSummary = "\(formatter.string(from: effectiveStartDate)) - \(formatter.string(from: effectiveEndDate))"
        } else {
            switch timeframe {
            case .week:
                effectiveStartDate = Calendar.current.date(byAdding: .day, value: -6, to: effectiveEndDate)!
                daysInPeriodForSummary = 7
            case .month:
                effectiveStartDate = Calendar.current.date(byAdding: .day, value: -29, to: effectiveEndDate)!
                daysInPeriodForSummary = 30
            case .custom:
                errorMessage = "Invalid timeframe state for non-custom path."
                isLoading = false
                return
            }
        }
        
        dailyLogService.fetchDailyHistory(for: userID, startDate: effectiveStartDate, endDate: effectiveEndDate) { [weak self] (result: Result<[DailyLog], Error>) in
            guard let self = self else { return }
            Task { @MainActor in
                self.isLoading = false
                switch result {
                case .success(let logs):
                    if logs.isEmpty {
                        self.errorMessage = "No data available for the selected period."
                    } else {
                        self.processLogs(logs: logs, timeframeName: timeframeNameForSummary, totalDaysInPeriod: daysInPeriodForSummary)
                    }
                case .failure(let e):
                    self.errorMessage = "Error fetching report data: \(e.localizedDescription)"
                }
            }
        }
    }

    private func processLogs(logs: [DailyLog], timeframeName: String, totalDaysInPeriod: Int) {
        guard let goals = currentGoals else { return }
        let validLogs = logs.filter { !$0.meals.isEmpty || !($0.exercises?.isEmpty ?? true) }
        let daysWithActualLogEntries = validLogs.count
        
        guard daysWithActualLogEntries > 0 else {
            self.errorMessage = "No food or exercise logged in the selected period."
            self.summary = ReportSummary(timeframe: timeframeName, averageCalories: 0, averageProtein: 0, averageCarbs: 0, averageFats: 0, daysLogged: 0)
            return
        }
        
        var totCals=0.0, totProt=0.0, totCarb=0.0, totFat=0.0
        var totCa=0.0, totFe=0.0, totK=0.0, totNa=0.0, totVa=0.0, totVc=0.0, totVd=0.0
        var mealCals: [String: Double] = [:]
        var tmpCalT=[DateValuePoint](), tmpProtT=[DateValuePoint](), tmpCarbT=[DateValuePoint](), tmpFatT=[DateValuePoint]()

        for log in validLogs {
            let c = log.totalCalories(); let mac = log.totalMacros(); let mic = log.totalMicronutrients()
            totCals += c; totProt += mac.protein; totCarb += mac.carbs; totFat += mac.fats
            totCa += mic.calcium; totFe += mic.iron; totK += mic.potassium; totNa += mic.sodium; totVa += mic.vitaminA; totVc += mic.vitaminC; totVd += mic.vitaminD
            let date = Calendar.current.startOfDay(for: log.date)
            tmpCalT.append(DateValuePoint(date: date, value: c)); tmpProtT.append(DateValuePoint(date: date, value: mac.protein)); tmpCarbT.append(DateValuePoint(date: date, value: mac.carbs)); tmpFatT.append(DateValuePoint(date: date, value: mac.fats))
            for meal in log.meals { mealCals[meal.name, default: 0.0] += meal.foodItems.reduce(0) { $0 + $1.calories } }
        }

        let divisor = Double(daysWithActualLogEntries)
        let avgCals = totCals/divisor; let avgProt = totProt/divisor; let avgCarb = totCarb/divisor; let avgFat = totFat/divisor
        
        self.summary = ReportSummary(timeframe: timeframeName, averageCalories: avgCals, averageProtein: avgProt, averageCarbs: avgCarb, averageFats: avgFat, daysLogged: daysWithActualLogEntries)
        
        self.calorieTrend = tmpCalT.sorted{$0.date < $1.date}; self.proteinTrend = tmpProtT.sorted{$0.date < $1.date}; self.carbTrend = tmpCarbT.sorted{$0.date < $1.date}; self.fatTrend = tmpFatT.sorted{$0.date < $1.date}
        
        var tmpMicros: [MicroAverageDataPoint] = []
        if divisor > 0 {
            tmpMicros.append(MicroAverageDataPoint(name: "Calcium", unit: "mg", averageValue: totCa/divisor, goalValue: goals.calciumGoal ?? 1))
            tmpMicros.append(MicroAverageDataPoint(name: "Iron", unit: "mg", averageValue: totFe/divisor, goalValue: goals.ironGoal ?? 1))
            tmpMicros.append(MicroAverageDataPoint(name: "Potassium", unit: "mg", averageValue: totK/divisor, goalValue: goals.potassiumGoal ?? 1))
            tmpMicros.append(MicroAverageDataPoint(name: "Sodium", unit: "mg", averageValue: totNa/divisor, goalValue: goals.sodiumGoal ?? 2300))
            tmpMicros.append(MicroAverageDataPoint(name: "Vitamin A", unit: "mcg", averageValue: totVa/divisor, goalValue: goals.vitaminAGoal ?? 1))
            tmpMicros.append(MicroAverageDataPoint(name: "Vitamin C", unit: "mg", averageValue: totVc/divisor, goalValue: goals.vitaminCGoal ?? 1))
            tmpMicros.append(MicroAverageDataPoint(name: "Vitamin D", unit: "mcg", averageValue: totVd/divisor, goalValue: goals.vitaminDGoal ?? 1))
        }
        self.micronutrientAverages = tmpMicros.filter { $0.goalValue > 0 }
        
        self.reportSpecificInsight = generateReportInsight(from: validLogs)
        
        guard totCals > 0 && divisor > 0 else { self.mealDistributionData = []; return }
        var tmpMealDist: [MealDistributionDataPoint] = []
        for (n, c) in mealCals { tmpMealDist.append(MealDistributionDataPoint(mealName: n, totalCalories: c / divisor)) }
        self.mealDistributionData = tmpMealDist.sorted { $0.mealName < $1.mealName }
    }
    
    private func generateReportInsight(from logs: [DailyLog]) -> UserInsight? {
        guard !logs.isEmpty, let highestCalorieLog = logs.max(by: { $0.totalCalories() < $1.totalCalories() }) else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateString = formatter.string(from: highestCalorieLog.date)
        
        return UserInsight(
            title: "Highest Calorie Day",
            message: "Your highest calorie day in this period was \(dateString), with a total of \(String(format: "%.0f", highestCalorieLog.totalCalories())) calories logged.",
            category: .smartSuggestion
        )
    }
}
