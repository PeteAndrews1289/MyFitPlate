import Foundation
import FirebaseFirestore
import FirebaseAuth
import HealthKit
import SwiftUI
import Combine

class GoalSettings: ObservableObject {
    @Published var calories: Double?
    @Published var protein: Double = 150
    @Published var fats: Double = 70
    @Published var carbs: Double = 250
    @Published var weight: Double = 150.0
    @Published var height: Double = 170.0
    @Published var age: Int = 25
    @Published var gender: String = "Male"
    @Published var activityLevel: Double = 1.2
    @Published var goal: String = "Maintain"
    @Published var targetWeight: Double?
    @Published var proteinPercentage: Double = 30.0
    @Published var carbsPercentage: Double = 50.0
    @Published var fatsPercentage: Double = 20.0
    @Published var weightHistory: [(id: String, date: Date, weight: Double)] = []
    @Published var isUpdatingGoal: Bool = false
    @Published var nutritionViewIndex: Int = 0

    @Published var calciumGoal: Double?
    @Published var ironGoal: Double?
    @Published var potassiumGoal: Double?
    @Published var sodiumGoal: Double?
    @Published var vitaminAGoal: Double?
    @Published var vitaminCGoal: Double?
    @Published var vitaminDGoal: Double?
    
    @Published var calorieGoalMethod: CalorieGoalMethod = .mifflinWithActivity { didSet { recalculateAllGoals() } }
    @Published var waterGoal: Double = 64.0

    private let db = Firestore.firestore()
    private var weightHistoryListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    weak var dailyLogService: DailyLogService?

    init(dailyLogService: DailyLogService? = nil) {
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
        weightHistoryListener?.remove()
        cancellables.forEach { $0.cancel() }
    }

    func setupDependencies(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }
    
