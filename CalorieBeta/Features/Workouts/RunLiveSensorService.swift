import Foundation
import HealthKit
import CoreMotion
import MyFitPlateCore

/// Reads permissioned Health samples as they arrive and iPhone cadence. Health can
/// arrive late; this does not claim ownership of a Watch workout or a live Watch link.
@MainActor final class RunLiveSensorService {
    var onHeartRate: ((RunHeartRateSample) -> Void)?
    var onCadence: ((RunCadenceSample) -> Void)?
    private let health = HKHealthStore()
    private let pedometer = CMPedometer()
    private var query: HKAnchoredObjectQuery?
    private var generation = UUID()

    func start(at resumedAt: Date) {
        stop()
        let generation = self.generation
        if HKHealthStore.isHealthDataAvailable() {
            let type = HKQuantityType(.heartRate)
            let predicate = HKQuery.predicateForSamples(withStart: resumedAt, end: nil, options: .strictStartDate)
            let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, error in
                guard error == nil else { return }
                let evidence = (samples as? [HKQuantitySample] ?? []).sorted { $0.endDate < $1.endDate }.map {
                    RunHeartRateSample(date: $0.endDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                        sourceID: $0.sourceRevision.source.bundleIdentifier, sourceName: $0.sourceRevision.source.name)
                }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    for sample in evidence { self.onHeartRate?(sample) }
                }
            }
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
            query.updateHandler = handler
            self.query = query
            health.execute(query)
        }
        if CMPedometer.isCadenceAvailable() {
            pedometer.startUpdates(from: resumedAt) { [weak self] data, error in
                guard error == nil, let data, let value = data.currentCadence?.doubleValue else { return }
                let sample = RunCadenceSample(date: data.endDate, stepsPerMinute: value * 60)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.onCadence?(sample)
                }
            }
        }
    }
    func stop() {
        generation = UUID()
        if let query { health.stop(query) }
        query = nil
        pedometer.stopUpdates()
    }
    deinit { if let query { health.stop(query) }; pedometer.stopUpdates() }
}
