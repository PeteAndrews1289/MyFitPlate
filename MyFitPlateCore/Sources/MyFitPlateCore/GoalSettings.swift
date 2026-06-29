import Foundation
import HealthKit
import SwiftUI
import Combine

/// Body-measurement unit helpers. Weight is stored internally in pounds and height in
/// centimeters; these convert only at the display/entry edges based on the user's preference
/// (`useMetricBodyUnits`, defaulted from the device locale). Internal storage stays lbs/cm.
public enum BodyUnits {
    public static let lbsPerKg = 2.2046226218
    public static let cmPerInch = 2.54

    /// Pounds -> the value shown in the user's chosen unit (kg if metric, else lbs).
    public static func weightDisplayValue(lbs: Double, metric: Bool) -> Double {
        metric ? lbs / lbsPerKg : lbs
    }

    /// A value the user typed (kg if metric, else lbs) -> pounds for storage.
    public static func weightToLbs(_ value: Double, metric: Bool) -> Double {
        metric ? value * lbsPerKg : value
    }

    public static func weightUnit(metric: Bool) -> String { metric ? "kg" : "lbs" }

    /// Formatted weight, e.g. "75.0 kg" or "165.3 lbs".
    public static func weightString(lbs: Double, metric: Bool, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f %@", weightDisplayValue(lbs: lbs, metric: metric), weightUnit(metric: metric))
    }

    public static func cm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * cmPerInch
    }
}

public class GoalSettings: ObservableObject {
    // Core Nutrition Goals
    @Published public var calories: Double?
    @Published public var protein: Double = 150
    @Published public var fats: Double = 70
    @Published public var carbs: Double = 250

    // User Stats
    @Published public var weight: Double = 150.0
    @Published public var height: Double = 170.0
    @Published public var age: Int = 25
    @Published public var gender: String = "Male"
    @Published public var activityLevel: Double = 1.2
    @Published public var goal: String = "Maintain"
    @Published public var targetWeight: Double?
    
    // Macro Split (%)
    @Published public var proteinPercentage: Double = 30.0
    @Published public var carbsPercentage: Double = 50.0
    @Published public var fatsPercentage: Double = 20.0
    
    // History & State
    @Published public var weightHistory: [(id: String, date: Date, weight: Double)] = []
    @Published public var isUpdatingGoal: Bool = false
    @Published public var nutritionViewIndex: Int = 0
    @Published public var lastCheckInDate: Date?
    
    public var isCheckInReady: Bool {
        guard calorieGoalMethod == .dynamicTDEE else { return false }
        let confidence = adaptiveGoalService?.dataConfidence
        guard confidence == .high || confidence == .medium else { return false }
        
        if let last = lastCheckInDate {
            if let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day, days >= 7 {
                return true
            }
            return false
        }
        return true
    }

    // Micronutrient Goals
    @Published public var calciumGoal: Double?
    @Published public var ironGoal: Double?
    @Published public var potassiumGoal: Double?
    @Published public var sodiumGoal: Double?
    @Published public var vitaminAGoal: Double?
    @Published public var vitaminCGoal: Double?
    @Published public var vitaminDGoal: Double?
    @Published public var vitaminB12Goal: Double?
    @Published public var folateGoal: Double?
    @Published public var waterGoal: Double = 64.0
    
    // Calculation Method
    @Published public var calorieGoalMethod: CalorieGoalMethod = .mifflinWithActivity { didSet { recalculateAllGoals() } }
    @Published public var suggestionProteins: [String] = ["Chicken", "Beef", "Fish"]
    @Published public var suggestionCuisines: [String] = ["Any"]
    @Published public var suggestionCarbs: [String] = ["Rice", "Potatoes", "Pasta"]
    @Published public var suggestionVeggies: [String] = ["Broccoli", "Bell Peppers"]
    @Published public var trainingIntent: String = "General Fitness"
    @Published public var reminderStyle: String = "Gentle"
    @Published public var maiaTone: String = "Balanced"
    @Published public var cookingStyle: String = "Macro-Focused Prep" // "Macro-Focused Prep", "Aesthetic Prep", "Daily Fresh", "Flexible"

