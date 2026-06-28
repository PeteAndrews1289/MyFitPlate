import Foundation
import FirebaseAuth
import HealthKit
import FirebaseFirestore
import SwiftUI
import Combine

/// Body-measurement unit helpers. Weight is stored internally in pounds and height in
/// centimeters; these convert only at the display/entry edges based on the user's preference
/// (`useMetricBodyUnits`, defaulted from the device locale). Internal storage stays lbs/cm.
enum BodyUnits {
    static let lbsPerKg = 2.2046226218
    static let cmPerInch = 2.54

    /// Pounds -> the value shown in the user's chosen unit (kg if metric, else lbs).
    static func weightDisplayValue(lbs: Double, metric: Bool) -> Double {
        metric ? lbs / lbsPerKg : lbs
    }

    /// A value the user typed (kg if metric, else lbs) -> pounds for storage.
    static func weightToLbs(_ value: Double, metric: Bool) -> Double {
        metric ? value * lbsPerKg : value
    }

    static func weightUnit(metric: Bool) -> String { metric ? "kg" : "lbs" }

    /// Formatted weight, e.g. "75.0 kg" or "165.3 lbs".
    static func weightString(lbs: Double, metric: Bool, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f %@", weightDisplayValue(lbs: lbs, metric: metric), weightUnit(metric: metric))
    }

    static func cm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * cmPerInch
    }
}

class GoalSettings: ObservableObject {
    // Core Nutrition Goals
    @Published var calories: Double?
    @Published var protein: Double = 150
    @Published var fats: Double = 70
    @Published var carbs: Double = 250
    
    // User Stats
    @Published var weight: Double = 150.0
    @Published var height: Double = 170.0
    @Published var age: Int = 25
    @Published var gender: String = "Male"
    @Published var activityLevel: Double = 1.2
    @Published var goal: String = "Maintain"
    @Published var targetWeight: Double?
    
    // Macro Split (%)
    @Published var proteinPercentage: Double = 30.0
    @Published var carbsPercentage: Double = 50.0
    @Published var fatsPercentage: Double = 20.0
    
    // History & State
    @Published var weightHistory: [(id: String, date: Date, weight: Double)] = []
    @Published var isUpdatingGoal: Bool = false
    @Published var nutritionViewIndex: Int = 0
    @Published var lastCheckInDate: Date?
    
