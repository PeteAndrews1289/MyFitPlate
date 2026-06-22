import Foundation
import HealthKit


protocol HealthKitManaging {
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void)
    func fetchWorkouts(for date: Date, completion: @escaping ([HKWorkout]?, Error?) -> Void)
    func fetchSleepAnalysis(startDate: Date, endDate: Date, completion: @escaping ([HKCategorySample]?, Error?) -> Void)
    func fetchLatestRestingHeartRate(completion: @escaping (HKQuantitySample?) -> Void)
    func fetchLatestHRV(completion: @escaping (HKQuantitySample?) -> Void)
    func fetchTodaySteps(completion: @escaping (Double) -> Void)
    func fetchTodayActiveEnergy(completion: @escaping (Double) -> Void)
    func fetchBiologicalSex() -> HKBiologicalSexObject?
    func fetchTodayDistance(completion: @escaping (Double) -> Void)
    func fetchTodayFlights(completion: @escaping (Double) -> Void)
    func fetchTodayExerciseTime(completion: @escaping (Double) -> Void)
    func saveNutrition(for foodItem: FoodItem)
    func appFoodMetadataPredicate(for foodItem: FoodItem) -> NSPredicate
    func deleteNutrition(for foodItem: FoodItem, completion: ((Bool) -> Void)?)
    func replaceNutrition(oldItem: FoodItem, newItem: FoodItem)
    func saveWeightSample(weightLbs: Double, date: Date)
}

class HealthKitManager: HealthKitManaging {


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

