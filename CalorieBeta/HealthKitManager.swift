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

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        // As per instructions, create a set of HKSampleType to share.
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!,
            HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!
        ]

        // Pass the new set to the toShare parameter.
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
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
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

    
    public func saveNutrition(for foodItem: FoodItem) {
        
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
              let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates), // Fixed typo: forIdentifier
              let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
        else {
            print("Failed to get quantity types.")
            return
        }

       
        let timestamp = foodItem.timestamp ?? Date()
        
       
        var nutrientSamples: [HKQuantitySample] = []
        
       
        let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: foodItem.calories)
        let calorieSample = HKQuantitySample(type: energyType, quantity: calorieQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(calorieSample)
        
        // Protein
        let proteinQuantity = HKQuantity(unit: .gram(), doubleValue: foodItem.protein)
        let proteinSample = HKQuantitySample(type: proteinType, quantity: proteinQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(proteinSample)
        
        // Carbs
        let carbQuantity = HKQuantity(unit: .gram(), doubleValue: foodItem.carbs)
        let carbSample = HKQuantitySample(type: carbType, quantity: carbQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(carbSample)
        
        // Fats
        let fatQuantity = HKQuantity(unit: .gram(), doubleValue: foodItem.fats)
        let fatSample = HKQuantitySample(type: fatType, quantity: fatQuantity, start: timestamp, end: timestamp)
        nutrientSamples.append(fatSample)
        
        // Save the array of samples to the HealthStore.
        healthStore.save(nutrientSamples) { success, error in
            if success {
                print("Nutrients saved successfully.")
            } else if let error = error {
                print("Failed to save nutrients with error \(error.localizedDescription)")
            }
        }
    }
}