    var isCheckInReady: Bool {
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
    @Published var calciumGoal: Double?
    @Published var ironGoal: Double?
    @Published var potassiumGoal: Double?
    @Published var sodiumGoal: Double?
    @Published var vitaminAGoal: Double?
    @Published var vitaminCGoal: Double?
    @Published var vitaminDGoal: Double?
    @Published var vitaminB12Goal: Double?
    @Published var folateGoal: Double?
    @Published var waterGoal: Double = 64.0
    
    // Calculation Method
    @Published var calorieGoalMethod: CalorieGoalMethod = .mifflinWithActivity { didSet { recalculateAllGoals() } }
    @Published var suggestionProteins: [String] = ["Chicken", "Beef", "Fish"]
    @Published var suggestionCuisines: [String] = ["Any"]
    @Published var suggestionCarbs: [String] = ["Rice", "Potatoes", "Pasta"]
    @Published var suggestionVeggies: [String] = ["Broccoli", "Bell Peppers"]
    @Published var trainingIntent: String = "General Fitness"
    @Published var reminderStyle: String = "Gentle"
    @Published var maiaTone: String = "Balanced"
    @Published var cookingStyle: String = "Macro-Focused Prep" // "Macro-Focused Prep", "Aesthetic Prep", "Daily Fresh", "Flexible"

    private var weightHistoryCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    weak var dailyLogService: DailyLogService?
    weak var adaptiveGoalService: AdaptiveGoalService?

    private let healthKitManager: HealthKitManaging
    
    init(dailyLogService: DailyLogService? = nil, healthKitManager: HealthKitManaging = HealthKitManager.shared) {
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

    func setupDependencies(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }
    
    // MARK: - Calculation Logic
    
    func recalculateAllGoals() {
        DispatchQueue.main.async {
            self._recalculateCalorieGoal()
            self.calculateMicronutrientGoals()
            self.syncAnalyticsUserProperties()
        }
    }

    /// Mirrors key profile attributes into Firebase Analytics user properties so dashboards can be
    /// segmented (e.g. "how do losers vs. gainers use the app", "adaptive-TDEE vs. standard").
    private func syncAnalyticsUserProperties() {
        AnalyticsManager.setUserProperty(goal.lowercased(), for: .goalType)
        AnalyticsManager.setUserProperty(calorieGoalMethod.rawValue, for: .calorieMethod)
        AnalyticsManager.setUserProperty(gender.lowercased(), for: .biologicalSex)
    }
    
    private func calculateBMR() -> Double {
        guard age > 0 else { return 1500 }
        let kg = weight * 0.453592
        let cm = height
        if gender.lowercased() == "male" {
            return (10 * kg) + (6.25 * cm) - (5 * Double(age)) + 5
        } else {
            return (10 * kg) + (6.25 * cm) - (5 * Double(age)) - 161
        }
    }
    
    @MainActor
    private func _recalculateCalorieGoal() {
        let bmr = calculateBMR()
        var calculatedCalories: Double
        var calorieAdjustmentForWeightGoal: Double = 0
        
        switch goal {
        case "Lose": calorieAdjustmentForWeightGoal = -250
        case "Gain": calorieAdjustmentForWeightGoal = 250
        default: break
        }
        
        let minimumGoal: Double = (gender.lowercased() == "male") ? 1500 : 1200
        
        switch self.calorieGoalMethod {
        case .custom:
            if self.calories == nil { self.calories = 2000 }
            if let current = self.calories, current < minimumGoal {
                self.calories = minimumGoal
            }
            self.updateMacros()
            return
        case .mifflinWithActivity:
            let maintenanceCalories = bmr * activityLevel
            calculatedCalories = maintenanceCalories + calorieAdjustmentForWeightGoal
            
        case .dynamicTDEE:
            if let adaptiveTDEE = self.adaptiveGoalService?.calculatedTDEE {
                calculatedCalories = adaptiveTDEE + calorieAdjustmentForWeightGoal
            } else {
                // Fallback if we don't have enough data
                calculatedCalories = bmr + (self.dailyLogService?.currentDailyLog?.totalCaloriesBurnedFromManualExercises() ?? 0) + calorieAdjustmentForWeightGoal
            }
        }

        let finalCalculatedCalories = max(minimumGoal, calculatedCalories)
        
        if self.calories == nil || abs((self.calories ?? 0) - finalCalculatedCalories) > 0.1 {
            self.calories = finalCalculatedCalories
            self.updateMacros()
        } else if self.calories != nil && (self.protein == 0 && self.fats == 0 && self.carbs == 0 && finalCalculatedCalories > 0) {
            self.updateMacros()
        }
    }
    
    private func updateMacros() {
        guard let calGoal = self.calories, calGoal > 0 else {
            self.protein = 150; self.fats = 70; self.carbs = 250
            return
        }
        let totalPct = proteinPercentage + carbsPercentage + fatsPercentage
        guard abs(totalPct - 100.0) < 1.0 else {
            // Reset to defaults if percentages are invalid
            self.proteinPercentage = 30; self.carbsPercentage = 50; self.fatsPercentage = 20
            DispatchQueue.main.async { self.updateMacros() }
            return
        }
        let pCals = (proteinPercentage / 100) * calGoal
        let cCals = (carbsPercentage / 100) * calGoal
        let fCals = (fatsPercentage / 100) * calGoal
        self.protein = pCals / 4
        self.carbs = cCals / 4
        self.fats = fCals / 9
    }
    
    private func calculateMicronutrientGoals() {
        // Basic DRI approximations based on age/gender
        let age = self.age
        let gender = self.gender.lowercased()
        
        switch age {
            case 0...3: calciumGoal = 700; case 4...8: calciumGoal = 1000; case 9...18: calciumGoal = 1300
            case 19...50: calciumGoal = 1000; case 51...70: calciumGoal = (gender == "female") ? 1200 : 1000
            case 71...: calciumGoal = 1200; default: calciumGoal = 1000
        }
        switch age {
            case 0...3: ironGoal = 7; case 4...8: ironGoal = 10; case 9...13: ironGoal = 8
            case 14...18: ironGoal = (gender == "female") ? 15 : 11
            case 19...50: ironGoal = (gender == "female") ? 18 : 8
            case 51...: ironGoal = 8; default: ironGoal = (gender == "female") ? 18 : 8
        }
        switch age {
            case 0...3: potassiumGoal = 2000; case 4...8: potassiumGoal = 2300
            case 9...13: potassiumGoal = (gender == "female") ? 2300 : 2500
            case 14...18: potassiumGoal = (gender == "female") ? 2300 : 3000
            case 19...: potassiumGoal = (gender == "female") ? 2600 : 3400
            default: potassiumGoal = (gender == "female") ? 2600 : 3400
        }
        sodiumGoal = 2300
        switch age {
            case 0...3: vitaminAGoal = 300; case 4...8: vitaminAGoal = 400; case 9...13: vitaminAGoal = 600
            case 14...18: vitaminAGoal = (gender == "female") ? 700 : 900
            case 19...: vitaminAGoal = (gender == "female") ? 700 : 900
            default: vitaminAGoal = (gender == "female") ? 700 : 900
        }
        switch age {
            case 0...3: vitaminCGoal = 15; case 4...8: vitaminCGoal = 25; case 9...13: vitaminCGoal = 45
            case 14...18: vitaminCGoal = (gender == "female") ? 65 : 75
            case 19...: vitaminCGoal = (gender == "female") ? 75 : 90
            default: vitaminCGoal = (gender == "female") ? 75 : 90
        }
        switch age {
            case 0...70: vitaminDGoal = 15; case 71...: vitaminDGoal = 20; default: vitaminDGoal = 15
        }
        vitaminB12Goal = 2.4
        folateGoal = 400
    }
    
    // MARK: - Firestore Persistence
    
    @MainActor
    func loadUserGoals(userID: String, completion: @escaping () -> Void = {}) {
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

                if let timestamp = goalsMap["lastCheckInDate"] as? Date {
                    self.lastCheckInDate = timestamp
                } else if let timestamp = goalsMap["lastCheckInDate"] as? Timestamp {
                    // For backward compatibility with Firestore Timestamp
                    self.lastCheckInDate = timestamp.dateValue()
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

    func saveUserGoals(userID: String) {
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
                "goals": goalsDict, "height": self.height, "age": self.age, "gender": self.gender, "isFirstLogin": false,
                "calorieGoalMethod": self.calorieGoalMethod.rawValue
            ]
            Task {
                try? await DIContainer.shared.settingsRepository.saveUserGoals(userID: userID, data: userData)
            }
        }
    }
    
    func applyWeeklyCheckIn(userID: String, newCalories: Double) {
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
    func loadWeightHistory() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        weightHistoryCancellable?.cancel()
        weightHistoryCancellable = DIContainer.shared.settingsRepository.weightHistoryPublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] history in
                self?.weightHistory = history
            })
    }
    
    func updateUserWeight(_ newWeight: Double, date: Date = Date()) {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        // Only a present-day weigh-in should move the "current" weight and re-run goal math.
        // A back-dated entry just fills in history so the trend and adaptive TDEE stay accurate.
        if Calendar.current.isDateInToday(date) {
            DispatchQueue.main.async {
                self.weight = newWeight
                self.recalculateAllGoals()
            }
        }

        Task {
            try? await DIContainer.shared.settingsRepository.saveWeightEntry(userID: userID, weight: newWeight, date: date)
        }

        self.healthKitManager.saveWeightSample(weightLbs: newWeight, date: date)
    }
    
    func deleteWeightEntry(entryID: String, completion: @escaping (Error?) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else { completion(NSError(domain:"App",code:401));return}
        Task {
            do {
                try await DIContainer.shared.settingsRepository.deleteWeightEntry(userID: userID, entryID: entryID)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }
    
    // MARK: - Helpers
    
    func getHeightInFeetAndInches() -> (feet: Int, inches: Int) {
        let hCm = self.height; guard hCm > 0 else { return (0,0) }; let totalInches = Int(round(hCm / 2.54))
        return (totalInches / 12, totalInches % 12)
    }
    
    func setHeight(feet: Int, inches: Int) {
        let totalInches = Double((feet * 12) + inches); guard totalInches > 0 else { return }
        DispatchQueue.main.async {
            let newHeightCm = totalInches * 2.54
            if abs(self.height - newHeightCm) > 0.1 { self.height = newHeightCm; self.recalculateAllGoals() }
        }
    }
    
    func calculateWeightProgress() -> Double? {
        guard let target = targetWeight else { return nil }
        let initial = weightHistory.first?.weight ?? weight
        let totalNeeded = initial - target
        guard abs(totalNeeded) > 0.01 else { return abs(weight - target) < 0.01 ? 100.0 : 0.0 }
        let changeSoFar = initial - weight
        return max(0.0, min(100.0, (changeSoFar / totalNeeded) * 100.0))
    }

    func calculateWeeklyWeightChange() -> Double? {
        guard weightHistory.count >= 2 else { return nil }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: end) else { return nil }
        let recent = weightHistory.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
        guard recent.count >= 2, let first = recent.first, let last = recent.last,
              let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day, days > 0 else { return nil }
        let change = last.weight - first.weight
        return (change / Double(days)) * 7
    }
    
    func getWeightStats(for periodData: [(id: String, date: Date, weight: Double)]) -> (trend: Double?, highest: Double?, lowest: Double?, dailyRate: Double?) {
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
    
    func updateUserAsOnboarded(userID: String) {
        guard !userID.isEmpty else { return }
        Task {
            try? await DIContainer.shared.settingsRepository.updateUserAsOnboarded(userID: userID)
        }
    }
}

// MARK: - AdaptiveGoalService
class AdaptiveGoalService: ObservableObject {
    @Published var calculatedTDEE: Double?
    @Published var weightTrendLine: [Double] = []
    @Published var calorieTrendLine: [Double] = []
    
    @Published var last21DaysCalorieAverage: Double?
    @Published var weightChangeRatePerDay: Double?
    @Published var dataConfidence: DataConfidence = .insufficient
    /// How many weigh-ins / food-log days exist in the last 21 days. Drives the
    /// "progress to your first estimate" UI shown before there's enough data for a TDEE.
    @Published var recentWeighInCount: Int = 0
    @Published var recentLogCount: Int = 0
    @Published var lastCalculationDate: Date?
    
    enum DataConfidence: String {
        case high = "High Confidence"
        case medium = "Medium Confidence"
        case low = "Low Confidence"
        case insufficient = "Needs More Data"
        
        var colorName: String {
            switch self {
            case .high: return "accentPositive"
            case .medium: return "orange"
            case .low: return "red"
            case .insufficient: return "gray"
            }
        }
    }
    
    /// Calculate the true TDEE based on weight changes and caloric intake over the last 21 days.
    func calculateExpenditure(weightHistory: [(id: String, date: Date, weight: Double)], dailyLogs: [DailyLog]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let twentyOneDaysAgo = calendar.date(byAdding: .day, value: -21, to: today) else { return }
        
        // 1. Filter data to last 21 days
        let recentWeights = weightHistory.filter { $0.date >= twentyOneDaysAgo }.sorted { $0.date < $1.date }
        let recentLogs = dailyLogs.filter { $0.date >= twentyOneDaysAgo }.sorted { $0.date < $1.date }

        // Always expose progress counts so the UI can show how close the user is to a result.
        DispatchQueue.main.async {
            self.recentWeighInCount = recentWeights.count
            self.recentLogCount = recentLogs.count
        }
        
        // We need at least 7 days of weight data and 10 days of food logs to make a semi-confident guess.
        if recentWeights.count < 7 || recentLogs.count < 10 {
            DispatchQueue.main.async {
                self.dataConfidence = .insufficient
                self.calculatedTDEE = nil
            }
            return
        }
        
        // 2. Exponential Moving Average (EMA) of Weight
        // EMA smooths out daily water weight fluctuations to find the true biological tissue trend.
        var emaWeights: [Date: Double] = [:]
        guard let firstRecord = recentWeights.first else { return }
        var currentEMA: Double = firstRecord.weight
        let smoothingFactor = 2.0 / (7.0 + 1.0) // 7-day EMA
        
        for record in recentWeights {
            currentEMA = (record.weight - currentEMA) * smoothingFactor + currentEMA
            let dayStart = calendar.startOfDay(for: record.date)
            emaWeights[dayStart] = currentEMA
        }
        
        // Get start and end EMA to find total weight change rate
        guard let firstEmaRecord = recentWeights.first, let lastEmaRecord = recentWeights.last else { return }
        let firstDay = calendar.startOfDay(for: firstEmaRecord.date)
        let lastDay = calendar.startOfDay(for: lastEmaRecord.date)
        
        guard let startWeight = emaWeights[firstDay], let endWeight = emaWeights[lastDay] else { return }
        let daysBetween = Double(calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 1)
        
        var ratePerDay = 0.0
        if daysBetween > 0 {
            ratePerDay = (endWeight - startWeight) / daysBetween
        }
        
        // 3. Average Calorie Intake
        // Only count days where user actually logged a meaningful amount of food (> 500 cals)
        let validLogs = recentLogs.filter { $0.totalCalories() > 500 }
        let totalCaloriesLogged = validLogs.reduce(0.0) { $0 + $1.totalCalories() }
        let averageCalories = validLogs.isEmpty ? 0 : totalCaloriesLogged / Double(validLogs.count)
        
        // 4. Calculate True TDEE
        // 1 lb of body tissue = ~3500 kcal
        let dailyCalorieDeficitOrSurplus = ratePerDay * 3500.0
        
        let rawTDEE = averageCalories - dailyCalorieDeficitOrSurplus
        
        // 5. Calculate Confidence
        let loggingConsistency = Double(validLogs.count) / 21.0
        let weightConsistency = Double(recentWeights.count) / 21.0
        
        var confidence: DataConfidence = .low
        if loggingConsistency > 0.8 && weightConsistency > 0.6 {
            confidence = .high
        } else if loggingConsistency > 0.6 && weightConsistency > 0.4 {
            confidence = .medium
        }
        
        DispatchQueue.main.async {
            self.last21DaysCalorieAverage = averageCalories
            self.weightChangeRatePerDay = ratePerDay
            self.calculatedTDEE = max(1000, min(rawTDEE, 5000))
            self.dataConfidence = confidence
        }
    }
    
    func fetchAndCalculate(userID: String, goalSettings: GoalSettings, dailyLogService: DailyLogService) async {
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
    func fetchAndCalculateIfNeeded(userID: String, goalSettings: GoalSettings, dailyLogService: DailyLogService) async {
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
