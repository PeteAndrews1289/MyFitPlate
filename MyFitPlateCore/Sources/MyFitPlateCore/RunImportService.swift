import Foundation
import HealthKit
import CoreLocation

/// Reads running workouts out of HealthKit from ANY source — Apple Watch directly, or
/// Garmin/Polar/Coros/Suunto/Whoop via their companion apps' Health sync. Thin glue:
/// all decisions live in RunImportRules (tested); this class only builds queries and maps
/// HKWorkout into the plain ImportedWorkoutSummary the rules understand.
public final class RunImportService {

    private let healthStore: HealthStoreScheduling
    private let fallbackStore: RunFallbackStore

    public init(
        healthStore: HealthStoreScheduling = HealthKitManager.shared.store,
        fallbackStore: RunFallbackStore = .shared
    ) {
        self.healthStore = healthStore
        self.fallbackStore = fallbackStore
    }

    /// Runs since `since`, newest first, already filtered and de-duplicated.
    /// Completion is delivered on the main queue.
    public func fetchRuns(
        since: Date,
        userID: String? = nil,
        completion: @escaping ([Run]) -> Void
    ) {
        fetchRunsResult(since: since, userID: userID) { result in
            switch result {
            case .success(let runs): completion(runs)
            case .failure:
                let local = userID.map { self.fallbackStore.runs(since: since, for: $0) } ?? []
                completion(userID.flatMap { try? RunReviewStore().projecting(local, userID: $0) } ?? [])
            }
        }
    }

