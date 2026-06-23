import Foundation
import HealthKit
@testable import MyFitPlate

class MockHealthKitManager: HealthKitManaging {
    var isAuthorizationRequested = false
    var savedWeightSamples: [(weight: Double, date: Date)] = []
    
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        isAuthorizationRequested = true
        completion(true, nil)
    }
    
    func fetchWorkouts(for date: Date, completion: @escaping ([HKWorkout]?, Error?) -> Void) {
        completion([], nil)
    }
    
    func fetchSleepAnalysis(startDate: Date, endDate: Date, completion: @escaping ([HKCategorySample]?, Error?) -> Void) {
        completion([], nil)
    }
    
    func fetchLatestRestingHeartRate(completion: @escaping (HKQuantitySample?) -> Void) {
        completion(nil)
    }
    
    func fetchLatestHRV(completion: @escaping (HKQuantitySample?) -> Void) {
        completion(nil)
    }
    
    func fetchTodaySteps(completion: @escaping (Double) -> Void) {
        completion(5000)
    }
    
    func fetchTodayActiveEnergy(completion: @escaping (Double) -> Void) {
        completion(300)
    }

    func fetchBiologicalSex() -> HKBiologicalSexObject? {
        return nil
    }

    func fetchTodayDistance(completion: @escaping (Double) -> Void) {
        completion(0)
    }

    func fetchTodayFlights(completion: @escaping (Double) -> Void) {
        completion(0)
    }

    func fetchTodayExerciseTime(completion: @escaping (Double) -> Void) {
        completion(0)
    }

    func saveNutrition(for foodItem: FoodItem) {
        // no-op for tests
    }
    
    func appFoodMetadataPredicate(for foodItem: FoodItem) -> NSPredicate {
        return NSPredicate(value: true)
    }
    
    func deleteNutrition(for foodItem: FoodItem, completion: ((Bool) -> Void)?) {
        completion?(true)
    }
    
    func replaceNutrition(oldItem: FoodItem, newItem: FoodItem) {
        // no-op
    }
    
    func saveWeightSample(weightLbs: Double, date: Date) {
        savedWeightSamples.append((weightLbs, date))
    }
}
