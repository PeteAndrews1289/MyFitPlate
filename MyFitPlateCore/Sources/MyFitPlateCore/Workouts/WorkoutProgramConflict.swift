import Foundation

public struct WorkoutEditorConflict: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var localSummary: String
    public var savedSummary: String
}
public enum WorkoutEditorConflictChoice: String, Codable { case mine, saved }
public struct WorkoutProgramMergeReview {
    public let conflicts: [WorkoutEditorConflict]
    fileprivate let baseline: Data
    fileprivate let local: Data
    fileprivate let saved: Data
}
public enum WorkoutProgramMergeRules {
    public static func review(baseline: WorkoutProgram, local: WorkoutProgram, saved: WorkoutProgram) throws -> WorkoutProgramMergeReview {
        guard baseline.id == local.id, local.id == saved.id, baseline.userID == local.userID, local.userID == saved.userID else { throw WorkoutBlockError.accountChanged }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var conflicts: [WorkoutEditorConflict] = []
        func add<Value: Encodable>(_ id: String, _ title: String, _ before: Value, _ mine: Value, _ remote: Value, mineText: String, remoteText: String) throws {
            let original = try encoder.encode(before), local = try encoder.encode(mine), saved = try encoder.encode(remote)
            if local != original && saved != original && local != saved {
                conflicts.append(WorkoutEditorConflict(id: id, title: title, localSummary: mineText, savedSummary: remoteText))
            }
        }
        try add("name", "Program name", baseline.name, local.name, saved.name, mineText: local.name, remoteText: saved.name)
        try add("start", "Training start date", baseline.startDate, local.startDate, saved.startDate,
            mineText: local.startDate?.formatted() ?? "Not scheduled", remoteText: saved.startDate?.formatted() ?? "Not scheduled")
        try add("days", "Weekdays", baseline.daysOfWeek, local.daysOfWeek, saved.daysOfWeek,
            mineText: String(describing: local.daysOfWeek ?? []), remoteText: String(describing: saved.daysOfWeek ?? []))
        try add("order", "Routine rotation order", baseline.routines.map(\.id), local.routines.map(\.id), saved.routines.map(\.id),
            mineText: local.routines.map(\.name).joined(separator: " → "), remoteText: saved.routines.map(\.name).joined(separator: " → "))
        let ids = Set(baseline.routines.map(\.id) + local.routines.map(\.id) + saved.routines.map(\.id))
        for id in ids.sorted() {
            let before = baseline.routines.first { $0.id == id }, mine = local.routines.first { $0.id == id }, remote = saved.routines.first { $0.id == id }
            try add("routine:\(id)", "Session: \(mine?.name ?? remote?.name ?? before?.name ?? "Removed")", before, mine, remote,
                mineText: summary(mine), remoteText: summary(remote))
        }
        return WorkoutProgramMergeReview(conflicts: conflicts, baseline: try encoder.encode(baseline), local: try encoder.encode(local), saved: try encoder.encode(saved))
    }
    public static func resolving(_ review: WorkoutProgramMergeReview, choices: [String: WorkoutEditorConflictChoice], latest: WorkoutProgram) throws -> WorkoutProgram {
        let decoder = JSONDecoder()
        let before = try decoder.decode(WorkoutProgram.self, from: review.baseline)
        let mine = try decoder.decode(WorkoutProgram.self, from: review.local)
        let remote = try decoder.decode(WorkoutProgram.self, from: review.saved)
        guard try WorkoutBlockRules.structureFingerprint(remote) == WorkoutBlockRules.structureFingerprint(latest),
              review.conflicts.allSatisfy({ choices[$0.id] != nil }) else { throw WorkoutBlockError.changed }
        func choose<Value: Encodable>(_ id: String, _ old: Value, _ local: Value, _ saved: Value) throws -> Value {
            if review.conflicts.contains(where: { $0.id == id }) { return choices[id] == .mine ? local : saved }
            return try WorkoutBlockRules.fingerprint(local) != WorkoutBlockRules.fingerprint(old) ? local : saved
        }
        var result = latest
        result.name = try choose("name", before.name, mine.name, remote.name)
        result.startDate = try choose("start", before.startDate, mine.startDate, remote.startDate)
        result.daysOfWeek = try choose("days", before.daysOfWeek, mine.daysOfWeek, remote.daysOfWeek)
        var order = try choose("order", before.routines.map(\.id), mine.routines.map(\.id), remote.routines.map(\.id))
        for id in remote.routines.map(\.id) + mine.routines.map(\.id) where !order.contains(id) {
            // A routine removed deliberately in the selected rotation stays removed.
            if before.routines.contains(where: { $0.id == id }) && !review.conflicts.contains(where: { $0.id == "routine:\(id)" }) { continue }
            let chosen: WorkoutRoutine? = try choose("routine:\(id)", before.routines.first { $0.id == id }, mine.routines.first { $0.id == id }, remote.routines.first { $0.id == id })
            if chosen != nil { order.append(id) }
        }
        result.routines = try order.compactMap { id in
            try choose("routine:\(id)", before.routines.first { $0.id == id }, mine.routines.first { $0.id == id }, remote.routines.first { $0.id == id })
        }
        try WorkoutProgramEditRules.validateOrdinarySave(result, against: latest)
        return try WorkoutLibraryRules.preservingPassedDates(in: result, from: latest)
    }
    private static func summary(_ routine: WorkoutRoutine?) -> String {
        guard let routine else { return "Session removed" }
        return routine.name + "\n" + routine.exercises.map { exercise in
            "\(exercise.name): " + exercise.sets.map { $0.prescription?.summary ?? $0.target ?? "Manual" }.joined(separator: ", ")
        }.joined(separator: "\n")
    }
}

