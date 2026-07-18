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
    public static let preferenceKey = "useMetricBodyUnits"

    public static func prefersMetric(
        defaults: UserDefaults = .standard,
        locale: Locale = .current
    ) -> Bool {
        if let storedPreference = defaults.object(forKey: preferenceKey) as? Bool {
            return storedPreference
        }
        return locale.measurementSystem != .us
    }

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
    @Published public var calorieGoalMethod: CalorieGoalMethod = .mifflinWithActivity {
        didSet {
            guard !isHydratingPersistedGoals else { return }
            recalculateAllGoals()
        }
    }
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
    private var isHydratingPersistedGoals = false
    private var isSyncingWeightFromHealthKit = false
    private var hasAutoSyncedWeightThisSession = false
    private var loadedGoalUserIDs = Set<String>()
    private var activeUserID: String?
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

    @MainActor
    public func activateAccount(_ userID: String?) {
        guard activeUserID != userID else { return }
        weightHistoryCancellable?.cancel()
        weightHistoryCancellable = nil
        activeUserID = userID
        loadedGoalUserIDs.removeAll()
        hasAutoSyncedWeightThisSession = false
        isSyncingWeightFromHealthKit = false

        isHydratingPersistedGoals = true
        calories = nil
        protein = 150
        fats = 70
        carbs = 250
        weight = 150
        height = 170
        age = 25
        gender = "Male"
        activityLevel = 1.2
        goal = "Maintain"
        targetWeight = nil
        proteinPercentage = 30
        carbsPercentage = 50
        fatsPercentage = 20
        weightHistory = []
        lastCheckInDate = nil
        calciumGoal = nil
        ironGoal = nil
        potassiumGoal = nil
        sodiumGoal = nil
        vitaminAGoal = nil
        vitaminCGoal = nil
        vitaminDGoal = nil
        vitaminB12Goal = nil
        folateGoal = nil
        waterGoal = 64
        calorieGoalMethod = .mifflinWithActivity
        suggestionProteins = ["Chicken", "Beef", "Fish"]
        suggestionCuisines = ["Any"]
        suggestionCarbs = ["Rice", "Potatoes", "Pasta"]
        suggestionVeggies = ["Broccoli", "Bell Peppers"]
        trainingIntent = "General Fitness"
        reminderStyle = "Gentle"
        maiaTone = "Balanced"
        cookingStyle = "Macro-Focused Prep"
        isHydratingPersistedGoals = false
        recalculateAllGoals()
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
        if activeUserID != userID {
            activateAccount(userID)
        }
        var localResult: (updatedData: [String: Any], shouldUpdateFirestore: Bool)?
        if let localData = loadFromLocalCache(userID: userID) {
            localResult = applyDecodedGoals(from: localData)
        }
        DIContainer.shared.settingsRepository.fetchUserGoals(userID: userID) { [weak self] data in
            Task { @MainActor in
                guard let self else { completion(); return }
                guard self.activeUserID == userID else {
                    completion()
                    return
                }

                var shouldUpdateFirestore = false

                if let data {
                    if let localResult, self.shouldPreferLocalGoals(local: localResult.updatedData, remote: data) {
                        shouldUpdateFirestore = true
                        self.saveToLocalCache(userID: userID, data: localResult.updatedData)
                    } else {
                        let result = self.applyDecodedGoals(from: data)
                        shouldUpdateFirestore = result.shouldUpdateFirestore
                        self.saveToLocalCache(userID: userID, data: result.updatedData)
                    }
                }

                if shouldUpdateFirestore {
                    self.saveUserGoals(userID: userID)
                }

                self.loadedGoalUserIDs.insert(userID)
                self.recalculateAllGoals()
                completion()
            }
        }
    }

    private func applyDecodedGoals(from rawData: [String: Any]) -> (updatedData: [String: Any], shouldUpdateFirestore: Bool) {
        var data = rawData
        var shouldUpdateFirestore = false

        self.isHydratingPersistedGoals = true
        defer { self.isHydratingPersistedGoals = false }

        // Load core stats
        if data["weight"] == nil { data["weight"] = self.weight; shouldUpdateFirestore = true }
        if data["height"] == nil { data["height"] = self.height; shouldUpdateFirestore = true }
        if data["age"] == nil { data["age"] = self.age; shouldUpdateFirestore = true }
        if data["gender"] == nil { data["gender"] = self.gender; shouldUpdateFirestore = true }
        var goalsMap = data["goals"] as? [String: Any] ?? [:]
        let savedCalories = doubleValue(goalsMap["calories"])
        if data["calorieGoalMethod"] == nil {
            let inferredMethod: CalorieGoalMethod = (savedCalories ?? 0) > 0 ? .custom : self.calorieGoalMethod
            data["calorieGoalMethod"] = inferredMethod.rawValue
            shouldUpdateFirestore = true
        }

        self.weight = doubleValue(data["weight"]) ?? self.weight
        self.height = doubleValue(data["height"]) ?? self.height
        self.age = intValue(data["age"]) ?? self.age
        self.gender = data["gender"] as? String ?? self.gender
        if let methodStr = data["calorieGoalMethod"] as? String {
            self.calorieGoalMethod = CalorieGoalMethod(rawValue: methodStr) ?? self.calorieGoalMethod
        }

        // Load or default new fields
        if goalsMap["proteinPercentage"] == nil { goalsMap["proteinPercentage"] = self.proteinPercentage; shouldUpdateFirestore = true }
        if goalsMap["carbsPercentage"] == nil { goalsMap["carbsPercentage"] = self.carbsPercentage; shouldUpdateFirestore = true }
        if goalsMap["fatsPercentage"] == nil { goalsMap["fatsPercentage"] = self.fatsPercentage; shouldUpdateFirestore = true }
        let topLevelActivity = doubleValue(data["activityLevel"])
        let nestedActivity = doubleValue(goalsMap["activityLevel"])
        let topLevelGoal = data["goal"] as? String
        let nestedGoal = goalsMap["goal"] as? String
        let nestedGoalIsDefault = nestedGoal == nil || nestedGoal == "Maintain"
        let nestedActivityIsDefault = nestedActivity == nil || abs((nestedActivity ?? 1.2) - 1.2) < 0.0001
        let topLevelHasChosenGoal = topLevelGoal != nil && topLevelGoal != "Maintain"
        let topLevelHasChosenActivity = topLevelActivity != nil && abs((topLevelActivity ?? 1.2) - 1.2) >= 0.0001

        if nestedGoalIsDefault && topLevelHasChosenGoal, let topLevelGoal {
            goalsMap["goal"] = topLevelGoal
            shouldUpdateFirestore = true
        } else if nestedGoal == nil {
            goalsMap["goal"] = topLevelGoal ?? self.goal
            shouldUpdateFirestore = true
        }

        if nestedActivityIsDefault && topLevelHasChosenActivity, let topLevelActivity {
            goalsMap["activityLevel"] = topLevelActivity
            shouldUpdateFirestore = true
        } else if nestedActivity == nil {
            goalsMap["activityLevel"] = topLevelActivity ?? self.activityLevel
            shouldUpdateFirestore = true
        }
        if goalsMap["waterGoal"] == nil { goalsMap["waterGoal"] = self.waterGoal; shouldUpdateFirestore = true }
        if goalsMap["trainingIntent"] == nil { goalsMap["trainingIntent"] = self.trainingIntent; shouldUpdateFirestore = true }
        if goalsMap["reminderStyle"] == nil { goalsMap["reminderStyle"] = self.reminderStyle; shouldUpdateFirestore = true }
        if goalsMap["maiaTone"] == nil { goalsMap["maiaTone"] = self.maiaTone; shouldUpdateFirestore = true }
        if goalsMap["cookingStyle"] == nil { goalsMap["cookingStyle"] = self.cookingStyle; shouldUpdateFirestore = true }

        if let timestamp = data["lastCheckInDate"] as? Date {
            self.lastCheckInDate = timestamp
        } else if let timestamp = goalsMap["lastCheckInDate"] as? Date {
            self.lastCheckInDate = timestamp
        } else if let tsNumber = data["lastCheckInDate"] as? TimeInterval {
            self.lastCheckInDate = Date(timeIntervalSince1970: tsNumber)
        } else if let tsNumber = goalsMap["lastCheckInDate"] as? TimeInterval {
            self.lastCheckInDate = Date(timeIntervalSince1970: tsNumber)
        }

        // Handle target weight (might be null)
        self.targetWeight = goalsMap["targetWeight"] as? Double
        if self.targetWeight == nil {
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

        self.proteinPercentage = doubleValue(goalsMap["proteinPercentage"]) ?? self.proteinPercentage
        self.carbsPercentage = doubleValue(goalsMap["carbsPercentage"]) ?? self.carbsPercentage
        self.fatsPercentage = doubleValue(goalsMap["fatsPercentage"]) ?? self.fatsPercentage
        self.activityLevel = doubleValue(goalsMap["activityLevel"]) ?? self.activityLevel
        self.goal = goalsMap["goal"] as? String ?? self.goal
        self.waterGoal = doubleValue(goalsMap["waterGoal"]) ?? self.waterGoal

        if let savedCalories, savedCalories > 0 {
            self.calories = savedCalories
        }
        self.protein = doubleValue(goalsMap["protein"]) ?? self.protein
        self.carbs = doubleValue(goalsMap["carbs"]) ?? self.carbs
        self.fats = doubleValue(goalsMap["fats"]) ?? self.fats

        return (data, shouldUpdateFirestore)
    }

    private func shouldPreferLocalGoals(local: [String: Any], remote: [String: Any]) -> Bool {
        let localUpdatedAt = goalSettingsUpdatedAt(from: local)
        let remoteUpdatedAt = goalSettingsUpdatedAt(from: remote)

        if let localUpdatedAt, let remoteUpdatedAt {
            return localUpdatedAt.timeIntervalSince(remoteUpdatedAt) > 1
        }

        if localUpdatedAt != nil && remoteUpdatedAt == nil {
            return hasUserSelectedGoal(in: local) && hasDefaultGoalSelection(in: remote)
        }

        if localUpdatedAt == nil && remoteUpdatedAt == nil {
            return hasUserSelectedGoal(in: local) && hasDefaultGoalSelection(in: remote)
        }

        return false
    }

    private func goalSettingsUpdatedAt(from data: [String: Any]) -> Date? {
        if let date = dateValue(data["goalSettingsUpdatedAt"]) {
            return date
        }
        if let goalsMap = data["goals"] as? [String: Any] {
            return dateValue(goalsMap["updatedAt"])
        }
        return nil
    }

    private func hasUserSelectedGoal(in data: [String: Any]) -> Bool {
        let selection = goalSelection(in: data)
        let hasChosenActivity = selection.activityLevel.map { abs($0 - 1.2) >= 0.0001 } ?? false
        let hasChosenGoal = selection.goal.map { $0 != "Maintain" } ?? false
        return hasChosenActivity || hasChosenGoal
    }

    private func hasDefaultGoalSelection(in data: [String: Any]) -> Bool {
        let selection = goalSelection(in: data)
        let hasDefaultActivity = selection.activityLevel.map { abs($0 - 1.2) < 0.0001 } ?? true
        let hasDefaultGoal = selection.goal.map { $0 == "Maintain" } ?? true
        return hasDefaultActivity && hasDefaultGoal
    }

    private func goalSelection(in data: [String: Any]) -> (activityLevel: Double?, goal: String?) {
        let goalsMap = data["goals"] as? [String: Any]
        return (
            doubleValue(goalsMap?["activityLevel"]) ?? doubleValue(data["activityLevel"]),
            goalsMap?["goal"] as? String ?? data["goal"] as? String
        )
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let interval = value as? TimeInterval { return Date(timeIntervalSince1970: interval) }
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        if let string = value as? String {
            if let interval = TimeInterval(string) {
                return Date(timeIntervalSince1970: interval)
            }
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private func plistSafeValue(_ value: Any) -> Any? {
        if value is NSNull { return nil }
        if let dict = value as? [String: Any] {
            var cleanDict: [String: Any] = [:]
            for (k, v) in dict {
                if let cleanV = plistSafeValue(v) {
                    cleanDict[k] = cleanV
                }
            }
            return cleanDict
        }
        if let array = value as? [Any] {
            return array.compactMap { plistSafeValue($0) }
        }
        if value is String || value is NSNumber || value is Date || value is Data {
            return value
        }
        return nil
    }

    private func saveToLocalCache(userID: String, data: [String: Any]) {
        guard let cacheKey = AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: userID),
              let cleanDict = plistSafeValue(data) as? [String: Any] else { return }
        UserDefaults.standard.set(cleanDict, forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: "cached_user_goals_\(userID)")
    }

    private func loadFromLocalCache(userID: String) -> [String: Any]? {
        guard let cacheKey = AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: userID) else {
            return nil
        }
        if let cached = UserDefaults.standard.dictionary(forKey: cacheKey) {
            return cached
        }

        let legacyKey = "cached_user_goals_\(userID)"
        guard let legacyCache = UserDefaults.standard.dictionary(forKey: legacyKey) else { return nil }
        UserDefaults.standard.set(legacyCache, forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        return legacyCache
    }

    public func saveUserGoals(userID: String) {
        guard !userID.isEmpty else { return }
        loadedGoalUserIDs.insert(userID)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self._recalculateCalorieGoal()
            self.calculateMicronutrientGoals()
            self.syncAnalyticsUserProperties()
            let updatedAt = Date()
            var goalsDict: [String: Any] = [
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
                "cookingStyle": self.cookingStyle, "updatedAt": updatedAt
            ]
            if let lastDate = self.lastCheckInDate {
                goalsDict["lastCheckInDate"] = lastDate
            }
            let userData: [String: Any] = [
                "goals": goalsDict, "height": self.height, "weight": self.weight, "age": self.age, "gender": self.gender, "isFirstLogin": false,
                "calorieGoalMethod": self.calorieGoalMethod.rawValue, "activityLevel": self.activityLevel, "goal": self.goal,
                "calories": self.calories ?? 0, "goalSettingsUpdatedAt": updatedAt
            ]
            self.saveToLocalCache(userID: userID, data: userData)
            Task {
                do {
                    try await DIContainer.shared.settingsRepository.saveUserGoals(userID: userID, data: userData)
                } catch {
                    AppLog.data.error(
                        "Failed to save user goals: \(error.localizedDescription, privacy: .private)"
                    )
                }
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
        if activeUserID != userID {
            activateAccount(userID)
        }
        weightHistoryCancellable?.cancel()
        weightHistoryCancellable = DIContainer.shared.settingsRepository.weightHistoryPublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] history in
                guard let self,
                      self.activeUserID == userID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
                self.weightHistory = history
                // Auto-import HealthKit weights ONCE per session, not on every emission:
                // syncWeightFromHealthKit writes back into history, which re-emits here — a
                // feedback loop the dedup check only just contains, plus a redundant HK
                // round-trip on every weigh-in. Skip entirely under XCTest (async HK writes
                // otherwise bleed across test cases). Explicit syncWeightFromHealthKit() calls
                // are unaffected.
                if !self.hasAutoSyncedWeightThisSession && NSClassFromString("XCTest") == nil {
                    self.hasAutoSyncedWeightThisSession = true
                    self.syncWeightFromHealthKit()
                }
            })
    }
    
    public func updateUserWeight(_ newWeight: Double, date: Date = Date(), syncToHealthKit: Bool = true) {
        Task { @MainActor in
            guard let userID = DIContainer.shared.authService.currentUserID else { return }

            // Only a present-day weigh-in should move the "current" weight and re-run goal math.
            // A back-dated entry just fills in history so the trend and adaptive TDEE stay accurate.
            if Calendar.current.isDateInToday(date) {
                self.weight = newWeight
                self.recalculateAllGoals()
                if self.loadedGoalUserIDs.contains(userID) {
                    self.saveUserGoals(userID: userID)
                } else {
                    AppLog.data.info("Skipping full goal save for weight update until persisted goals finish loading.")
                }
            }
        
            do {
                try await DIContainer.shared.settingsRepository.saveWeightEntry(userID: userID, weight: newWeight, date: date)
                self.loadWeightHistory()
            } catch {
                AppLog.data.error(
                    "Failed to save weight sample: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        if syncToHealthKit {
            self.healthKitManager.saveWeightSample(weightLbs: newWeight, date: date)
        }
    }

    @MainActor
    public func syncWeightFromHealthKit() {
        guard !isSyncingWeightFromHealthKit, healthKitManager.isHealthDataAvailable() else { return }
        isSyncingWeightFromHealthKit = true
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) else {
            isSyncingWeightFromHealthKit = false
            return
        }

        healthKitManager.fetchRecentWeightSamples(startDate: startDate, endDate: endDate) { [weak self] samples, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSyncingWeightFromHealthKit = false
                guard let samples = samples, !samples.isEmpty else { return }
                
                let calendar = Calendar.current
                var latestSamplePerDay: [Date: HKQuantitySample] = [:]
                for sample in samples {
                    let dayStart = calendar.startOfDay(for: sample.startDate)
                    if let existing = latestSamplePerDay[dayStart] {
                        if sample.startDate > existing.startDate {
                            latestSamplePerDay[dayStart] = sample
                        }
                    } else {
                        latestSamplePerDay[dayStart] = sample
                    }
                }
                
                let sortedDays = latestSamplePerDay.keys.sorted()
                for day in sortedDays {
                    guard let sample = latestSamplePerDay[day] else { continue }
                    let weightLbs = sample.quantity.doubleValue(for: .pound())
                    let sampleDate = sample.startDate
                    
                    let alreadyLogged = self.weightHistory.contains { entry in
                        calendar.isDate(entry.date, inSameDayAs: sampleDate) && abs(entry.weight - weightLbs) < 0.2
                    }
                    
                    if !alreadyLogged {
                        AppLog.health.info(
                            "Importing HealthKit weight sample: \(weightLbs, privacy: .private) lbs on \(sampleDate, privacy: .private)"
                        )
                        self.updateUserWeight(weightLbs, date: sampleDate, syncToHealthKit: false)
                    }
                }
            }
        }
    }
    
    public func deleteWeightEntry(entryID: String, completion: @escaping (Error?) -> Void) {
        Task { @MainActor in
            guard let userID = DIContainer.shared.authService.currentUserID else {
                completion(NSError(domain: "App", code: 401))
                return
            }
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
        let hCm = self.height; guard hCm > 0 else { return (0, 0) }; let totalInches = Int(round(hCm / 2.54))
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
        var trend: Double?, dailyRate: Double?
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
    @Published public var recentValidLogCount: Int = 0
    @Published public var recentWorkoutCount: Int = 0
    /// How many weigh-ins / food-log days exist in the last 21 days. Drives the
    /// "progress to your first estimate" UI shown before there's enough data for a TDEE.
    @Published public var recentWeighInCount: Int = 0
    @Published public var recentLogCount: Int = 0
    @Published public var partialLogCount: Int = 0
    @Published public var isEstimateActionable: Bool = false
    @Published public var tdeeGuardrailMessage: String?
    @Published public var lastCalculationDate: Date?
    private var activeUserID: String?
    private var activeCalculationRequestID: UUID?
    
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
        public let validLogCount: Int
        public let recentWorkoutCount: Int
        public let partialLogCount: Int
        public let isActionable: Bool
        public let guardrailMessage: String?

        public init(
            recentWeighInCount: Int,
            recentLogCount: Int,
            last21DaysCalorieAverage: Double?,
            weightChangeRatePerDay: Double?,
            calculatedTDEE: Double?,
            dataConfidence: DataConfidence,
            validLogCount: Int = 0,
            recentWorkoutCount: Int = 0,
            partialLogCount: Int = 0,
            isActionable: Bool = false,
            guardrailMessage: String? = nil
        ) {
            self.recentWeighInCount = recentWeighInCount
            self.recentLogCount = recentLogCount
            self.last21DaysCalorieAverage = last21DaysCalorieAverage
            self.weightChangeRatePerDay = weightChangeRatePerDay
            self.calculatedTDEE = calculatedTDEE
            self.dataConfidence = dataConfidence
            self.validLogCount = validLogCount
            self.recentWorkoutCount = recentWorkoutCount
            self.partialLogCount = partialLogCount
            self.isActionable = isActionable
            self.guardrailMessage = guardrailMessage
        }
    }

    public struct WeeklyGoalProposal: Equatable {
        public let title: String
        public let summary: String
        public let currentCalories: Double?
        public let proposedCalories: Double
        public let calorieDelta: Double
        public let macroGoals: MacroGoals
        public let confidence: DataConfidence
        public let trainingLoadLabel: String
        public let reasons: [String]
        public let shouldAdjust: Bool
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

        let calorieTotals = recentLogs.map { max($0.totalCalories(), 0) }
        let positiveTotals = calorieTotals.filter { $0 > 0 }.sorted()
        let medianCalories: Double = {
            guard !positiveTotals.isEmpty else { return 0 }
            let middle = positiveTotals.count / 2
            if positiveTotals.count.isMultiple(of: 2) {
                return (positiveTotals[middle - 1] + positiveTotals[middle]) / 2
            }
            return positiveTotals[middle]
        }()
        let completeDayFloor = max(500, medianCalories * 0.5)
        let validLogs = recentLogs.filter { $0.totalCalories() >= completeDayFloor }
        let partialLogCount = recentLogs.filter {
            let calories = $0.totalCalories()
            return calories > 0 && calories < completeDayFloor
        }.count
        let recentWorkoutCount = recentLogs.reduce(0) { $0 + ($1.exercises?.count ?? 0) }

        guard recentWeighInCount >= 7, validLogs.count >= 10 else {
            let guardrailMessage: String?
            if partialLogCount > 0 || (recentLogCount >= 10 && validLogs.count < 10) {
                guardrailMessage = "Some days look only partly logged. Finish logging meals on at least 10 days before MyFitPlate estimates your TDEE."
            } else {
                guardrailMessage = nil
            }
            return ExpenditureSnapshot(
                recentWeighInCount: recentWeighInCount,
                recentLogCount: recentLogCount,
                last21DaysCalorieAverage: nil,
                weightChangeRatePerDay: nil,
                calculatedTDEE: nil,
                dataConfidence: .insufficient,
                validLogCount: validLogs.count,
                recentWorkoutCount: recentWorkoutCount,
                partialLogCount: partialLogCount,
                isActionable: false,
                guardrailMessage: guardrailMessage
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

        let isWithinSupportedRange = (1000...5000).contains(rawTDEE)
        let hasTooManyPartialDays = partialLogCount > 3
        let hasUsableConfidence = confidence == .high || confidence == .medium
        let isActionable = hasUsableConfidence && isWithinSupportedRange && !hasTooManyPartialDays

        let guardrailMessage: String?
        if hasTooManyPartialDays {
            guardrailMessage = "\(partialLogCount) days look only partly logged, so this estimate is paused. Complete those days or build a cleaner 21-day window."
            confidence = .low
        } else if !isWithinSupportedRange {
            guardrailMessage = "The result falls outside MyFitPlate's supported TDEE range. Check for missing food entries or unusual weigh-ins before using it."
            confidence = .low
        } else if !hasUsableConfidence {
            guardrailMessage = "Only \(validLogs.count) complete food-log days are available. Reach at least 13 complete days and 10 weigh-ins before using this estimate."
        } else {
            guardrailMessage = nil
        }

        return ExpenditureSnapshot(
            recentWeighInCount: recentWeighInCount,
            recentLogCount: recentLogCount,
            last21DaysCalorieAverage: averageCalories,
            weightChangeRatePerDay: ratePerDay,
            calculatedTDEE: isWithinSupportedRange && !hasTooManyPartialDays ? rawTDEE : nil,
            dataConfidence: confidence,
            validLogCount: validLogs.count,
            recentWorkoutCount: recentWorkoutCount,
            partialLogCount: partialLogCount,
            isActionable: isActionable,
            guardrailMessage: guardrailMessage
        )
    }

    public static func weeklyGoalProposal(
        snapshot: ExpenditureSnapshot,
        currentCalories: Double?,
        goal: String,
        gender: String,
        proteinPercentage: Double,
        carbsPercentage: Double,
        fatsPercentage: Double
    ) -> WeeklyGoalProposal? {
        guard snapshot.isActionable,
              let calculatedTDEE = snapshot.calculatedTDEE,
              snapshot.dataConfidence == .high || snapshot.dataConfidence == .medium else {
            return nil
        }

        let proposedCalories = GoalSettingsRules.calculateCalorieGoal(
            bmr: calculatedTDEE,
            goal: goal,
            gender: gender,
            calorieGoalMethod: .dynamicTDEE,
            activityLevel: 1.0,
            adaptiveTDEE: calculatedTDEE,
            manualCaloriesBurned: 0,
            currentCalories: nil
        )
        let delta = proposedCalories - (currentCalories ?? proposedCalories)
        let shouldAdjust = abs(delta) >= 50
        let macroGoals = GoalSettingsRules.updateMacros(
            calories: proposedCalories,
            proteinPercentage: proteinPercentage,
            carbsPercentage: carbsPercentage,
            fatsPercentage: fatsPercentage
        )
        let trainingLoad = trainingLoadLabel(for: snapshot.recentWorkoutCount)
        let weeklyWeightRate = (snapshot.weightChangeRatePerDay ?? 0) * 7
        let direction = delta > 0 ? "Raise" : "Lower"
        let title = shouldAdjust
            ? "\(direction) target by \(Int(abs(delta).rounded())) cal"
            : "Hold current target"
        let summary: String
        if shouldAdjust {
            summary = "Maia recommends \(Int(proposedCalories.rounded()).formatted()) calories/day based on your observed expenditure and \(goal.lowercased()) goal."
        } else {
            summary = "Your current target is already close to the adaptive estimate, so the safest move is to keep it steady."
        }

        let reasons = [
            "Average intake: \(formatCalories(snapshot.last21DaysCalorieAverage)) over logged days",
            "Weight trend: \(formatWeeklyWeightRate(weeklyWeightRate)) per week",
            "Food-log adherence: \(snapshot.validLogCount)/21 usable days",
            "Training load: \(trainingLoad) (\(snapshot.recentWorkoutCount) workouts)"
        ]

        return WeeklyGoalProposal(
            title: title,
            summary: summary,
            currentCalories: currentCalories,
            proposedCalories: proposedCalories,
            calorieDelta: delta,
            macroGoals: macroGoals,
            confidence: snapshot.dataConfidence,
            trainingLoadLabel: trainingLoad,
            reasons: reasons,
            shouldAdjust: shouldAdjust
        )
    }

    public func currentWeeklyGoalProposal(
        currentCalories: Double?,
        goal: String,
        gender: String,
        proteinPercentage: Double,
        carbsPercentage: Double,
        fatsPercentage: Double
    ) -> WeeklyGoalProposal? {
        let snapshot = ExpenditureSnapshot(
            recentWeighInCount: recentWeighInCount,
            recentLogCount: recentLogCount,
            last21DaysCalorieAverage: last21DaysCalorieAverage,
            weightChangeRatePerDay: weightChangeRatePerDay,
            calculatedTDEE: calculatedTDEE,
            dataConfidence: dataConfidence,
            validLogCount: recentValidLogCount,
            recentWorkoutCount: recentWorkoutCount,
            partialLogCount: partialLogCount,
            isActionable: isEstimateActionable,
            guardrailMessage: tdeeGuardrailMessage
        )
        return Self.weeklyGoalProposal(
            snapshot: snapshot,
            currentCalories: currentCalories,
            goal: goal,
            gender: gender,
            proteinPercentage: proteinPercentage,
            carbsPercentage: carbsPercentage,
            fatsPercentage: fatsPercentage
        )
    }

    /// Estimate TDEE from weight changes and logged caloric intake over the last 21 days.
    public func calculateExpenditure(weightHistory: [(id: String, date: Date, weight: Double)], dailyLogs: [DailyLog]) {
        guard let snapshot = Self.expenditureSnapshot(weightHistory: weightHistory, dailyLogs: dailyLogs) else { return }

        DispatchQueue.main.async {
            self.apply(snapshot)
        }
    }

    private func activateAccount(_ userID: String) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        activeCalculationRequestID = nil
        calculatedTDEE = nil
        weightTrendLine = []
        calorieTrendLine = []
        last21DaysCalorieAverage = nil
        weightChangeRatePerDay = nil
        dataConfidence = .insufficient
        recentValidLogCount = 0
        recentWorkoutCount = 0
        recentWeighInCount = 0
        recentLogCount = 0
        partialLogCount = 0
        isEstimateActionable = false
        tdeeGuardrailMessage = nil
        lastCalculationDate = nil
    }

    private func apply(_ snapshot: ExpenditureSnapshot) {
        recentWeighInCount = snapshot.recentWeighInCount
        recentLogCount = snapshot.recentLogCount
        recentValidLogCount = snapshot.validLogCount
        recentWorkoutCount = snapshot.recentWorkoutCount
        partialLogCount = snapshot.partialLogCount
        isEstimateActionable = snapshot.isActionable
        tdeeGuardrailMessage = snapshot.guardrailMessage
        last21DaysCalorieAverage = snapshot.last21DaysCalorieAverage
        weightChangeRatePerDay = snapshot.weightChangeRatePerDay
        calculatedTDEE = snapshot.calculatedTDEE
        dataConfidence = snapshot.dataConfidence
    }

    private static func trainingLoadLabel(for workoutCount: Int) -> String {
        switch workoutCount {
        case 0:
            return "No logged training"
        case 1...2:
            return "Light"
        case 3...5:
            return "Steady"
        default:
            return "High"
        }
    }

    private static func formatCalories(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()).formatted()) cal"
    }

    private static func formatWeeklyWeightRate(_ value: Double) -> String {
        if abs(value) < 0.05 {
            return "stable"
        }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value)) lb"
    }
    
    public func fetchAndCalculate(userID: String, goalSettings: GoalSettings, dailyLogService: DailyLogService) async {
        let isCurrentAccount = await MainActor.run {
            DIContainer.shared.authService.currentUserID == userID
        }
        guard isCurrentAccount else { return }
        let requestID = UUID()
        await MainActor.run {
            self.activateAccount(userID)
            self.activeCalculationRequestID = requestID
        }

        let calendar = Calendar.current
        let today = Date()
        guard let twentyOneDaysAgo = calendar.date(byAdding: .day, value: -21, to: today) else { return }

        let result = await dailyLogService.fetchDailyHistory(for: userID, startDate: twentyOneDaysAgo, endDate: today)
        switch result {
        case .success(let logs):
            guard let snapshot = Self.expenditureSnapshot(
                weightHistory: goalSettings.weightHistory,
                dailyLogs: logs
            ) else { return }
            await MainActor.run {
                guard DIContainer.shared.authService.currentUserID == userID,
                      self.activeUserID == userID,
                      self.activeCalculationRequestID == requestID else { return }
                self.apply(snapshot)

                // Close the loop: if the user is already on adaptive TDEE, refresh their
                // calorie/macro goals so the target tracks the freshly calculated metabolism.
                if goalSettings.calorieGoalMethod == .dynamicTDEE,
                   self.isEstimateActionable {
                    goalSettings.recalculateAllGoals()
                }
            }
        case .failure(let error):
            AppLog.data.error(
                "Adaptive goal calculation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Throttled wrapper — recalculates at most once per calendar day. Safe to call on every Home
    /// appearance so the weekly check-in can surface without the user first visiting Reports.
    public func fetchAndCalculateIfNeeded(userID: String, goalSettings: GoalSettings, dailyLogService: DailyLogService) async {
        let isCurrentAccount = await MainActor.run {
            DIContainer.shared.authService.currentUserID == userID
        }
        guard isCurrentAccount else { return }
        let alreadyCalculatedToday = await MainActor.run { () -> Bool in
            self.activateAccount(userID)
            if let last = self.lastCalculationDate {
                return Calendar.current.isDateInToday(last)
            }
            return false
        }
        guard !alreadyCalculatedToday else { return }

        await fetchAndCalculate(userID: userID, goalSettings: goalSettings, dailyLogService: dailyLogService)
        await MainActor.run {
            guard DIContainer.shared.authService.currentUserID == userID,
                  self.activeUserID == userID else { return }
            self.lastCalculationDate = Date()
        }
    }
}
