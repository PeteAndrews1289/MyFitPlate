import Foundation
import HealthKit
import CoreLocation

public enum RunRecorderRules {
    public static let recordingIDMetadataKey = "MyFitPlateRecordingID"
    /// Legacy runs have no known pause history. Partial timelines export their known
    /// boundaries only; a complete timeline must reconcile with the active duration.
    public static func workoutEvents(for run: Run) -> [HKWorkoutEvent]? {
        guard let timeline = run.pauseTimeline else { return [] }
        guard let intervals = timeline.validatedUnionIntervals(startDate: run.startDate, endDate: run.endDate,
                                                               activeSeconds: run.movingSeconds) else { return nil }
        return intervals.flatMap { interval in
            [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: interval.start, duration: 0), metadata: nil),
             HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: interval.end, duration: 0), metadata: nil)]
        }
    }

    /// Route samples may arrive flattened at the recorder seam. Restore explicit
    /// segment boundaries before export; the workout metrics are never recalculated.
    public static func routeSegments(for run: Run, locations: [CLLocation]) -> [[CLLocation]] {
        let starts = (run.routeSegmentStarts ?? []).sorted()
        var result: [[CLLocation]] = []
        var previous: CLLocation?
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard location.timestamp >= run.startDate, location.timestamp <= run.endDate,
                  CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy.isFinite,
                  (0...RunSession.accuracyCutoffMeters).contains(location.horizontalAccuracy),
                  previous.map({ location.timestamp > $0.timestamp }) ?? true else { continue }
            let boundary = previous.map { prior in
                starts.contains { $0 > prior.timestamp && $0 <= location.timestamp }
                    || location.timestamp.timeIntervalSince(prior.timestamp) > RunSession.movingTimeGapCapSeconds
                    || (run.pauseTimeline?.intervals.contains {
                        $0.startDate >= prior.timestamp && $0.endDate <= location.timestamp
                    } ?? false)
            } ?? true
            if boundary { result.append([location]) } else { result[result.count - 1].append(location) }
            previous = location
        }
        return result.filter { $0.count > 1 }
    }

    /// Window-only compatibility check. Export additionally requires evidence for
    /// each quantity; an overlapping workout alone does not establish duplication.
    public static func hasExternalOverlap(
        runStart: Date,
        runEnd: Date,
        workouts: [(start: Date, end: Date, isOwn: Bool)]
    ) -> Bool {
        workouts.contains { workout in
            guard !workout.isOwn else { return false }
            let overlap = min(runEnd, workout.end).timeIntervalSince(max(runStart, workout.start))
            return overlap > 60
        }
    }

    struct WorkoutQuantityEvidence: Sendable {
        let start: Date
        let end: Date
        let sourceBundleID: String
        let activity: HKWorkoutActivityType
        /// Typed distanceWalkingRunning statistics, never a generic cycling distance.
        let distanceMeters: Double?
        let activeCalories: Double?
    }

    struct QuantitySuppression: Equatable, Sendable {
        var distance = false
        var activeEnergy = false
    }

    static func quantitySuppression(
        runStart: Date, runEnd: Date, workouts: [WorkoutQuantityEvidence]
    ) -> QuantitySuppression {
        var result = QuantitySuppression()
        guard runStart.timeIntervalSinceReferenceDate.isFinite, runEnd.timeIntervalSinceReferenceDate.isFinite,
              runEnd > runStart else { return result }
        for workout in workouts {
            guard !RunImportRules.isOwnRecording(sourceBundleID: workout.sourceBundleID),
                  workout.start.timeIntervalSinceReferenceDate.isFinite, workout.end.timeIntervalSinceReferenceDate.isFinite,
                  workout.end > workout.start,
                  min(runEnd, workout.end).timeIntervalSince(max(runStart, workout.start)) > 60 else { continue }
            if let calories = workout.activeCalories, calories.isFinite, calories > 0 {
                result.activeEnergy = true
            }
            if workout.activity == .running || workout.activity == .walking,
               let meters = workout.distanceMeters, meters.isFinite, meters > 0 {
                result.distance = true
            }
        }
        return result
    }
}