public struct WorkoutProgramEditCommand: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case weekRescue }
    public var kind: Kind?
    public let id: String
    public let ownerID: String
    public let programID: String
    public let expectedData: Data
    public let proposedData: Data
    public let protectedSlots: [Int]
    public init(expected: WorkoutProgram, proposed: WorkoutProgram, id: String = UUID().uuidString, protectedSlots: Set<Int> = [], kind: Kind? = nil) throws {
        guard let programID = expected.id, proposed.id == programID, expected.userID == proposed.userID,
              !programID.isEmpty, !id.isEmpty, !id.contains("/"), id.count <= 128 else { throw WorkoutBlockError.invalid }
        self.kind = kind
        self.id = id; ownerID = expected.userID; self.programID = programID; self.protectedSlots = protectedSlots.sorted()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        expectedData = try encoder.encode(expected); proposedData = try encoder.encode(proposed)
        _ = try applying(to: expected)
    }
    public func expected() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: expectedData) }
    public func proposed() throws -> WorkoutProgram { try JSONDecoder().decode(WorkoutProgram.self, from: proposedData) }
    public func fingerprint() throws -> String { try PlanFingerprint.make(self) }
    public func applying(to latest: WorkoutProgram) throws -> WorkoutProgram {
        let expected = try expected(), proposed = try proposed()
        guard latest.id == programID, latest.userID == ownerID, expected.id == programID, expected.userID == ownerID,
              proposed.id == programID, proposed.userID == ownerID else { throw WorkoutBlockError.accountChanged }
        guard try WorkoutBlockRules.structureFingerprint(latest) == WorkoutBlockRules.structureFingerprint(expected) else { throw WorkoutBlockError.changed }
        if kind == .weekRescue {
            var unchanged = proposed; unchanged.weekRescue = expected.weekRescue
            guard try WorkoutBlockRules.fingerprint(unchanged) == WorkoutBlockRules.fingerprint(expected) else { throw WorkoutBlockError.invalid }
            var result = latest
            if let rescue = proposed.weekRescue {
                result = try WeekRescueRules.applying(rescue, to: latest)
            } else {
                guard let rescueID = expected.weekRescue?.id, latest.weekRescue?.id == rescueID else { throw WorkoutBlockError.changed }
                result = try WeekRescueRules.undoing(id: rescueID, in: latest)
            }
            let protected = Set(protectedSlots).union((latest.slotCompletionProofs ?? []).map(\.slotIndex))
            result = try WorkoutLibraryRules.preservingPassedDates(in: result, from: latest, protectedSlots: protected)
            // Undo removes future guidance, never accepted log snapshots. Preserve
            // completed dates while active drafts retain their full current targets.
            let unchangedTargets = proposed.weekRescue == nil ? Set(protectedSlots) : protected
            for slot in unchangedTargets {
                guard latest.date(forSlot: slot) == result.date(forSlot: slot),
                      try WorkoutBlockRules.fingerprint(latest.routine(forSlot: slot)) == WorkoutBlockRules.fingerprint(result.routine(forSlot: slot)) else {
                    throw WorkoutBlockError.progressChanged
                }
            }
            return result
        }
        try WorkoutProgramEditRules.validateOrdinarySave(proposed, against: latest)
        var result = latest
        result.name = proposed.name; result.startDate = proposed.startDate; result.daysOfWeek = proposed.daysOfWeek; result.routines = proposed.routines
        result = try WorkoutLibraryRules.preservingPassedDates(in: result, from: latest, protectedSlots: Set(protectedSlots))
        guard !result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.routines.isEmpty, result.routines.allSatisfy({ $0.userID == ownerID && !$0.exercises.isEmpty }),
              result.daysOfWeek?.isEmpty == false else { throw WorkoutBlockError.invalid }
        return result
    }
}
public struct WorkoutProgramEditOperationReceipt: Codable, Equatable {
    public enum Status: String, Codable { case accepted, cancelled }
    public var id: String
    public var fingerprint: String
    public var programID: String
    public var status: Status
    public init(id: String, fingerprint: String, programID: String, status: Status) {
        self.id = id; self.fingerprint = fingerprint; self.programID = programID; self.status = status
    }
}
public enum WorkoutProgramEditResolution { case pending, accepted(WorkoutProgram?), cancelled }
