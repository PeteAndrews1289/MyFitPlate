import Foundation
import HealthKit
import CoreLocation

/// Seam over HKHealthStore. The real store can't be instantiated or executed outside an entitled
/// app bundle or iOS device without throwing or crashing, so anything that talks to it directly
/// is untestable from the package — inject this instead.
public protocol HealthStoreScheduling: Sendable {
    func isHealthDataAvailable() -> Bool
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, Error?) -> Void)
    func getRequestStatusForAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>, completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void)
    func execute(_ query: HKQuery)
    func biologicalSex() throws -> HKBiologicalSexObject
    func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void)
    func save(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void)
    func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate, withCompletion completion: @escaping @Sendable (Bool, Int, Error?) -> Void)
    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation], completion: @escaping @Sendable (String?, Error?) -> Void)
    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation], events: [HKWorkoutEvent], metadata: [String: Any], completion: @escaping @Sendable (String?, Error?) -> Void)
    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], routeSegments: [[CLLocation]], events: [HKWorkoutEvent], metadata: [String: Any], completion: @escaping @Sendable (String?, Error?) -> Void)
    func repairWorkoutRoute(workoutID: UUID, recordingID: String, routeSegments: [[CLLocation]], completion: @escaping @Sendable (Bool, Error?) -> Void)
}

public extension HealthStoreScheduling {
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { .notDetermined }
    /// Existing conformers remain source-compatible. A writer without event support
    /// may handle an unpaused workout, but must never silently drop pause boundaries.
    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation], events: [HKWorkoutEvent], completion: @escaping @Sendable (String?, Error?) -> Void) {
        saveWorkout(configuration: configuration, start: start, end: end, samples: samples, locations: locations,
                    events: events, metadata: [:], completion: completion)
    }

    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation], events: [HKWorkoutEvent], metadata: [String: Any], completion: @escaping @Sendable (String?, Error?) -> Void) {
        guard events.isEmpty, metadata.isEmpty else {
            DispatchQueue.main.async { completion(nil, HealthWorkoutWriteError.eventsUnsupported) }
            return
        }
        saveWorkout(configuration: configuration, start: start, end: end, samples: samples, locations: locations, completion: completion)
    }
    /// Old injected writers may handle one continuous segment. They must never flatten
    /// separate segments into a fictional connecting route.
    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], routeSegments: [[CLLocation]], events: [HKWorkoutEvent], metadata: [String: Any], completion: @escaping @Sendable (String?, Error?) -> Void) {
        guard routeSegments.count <= 1 else {
            DispatchQueue.main.async { completion(nil, HealthWorkoutWriteError.eventsUnsupported) }
            return
        }
        saveWorkout(configuration: configuration, start: start, end: end, samples: samples, locations: routeSegments.first ?? [],
                    events: events, metadata: metadata, completion: completion)
    }

    func repairWorkoutRoute(workoutID: UUID, recordingID: String, routeSegments: [[CLLocation]], completion: @escaping @Sendable (Bool, Error?) -> Void) {
        completion(false, HealthWorkoutWriteError.eventsUnsupported)
    }

}

public struct SystemHealthStore: HealthStoreScheduling {
    public init() {}

    // Computed so constructing the wrapper (e.g. as a default argument during tests)
    // never touches the real store — only actual execution does.
    private var store: HKHealthStore { HKHealthStore() }

