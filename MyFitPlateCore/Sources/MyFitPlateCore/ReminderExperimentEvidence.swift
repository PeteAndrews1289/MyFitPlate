import Foundation

/// A reminder may point only to a still-unanswered trial and its exact accepted program/session occurrence.
public struct ReminderExperimentEvidence: Equatable {
    public let ownerID: String
    public let experimentID: String
    public let trialID: String
    public let sessionID: String
    public let sessionDate: Date
    public let expiresAt: Date
    public let fingerprint: String

    public func matches(_ target: ReminderTarget, now: Date) -> Bool {
        target.kind == .experimentCheckIn && target.ownerID == ownerID && now < expiresAt
            && target.experimentID == experimentID && target.experimentTrialID == trialID
            && target.experimentSessionID == sessionID && target.experimentFingerprint == fingerprint
    }

    public static func eligible(ownerID: String, experiments: [MealExperiment], sessions: [WorkoutSessionLog],
                                now: Date = Date()) -> [ReminderExperimentEvidence] {
        guard !ownerID.isEmpty else { return [] }
        var result: [ReminderExperimentEvidence] = []
        for experiment in experiments where !experiment.isFinished {
            let used = Set(experiment.trials.compactMap { $0.observation?.sessionID })
            for trial in experiment.trials where trial.observation == nil && !trial.skipped
                && (trial.conflictingObservations ?? []).isEmpty {
                let matching = sessions.filter { session in
                    guard let id = session.id, !used.contains(id), !session.completedExercises.flatMap(\.sets).isEmpty else { return false }
                    return MealExperimentEvidenceRules.matches(session, experiment: experiment, trial: trial, allowLegacy: false, now: now)
                        && session.date.addingTimeInterval(48 * 3_600) > now
                }
                // Multiple completed copies of the occurrence need a person's review, not a guessed match.
                guard matching.count == 1, let session = matching.first, let sessionID = session.id,
                      let fingerprint = try? PlanFingerprint.make([
                        ownerID, experiment.id, experiment.programID, experiment.routineID, String(experiment.minutesBefore),
                        PlanFingerprint.make(experiment.mealA), PlanFingerprint.make(experiment.mealB),
                        PlanFingerprint.make(trial), PlanFingerprint.make(session)
                      ]) else { continue }
                result.append(.init(ownerID: ownerID, experimentID: experiment.id, trialID: trial.id,
                    sessionID: sessionID, sessionDate: session.date, expiresAt: session.date.addingTimeInterval(48 * 3_600),
                    fingerprint: fingerprint))
            }
        }
        return result.sorted { $0.sessionDate == $1.sessionDate ? $0.trialID < $1.trialID : $0.sessionDate < $1.sessionDate }
    }
}