/// A successful Health commit can temporarily lack a readable workout while locked.
/// That state must not invite a second write or discard the local recording identity.
public enum RunHealthSaveOutcome: Equatable, Sendable {
    case saved(String)
    case savedRoutePending(String)
    case savedAwaitingReadAccess
    /// An interrupted write has no readable receipt; it may or may not have committed.
    case confirmationRequired
    case failed
}

public enum RunEnergy {
    /// Flat-ground running cost ≈ 1.036 kcal per kg per km — the standard estimate when
    /// there's no heart-rate stream to do better.
    public static func estimateKcal(distanceMeters: Double, weightLbs: Double) -> Double {
        guard distanceMeters > 0, weightLbs > 0 else { return 0 }
        let kg = weightLbs * 0.45359237
        return (distanceMeters / 1000) * kg * 1.036
    }
}

/// Writes an in-app recorded run back to HealthKit — workout, distance, energy, and the
/// GPS route — so the run shows up in Apple Health, in other fitness apps, and back in
/// our own import path exactly like a watch recording would.
public final class RunRecorderStore: RunHealthSaving {

    private let healthStore: HealthStoreScheduling

    public init(healthStore: HealthStoreScheduling = HealthKitManager.shared.store) {
        self.healthStore = healthStore
    }

    /// Compatibility API: nil means there is no readable UUID, including a committed
    /// workout awaiting read access. New callers should use saveWithOutcome.
    public func save(
        run: Run,
        locations: [CLLocation],
        weightLbs: Double,
        completion: @escaping (String?) -> Void
    ) {
        saveWithOutcome(run: run, locations: locations, weightLbs: weightLbs) { outcome in
            switch outcome {
            case .saved(let id), .savedRoutePending(let id): completion(id)
            case .savedAwaitingReadAccess, .confirmationRequired, .failed: completion(nil)
            }
        }
    }

