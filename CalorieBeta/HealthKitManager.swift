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

        let typesToShare: Set<HKSampleType> = [
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

    // Ensures end date includes the full day for sleep queries
    func fetchSleepAnalysis(startDate: Date, endDate: Date, completion: @escaping ([HKCategorySample]?, Error?) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil, NSError(domain: "com.MyFitPlate.HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sleep analysis is not available."]))
            return
        }

        // Use the very start of the start day and the very end of the end day
        let calendar = Calendar.current
        let queryStartDate = calendar.startOfDay(for: startDate)
        // Go to the start of the day *after* the end date to include the full end date.
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


    public func saveNutrition(for foodItem: FoodItem) {

        guard let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
              let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
        else {
            print("❌ Unable to get HealthKit nutrition types.")
            return
        }

        let timestamp = foodItem.timestamp ?? Date()
        var nutrientSamples: [HKQuantitySample] = []

        let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: foodItem.calories)
        let calorieSample = HKQuantitySample(type: energyType, quantity: calorieQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(calorieSample)

        let proteinQuantity = HKQuantity(unit: .gram(), doubleValue: foodItem.protein)
        let proteinSample = HKQuantitySample(type: proteinType, quantity: proteinQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(proteinSample)

        let carbQuantity = HKQuantity(unit: .gram(), doubleValue: foodItem.carbs)
        let carbSample = HKQuantitySample(type: carbType, quantity: carbQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(carbSample)

        let fatQuantity = HKQuantity(unit: .gram(), doubleValue: foodItem.fats)
        let fatSample = HKQuantitySample(type: fatType, quantity: fatQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(fatSample)

        healthStore.save(nutrientSamples) { success, error in
            if !success, let error = error {
                print("❌ Error saving nutrition to HealthKit: \(error.localizedDescription)")
            } else if success {
                 // print("✅ Nutrition data saved to HealthKit for \(foodItem.name)") // Reduced logging noise
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
            } else if success {
                 // print("✅ Weight data saved to HealthKit: \(weightLbs) lbs on \(date)") // Reduced logging noise
            }
        }
    }
}
