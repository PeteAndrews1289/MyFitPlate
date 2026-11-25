import Foundation

public enum MealExperimentEvidenceRules {
    public struct EligibleSlot: Equatable {
        public let slot: Int
        public let date: Date
    }
    public static func eligibleSlots(in program: WorkoutProgram, routineID: String, protectedSlots: Set<Int> = [],
                                     now: Date = Date(), calendar: Calendar = .current) -> [EligibleSlot] {
        let first = max(0, program.currentProgressIndex ?? 0)
        guard first < program.totalSlots else { return [] }
        return (first..<program.totalSlots).compactMap { slot in
            guard !protectedSlots.contains(slot), !(program.skippedIndices ?? []).contains(slot),
                  !(program.slotCompletionProofs ?? []).contains(where: { $0.slotIndex == slot }),
                  program.routine(forSlot: slot)?.id == routineID,
                  let date = program.date(forSlot: slot, calendar: calendar),
                  date >= calendar.startOfDay(for: now) else { return nil }
            return EligibleSlot(slot: slot, date: date)
        }
    }

    public static func matches(_ session: WorkoutSessionLog, experiment: MealExperiment,
                               trial: MealExperimentTrial? = nil, allowLegacy: Bool, now: Date = Date()) -> Bool {
        guard session.id?.isEmpty == false, session.routineID == experiment.routineID,
              session.programLinkDecision != .standalone, session.date.timeIntervalSinceReferenceDate.isFinite,
              session.date >= experiment.createdAt, session.date <= now else { return false }
        guard let context = session.programContext else { return allowLegacy }
        return context.programID == experiment.programID && (trial == nil || context.slotIndex == trial?.slot)
    }

