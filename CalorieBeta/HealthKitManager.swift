import Foundation
import HealthKit

class HealthKitManager {

    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()
    private enum MetadataKey {
        static let source = "MyFitPlateSource"
        static let foodItemID = "MyFitPlateFoodItemID"
        static let loggedAt = "MyFitPlateLoggedAt"
        static let macroDerivedCalories = "MyFitPlateMacroDerivedCalories"
        static let calorieMacroDelta = "MyFitPlateCalorieMacroDelta"
    }

    private init() { }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "com.MyFitPlate.HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit not available on this device."]))
            return
        }

        // We need to write .food correlations
        guard let foodCorrelationType = HKObjectType.correlationType(forIdentifier: .food),
              let dietaryEnergyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let dietaryProteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
              let dietaryCarbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let dietaryFatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
              let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepAnalysisType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            completion(false, NSError(domain: "com.MyFitPlate.HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Required HealthKit types are unavailable."]))
            return
        }

        let typesToShare: Set<HKSampleType> = [
            foodCorrelationType,
            dietaryEnergyType,
            dietaryProteinType,
            dietaryCarbType,
            dietaryFatType,
            bodyMassType
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            activeEnergyType,
            sleepAnalysisType,
            restingHeartRateType,
            stepCountType,
            hrvType,
            bodyMassType
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            completion(success, error)
        }
    }

    func fetchWorkouts(for date: Date, completion: @escaping ([HKWorkout]?, Error?) -> Void) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in

            DispatchQueue.main.async {
                guard let workouts = samples as? [HKWorkout], error == nil else {
                    completion(nil, error)
                    return
                }
                completion(workouts, nil)
            }
        }
        healthStore.execute(query)
    }

    func fetchSleepAnalysis(startDate: Date, endDate: Date, completion: @escaping ([HKCategorySample]?, Error?) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil, NSError(domain: "com.MyFitPlate.HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sleep analysis is not available."]))
            return
        }

        let calendar = Calendar.current
        let queryStartDate = calendar.startOfDay(for: startDate)
        let queryEndDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))

        let predicate = HKQuery.predicateForSamples(withStart: queryStartDate, end: queryEndDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
            DispatchQueue.main.async {
                guard let sleepSamples = samples as? [HKCategorySample], error == nil else {
                    completion(nil, error)
                    return
                }
                completion(sleepSamples, nil)
            }
        }
        healthStore.execute(query)
    }

    func fetchLatestRestingHeartRate(completion: @escaping (HKQuantitySample?) -> Void) {
        guard let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            completion(nil)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: restingHeartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            DispatchQueue.main.async {
                completion(samples?.first as? HKQuantitySample)
            }
        }
        healthStore.execute(query)
    }

    func fetchLatestHRV(completion: @escaping (HKQuantitySample?) -> Void) {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            completion(nil)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrvType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            DispatchQueue.main.async {
                completion(samples?.first as? HKQuantitySample)
            }
        }
        healthStore.execute(query)
    }

    func fetchTodaySteps(completion: @escaping (Double) -> Void) {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            completion(0)
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async {
                let sum = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                completion(sum)
            }
        }
        healthStore.execute(query)
    }

    func fetchTodayActiveEnergy(completion: @escaping (Double) -> Void) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(0)
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async {
                let sum = result?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                completion(sum)
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Nutrition Saving
    public func saveNutrition(for foodItem: FoodItem) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
              let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
              let foodCorrelationType = HKObjectType.correlationType(forIdentifier: .food)
        else {
            AppLog.health.error("Unable to get HealthKit nutrition types.")
            return
        }

        let timestamp = foodItem.timestamp ?? Date()
        var nutrientSamples: [HKQuantitySample] = []

        // Create samples
        if foodItem.calories > 0 {
            nutrientSamples.append(HKQuantitySample(type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: foodItem.calories), start: timestamp, end: timestamp))
        }
        if foodItem.protein > 0 {
            nutrientSamples.append(HKQuantitySample(type: proteinType, quantity: HKQuantity(unit: .gram(), doubleValue: foodItem.protein), start: timestamp, end: timestamp))
        }
        if foodItem.carbs > 0 {
            nutrientSamples.append(HKQuantitySample(type: carbType, quantity: HKQuantity(unit: .gram(), doubleValue: foodItem.carbs), start: timestamp, end: timestamp))
        }
        if foodItem.fats > 0 {
            nutrientSamples.append(HKQuantitySample(type: fatType, quantity: HKQuantity(unit: .gram(), doubleValue: foodItem.fats), start: timestamp, end: timestamp))
        }

        guard !nutrientSamples.isEmpty else { return }

        let foodMetadata: [String: Any] = [
            HKMetadataKeyFoodType: foodItem.name,
            MetadataKey.source: "MyFitPlate",
            MetadataKey.foodItemID: foodItem.id,
            MetadataKey.loggedAt: timestamp.timeIntervalSince1970,
            MetadataKey.macroDerivedCalories: foodItem.macroDerivedCalories,
            MetadataKey.calorieMacroDelta: foodItem.calorieConsistencyStatus.delta
        ]

        let foodCorrelation = HKCorrelation(type: foodCorrelationType, start: timestamp, end: timestamp, objects: Set(nutrientSamples), metadata: foodMetadata)

        healthStore.save(foodCorrelation) { success, error in
            if !success, let error = error {
                AppLog.health.error("Failed to save food correlation to HealthKit: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func appFoodMetadataPredicate(for foodItem: FoodItem) -> NSPredicate {
        HKQuery.predicateForObjects(withMetadataKey: MetadataKey.foodItemID, operatorType: .equalTo, value: foodItem.id)
    }

    func deleteNutrition(for foodItem: FoodItem, completion: ((Bool) -> Void)? = nil) {
        guard let foodCorrelationType = HKObjectType.correlationType(forIdentifier: .food) else {
            completion?(false)
            return
        }

        let predicate = appFoodMetadataPredicate(for: foodItem)
        healthStore.deleteObjects(of: foodCorrelationType, predicate: predicate) { success, deletedCount, error in
            if let error {
                AppLog.health.error("Failed to delete MyFitPlate food samples from HealthKit: \(error.localizedDescription, privacy: .public)")
            } else if deletedCount > 0 {
                AppLog.health.info("Deleted \(deletedCount, privacy: .public) MyFitPlate food sample(s) from HealthKit.")
            }
            completion?(success)
        }
    }

    func replaceNutrition(oldItem: FoodItem, newItem: FoodItem) {
        deleteNutrition(for: oldItem) { [weak self] _ in
            self?.saveNutrition(for: newItem)
        }
    }

    func saveWeightSample(weightLbs: Double, date: Date) {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            AppLog.health.error("HealthKit body mass type is unavailable.")
            return
        }

        let weightQuantity = HKQuantity(unit: .pound(), doubleValue: weightLbs)
        let weightSample = HKQuantitySample(type: bodyMassType, quantity: weightQuantity, start: date, end: date)

        healthStore.save(weightSample) { success, error in
            if !success, let error = error {
                AppLog.health.error("Failed to save weight to HealthKit: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
