import Foundation
import HealthKit
import CoreLocation

/// Reads running workouts out of HealthKit from ANY source — Apple Watch directly, or
/// Garmin/Polar/Coros/Suunto/Whoop via their companion apps' Health sync. Thin glue:
/// all decisions live in RunImportRules (tested); this class only builds queries and maps
/// HKWorkout into the plain ImportedWorkoutSummary the rules understand.
public final class RunImportService {

    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HealthKitManager.shared.healthStore) {
        self.healthStore = healthStore
    }

    /// Runs since `since`, newest first, already filtered and de-duplicated.
    /// Completion is delivered on the main queue.
    public func fetchRuns(since: Date, completion: @escaping ([Run]) -> Void) {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        ])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: 400,
            sortDescriptors: [sort]
        ) { _, samples, error in
            if let error {
                AppLog.health.error("Run import query failed: \(error.localizedDescription, privacy: .public)")
            }
            let workouts = (samples as? [HKWorkout]) ?? []
            let runs = RunImportRules.deduplicated(
                workouts
                    .map(Self.summary(from:))
                    .filter(RunImportRules.isImportableRun)
                    .map(RunImportRules.run(from:))
            )
            DispatchQueue.main.async {
                completion(runs)
            }
        }
        healthStore.execute(query)
    }

    /// The GPS trace for a run, as engine-friendly fixes (empty for indoor/routeless runs).
    /// Completion is delivered on the main queue.
    public func fetchRoute(forRunID runID: String, completion: @escaping ([RunLocationFix]) -> Void) {
        guard let uuid = UUID(uuidString: runID) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let workoutQuery = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: HKQuery.predicateForObject(with: uuid),
            limit: 1,
            sortDescriptors: nil
        ) { [weak self] _, samples, _ in
            guard let self, let workout = samples?.first as? HKWorkout else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            self.fetchRoute(for: workout, completion: completion)
        }
        healthStore.execute(workoutQuery)
    }

    /// Average heart rate over an interval, in beats per minute.
    /// Completion is delivered on the main queue.
    public func fetchAverageHeartRate(start: Date, end: Date, completion: @escaping (Double?) -> Void) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKStatisticsQuery(
            quantityType: heartRateType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { _, statistics, _ in
            let bpm = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            DispatchQueue.main.async { completion(bpm) }
        }
        healthStore.execute(query)
    }

    // MARK: - Mapping

    static func summary(from workout: HKWorkout) -> ImportedWorkoutSummary {
        let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
        let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        let indoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false

        return ImportedWorkoutSummary(
            uuid: workout.uuid.uuidString,
            activity: activity(from: workout.workoutActivityType),
            startDate: workout.startDate,
            endDate: workout.endDate,
            distanceMeters: distance,
            activeCalories: calories,
            averageHeartRate: nil,
            sourceName: workout.sourceRevision.source.name,
            sourceBundleID: workout.sourceRevision.source.bundleIdentifier,
            isIndoor: indoor,
            hasRoute: false
        )
    }

    static func activity(from type: HKWorkoutActivityType) -> ImportedWorkoutSummary.Activity {
        switch type {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        default: return .other
        }
    }

    private func fetchRoute(for workout: HKWorkout, completion: @escaping ([RunLocationFix]) -> Void) {
        let routeQuery = HKSampleQuery(
            sampleType: HKSeriesType.workoutRoute(),
            predicate: HKQuery.predicateForObjects(from: workout),
            limit: 1,
            sortDescriptors: nil
        ) { [weak self] _, samples, _ in
            guard let self, let route = samples?.first as? HKWorkoutRoute else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            var fixes: [RunLocationFix] = []
            let locationQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    AppLog.health.error("Route stream failed: \(error.localizedDescription, privacy: .public)")
                }
                if let locations {
                    fixes.append(contentsOf: locations.map { location in
                        RunLocationFix(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            horizontalAccuracy: location.horizontalAccuracy,
                            timestamp: location.timestamp
                        )
                    })
                }
                if done {
                    DispatchQueue.main.async { completion(fixes) }
                }
            }
            self.healthStore.execute(locationQuery)
        }
        healthStore.execute(routeQuery)
    }
}