    private var weightHistoryCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    public weak var dailyLogService: DailyLogService?
    public weak var adaptiveGoalService: AdaptiveGoalService?

    private let healthKitManager: HealthKitManaging
    
    public init(dailyLogService: DailyLogService? = nil, healthKitManager: HealthKitManaging = HealthKitManager.shared) {
        self.healthKitManager = healthKitManager
        self.dailyLogService = dailyLogService
        recalculateAllGoals()

        NotificationCenter.default.publisher(for: .didUpdateExerciseLog)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateAllGoals()
            }
            .store(in: &cancellables)
    }

    deinit {
        weightHistoryCancellable?.cancel()
        cancellables.forEach { $0.cancel() }
    }

    public func setupDependencies(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }
    
    // MARK: - Calculation Logic
    
    public func recalculateAllGoals() {
        DispatchQueue.main.async {
            self._recalculateCalorieGoal()
            self.calculateMicronutrientGoals()
            self.syncAnalyticsUserProperties()
        }
    }

    /// Mirrors key profile attributes into Firebase Analytics user properties so dashboards can be
    /// segmented (e.g. "how do losers vs. gainers use the app", "adaptive-TDEE vs. standard").
    private func syncAnalyticsUserProperties() {
        // AnalyticsManager.setUserProperty(goal.lowercased(), for: .goalType)
        // AnalyticsManager.setUserProperty(calorieGoalMethod.rawValue, for: .calorieMethod)
        // AnalyticsManager.setUserProperty(gender.lowercased(), for: .biologicalSex)
    }
    
    private func calculateBMR() -> Double {
        return GoalSettingsRules.calculateBMR(age: age, weightKg: weight * 0.453592, heightCm: height, gender: gender)
    }
    
    @MainActor
    private func _recalculateCalorieGoal() {
        if self.calorieGoalMethod == .custom {
            if self.calories == nil { self.calories = 2000 }
            let minimumGoal: Double = (gender.lowercased() == "male") ? 1500 : 1200
            if let current = self.calories, current < minimumGoal {
                self.calories = minimumGoal
            }
            self.updateMacros()
            return
        }
        
        let bmr = calculateBMR()
        let manualCaloriesBurned = dailyLogService?.currentDailyLog?.totalCaloriesBurnedFromManualExercises() ?? 0
        
        let finalCalculatedCalories = GoalSettingsRules.calculateCalorieGoal(
            bmr: bmr,
            goal: goal,
            gender: gender,
            calorieGoalMethod: calorieGoalMethod,
            activityLevel: activityLevel,
            adaptiveTDEE: adaptiveGoalService?.calculatedTDEE,
            manualCaloriesBurned: manualCaloriesBurned,
            currentCalories: calories
        )
        
        if self.calories == nil || abs((self.calories ?? 0) - finalCalculatedCalories) > 0.1 {
            self.calories = finalCalculatedCalories
            self.updateMacros()
        } else if self.calories != nil && (self.protein == 0 && self.fats == 0 && self.carbs == 0 && finalCalculatedCalories > 0) {
            self.updateMacros()
        }
    }
    
    private func updateMacros() {
        let macroGoals = GoalSettingsRules.updateMacros(
            calories: calories,
            proteinPercentage: proteinPercentage,
            carbsPercentage: carbsPercentage,
            fatsPercentage: fatsPercentage
        )
        
        if !macroGoals.validPercentages {
            self.proteinPercentage = 30
            self.carbsPercentage = 50
            self.fatsPercentage = 20
            DispatchQueue.main.async { self.updateMacros() }
            return
        }
        
        self.protein = macroGoals.protein
        self.carbs = macroGoals.carbs
        self.fats = macroGoals.fats
    }
    
    private func calculateMicronutrientGoals() {
        let micronutrientGoals = GoalSettingsRules.calculateMicronutrientGoals(age: age, gender: gender)
        
        self.calciumGoal = micronutrientGoals.calcium
        self.ironGoal = micronutrientGoals.iron
        self.potassiumGoal = micronutrientGoals.potassium
        self.sodiumGoal = micronutrientGoals.sodium
        self.vitaminAGoal = micronutrientGoals.vitaminA
        self.vitaminCGoal = micronutrientGoals.vitaminC
        self.vitaminDGoal = micronutrientGoals.vitaminD
        self.vitaminB12Goal = micronutrientGoals.vitaminB12
        self.folateGoal = micronutrientGoals.folate
        self.waterGoal = micronutrientGoals.water
    }
    
    // MARK: - Firestore Persistence
    
    @MainActor
    public func loadUserGoals(userID: String, completion: @escaping () -> Void = {}) {
        DIContainer.shared.settingsRepository.fetchUserGoals(userID: userID) { [weak self] data in
            guard let self = self else { completion(); return }
            
            var shouldUpdateFirestore = false
            
            if var data = data {
                // Load core stats
                if data["weight"] == nil { data["weight"] = self.weight; shouldUpdateFirestore = true }
                if data["height"] == nil { data["height"] = self.height; shouldUpdateFirestore = true }
                if data["age"] == nil { data["age"] = self.age; shouldUpdateFirestore = true }
                if data["gender"] == nil { data["gender"] = self.gender; shouldUpdateFirestore = true }
                if data["calorieGoalMethod"] == nil { data["calorieGoalMethod"] = self.calorieGoalMethod.rawValue; shouldUpdateFirestore = true }

                self.weight = data["weight"] as? Double ?? self.weight
                self.height = data["height"] as? Double ?? self.height
                self.age = data["age"] as? Int ?? self.age
                self.gender = data["gender"] as? String ?? self.gender
                if let methodStr = data["calorieGoalMethod"] as? String {
                    self.calorieGoalMethod = CalorieGoalMethod(rawValue: methodStr) ?? self.calorieGoalMethod
                }
                
                var goalsMap = data["goals"] as? [String: Any] ?? [:]
                
                // Load or default new fields
                if goalsMap["proteinPercentage"] == nil { goalsMap["proteinPercentage"] = self.proteinPercentage; shouldUpdateFirestore = true }
                if goalsMap["carbsPercentage"] == nil { goalsMap["carbsPercentage"] = self.carbsPercentage; shouldUpdateFirestore = true }
                if goalsMap["fatsPercentage"] == nil { goalsMap["fatsPercentage"] = self.fatsPercentage; shouldUpdateFirestore = true }
                if goalsMap["activityLevel"] == nil { goalsMap["activityLevel"] = self.activityLevel; shouldUpdateFirestore = true }
                if goalsMap["goal"] == nil { goalsMap["goal"] = self.goal; shouldUpdateFirestore = true }
                if goalsMap["waterGoal"] == nil { goalsMap["waterGoal"] = self.waterGoal; shouldUpdateFirestore = true }
                if goalsMap["trainingIntent"] == nil { goalsMap["trainingIntent"] = self.trainingIntent; shouldUpdateFirestore = true }
                if goalsMap["reminderStyle"] == nil { goalsMap["reminderStyle"] = self.reminderStyle; shouldUpdateFirestore = true }
                if goalsMap["maiaTone"] == nil { goalsMap["maiaTone"] = self.maiaTone; shouldUpdateFirestore = true }
                if goalsMap["cookingStyle"] == nil { goalsMap["cookingStyle"] = self.cookingStyle; shouldUpdateFirestore = true }

                if let timestamp = data["lastCheckInDate"] as? Date {
                    self.lastCheckInDate = timestamp
                } else if let timestamp = goalsMap["lastCheckInDate"] as? Date {
                    // For backward compatibility with Firestore Date
                    self.lastCheckInDate = timestamp
                }

                // Handle target weight (might be null)
                self.targetWeight = goalsMap["targetWeight"] as? Double
                if self.targetWeight == nil {
                     // Backward compatibility check
                    if let topLevelTargetWeight = data["targetWeight"] as? Double {
                        self.targetWeight = topLevelTargetWeight
                        goalsMap["targetWeight"] = topLevelTargetWeight
                        shouldUpdateFirestore = true
                    } else if goalsMap["targetWeight"] == nil {
                        goalsMap["targetWeight"] = NSNull()
                        shouldUpdateFirestore = true
                    }
                }
                
                // Load AI Preferences
                self.suggestionProteins = goalsMap["suggestionProteins"] as? [String] ?? self.suggestionProteins
                self.suggestionCuisines = goalsMap["suggestionCuisines"] as? [String] ?? self.suggestionCuisines
                self.suggestionCarbs = goalsMap["suggestionCarbs"] as? [String] ?? self.suggestionCarbs
                self.suggestionVeggies = goalsMap["suggestionVeggies"] as? [String] ?? self.suggestionVeggies
                self.trainingIntent = goalsMap["trainingIntent"] as? String ?? self.trainingIntent
                self.reminderStyle = goalsMap["reminderStyle"] as? String ?? self.reminderStyle
                self.maiaTone = goalsMap["maiaTone"] as? String ?? self.maiaTone
                self.cookingStyle = goalsMap["cookingStyle"] as? String ?? self.cookingStyle
                
                data["goals"] = goalsMap

                self.proteinPercentage = goalsMap["proteinPercentage"] as? Double ?? self.proteinPercentage
                self.carbsPercentage = goalsMap["carbsPercentage"] as? Double ?? self.carbsPercentage
                self.fatsPercentage = goalsMap["fatsPercentage"] as? Double ?? self.fatsPercentage
                self.activityLevel = goalsMap["activityLevel"] as? Double ?? self.activityLevel
                self.goal = goalsMap["goal"] as? String ?? self.goal
                self.waterGoal = goalsMap["waterGoal"] as? Double ?? self.waterGoal

                // Restore saved calorie/macro targets so CUSTOM goals survive launch — the .custom
                // method preserves self.calories instead of recomputing, so without this a custom
                // user gets reset to the 2000 default every cold start.
                if let savedCalories = goalsMap["calories"] as? Double, savedCalories > 0 {
                    self.calories = savedCalories
                }
                self.protein = goalsMap["protein"] as? Double ?? self.protein
                self.carbs = goalsMap["carbs"] as? Double ?? self.carbs
                self.fats = goalsMap["fats"] as? Double ?? self.fats
            }
            
            if shouldUpdateFirestore {
                self.saveUserGoals(userID: userID)
            }
            
            DispatchQueue.main.async {
                self.recalculateAllGoals()
                completion()
            }
        }
    }

    public func saveUserGoals(userID: String) {
        guard !userID.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.recalculateAllGoals()
            var goalsDict: [String:Any] = [
                "calories": self.calories ?? 0, "protein": self.protein, "fats": self.fats, "carbs": self.carbs,
                "proteinPercentage": self.proteinPercentage, "carbsPercentage": self.carbsPercentage, "fatsPercentage": self.fatsPercentage,
                "activityLevel": self.activityLevel, "goal": self.goal, "targetWeight": self.targetWeight ?? NSNull(),
                "calciumGoal": self.calciumGoal ?? NSNull(), "ironGoal": self.ironGoal ?? NSNull(), "potassiumGoal": self.potassiumGoal ?? NSNull(),
                "sodiumGoal": self.sodiumGoal ?? NSNull(), "vitaminAGoal": self.vitaminAGoal ?? NSNull(), "vitaminCGoal": self.vitaminCGoal ?? NSNull(),
                "vitaminDGoal": self.vitaminDGoal ?? NSNull(), "waterGoal": self.waterGoal, "vitaminB12Goal": self.vitaminB12Goal ?? NSNull(), "folateGoal": self.folateGoal ?? NSNull(),
                // Saving AI Preferences
                "suggestionProteins": self.suggestionProteins, "suggestionCuisines": self.suggestionCuisines,
                "suggestionCarbs": self.suggestionCarbs, "suggestionVeggies": self.suggestionVeggies,
                "trainingIntent": self.trainingIntent, "reminderStyle": self.reminderStyle, "maiaTone": self.maiaTone,
                "cookingStyle": self.cookingStyle
            ]
            if let lastDate = self.lastCheckInDate {
                goalsDict["lastCheckInDate"] = lastDate
            }
            let userData:[String:Any] = [
                "goals": goalsDict, "height": self.height, "weight": self.weight, "age": self.age, "gender": self.gender, "isFirstLogin": false,
                "calorieGoalMethod": self.calorieGoalMethod.rawValue
            ]
            Task {
                try? await DIContainer.shared.settingsRepository.saveUserGoals(userID: userID, data: userData)
            }
        }
    }
    
    public func applyWeeklyCheckIn(userID: String, newCalories: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let minimumGoal: Double = (self.gender.lowercased() == "male") ? 1500 : 1200
            self.calories = max(minimumGoal, newCalories)
            self.lastCheckInDate = Date()
            self.updateMacros()
            self.saveUserGoals(userID: userID)
        }
    }
    
    // MARK: - Weight Tracking
    
    @MainActor
    public func loadWeightHistory() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        weightHistoryCancellable?.cancel()
        weightHistoryCancellable = DIContainer.shared.settingsRepository.weightHistoryPublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] history in
                self?.weightHistory = history
            })
    }
    
    public func updateUserWeight(_ newWeight: Double, date: Date = Date()) {
    Task { @MainActor in
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        // Only a present-day weigh-in should move the "current" weight and re-run goal math.
        // A back-dated entry just fills in history so the trend and adaptive TDEE stay accurate.
            if Calendar.current.isDateInToday(date) {
                self.weight = newWeight
                self.recalculateAllGoals()
                self.saveUserGoals(userID: userID)
            }
        
        do {
            try await DIContainer.shared.settingsRepository.saveWeightEntry(userID: userID, weight: newWeight, date: date)
            self.loadWeightHistory()
        } catch {
            AppLog.data.error("Failed to save weight sample: \(error.localizedDescription)")
        }
    }
    self.healthKitManager.saveWeightSample(weightLbs: newWeight, date: date)
}
    
    public func deleteWeightEntry(entryID: String, completion: @escaping (Error?) -> Void) {
    Task { @MainActor in
        guard let userID = DIContainer.shared.authService.currentUserID else { completion(NSError(domain:"App",code:401)); return }
        do {
            try await DIContainer.shared.settingsRepository.deleteWeightEntry(userID: userID, entryID: entryID)
            completion(nil)
        } catch {
            completion(error)
        }
    }
}
    
    // MARK: - Helpers
    
    public func getHeightInFeetAndInches() -> (feet: Int, inches: Int) {
        let hCm = self.height; guard hCm > 0 else { return (0,0) }; let totalInches = Int(round(hCm / 2.54))
        return (totalInches / 12, totalInches % 12)
    }
    
    public func setHeight(feet: Int, inches: Int) {
        let totalInches = Double((feet * 12) + inches); guard totalInches > 0 else { return }
        DispatchQueue.main.async {
            let newHeightCm = totalInches * 2.54
            if abs(self.height - newHeightCm) > 0.1 { self.height = newHeightCm; self.recalculateAllGoals() }
        }
    }
    
    public func calculateWeightProgress() -> Double? {
        guard let target = targetWeight else { return nil }
        let initial = weightHistory.first?.weight ?? weight
        let totalNeeded = initial - target
        guard abs(totalNeeded) > 0.01 else { return abs(weight - target) < 0.01 ? 100.0 : 0.0 }
        let changeSoFar = initial - weight
        return max(0.0, min(100.0, (changeSoFar / totalNeeded) * 100.0))
    }

    public func calculateWeeklyWeightChange() -> Double? {
        guard weightHistory.count >= 2 else { return nil }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: end) else { return nil }
        let recent = weightHistory.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
        guard recent.count >= 2, let first = recent.first, let last = recent.last,
              let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day, days > 0 else { return nil }
        let change = last.weight - first.weight
        return (change / Double(days)) * 7
    }
    
    public func getWeightStats(for periodData: [(id: String, date: Date, weight: Double)]) -> (trend: Double?, highest: Double?, lowest: Double?, dailyRate: Double?) {
        guard !periodData.isEmpty else { return (nil, nil, nil, nil) }
        let sortedData = periodData.sorted { $0.date < $1.date }
        let highest = sortedData.max(by: { $0.weight < $1.weight })?.weight
        let lowest = sortedData.min(by: { $0.weight < $1.weight })?.weight
        var trend: Double? = nil, dailyRate: Double? = nil
        if sortedData.count >= 2, let first = sortedData.first, let last = sortedData.last {
            trend = last.weight - first.weight
            if let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day, days > 0 {
                dailyRate = (trend ?? 0) / Double(days)
            }
        }
        return (trend, highest, lowest, dailyRate)
    }
    
    public func updateUserAsOnboarded(userID: String) {
        guard !userID.isEmpty else { return }
        Task {
            try? await DIContainer.shared.settingsRepository.updateUserAsOnboarded(userID: userID)
        }
    }
}

