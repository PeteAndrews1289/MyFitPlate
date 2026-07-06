import Foundation
import HealthKit
import CoreLocation

/// Seam over HKHealthStore. The real store can't be instantiated or executed outside an entitled
/// app bundle or iOS device without throwing or crashing, so anything that talks to it directly
/// is untestable from the package — inject this instead.
public protocol HealthStoreScheduling: Sendable {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, Error?) -> Void)
    func getRequestStatusForAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>, completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void)
    func execute(_ query: HKQuery)
    func biologicalSex() throws -> HKBiologicalSexObject
    func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void)
    func save(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void)
    func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate, withCompletion completion: @escaping @Sendable (Bool, Int, Error?) -> Void)
    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation], completion: @escaping @Sendable (String?, Error?) -> Void)
}

public struct SystemHealthStore: HealthStoreScheduling {
    public init() {}

    // Computed so constructing the wrapper (e.g. as a default argument during tests)
    // never touches the real store — only actual execution does.
    private var store: HKHealthStore { HKHealthStore() }

    public func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        store.requestAuthorization(toShare: typesToShare, read: typesToRead, completion: completion)
    }

    public func getRequestStatusForAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>, completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void) {
        store.getRequestStatusForAuthorization(toShare: typesToShare, read: typesToRead, completion: completion)
    }

    public func execute(_ query: HKQuery) {
        store.execute(query)
    }

    public func biologicalSex() throws -> HKBiologicalSexObject {
        try store.biologicalSex()
    }

    public func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void) {
        store.save(object, withCompletion: completion)
    }

    public func save(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void) {
        store.save(objects, withCompletion: completion)
    }

    public func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate, withCompletion completion: @escaping @Sendable (Bool, Int, Error?) -> Void) {
        store.deleteObjects(of: objectType, predicate: predicate, withCompletion: completion)
    }

    public func saveWorkout(
        configuration: HKWorkoutConfiguration,
        start: Date,
        end: Date,
        samples: [HKSample],
        locations: [CLLocation],
        completion: @escaping @Sendable (String?, Error?) -> Void
    ) {
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        func fail(_ stage: String, _ error: Error?) {
            AppLog.health.error("Run save failed at \(stage, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
            DispatchQueue.main.async { completion(nil, error) }
        }

        let currentStore = store
        builder.beginCollection(withStart: start) { began, error in
            guard began else { return fail("begin", error) }

            let addSamplesAndFinish = {
                builder.endCollection(withEnd: end) { ended, error in
                    guard ended else { return fail("end", error) }
                    builder.finishWorkout { workout, error in
                        guard let workout else { return fail("finish", error) }

                        guard locations.count > 1 else {
                            DispatchQueue.main.async { completion(workout.uuid.uuidString, nil) }
                            return
                        }
                        let routeBuilder = HKWorkoutRouteBuilder(healthStore: currentStore, device: nil)
                        routeBuilder.insertRouteData(locations) { inserted, error in
                            guard inserted else {
                                AppLog.health.error("Route insert failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                                DispatchQueue.main.async { completion(workout.uuid.uuidString, nil) }
                                return
                            }
                            routeBuilder.finishRoute(with: workout, metadata: nil) { _, error in
                                if let error {
                                    AppLog.health.error("Route finish failed: \(error.localizedDescription, privacy: .public)")
                                }
                                DispatchQueue.main.async { completion(workout.uuid.uuidString, nil) }
                            }
                        }
                    }
                }
            }

            if samples.isEmpty {
                addSamplesAndFinish()
            } else {
                builder.add(samples) { added, error in
                    guard added else { return fail("samples", error) }
                    addSamplesAndFinish()
                }
            }
        }
    }
}
