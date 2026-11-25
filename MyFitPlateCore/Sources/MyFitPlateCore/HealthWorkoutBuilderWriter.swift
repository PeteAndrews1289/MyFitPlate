import Foundation
import HealthKit

enum HealthWorkoutWriteError: LocalizedError, Equatable {
    case eventsUnsupported
    case invalidEventTimeline
    case savedButUnreadable
    case routeAttachmentFailed
    case failedStage(String)

    var errorDescription: String? {
        switch self {
        case .eventsUnsupported: return "This Health writer cannot preserve workout pause events."
        case .invalidEventTimeline: return "The workout event dates are invalid."
        case .routeAttachmentFailed: return "The workout is saved, but its route needs another sync attempt."
        case .savedButUnreadable: return "Apple Health saved the workout, but its identifier is not yet readable."
        case .failedStage(let stage): return "Apple Health could not finish the workout's \(stage) step."
        }
    }
}

/// HKWorkoutBuilder's entitled lifecycle is isolated behind this seam so acceptance
/// tests execute the same event ordering and error paths without a real Health store.
protocol HealthWorkoutBuilding: Sendable {
    func beginCollection(withStart start: Date, completion: @escaping @Sendable (Bool, Error?) -> Void)
    func addMetadata(_ metadata: [String: Any], completion: @escaping @Sendable (Bool, Error?) -> Void)
    func add(_ samples: [HKSample], completion: @escaping @Sendable (Bool, Error?) -> Void)
    func addWorkoutEvents(_ events: [HKWorkoutEvent], completion: @escaping @Sendable (Bool, Error?) -> Void)
    func endCollection(withEnd end: Date, completion: @escaping @Sendable (Bool, Error?) -> Void)
    func finishWorkout(completion: @escaping @Sendable (HKWorkout?, Error?) -> Void)
    func discardWorkout()
}

extension HKWorkoutBuilder: HealthWorkoutBuilding {}

struct HealthWorkoutBuilderWriter: Sendable {
    let builder: HealthWorkoutBuilding

    func save(start: Date, end: Date, samples: [HKSample], events: [HKWorkoutEvent],
              metadata: [String: Any] = [:],
              completion: @escaping @Sendable (HKWorkout?, Error?) -> Void) {
        let ordered = events.sorted { $0.dateInterval.start < $1.dateInterval.start }
        guard Self.valid(events: ordered, start: start, end: end) else {
            completion(nil, HealthWorkoutWriteError.invalidEventTimeline)
            return
        }
        let frozenMetadata = MetadataSnapshot(values: metadata)
        builder.beginCollection(withStart: start) { success, error in
            guard success, error == nil else { completion(nil, error ?? HealthWorkoutWriteError.failedStage("begin")); return }
            addMetadata(frozenMetadata.values, thenEvents: ordered, samples: samples, end: end, completion: completion)
        }
    }

    /// Recorder metadata contains immutable Foundation leaf values. Copy dictionary
    /// storage before crossing HealthKit's callback queues.
    private struct MetadataSnapshot: @unchecked Sendable { let values: [String: Any] }

    private func addMetadata(_ metadata: [String: Any], thenEvents events: [HKWorkoutEvent], samples: [HKSample], end: Date,
                             completion: @escaping @Sendable (HKWorkout?, Error?) -> Void) {
        guard !metadata.isEmpty else { addEvents(events, thenSamples: samples, end: end, completion: completion); return }
        builder.addMetadata(metadata) { success, error in
            guard success, error == nil else { fail("metadata", error: error, completion: completion); return }
            addEvents(events, thenSamples: samples, end: end, completion: completion)
        }
    }

    private func addEvents(_ events: [HKWorkoutEvent], thenSamples samples: [HKSample], end: Date,
                           completion: @escaping @Sendable (HKWorkout?, Error?) -> Void) {
        guard !events.isEmpty else { addSamples(samples, end: end, completion: completion); return }
        // Discarding a builder does not delete quantity samples already added to
        // Health. Validate and insert pause events before any such samples.
        builder.addWorkoutEvents(events) { success, error in
            guard success, error == nil else { fail("events", error: error, completion: completion); return }
            addSamples(samples, end: end, completion: completion)
        }
    }

    private func addSamples(_ samples: [HKSample], end: Date, completion: @escaping @Sendable (HKWorkout?, Error?) -> Void) {
        guard !samples.isEmpty else { finish(end: end, completion: completion); return }
        builder.add(samples) { success, error in
            guard success, error == nil else { fail("samples", error: error, completion: completion); return }
            finish(end: end, completion: completion)
        }
    }

    private func finish(end: Date, completion: @escaping @Sendable (HKWorkout?, Error?) -> Void) {
        builder.endCollection(withEnd: end) { success, error in
            guard success, error == nil else { fail("end", error: error, completion: completion); return }
            builder.finishWorkout { workout, error in
                if workout == nil, error == nil { completion(nil, HealthWorkoutWriteError.savedButUnreadable) } else { completion(workout, error) }
            }
        }
    }

    private func fail(_ stage: String, error: Error?, completion: @escaping @Sendable (HKWorkout?, Error?) -> Void) {
        builder.discardWorkout()
        completion(nil, error ?? HealthWorkoutWriteError.failedStage(stage))
    }

    private static func valid(events: [HKWorkoutEvent], start: Date, end: Date) -> Bool {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite, end >= start else { return false }
        return events.allSatisfy { event in
            let interval = event.dateInterval
            let instant = event.type == .pause || event.type == .resume
            return interval.start.timeIntervalSinceReferenceDate.isFinite && interval.end.timeIntervalSinceReferenceDate.isFinite
                && interval.start >= start && interval.end <= end && (!instant || interval.duration == 0)
        }
    }
}
