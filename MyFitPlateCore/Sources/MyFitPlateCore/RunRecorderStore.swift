import Foundation
import HealthKit
import CoreLocation

public enum RunRecorderRules {
    /// True when another app's workout meaningfully overlaps the run window (over a
    /// minute). If the user's watch recorded the same run, its energy/distance samples
    /// are the better ones — writing ours too would double-count the day's burn, the
    /// same failure mode as the old strength double-count.
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
public final class RunRecorderStore {

    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HealthKitManager.shared.healthStore) {
        self.healthStore = healthStore
    }

    /// Saves the run; completion (main queue) carries the HealthKit workout UUID, or nil
    /// on failure (failure is logged + non-fatal — the run summary was already shown, so
    /// the user's session is never lost to a save error).
    public func save(
        run: Run,
        locations: [CLLocation],
        weightLbs: Double,
        completion: @escaping (String?) -> Void
    ) {
        // Parallel-device guard: if a watch (or any other app) recorded this same window,
        // save our workout + route but defer energy/distance to that recording.
        fetchHasOverlappingExternalWorkout(start: run.startDate, end: run.endDate) { [weak self] hasExternal in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if hasExternal {
                AppLog.health.info("Another recording overlaps this run; deferring energy/distance samples to it.")
            }
            self.performSave(run: run, locations: locations, weightLbs: weightLbs, includeQuantitySamples: !hasExternal, completion: completion)
        }
    }

    private func fetchHasOverlappingExternalWorkout(start: Date, end: Date, completion: @escaping (Bool) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: 25,
            sortDescriptors: nil
        ) { _, samples, _ in
            let windows = ((samples as? [HKWorkout]) ?? []).map { workout in
                (
                    start: workout.startDate,
                    end: workout.endDate,
                    isOwn: RunImportRules.isOwnRecording(sourceBundleID: workout.sourceRevision.source.bundleIdentifier)
                )
            }
            completion(RunRecorderRules.hasExternalOverlap(runStart: start, runEnd: end, workouts: windows))
        }
        healthStore.execute(query)
    }

    private func performSave(
        run: Run,
        locations: [CLLocation],
        weightLbs: Double,
        includeQuantitySamples: Bool,
        completion: @escaping (String?) -> Void
    ) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = run.isIndoor ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        func fail(_ stage: String, _ error: Error?) {
            AppLog.health.error("Run save failed at \(stage, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
            DispatchQueue.main.async { completion(nil) }
        }

        builder.beginCollection(withStart: run.startDate) { [healthStore] began, error in
            guard began else { return fail("begin", error) }

            var samples: [HKSample] = []
            if includeQuantitySamples, run.distanceMeters > 0, let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                samples.append(HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: run.distanceMeters),
                    start: run.startDate,
                    end: run.endDate
                ))
            }
            let kcal = run.activeCalories ?? RunEnergy.estimateKcal(distanceMeters: run.distanceMeters, weightLbs: weightLbs)
            if includeQuantitySamples, kcal > 0, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                samples.append(HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: run.startDate,
                    end: run.endDate
                ))
            }

            let addSamplesAndFinish = {
                builder.endCollection(withEnd: run.endDate) { ended, error in
                    guard ended else { return fail("end", error) }
                    builder.finishWorkout { workout, error in
                        guard let workout else { return fail("finish", error) }

                        guard locations.count > 1 else {
                            DispatchQueue.main.async { completion(workout.uuid.uuidString) }
                            return
                        }
                        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                        routeBuilder.insertRouteData(locations) { inserted, error in
                            guard inserted else {
                                // The workout itself saved; a lost route is a degraded
                                // result, not a failure.
                                AppLog.health.error("Route insert failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                                DispatchQueue.main.async { completion(workout.uuid.uuidString) }
                                return
                            }
                            routeBuilder.finishRoute(with: workout, metadata: nil) { _, error in
                                if let error {
                                    AppLog.health.error("Route finish failed: \(error.localizedDescription, privacy: .public)")
                                }
                                DispatchQueue.main.async { completion(workout.uuid.uuidString) }
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
