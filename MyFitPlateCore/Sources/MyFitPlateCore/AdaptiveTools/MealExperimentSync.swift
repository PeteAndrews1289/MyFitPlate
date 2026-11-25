import Foundation

public struct MealExperimentRevision: Codable, Comparable {
    public let date: Date
    public let token: String
    public init(date: Date = Date(), token: String = UUID().uuidString) { self.date = date; self.token = token }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.date == rhs.date ? lhs.token < rhs.token : lhs.date < rhs.date
    }
}

/// Merge individual trial changes, so an offline check-in does not replace another device's work.
public struct MealExperimentCloudState: Codable {
    public struct Record: Codable {
        public var value: MealExperiment
        public var revision: MealExperimentRevision
        public var trialRevisions: [String: MealExperimentRevision]
    }
    public var records: [String: Record] = [:]
    public var deletedBefore: Date?
    public var deletedExperimentIDs: [String: MealExperimentRevision]?
    public init() {}
    public var experiments: [MealExperiment] {
        records.values.map(\.value).filter { $0.createdAt > (deletedBefore ?? .distantPast) && deletedExperimentIDs?[$0.id] == nil }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }

    public mutating func update(_ experiment: MealExperiment, now: Date = Date()) {
        guard deletedExperimentIDs?[experiment.id] == nil else { return }
        let revision = MealExperimentRevision(date: now)
        let old = records[experiment.id]
        var stamps = old?.trialRevisions ?? [:]
        for trial in experiment.trials {
            let previous = old?.value.trials.first { $0.id == trial.id }
            if (try? PlanFingerprint.make(previous)) != (try? PlanFingerprint.make(Optional(trial))) {
                stamps[trial.id] = revision
            }
        }
        records[experiment.id] = Record(value: experiment, revision: revision, trialRevisions: stamps)
    }

    public mutating func delete(experimentID: String, now: Date = Date()) {
        var deleted = deletedExperimentIDs ?? [:]
        deleted[experimentID] = MealExperimentRevision(date: now)
        deletedExperimentIDs = deleted
        records.removeValue(forKey: experimentID)
    }

    public mutating func deleteAll(now: Date = Date()) {
        deletedBefore = max(deletedBefore ?? .distantPast, now)
        records = records.filter { $0.value.value.createdAt > now }
    }

    public func merging(_ other: Self) -> Self {
        var result = self
        result.deletedBefore = [deletedBefore, other.deletedBefore].compactMap { $0 }.max()
        var deleted = deletedExperimentIDs ?? [:]
        for (id, revision) in other.deletedExperimentIDs ?? [:] { deleted[id] = max(deleted[id] ?? revision, revision) }
        result.deletedExperimentIDs = deleted.isEmpty ? nil : deleted
        for (id, incoming) in other.records {
            guard let existing = result.records[id] else { result.records[id] = incoming; continue }
            var merged = incoming.revision > existing.revision ? incoming : existing
            let fallback = MealExperimentRevision(date: .distantPast, token: "")
            var trials = Dictionary(existing.value.trials.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            var stamps = existing.trialRevisions
            for trial in incoming.value.trials {
                let previous = trials[trial.id]
                // Observations are append-only. A freshly created baseline on another
                // device cannot clear a check-in just because its timestamp is newer.
                if previous?.observation != nil, trial.observation == nil { continue }
                let incomingIsNewer = (incoming.trialRevisions[trial.id] ?? fallback) > (stamps[trial.id] ?? fallback)
                if let old = previous, let recorded = old.observation, let added = trial.observation,
                   recorded.sessionID == added.sessionID || MealExperimentEvidenceRules.contains(old.observationHistory, added)
                    || MealExperimentEvidenceRules.contains(trial.observationHistory, recorded) {
                    trials[trial.id] = MealExperimentEvidenceRules.mergeSameSession(existing: old, incoming: trial, incomingIsNewer: incomingIsNewer)
                    stamps[trial.id] = max(stamps[trial.id] ?? fallback, incoming.trialRevisions[trial.id] ?? fallback)
                    continue
                }
                if let old = previous, let recorded = old.observation, let added = trial.observation,
                   recorded.sessionID != added.sessionID {
                    let retained = incomingIsNewer ? old : trial
                    let sessionID = retained.observation?.sessionID ?? ""
                    let conflictID = trial.id + "-recovered-" + sessionID
                    trials[conflictID] = MealExperimentTrial(id: conflictID, slot: retained.slot, date: retained.date,
                        side: retained.side, observation: retained.observation, skipped: false,
                        observationHistory: retained.observationHistory, conflictingObservations: retained.conflictingObservations)
                    stamps[conflictID] = incomingIsNewer ? stamps[trial.id] : incoming.trialRevisions[trial.id]
                }
                if previous == nil || (previous?.observation == nil && trial.observation != nil) || incomingIsNewer {
                    trials[trial.id] = trial
                    stamps[trial.id] = incoming.trialRevisions[trial.id]
                }
            }
            // Keep independently recorded trials, including concurrent extensions. Summary
            // calculations deduplicate session IDs; a check-in is never silently discarded.
            merged.value.trials = trials.values.sorted { $0.slot == $1.slot ? $0.id < $1.id : $0.slot < $1.slot }
            merged.value.endedAt = [existing.value.endedAt, incoming.value.endedAt].compactMap { $0 }.max()
            merged.trialRevisions = stamps
            result.records[id] = merged
        }
        result.records = result.records.filter { $0.value.value.createdAt > (result.deletedBefore ?? .distantPast) && result.deletedExperimentIDs?[$0.key] == nil }
        return result
    }
}

public protocol MealExperimentRepository: AnyObject {
    /// Atomically merge with the server, returning the accepted union. Throw when offline.
    func merge(_ state: MealExperimentCloudState, userID: String) async throws -> MealExperimentCloudState
}

struct MealExperimentCheckpoint: Codable {
    var state: MealExperimentCloudState
    var pending: Bool
}