    func recalculateAllGoals() {
        DispatchQueue.main.async {
            self._recalculateCalorieGoal()
            self.calculateMicronutrientGoals()
        }
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
    
    private func _recalculateCalorieGoal() {
        let bmr = calculateBMR()
        var calculatedCalories: Double
        var calorieAdjustmentForWeightGoal: Double = 0
        
        switch goal {
        case "Lose": calorieAdjustmentForWeightGoal = -500
        case "Gain": calorieAdjustmentForWeightGoal = 500
        default: break
        }
        
        switch self.calorieGoalMethod {
        case .mifflinWithActivity:
            let maintenanceCalories = bmr * activityLevel
            calculatedCalories = maintenanceCalories + calorieAdjustmentForWeightGoal
            
        case .dynamicTDEE:
            var totalBurnedFromWorkouts: Double = 0
            if let log = self.dailyLogService?.currentDailyLog, Calendar.current.isDateInToday(log.date) {
                totalBurnedFromWorkouts = (log.totalCaloriesBurnedFromManualExercises()) + (log.totalCaloriesBurnedFromHealthKitWorkouts())
            }
            calculatedCalories = bmr + totalBurnedFromWorkouts + calorieAdjustmentForWeightGoal
        }

        let minimumGoal: Double = (gender.lowercased() == "male") ? 1500 : 1200
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
    }
    
    func loadUserGoals(userID: String, completion: @escaping () -> Void = {}) {
        db.collection("users").document(userID).getDocument { [weak self] document, error in
            guard let self = self else { completion(); return }
            if let doc = document, doc.exists, let data = doc.data() {
                self.weight = data["weight"] as? Double ?? self.weight
                self.height = data["height"] as? Double ?? self.height
                self.age = data["age"] as? Int ?? self.age
                self.gender = data["gender"] as? String ?? self.gender
                if let methodStr = data["calorieGoalMethod"] as? String {
                    self.calorieGoalMethod = CalorieGoalMethod(rawValue: methodStr) ?? self.calorieGoalMethod
                }
                if let goalsMap = data["goals"] as? [String: Any] {
                    self.proteinPercentage = goalsMap["proteinPercentage"] as? Double ?? self.proteinPercentage
                    self.carbsPercentage = goalsMap["carbsPercentage"] as? Double ?? self.carbsPercentage
                    self.fatsPercentage = goalsMap["fatsPercentage"] as? Double ?? self.fatsPercentage
                    self.activityLevel = goalsMap["activityLevel"] as? Double ?? self.activityLevel
                    self.goal = goalsMap["goal"] as? String ?? self.goal
                    self.targetWeight = goalsMap["targetWeight"] as? Double
                    self.calciumGoal = goalsMap["calciumGoal"] as? Double; self.ironGoal = goalsMap["ironGoal"] as? Double
                    self.potassiumGoal = goalsMap["potassiumGoal"] as? Double; self.sodiumGoal = goalsMap["sodiumGoal"] as? Double
                    self.vitaminAGoal = goalsMap["vitaminAGoal"] as? Double; self.vitaminCGoal = goalsMap["vitaminCGoal"] as? Double
                    self.vitaminDGoal = goalsMap["vitaminDGoal"] as? Double
                    self.waterGoal = goalsMap["waterGoal"] as? Double ?? self.waterGoal
                }
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
            let goalsDict: [String:Any] = [
                "calories": self.calories ?? 0, "protein": self.protein, "fats": self.fats, "carbs": self.carbs,
                "proteinPercentage": self.proteinPercentage, "carbsPercentage": self.carbsPercentage, "fatsPercentage": self.fatsPercentage,
                "activityLevel": self.activityLevel, "goal": self.goal, "targetWeight": self.targetWeight ?? NSNull(),
                "calciumGoal": self.calciumGoal ?? NSNull(), "ironGoal": self.ironGoal ?? NSNull(), "potassiumGoal": self.potassiumGoal ?? NSNull(),
                "sodiumGoal": self.sodiumGoal ?? NSNull(), "vitaminAGoal": self.vitaminAGoal ?? NSNull(), "vitaminCGoal": self.vitaminCGoal ?? NSNull(),
                "vitaminDGoal": self.vitaminDGoal ?? NSNull(), "waterGoal": self.waterGoal
            ]
            let userData:[String:Any] = [
                "goals": goalsDict, "height": self.height, "age": self.age, "gender": self.gender, "isFirstLogin": false,
                "calorieGoalMethod": self.calorieGoalMethod.rawValue
            ]
            self.db.collection("users").document(userID).setData(userData, merge: true)
        }
    }
    
    func loadWeightHistory() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        if weightHistoryListener != nil { return }
        weightHistoryListener = db.collection("users").document(userID).collection("weightHistory").order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snap, err in
                guard let self = self, let docs = snap?.documents else { return }
                self.weightHistory = docs.compactMap { d -> (id: String, date: Date, weight: Double)? in
                    let data = d.data()
                    if let weight = data["weight"] as? Double, let timestamp = data["timestamp"] as? Timestamp {
                        return (id: d.documentID, date: timestamp.dateValue(), weight: weight)
                    }
                    return nil
                }.sorted { $0.date < $1.date }
            }
    }
    
    func updateUserWeight(_ newWeight: Double) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        DispatchQueue.main.async { self.weight = newWeight; self.recalculateAllGoals() }
        let weightData: [String:Any] = ["weight": newWeight, "timestamp": Timestamp(date: Date())]
        db.collection("users").document(userID).setData(["weight": newWeight], merge: true)
        db.collection("users").document(userID).collection("weightHistory").addDocument(data: weightData)
    }
    
    func deleteWeightEntry(entryID: String, completion: @escaping (Error?) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else { completion(NSError(domain:"App",code:401));return}
        db.collection("users").document(userID).collection("weightHistory").document(entryID).delete(completion: completion)
    }
    
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
                dailyRate = trend! / Double(days)
            }
        }
        return (trend, highest, lowest, dailyRate)
    }
    
    func updateUserAsOnboarded(userID: String) {
        guard !userID.isEmpty else { return }
        db.collection("users").document(userID).setData(["isFirstLogin": false], merge: true)
    }
}
