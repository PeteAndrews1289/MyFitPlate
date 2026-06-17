import Foundation
import HealthKit

class HealthKitManager {

    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()

    private init() { }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "com.MyFitPlate.HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit not available on this device."]))
            return
        }

        // We need to write .food correlations
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.correlationType(forIdentifier: .food)!, // Added this
            HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
            HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            completion(success, error)
        }
    }

    // ... (fetchWorkouts, fetchSleepAnalysis, fetchLatestRestingHeartRate, fetchLatestHRV remain unchanged) ...
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

    // MARK: - Updated Nutrition Saving with Correlations
    public func saveNutrition(for foodItem: FoodItem) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
              let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
              let foodCorrelationType = HKObjectType.correlationType(forIdentifier: .food)
        else {
            print("❌ Unable to get HealthKit nutrition types.")
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

        // Wrap them in a correlation (Food Object)
        let foodMetadata: [String: Any] = [
            HKMetadataKeyFoodType: foodItem.name
        ]
        
        let foodCorrelation = HKCorrelation(type: foodCorrelationType, start: timestamp, end: timestamp, objects: Set(nutrientSamples), metadata: foodMetadata)

        healthStore.save(foodCorrelation) { success, error in
            if !success, let error = error {
                print("❌ Error saving food correlation to HealthKit: \(error.localizedDescription)")
            } else if success {
                 // Success
            }
        }
    }

    func saveWeightSample(weightLbs: Double, date: Date) {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            print("❌ Body Mass type is unavailable.")
            return
        }

        let weightQuantity = HKQuantity(unit: .pound(), doubleValue: weightLbs)
        let weightSample = HKQuantitySample(type: bodyMassType, quantity: weightQuantity, start: date, end: date)

        healthStore.save(weightSample) { success, error in
            if !success, let error = error {
                print("❌ Error saving weight to HealthKit: \(error.localizedDescription)")
            }
        }
    }
}
