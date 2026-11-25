import Foundation

/// A review destination for one already accepted Fuel outcome. Opening a run never
/// creates another nutrition allocation or substitutes the currently selected diary.
public struct RunFuelReviewRequest: Codable, Equatable, Identifiable {
    public enum Intent: String, Codable { case linkedOutcome, planner }
    public let intent: Intent
    public let id: String
    public let ownerID: String
    public let planID: String?
    public let revisionID: String?
    public let outcome: TrainingFuelSessionOutcome?
    public let day: DiaryDayContext

    public static func make(run: Run, history: [TrainingFuelRevision], conflictingPlanIDs: [String],
                            ownerID: String, calendar: Calendar = .current) -> Self? {
        guard run.endDate.timeIntervalSinceReferenceDate.isFinite, run.startDate <= run.endDate,
              let day = DiaryDayContext(userID: ownerID, date: run.endDate, timeZone: calendar.timeZone) else { return nil }
        let identities = Set([run.id, run.recordingID].compactMap { $0 })
        let matches = history.filter { revision in
            guard revision.archivedAt == nil, revision.plan.ownerID == ownerID,
                  !conflictingPlanIDs.contains(revision.plan.id), let outcome = revision.plan.outcome,
                  outcome.status == .completed, [.recordedRun, .treadmillRun].contains(outcome.source),
                  let reference = outcome.referenceID, identities.contains(reference),
                  let start = outcome.actualStartAt, let end = outcome.actualEndAt else { return false }
            // Corrections keep the raw run window; never match unrelated workouts by time.
            return abs(start.timeIntervalSince(run.startDate)) < 1 && abs(end.timeIntervalSince(run.endDate)) < 1
        }
        guard matches.count == 1, let revision = matches.first, let outcome = revision.plan.outcome else { return nil }
        return Self(intent: .linkedOutcome, id: UUID().uuidString, ownerID: ownerID, planID: revision.plan.id,
                    revisionID: revision.id, outcome: outcome, day: day)
    }

    /// Explicitly open the ordinary planner. No link or allocation to this run is
    /// claimed, and any existing reviewed plan remains intact until the user edits it.
    public static func planning(ownerID: String, now: Date = Date(), calendar: Calendar = .current) -> Self? {
        guard let day = DiaryDayContext(userID: ownerID, date: now, timeZone: calendar.timeZone) else { return nil }
        return Self(intent: .planner, id: UUID().uuidString, ownerID: ownerID, planID: nil,
                    revisionID: nil, outcome: nil, day: day)
    }

    public func isCurrent(history: [TrainingFuelRevision], conflictingPlanIDs: [String], currentUserID: String?) -> Bool {
        guard ownerID == currentUserID, day.userID == ownerID else { return false }
        if intent == .planner { return planID == nil && revisionID == nil && outcome == nil }
        guard let planID, !conflictingPlanIDs.contains(planID) else { return false }
        let matches = history.filter { $0.plan.id == planID }
        return matches.count == 1 && matches[0].id == revisionID && matches[0].archivedAt == nil
            && matches[0].plan.ownerID == ownerID && matches[0].plan.outcome == outcome
    }
}