    public static func identity(_ observation: MealExperimentObservation) -> String {
        (observation.revisionID ?? "legacy") + "-" + ((try? PlanFingerprint.make(observation)) ?? "unreadable-observation")
    }
    public static func range(_ values: [Double]) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard let lower = finite.min(), let upper = finite.max() else { return nil }
        return lower...upper
    }
    public static func contains(_ history: [MealExperimentObservation]?, _ value: MealExperimentObservation) -> Bool {
        history?.contains { identity($0) == identity(value) } == true
    }
    public static func union(_ values: [MealExperimentObservation]) -> [MealExperimentObservation] {
        var seen = Set<String>()
        return values.filter { seen.insert(identity($0)).inserted }.sorted { identity($0) < identity($1) }
    }

    public static func correcting(_ experiment: MealExperiment, trialID: String, expectedObservationID: String,
                                  session: WorkoutSessionLog, energy: Int, comfort: Int, minutesBefore: Int,
                                  confounders: [String], note: String, confirmedLegacySession: Bool,
                                  now: Date = Date()) throws -> MealExperiment {
        guard let index = experiment.trials.firstIndex(where: { $0.id == trialID }),
              let previous = experiment.trials[index].observation, identity(previous) == expectedObservationID,
              (experiment.trials[index].conflictingObservations ?? []).isEmpty else { throw MealExperimentError.stale }
        var editable = experiment
        editable.trials[index].observation = nil
        // A finished comparison can correct an existing observation without
        // reopening its schedule or changing the accepted workout receipt.
        let ended = editable.endedAt; editable.endedAt = nil
        var updated = try MealExperimentRules.recording(in: editable, trialID: trialID, session: session,
            energy: energy, comfort: comfort, minutesBefore: minutesBefore, confounders: confounders, note: note,
            confirmedLegacySession: confirmedLegacySession, now: now)
        updated.endedAt = ended
        updated.trials[index].observationHistory = union((experiment.trials[index].observationHistory ?? []) + [previous])
        return updated
    }

    public static func correctingRatings(_ experiment: MealExperiment, trialID: String, expectedObservationID: String,
                                         energy: Int, comfort: Int, minutesBefore: Int, confounders: [String], note: String,
                                         confirmedLegacySession: Bool, now: Date = Date()) throws -> MealExperiment {
        guard let index = experiment.trials.firstIndex(where: { $0.id == trialID }),
              let previous = experiment.trials[index].observation, identity(previous) == expectedObservationID,
              (experiment.trials[index].conflictingObservations ?? []).isEmpty,
              previous.sourceProgramID != nil || confirmedLegacySession else { throw MealExperimentError.stale }
        guard (1...5).contains(energy), (1...5).contains(comfort), (0...360).contains(minutesBefore) else { throw MealExperimentError.invalidRating }
        let automatic = previous.confounders.filter {
            ["Workout exercises changed", "Working set count changed", "Check-in more than two days later"].contains($0)
        }
        var flags = automatic + confounders
        if abs(minutesBefore - experiment.minutesBefore) > 30 { flags.append("Meal timing changed") }
        var updated = experiment
        updated.trials[index].observationHistory = union((experiment.trials[index].observationHistory ?? []) + [previous])
        updated.trials[index].observation = MealExperimentObservation(sessionID: previous.sessionID, sessionDate: previous.sessionDate,
            energy: energy, comfort: comfort, minutesBefore: minutesBefore, confounders: Array(Set(flags)).sorted(),
            workingSets: previous.workingSets, volume: previous.volume, meanRPE: previous.meanRPE, note: String(note.prefix(300)),
            revisionID: UUID().uuidString, recordedAt: now, scaleVersion: previous.scaleVersion ?? 1,
            sourceProgramID: previous.sourceProgramID, sourceSlot: previous.sourceSlot, evidenceFingerprint: previous.evidenceFingerprint)
        return updated
    }

    public static func resolving(_ experiment: MealExperiment, trialID: String, chosenObservationID: String,
                                 expectedFingerprint: String, now: Date = Date()) throws -> MealExperiment {
        guard let index = experiment.trials.firstIndex(where: { $0.id == trialID }),
              try PlanFingerprint.make(experiment.trials[index]) == expectedFingerprint,
              let current = experiment.trials[index].observation else { throw MealExperimentError.stale }
        let options = [current] + (experiment.trials[index].conflictingObservations ?? [])
        guard var chosen = options.first(where: { identity($0) == chosenObservationID }) else { throw MealExperimentError.stale }
        var updated = experiment
        updated.trials[index].observationHistory = union((experiment.trials[index].observationHistory ?? []) + options)
        chosen.revisionID = UUID().uuidString; chosen.recordedAt = now
        updated.trials[index].observation = chosen
        updated.trials[index].conflictingObservations = nil
        return updated
    }

    /// Same-session edits retain alternatives until an explicit reviewed resolution.
    /// A correction that names the earlier observation in its history is causal.
    public static func mergeSameSession(existing: MealExperimentTrial, incoming: MealExperimentTrial,
                                        incomingIsNewer: Bool) -> MealExperimentTrial {
        guard let old = existing.observation, let new = incoming.observation else { return incomingIsNewer ? incoming : existing }
        var chosen: MealExperimentTrial
        if contains(incoming.observationHistory, old) { chosen = incoming } else if contains(existing.observationHistory, new) { chosen = existing } else { chosen = incomingIsNewer ? incoming : existing }
        let history = union((existing.observationHistory ?? []) + (incoming.observationHistory ?? []))
        chosen.observationHistory = history.isEmpty ? nil : history
        var alternatives = (existing.conflictingObservations ?? []) + (incoming.conflictingObservations ?? [])
        if identity(old) != identity(new), !contains(incoming.observationHistory, old), !contains(existing.observationHistory, new) {
            alternatives += [old, new]
        }
        let selectedID = chosen.observation.map(identity)
        alternatives = union(alternatives).filter {
            identity($0) != selectedID && !contains(chosen.observationHistory, $0)
        }
        chosen.conflictingObservations = alternatives.isEmpty ? nil : alternatives
        return chosen
    }

    public static func export(_ experiment: MealExperiment) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        guard let result = String(data: try encoder.encode(experiment), encoding: .utf8) else { throw MealExperimentError.unavailable }
        return result
    }
}