    public func fetchRunsResult(since: Date, userID: String? = nil, completion: @escaping (Result<[Run], Error>) -> Void) {
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
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let workouts = (samples as? [HKWorkout]) ?? []
            let healthRuns = workouts
                .map(Self.summary(from:))
                .filter(RunImportRules.isImportableRun)
                .map(RunImportRules.run(from:))
            let fallbackRuns = userID.map {
                self.fallbackStore.runs(since: since, for: $0)
            } ?? []
            let runs = RunLocalHistoryRules.merging(healthRuns: healthRuns, localRuns: fallbackRuns)
            DispatchQueue.main.async {
                do {
                    let reviewed = try userID.map { try RunReviewStore().projecting(runs, userID: $0) } ?? runs
                    completion(.success(reviewed))
                } catch { completion(.failure(error)) }
            }
        }
        healthStore.execute(query)
    }

    /// A complete available-history query for lifetime gear totals, independent of
    /// the hub's date window and its bounded recent-run query. Failure is explicit.
    public func fetchLifetimeRuns(userID: String, completion: @escaping (Result<[Run], Error>) -> Void) {
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            let healthRuns = ((samples as? [HKWorkout]) ?? []).map(Self.summary(from:))
                .filter(RunImportRules.isImportableRun).map(RunImportRules.run(from:))
            let local = self.fallbackStore.runs(since: .distantPast, for: userID)
            let runs = RunLocalHistoryRules.merging(healthRuns: healthRuns, localRuns: local)
            DispatchQueue.main.async {
                do { completion(.success(try RunReviewStore().projecting(runs, userID: userID))) } catch { completion(.failure(error)) }
            }
        }
        healthStore.execute(query)
    }

    /// Compatibility trace API. Map consumers use fetchRouteSegments to retain gaps.
    public func fetchRoute(forRunID runID: String, completion: @escaping ([RunLocationFix]) -> Void) {
        fetchHealthRouteSegments(forRunID: runID) { completion($0.flatMap { $0 }) }
    }

    public func fetchRouteSegments(for run: Run, userID: String?, completion: @escaping ([[RunLocationFix]]) -> Void) {
        if run.source == .recorded, let userID,
           let retained = try? RunRouteArchiveStore().load(recordingID: run.recordingID ?? run.id, userID: userID) {
            DispatchQueue.main.async { completion(retained.segments) }
            return
        }
        fetchHealthRouteSegments(forRunID: run.id) { segments in
            completion(segments.flatMap { Self.splitRoute($0, boundaries: run.routeSegmentStarts ?? []) })
        }
    }

    /// A legacy Health series can still carry explicit locally recorded boundaries.
    /// Also avoid connecting sparse GPS gaps whose path was not observed.
    static func splitRoute(_ fixes: [RunLocationFix], boundaries: [Date]) -> [[RunLocationFix]] {
        var segments: [[RunLocationFix]] = []
        var previous: RunLocationFix?
        for fix in fixes.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard previous.map({ fix.timestamp > $0.timestamp }) ?? true else { continue }
            let newSegment = previous.map { prior in
                fix.timestamp.timeIntervalSince(prior.timestamp) > RunSession.movingTimeGapCapSeconds
                    || boundaries.contains { $0 > prior.timestamp && $0 <= fix.timestamp }
            } ?? true
            if newSegment { segments.append([fix]) } else { segments[segments.count - 1].append(fix) }
            previous = fix
        }
        return segments
    }

    private func fetchHealthRouteSegments(forRunID runID: String, completion: @escaping ([[RunLocationFix]]) -> Void) {
        guard let uuid = UUID(uuidString: runID) else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let workoutQuery = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: uuid),
                                          limit: 1, sortDescriptors: nil) { [weak self] _, samples, _ in
            guard let self, let workout = samples?.first as? HKWorkout else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            self.fetchRouteSegments(for: workout, completion: completion)
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

    /// The full heart-rate series (in start-date order) for a run window — the input to
    /// time-in-zone. Empty when there's no HR data (e.g. a phone-only run with no sensor).
    public func fetchHeartRateSeries(start: Date, end: Date, completion: @escaping ([(date: Date, bpm: Double)]) -> Void) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: sort
        ) { _, samples, _ in
            let series: [(date: Date, bpm: Double)] = (samples as? [HKQuantitySample] ?? []).map {
                (date: $0.startDate, bpm: $0.quantity.doubleValue(for: bpmUnit))
            }
            DispatchQueue.main.async { completion(series) }
        }
        healthStore.execute(query)
    }

    /// Sensor evidence must belong to this workout. A time-window-only match can
    /// include another person's/device's ambient samples and is never used here.
    public func fetchWorkoutHeartRate(for run: Run, completion: @escaping ([RunHeartRateSample]) -> Void) {
        guard let uuid = UUID(uuidString: run.id), let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let workoutQuery = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: uuid), limit: 1, sortDescriptors: nil) { [weak self] _, samples, _ in
            guard let self, let workout = (samples as? [HKWorkout])?.first else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForObjects(from: workout),
                HKQuery.predicateForSamples(withStart: run.startDate, end: run.endDate, options: [.strictStartDate, .strictEndDate])
            ])
            let unit = HKUnit.count().unitDivided(by: .minute())
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let series = ((samples as? [HKQuantitySample]) ?? []).map { sample in
                    RunHeartRateSample(date: sample.startDate, bpm: sample.quantity.doubleValue(for: unit),
                        sourceID: sample.sourceRevision.source.bundleIdentifier + ":" + (sample.device?.localIdentifier ?? sample.device?.name ?? "unknown-device"),
                        sourceName: sample.sourceRevision.source.name)
                }
                DispatchQueue.main.async { completion(series) }
            }
            self.healthStore.execute(query)
        }
        healthStore.execute(workoutQuery)
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
            averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
            sourceName: workout.sourceRevision.source.name,
            sourceBundleID: workout.sourceRevision.source.bundleIdentifier,
            isIndoor: indoor,
            hasRoute: false,
            durationSeconds: workout.duration,
            recordingID: workout.metadata?[RunRecorderRules.recordingIDMetadataKey] as? String,
            saveReview: (workout.metadata?[RunSaveReviewRules.healthReviewMetadataKey] as? String).flatMap(RunSaveReview.init(rawValue:))
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

    private func fetchRouteSegments(for workout: HKWorkout, completion: @escaping ([[RunLocationFix]]) -> Void) {
        let routeQuery = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(),
                                      predicate: HKQuery.predicateForObjects(from: workout), limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { [weak self] _, samples, _ in
            guard let self else { DispatchQueue.main.async { completion([]) }; return }
            self.readRoutes((samples as? [HKWorkoutRoute]) ?? [], index: 0, accepted: [], completion: completion)
        }
        healthStore.execute(routeQuery)
    }

    private func readRoutes(_ routes: [HKWorkoutRoute], index: Int, accepted: [[RunLocationFix]],
                            completion: @escaping ([[RunLocationFix]]) -> Void) {
        guard routes.indices.contains(index) else {
            DispatchQueue.main.async { completion(accepted) }
            return
        }
        var fixes: [RunLocationFix] = []
        var failed = false
        let query = HKWorkoutRouteQuery(route: routes[index]) { [weak self] _, locations, done, error in
            guard let self else { return }
            if error != nil { failed = true }
            if let locations {
                fixes.append(contentsOf: locations.map {
                    RunLocationFix(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                                   horizontalAccuracy: $0.horizontalAccuracy, timestamp: $0.timestamp)
                })
            }
            if done {
                let next = failed || fixes.isEmpty ? accepted : accepted + [fixes]
                self.readRoutes(routes, index: index + 1, accepted: next, completion: completion)
            }
        }
        healthStore.execute(query)
    }
}