// MARK: - AdaptiveGoalService
public class AdaptiveGoalService: ObservableObject {
    public init() {}
    @Published public var calculatedTDEE: Double?
    @Published public var weightTrendLine: [Double] = []
    @Published public var calorieTrendLine: [Double] = []
    
    @Published public var last21DaysCalorieAverage: Double?
    @Published public var weightChangeRatePerDay: Double?
    @Published public var dataConfidence: DataConfidence = .insufficient
    /// How many weigh-ins / food-log days exist in the last 21 days. Drives the
    /// "progress to your first estimate" UI shown before there's enough data for a TDEE.
    @Published public var recentWeighInCount: Int = 0
    @Published public var recentLogCount: Int = 0
    @Published public var lastCalculationDate: Date?
    
    public enum DataConfidence: String {
        case high = "High Confidence"
        case medium = "Medium Confidence"
        case low = "Low Confidence"
        case insufficient = "Needs More Data"
        
        public var colorName: String {
            switch self {
            case .high: return "accentPositive"
            case .medium: return "orange"
            case .low: return "red"
            case .insufficient: return "gray"
            }
        }
    }

    public struct ExpenditureSnapshot: Equatable {
        public let recentWeighInCount: Int
        public let recentLogCount: Int
        public let last21DaysCalorieAverage: Double?
        public let weightChangeRatePerDay: Double?
        public let calculatedTDEE: Double?
        public let dataConfidence: DataConfidence