    /// Completion is delivered on the main queue; the app has already committed its
    /// local copy before calling this asynchronous writer.
    public func saveWithOutcome(
        run: Run,
        locations: [CLLocation],
        weightLbs: Double,
        completion: @escaping (RunHealthSaveOutcome) -> Void
    ) {
        let recordingID = run.recordingID ?? run.id
        guard RunSaveReviewRules.canSave(run), let events = RunRecorderRules.workoutEvents(for: run) else {
            AppLog.health.error("Run export rejected an inconsistent pause timeline; local metrics are retained.")
            DispatchQueue.main.async { completion(.failed) }
            return
        }
        guard !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DispatchQueue.main.async { completion(.failed) }
            return
        }
        // Defer only quantities another source actually recorded. A strength/cycling
        // window can carry energy evidence without replacing the run's distance.
        fetchQuantitySuppression(start: run.startDate, end: run.endDate) { [self] suppression in
            if suppression.distance || suppression.activeEnergy {
                AppLog.health.info("External workout quantities overlap this run; deferring matching samples.")
            }
            self.performSave(run: run, locations: locations, events: events, weightLbs: weightLbs,
                             recordingID: recordingID, suppression: suppression, completion: completion)
        }
    }

    public func reconcileRecording(recordingID: String, completion: @escaping (String?) -> Void) {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForObjects(withMetadataKey: RunRecorderRules.recordingIDMetadataKey, allowedValues: [recordingID])
        ])
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 2, sortDescriptors: nil) { _, samples, error in
            let matching = ((samples as? [HKWorkout]) ?? []).filter {
                RunImportRules.isOwnRecording(sourceBundleID: $0.sourceRevision.source.bundleIdentifier)
                    && ($0.metadata?[RunRecorderRules.recordingIDMetadataKey] as? String) == recordingID
            }
            DispatchQueue.main.async { completion(error == nil && matching.count == 1 ? matching.first?.uuid.uuidString : nil) }
        }
        healthStore.execute(query)
    }

    public func repairRoute(run: Run, locations: [CLLocation], healthID: String, completion: @escaping (RunHealthSaveOutcome) -> Void) {
        guard let uuid = UUID(uuidString: healthID) else { completion(.savedRoutePending(healthID)); return }
        healthStore.repairWorkoutRoute(workoutID: uuid, recordingID: run.recordingID ?? run.id,
                                      routeSegments: RunRecorderRules.routeSegments(for: run, locations: locations)) { success, _ in
            DispatchQueue.main.async { completion(success ? .saved(healthID) : .savedRoutePending(healthID)) }
        }
    }

    private func fetchQuantitySuppression(start: Date, end: Date, completion: @escaping (RunRecorderRules.QuantitySuppression) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: 25,
            sortDescriptors: nil
        ) { _, samples, _ in
            let evidence = ((samples as? [HKWorkout]) ?? []).map { workout in
                RunRecorderRules.WorkoutQuantityEvidence(
                    start: workout.startDate,
                    end: workout.endDate,
                    sourceBundleID: workout.sourceRevision.source.bundleIdentifier,
                    activity: workout.workoutActivityType,
                    distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?.doubleValue(for: .meter()),
                    activeCalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie())
                )
            }
            completion(RunRecorderRules.quantitySuppression(runStart: start, runEnd: end, workouts: evidence))
        }
        healthStore.execute(query)
    }

    private func performSave(
        run: Run,
        locations: [CLLocation],
        events: [HKWorkoutEvent],
        weightLbs: Double,
        recordingID: String,
        suppression: RunRecorderRules.QuantitySuppression,
        completion: @escaping (RunHealthSaveOutcome) -> Void
    ) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = run.isIndoor ? .indoor : .outdoor

        var samples: [HKSample] = []
        if !suppression.distance, run.distanceMeters > 0, let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            samples.append(HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: run.distanceMeters),
                start: run.startDate,
                end: run.endDate,
                metadata: syncMetadata(recordingID: recordingID, kind: distanceType.identifier)
            ))
        }
        let kcal = run.activeCalories ?? RunEnergy.estimateKcal(distanceMeters: run.distanceMeters, weightLbs: weightLbs)
        if !suppression.activeEnergy, kcal > 0, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: run.startDate,
                end: run.endDate,
                metadata: syncMetadata(recordingID: recordingID, kind: energyType.identifier)
            ))
        }

        var metadata = syncMetadata(recordingID: recordingID, kind: "workout")
        metadata[RunRecorderRules.recordingIDMetadataKey] = recordingID
        if let review = run.saveReview { metadata[RunSaveReviewRules.healthReviewMetadataKey] = review.rawValue }
        healthStore.saveWorkout(
            configuration: configuration,
            start: run.startDate,
            end: run.endDate,
            samples: samples,
            routeSegments: RunRecorderRules.routeSegments(for: run, locations: locations),
            events: events,
            metadata: metadata
        ) { uuid, error in
            let outcome: RunHealthSaveOutcome
            if error as? HealthWorkoutWriteError == .savedButUnreadable {
                outcome = .savedAwaitingReadAccess
            } else if error as? HealthWorkoutWriteError == .routeAttachmentFailed, let uuid, !uuid.isEmpty {
                outcome = .savedRoutePending(uuid)
            } else if error == nil, let uuid, !uuid.isEmpty {
                outcome = .saved(uuid)
            } else {
                outcome = .failed
            }
            if let error, outcome == .failed {
                AppLog.health.error("Run save failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private func syncMetadata(recordingID: String, kind: String) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: "myfitplate.recorded-run.\(recordingID).\(kind)", HKMetadataKeySyncVersion: 1]
    }
}
