import Foundation
import HealthKit
@testable import MyFitPlateCore

public final class MockHealthKitManager: HealthKitManaging, @unchecked Sendable {
    public init() {}

    public var requestAuthorizationSuccess: Bool = true
    public var requestAuthorizationError: Error? = nil
    public var authorizationStatusResult: HKAuthorizationRequestStatus = .unnecessary
    public var authorizationStatusError: Error? = nil

    public var workoutsResult: [HKWorkout]? = []
    public var workoutsError: Error? = nil
    public var sleepResult: [HKCategorySample]? = []
    public var sleepError: Error? = nil
    public var hrvSamplesResult: [HKQuantitySample]? = []
    public var hrvSamplesError: Error? = nil
    public var restingHRResult: HKQuantitySample? = nil
    public var hrvResult: HKQuantitySample? = nil
    public var latestWeightResult: HKQuantitySample? = nil
    public var recentWeightSamplesResult: [HKQuantitySample]? = []
    public var recentWeightSamplesError: Error? = nil

    public var todayStepsResult: Double = 0
    public var todayActiveEnergyResult: Double = 0
    public var todayDistanceResult: Double = 0
    public var todayFlightsResult: Double = 0
    public var todayExerciseTimeResult: Double = 0
    public var biologicalSexResult: HKBiologicalSexObject? = nil

    public var trendResult: [Double] = Array(repeating: 0.0, count: 7)
    public var savedWeightSamples: [(weight: Double, date: Date)] = []
    public var isHealthDataAvailableResult: Bool = true

    public func isHealthDataAvailable() -> Bool {
        isHealthDataAvailableResult
    }

    public func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        let success = requestAuthorizationSuccess
        let error = requestAuthorizationError
        DispatchQueue.main.async { completion(success, error) }
    }

    public func fetchWorkouts(for date: Date, completion: @escaping ([HKWorkout]?, Error?) -> Void) {
        let result = workoutsResult
        let error = workoutsError
        DispatchQueue.main.async { completion(result, error) }
    }

    public func fetchSleepAnalysis(startDate: Date, endDate: Date, completion: @escaping ([HKCategorySample]?, Error?) -> Void) {
        let result = sleepResult
        let error = sleepError
        DispatchQueue.main.async { completion(result, error) }
    }

    public func fetchHRVSamples(startDate: Date, endDate: Date, completion: @escaping ([HKQuantitySample]?, Error?) -> Void) {
        let result = hrvSamplesResult
        let error = hrvSamplesError
        DispatchQueue.main.async { completion(result, error) }
    }

    public func fetchLatestRestingHeartRate(completion: @escaping (HKQuantitySample?) -> Void) {
        let result = restingHRResult
        DispatchQueue.main.async { completion(result) }
    }

    public func fetchLatestHRV(completion: @escaping (HKQuantitySample?) -> Void) {
        let result = hrvResult
        DispatchQueue.main.async { completion(result) }
    }

    public func fetchLatestWeight(completion: @escaping (HKQuantitySample?) -> Void) {
        let result = latestWeightResult
        DispatchQueue.main.async { completion(result) }
    }

    public func fetchRecentWeightSamples(startDate: Date, endDate: Date, completion: @escaping ([HKQuantitySample]?, Error?) -> Void) {
        let result = recentWeightSamplesResult
        let error = recentWeightSamplesError
        DispatchQueue.main.async { completion(result, error) }
    }

    public func fetchTodaySteps(completion: @escaping (Double) -> Void) {
        let result = todayStepsResult
        DispatchQueue.main.async { completion(result) }
    }

    public func fetchTodayActiveEnergy(completion: @escaping (Double) -> Void) {
        let result = todayActiveEnergyResult
        DispatchQueue.main.async { completion(result) }
    }

    public func fetchBiologicalSex() -> HKBiologicalSexObject? {
        biologicalSexResult
    }

    public func fetchTodayDistance(completion: @escaping (Double) -> Void) {
        let result = todayDistanceResult
        DispatchQueue.main.async { completion(result) }
    }

    public func fetchTodayFlights(completion: @escaping (Double) -> Void) {
        let result = todayFlightsResult
        DispatchQueue.main.async { completion(result) }
    }

    public func fetchTodayExerciseTime(completion: @escaping (Double) -> Void) {
        let result = todayExerciseTimeResult
        DispatchQueue.main.async { completion(result) }
    }

    public func saveNutrition(for foodItem: FoodItem) {}

    public func appFoodMetadataPredicate(for foodItem: FoodItem) -> NSPredicate {
        NSPredicate(value: true)
    }

    public func deleteNutrition(for foodItem: FoodItem, completion: ((Bool) -> Void)?) {
        completion?(true)
    }

    public func replaceNutrition(oldItem: FoodItem, newItem: FoodItem) {}

    public func saveWeightSample(weightLbs: Double, date: Date) {
        savedWeightSamples.append((weightLbs, date))
    }

    public func getRequestStatusForAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>, completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void) {
        let result = authorizationStatusResult
        let error = authorizationStatusError
        DispatchQueue.main.async { completion(result, error) }
    }

    public func fetch7DayTrend(for typeIdentifier: HKQuantityTypeIdentifier, options: HKStatisticsOptions, unit: HKUnit, completion: @escaping ([Double]) -> Void) {
        let result = trendResult
        DispatchQueue.main.async { completion(result) }
    }

    public func saveWater(ounces: Double, date: Date) {}
}