        public init(
            recentWeighInCount: Int,
            recentLogCount: Int,
            last21DaysCalorieAverage: Double?,
            weightChangeRatePerDay: Double?,
            calculatedTDEE: Double?,
            dataConfidence: DataConfidence
        ) {
            self.recentWeighInCount = recentWeighInCount
            self.recentLogCount = recentLogCount
            self.last21DaysCalorieAverage = last21DaysCalorieAverage
            self.weightChangeRatePerDay = weightChangeRatePerDay
            self.calculatedTDEE = calculatedTDEE
            self.dataConfidence = dataConfidence
        }
    }

    public static func expenditureSnapshot(
        weightHistory: [(id: String, date: Date, weight: Double)],
        dailyLogs: [DailyLog],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> ExpenditureSnapshot? {
        let today = calendar.startOfDay(for: today)
        guard let twentyOneDaysAgo = calendar.date(byAdding: .day, value: -21, to: today) else { return nil }

        let recentWeights = weightHistory.filter { $0.date >= twentyOneDaysAgo }.sorted { $0.date < $1.date }
        let recentLogs = dailyLogs.filter { $0.date >= twentyOneDaysAgo }.sorted { $0.date < $1.date }

        let recentWeighInCount = recentWeights.count
        let recentLogCount = recentLogs.count

        guard recentWeighInCount >= 7, recentLogCount >= 10 else {
            return ExpenditureSnapshot(
                recentWeighInCount: recentWeighInCount,
                recentLogCount: recentLogCount,
                last21DaysCalorieAverage: nil,
                weightChangeRatePerDay: nil,
                calculatedTDEE: nil,
                dataConfidence: .insufficient
            )
        }

        var emaWeights: [Date: Double] = [:]
        guard let firstRecord = recentWeights.first else { return nil }
        var currentEMA = firstRecord.weight
        let smoothingFactor = 2.0 / (7.0 + 1.0)

        for record in recentWeights {
            currentEMA = (record.weight - currentEMA) * smoothingFactor + currentEMA
            let dayStart = calendar.startOfDay(for: record.date)
            emaWeights[dayStart] = currentEMA
        }

        guard let firstEmaRecord = recentWeights.first, let lastEmaRecord = recentWeights.last else { return nil }
        let firstDay = calendar.startOfDay(for: firstEmaRecord.date)
        let lastDay = calendar.startOfDay(for: lastEmaRecord.date)

        guard let startWeight = emaWeights[firstDay], let endWeight = emaWeights[lastDay] else { return nil }
        let daysBetween = Double(calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 1)

        let ratePerDay = daysBetween > 0 ? (endWeight - startWeight) / daysBetween : 0

        let validLogs = recentLogs.filter { $0.totalCalories() > 500 }
        let totalCaloriesLogged = validLogs.reduce(0.0) { $0 + $1.totalCalories() }
        let averageCalories = validLogs.isEmpty ? 0 : totalCaloriesLogged / Double(validLogs.count)

        let dailyCalorieDeficitOrSurplus = ratePerDay * 3500.0
        let rawTDEE = averageCalories - dailyCalorieDeficitOrSurplus

        let loggingConsistency = Double(validLogs.count) / 21.0
        let weightConsistency = Double(recentWeights.count) / 21.0

        var confidence: DataConfidence = .low
        if loggingConsistency > 0.8 && weightConsistency > 0.6 {
            confidence = .high
        } else if loggingConsistency > 0.6 && weightConsistency > 0.4 {
            confidence = .medium
        }

        return ExpenditureSnapshot(
            recentWeighInCount: recentWeighInCount,
            recentLogCount: recentLogCount,
            last21DaysCalorieAverage: averageCalories,
            weightChangeRatePerDay: ratePerDay,
            calculatedTDEE: max(1000, min(rawTDEE, 5000)),
            dataConfidence: confidence
        )
    }

    /// Calculate the true TDEE based on weight changes and caloric intake over the last 21 days.
    public func calculateExpenditure(weightHistory: [(id: String, date: Date, weight: Double)], dailyLogs: [DailyLog]) {
        guard let snapshot = Self.expenditureSnapshot(weightHistory: weightHistory, dailyLogs: dailyLogs) else { return }

        DispatchQueue.main.async {
            self.recentWeighInCount = snapshot.recentWeighInCount
            self.recentLogCount = snapshot.recentLogCount

            if let calculatedTDEE = snapshot.calculatedTDEE {
                self.last21DaysCalorieAverage = snapshot.last21DaysCalorieAverage
                self.weightChangeRatePerDay = snapshot.weightChangeRatePerDay
                self.calculatedTDEE = calculatedTDEE
                self.dataConfidence = snapshot.dataConfidence
            } else {
                self.dataConfidence = .insufficient
                self.calculatedTDEE = nil
            }
        }
    }
    
    public func fetchAndCalculate(userID: String, goalSettings: GoalSettings, dailyLogService: DailyLogService) async {
        let calendar = Calendar.current
        let today = Date()
        guard let twentyOneDaysAgo = calendar.date(byAdding: .day, value: -21, to: today) else { return }

        let result = await dailyLogService.fetchDailyHistory(for: userID, startDate: twentyOneDaysAgo, endDate: today)
        switch result {
        case .success(let logs):
            self.calculateExpenditure(weightHistory: goalSettings.weightHistory, dailyLogs: logs)
            // Close the loop: if the user is already on adaptive TDEE, refresh their
            // calorie/macro goals so the target tracks the freshly calculated metabolism.
            // calculatedTDEE is assigned on the main queue inside calculateExpenditure, so this
            // main-queue hop is guaranteed to run after that assignment (FIFO ordering).
            await MainActor.run {
                if goalSettings.calorieGoalMethod == .dynamicTDEE {
                    goalSettings.recalculateAllGoals()
                }
            }
        case .failure(let error):
            print("AdaptiveGoalService Error: \(error.localizedDescription)")
        }
    }

    /// Throttled wrapper — recalculates at most once per calendar day. Safe to call on every Home
    /// appearance so the weekly check-in can surface without the user first visiting Reports.
    public func fetchAndCalculateIfNeeded(userID: String, goalSettings: GoalSettings, dailyLogService: DailyLogService) async {
        let alreadyCalculatedToday = await MainActor.run { () -> Bool in
            if let last = self.lastCalculationDate {
                return Calendar.current.isDateInToday(last)
            }
            return false
        }
        guard !alreadyCalculatedToday else { return }

        await fetchAndCalculate(userID: userID, goalSettings: goalSettings, dailyLogService: dailyLogService)
        await MainActor.run { self.lastCalculationDate = Date() }
    }
}