        guard let dietaryEnergyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let dietaryProteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
              let dietaryCarbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let dietaryFatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
              let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepAnalysisType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let flightsType = HKObjectType.quantityType(forIdentifier: .flightsClimbed),
              let exerciseTimeType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
              let biologicalSexType = HKObjectType.characteristicType(forIdentifier: .biologicalSex),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            completion(false, NSError(domain: "com.MyFitPlate.HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Required HealthKit types are unavailable."]))
            return
        }

        let typesToShare: Set<HKSampleType> = [
            dietaryEnergyType,
            dietaryProteinType,
            dietaryCarbType,
            dietaryFatType,
            bodyMassType,
            waterType
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            activeEnergyType,
            sleepAnalysisType,
            restingHeartRateType,
            stepCountType,
            distanceType,
            flightsType,
            exerciseTimeType,
            biologicalSexType,
            hrvType,
            bodyMassType,
            waterType
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

        let predicate = HKQuery.predicateForSamples(withStart: queryStartDate, end: queryEndDate, options: [])
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

    func fetchBiologicalSex() -> HKBiologicalSexObject? {
        return try? healthStore.biologicalSex()
    }

    func fetchTodayDistance(completion: @escaping (Double) -> Void) {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            completion(0)
            return
        }
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: distanceType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { completion(result?.sumQuantity()?.doubleValue(for: .mile()) ?? 0) }
        }
        healthStore.execute(query)
    }

    func fetchTodayFlights(completion: @escaping (Double) -> Void) {
        guard let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) else {
            completion(0)
            return
        }
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: flightsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { completion(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0) }
        }
        healthStore.execute(query)
    }

    func fetchTodayExerciseTime(completion: @escaping (Double) -> Void) {
        guard let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            completion(0)
            return
        }
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: exerciseTimeType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { completion(result?.sumQuantity()?.doubleValue(for: .minute()) ?? 0) }
        }
        healthStore.execute(query)
    }

    func fetch7DayTrend(for typeIdentifier: HKQuantityTypeIdentifier, options: HKStatisticsOptions, unit: HKUnit, completion: @escaping ([Double]) -> Void) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            completion([])
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else {
            completion([])
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let anchorDate = calendar.startOfDay(for: now)
        let daily = DateComponents(day: 1)
        
        let query = HKStatisticsCollectionQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options, anchorDate: anchorDate, intervalComponents: daily)
        
        query.initialResultsHandler = { _, results, _ in
            var trends: [Double] = Array(repeating: 0.0, count: 7)
            guard let statsCollection = results else {
                DispatchQueue.main.async { completion(trends) }
                return
            }
            
            statsCollection.enumerateStatistics(from: startDate, to: now) { statistics, stop in
                let daysAgo = calendar.dateComponents([.day], from: statistics.startDate, to: calendar.startOfDay(for: now)).day ?? 0
                if daysAgo >= 0 && daysAgo < 7 {
                    let index = 6 - daysAgo
                    if options.contains(.cumulativeSum) {
                        trends[index] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                    } else if options.contains(.discreteAverage) {
                        trends[index] = statistics.averageQuantity()?.doubleValue(for: unit) ?? 0
                    }
                }
            }
            
            DispatchQueue.main.async { completion(trends) }
        }
        healthStore.execute(query)
    }

    // MARK: - Nutrition Saving
    public func saveNutrition(for foodItem: FoodItem) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
              let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
              let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
        else {
            AppLog.health.error("Unable to get HealthKit nutrition types.")
            return
        }

        let timestamp = foodItem.timestamp ?? Date()
        var nutrientSamples: [HKQuantitySample] = []

        let foodMetadata: [String: Any] = [
            HKMetadataKeyFoodType: foodItem.name,
            MetadataKey.source: "MyFitPlate",
            MetadataKey.foodItemID: foodItem.id,
            MetadataKey.loggedAt: timestamp.timeIntervalSince1970,
            MetadataKey.macroDerivedCalories: foodItem.macroDerivedCalories,
            MetadataKey.calorieMacroDelta: foodItem.calorieConsistencyStatus.delta
        ]

        if foodItem.calories > 0 {
            nutrientSamples.append(HKQuantitySample(type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: foodItem.calories), start: timestamp, end: timestamp, metadata: foodMetadata))
        }
        if foodItem.protein > 0 {
            nutrientSamples.append(HKQuantitySample(type: proteinType, quantity: HKQuantity(unit: .gram(), doubleValue: foodItem.protein), start: timestamp, end: timestamp, metadata: foodMetadata))
        }
        if foodItem.carbs > 0 {
            nutrientSamples.append(HKQuantitySample(type: carbType, quantity: HKQuantity(unit: .gram(), doubleValue: foodItem.carbs), start: timestamp, end: timestamp, metadata: foodMetadata))
        }
        if foodItem.fats > 0 {
            nutrientSamples.append(HKQuantitySample(type: fatType, quantity: HKQuantity(unit: .gram(), doubleValue: foodItem.fats), start: timestamp, end: timestamp, metadata: foodMetadata))
        }

        guard !nutrientSamples.isEmpty else { return }

        healthStore.save(nutrientSamples) { success, error in
            if !success, let error = error {
                AppLog.health.error("Failed to save nutrition samples to HealthKit: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Water Saving
    public func saveWater(ounces: Double, date: Date) {
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return }
        
        // Convert ounces to fluidOuncesUS (or milliliters)
        let quantity = HKQuantity(unit: .fluidOunceUS(), doubleValue: ounces)
        
        let metadata: [String: Any] = [
            MetadataKey.source: "MyFitPlate",
            MetadataKey.loggedAt: date.timeIntervalSince1970
        ]
        
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: date, end: date, metadata: metadata)
        
        healthStore.save(sample) { success, error in
            if !success, let error = error {
                AppLog.health.error("Failed to save water to HealthKit: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func appFoodMetadataPredicate(for foodItem: FoodItem) -> NSPredicate {
        HKQuery.predicateForObjects(withMetadataKey: MetadataKey.foodItemID, operatorType: .equalTo, value: foodItem.id)
    }

    func deleteNutrition(for foodItem: FoodItem, completion: ((Bool) -> Void)? = nil) {
        let sampleTypes = nutritionSampleTypes()
        guard !sampleTypes.isEmpty else {
            completion?(false)
            return
        }

        let predicate = appFoodMetadataPredicate(for: foodItem)
        let group = DispatchGroup()
        let stateLock = NSLock()
        var deletionSucceeded = true
        var deletedSamples = 0

        for sampleType in sampleTypes {
            group.enter()
            healthStore.deleteObjects(of: sampleType, predicate: predicate) { success, deletedCount, error in
                stateLock.lock()
                defer {
                    stateLock.unlock()
                    group.leave()
                }

                if let error {
                    deletionSucceeded = false
                    AppLog.health.error("Failed to delete MyFitPlate nutrition samples from HealthKit: \(error.localizedDescription, privacy: .public)")
                } else {
                    deletedSamples += deletedCount
                    if !success { deletionSucceeded = false }
                }
            }
        }

        group.notify(queue: .main) {
            stateLock.lock()
            let didSucceed = deletionSucceeded
            let totalDeleted = deletedSamples
            stateLock.unlock()

            if totalDeleted > 0 {
                AppLog.health.info("Deleted \(totalDeleted, privacy: .public) MyFitPlate nutrition sample(s) from HealthKit.")
            }
            completion?(didSucceed)
        }
    }

    func replaceNutrition(oldItem: FoodItem, newItem: FoodItem) {
        deleteNutrition(for: oldItem) { [weak self] _ in
            self?.saveNutrition(for: newItem)
        }
    }

    private func nutritionSampleTypes() -> [HKSampleType] {
        [
            HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)
        ].compactMap { $0 }
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
