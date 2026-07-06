import Foundation
import HealthKit
import CoreLocation
@testable import MyFitPlateCore

public final class MockBiologicalSexObject: HKBiologicalSexObject, @unchecked Sendable {
    private let _sex: HKBiologicalSex
    public init(sex: HKBiologicalSex) {
        self._sex = sex
        super.init()
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public override var biologicalSex: HKBiologicalSex { _sex }
}

public final class MockHealthStore: HealthStoreScheduling, @unchecked Sendable {
    public init() {}

    public var isHealthDataAvailableResult: Bool = true
    public var requestAuthorizationSuccess: Bool = true
    public var requestAuthorizationError: Error? = nil
    public var authorizationStatusResult: HKAuthorizationRequestStatus = .unnecessary
    public var authorizationStatusError: Error? = nil
    public var biologicalSexResult: HKBiologicalSexObject = MockBiologicalSexObject(sex: .notSet)
    public var biologicalSexError: Error? = nil

    public var workoutQueryResult: [HKWorkout]? = []
    public var workoutQueryError: Error? = nil
    public var sleepQueryResult: [HKCategorySample]? = []
    public var sleepQueryError: Error? = nil
    public var restingHeartRateQueryResult: [HKQuantitySample]? = []
    public var restingHeartRateQueryError: Error? = nil
    public var hrvQueryResult: [HKQuantitySample]? = []
    public var hrvQueryError: Error? = nil

    public var saveSuccess: Bool = true
    public var saveError: Error? = nil
    public var savedObjects: [HKObject] = []

    public var deleteSuccess: Bool = true
    public var deleteCount: Int = 1
    public var deleteError: Error? = nil
    public var deletedObjectTypes: [HKObjectType] = []

    public var saveWorkoutUUID: String? = UUID().uuidString
    public var saveWorkoutError: Error? = nil
    public var savedWorkouts: [(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation])] = []

    public var executedQueries: [HKQuery] = []

    public func isHealthDataAvailable() -> Bool {
        isHealthDataAvailableResult
    }

    public func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        let success = requestAuthorizationSuccess
        let error = requestAuthorizationError
        DispatchQueue.main.async {
            completion(success, error)
        }
    }

    public func getRequestStatusForAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>, completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void) {
        let status = authorizationStatusResult
        let error = authorizationStatusError
        DispatchQueue.main.async {
            completion(status, error)
        }
    }

    public func execute(_ query: HKQuery) {
        executedQueries.append(query)
        if let sampleQuery = query as? HKSampleQuery, let block = sampleQuery.value(forKey: "resultHandler") {
            typealias Handler = @convention(block) (HKSampleQuery, [HKSample]?, Error?) -> Void
            let handler = unsafeBitCast(block as AnyObject, to: Handler.self)

            var samples: [HKSample]? = nil
            var error: Error? = nil

            if sampleQuery.sampleType == HKObjectType.workoutType() {
                samples = workoutQueryResult
                error = workoutQueryError
            } else if sampleQuery.sampleType == HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                samples = sleepQueryResult
                error = sleepQueryError
            } else if sampleQuery.sampleType == HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
                samples = restingHeartRateQueryResult
                error = restingHeartRateQueryError
            } else if sampleQuery.sampleType == HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                samples = hrvQueryResult
                error = hrvQueryError
            }

            // Invoke handler asynchronously or synchronously as HealthKit does
            DispatchQueue.global().async {
                handler(sampleQuery, samples, error)
            }
        } else if let statQuery = query as? HKStatisticsQuery, let block = statQuery.value(forKey: "completionHandler") {
            typealias Handler = @convention(block) (HKStatisticsQuery, AnyObject?, Error?) -> Void
            let handler = unsafeBitCast(block as AnyObject, to: Handler.self)
            DispatchQueue.global().async {
                handler(statQuery, nil, nil)
            }
        } else if let colQuery = query as? HKStatisticsCollectionQuery, let block = colQuery.value(forKey: "initialResultsHandler") {
            typealias Handler = @convention(block) (HKStatisticsCollectionQuery, AnyObject?, Error?) -> Void
            let handler = unsafeBitCast(block as AnyObject, to: Handler.self)
            DispatchQueue.global().async {
                handler(colQuery, nil, nil)
            }
        }
    }

    public func biologicalSex() throws -> HKBiologicalSexObject {
        if let error = biologicalSexError {
            throw error
        }
        return biologicalSexResult
    }

    public func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void) {
        savedObjects.append(object)
        let success = saveSuccess
        let error = saveError
        DispatchQueue.main.async {
            completion(success, error)
        }
    }

    public func save(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void) {
        savedObjects.append(contentsOf: objects)
        let success = saveSuccess
        let error = saveError
        DispatchQueue.main.async {
            completion(success, error)
        }
    }

    public func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate, withCompletion completion: @escaping @Sendable (Bool, Int, Error?) -> Void) {
        deletedObjectTypes.append(objectType)
        let success = deleteSuccess
        let count = deleteCount
        let error = deleteError
        DispatchQueue.main.async {
            completion(success, count, error)
        }
    }

    public func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation], completion: @escaping @Sendable (String?, Error?) -> Void) {
        savedWorkouts.append((configuration, start, end, samples, locations))
        let uuid = saveWorkoutUUID
        let error = saveWorkoutError
        DispatchQueue.main.async {
            completion(uuid, error)
        }
    }
}