    public func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        store.authorizationStatus(for: type)
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
        saveWorkout(configuration: configuration, start: start, end: end, samples: samples, locations: locations,
                    events: [], metadata: [:], completion: completion)
    }

    public func saveWorkout(
        configuration: HKWorkoutConfiguration,
        start: Date,
        end: Date,
        samples: [HKSample],
        locations: [CLLocation],
        events: [HKWorkoutEvent],
        metadata: [String: Any],
        completion: @escaping @Sendable (String?, Error?) -> Void
    ) {
        saveWorkout(configuration: configuration, start: start, end: end, samples: samples, routeSegments: [locations],
                    events: events, metadata: metadata, completion: completion)
    }

    public func saveWorkout(
        configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample],
        routeSegments: [[CLLocation]], events: [HKWorkoutEvent], metadata: [String: Any],
        completion: @escaping @Sendable (String?, Error?) -> Void
    ) {
        let currentStore = store
        let builder = HKWorkoutBuilder(healthStore: currentStore, configuration: configuration, device: .local())
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: end, samples: samples, events: events, metadata: metadata) { workout, error in
            guard let workout, error == nil else {
                if let error, error as? HealthWorkoutWriteError != .savedButUnreadable {
                    AppLog.health.error("Workout save failed: \(error.localizedDescription, privacy: .public)")
                }
                // A nil result with no error is possible while locked. Never invent a
                // saved UUID; the caller retains its already committed local metrics.
                DispatchQueue.main.async { completion(nil, error) }
                return
            }
            Self.writeRouteSegments(routeSegments.filter { $0.count > 1 }, index: 0, workout: workout,
                                    recordingID: (metadata[RunRecorderRules.recordingIDMetadataKey] as? String) ?? workout.uuid.uuidString,
                                    existing: [], store: currentStore, completion: completion)
        }
    }

    public func repairWorkoutRoute(workoutID: UUID, recordingID: String, routeSegments: [[CLLocation]],
                                   completion: @escaping @Sendable (Bool, Error?) -> Void) {
        let currentStore = store
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: workoutID),
                                  limit: 1, sortDescriptors: nil) { _, samples, error in
            guard error == nil, let workout = samples?.first as? HKWorkout,
                  RunImportRules.isOwnRecording(sourceBundleID: workout.sourceRevision.source.bundleIdentifier),
                  (workout.metadata?[RunRecorderRules.recordingIDMetadataKey] as? String) == recordingID else {
                completion(false, error ?? HealthWorkoutWriteError.savedButUnreadable)
                return
            }
            let routeQuery = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout),
                                           limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil else { completion(false, error); return }
                let existing = Set(((samples as? [HKWorkoutRoute]) ?? []).compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
                Self.writeRouteSegments(routeSegments.filter { $0.count > 1 }, index: 0, workout: workout,
                                        recordingID: recordingID, existing: existing, store: currentStore) { _, error in
                    completion(error == nil, error)
                }
            }
            currentStore.execute(routeQuery)
        }
        currentStore.execute(query)
    }

    private static func writeRouteSegments(_ segments: [[CLLocation]], index: Int, workout: HKWorkout,
                                           recordingID: String, existing: Set<String>, store: HKHealthStore,
                                           completion: @escaping @Sendable (String?, Error?) -> Void) {
        guard segments.indices.contains(index) else {
            DispatchQueue.main.async { completion(workout.uuid.uuidString, nil) }
            return
        }
        let syncID = "MyFitPlate.run.\(recordingID).route.\(index)"
        if existing.contains(syncID) {
            writeRouteSegments(segments, index: index + 1, workout: workout, recordingID: recordingID,
                               existing: existing, store: store, completion: completion)
            return
        }
        // Each segment is a separate series attached to the same workout. A route
        // consumer can never mistake an interruption for a measured straight line.
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        routeBuilder.insertRouteData(segments[index]) { inserted, error in
            guard inserted, error == nil else {
                AppLog.health.error("Route segment insert failed; the protected local route is retained.")
                DispatchQueue.main.async { completion(workout.uuid.uuidString, HealthWorkoutWriteError.routeAttachmentFailed) }
                return
            }
            let metadata: [String: Any] = ["MyFitPlateRouteSegment": index, HKMetadataKeySyncIdentifier: syncID, HKMetadataKeySyncVersion: 1]
            routeBuilder.finishRoute(with: workout, metadata: metadata) { _, error in
                if error != nil {
                    AppLog.health.error("Route segment finish failed; the protected local route is retained.")
                    DispatchQueue.main.async { completion(workout.uuid.uuidString, HealthWorkoutWriteError.routeAttachmentFailed) }
                    return
                }
                writeRouteSegments(segments, index: index + 1, workout: workout, recordingID: recordingID,
                                   existing: existing, store: store, completion: completion)
            }
        }
    }

}
