import Foundation

public struct WorkoutReportScope: Codable, Equatable {
    public var startDate: Date?
    public var endDate: Date?
    public var programID: String?
    public var blockID: String?
    public var exerciseType: ExerciseType?
    public var setupKey: String?
    public init(startDate: Date? = nil, endDate: Date? = nil, programID: String? = nil, blockID: String? = nil,
                exerciseType: ExerciseType? = nil, setupKey: String? = nil) {
        self.startDate = startDate; self.endDate = endDate; self.programID = programID; self.blockID = blockID
        self.exerciseType = exerciseType; self.setupKey = setupKey
    }
    public func contains(_ log: WorkoutSessionLog, now: Date = Date()) -> Bool {
        log.date <= now && (startDate.map { log.date >= $0 } ?? true) && (endDate.map { log.date <= $0 } ?? true)
            && (programID.map { log.programContext?.programID == $0 } ?? true)
            && (blockID.map { log.programContext?.blockSession?.blockID == $0 } ?? true)
            && (exerciseType.map { type in log.completedExercises.contains { $0.exercise.type == type } } ?? true)
            && (setupKey.map { key in log.completedExercises.contains { WorkoutEvidenceReportRules.setupKey($0.exercise) == key } } ?? true)
    }
}
public enum WorkoutTrendMetric: String, Codable, CaseIterable, Identifiable {
    case load, repetitions, volume, estimatedStrength, effort
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .load: "Peak working load"
        case .repetitions: "Working repetitions"
        case .volume: "Recorded working volume"
        case .estimatedStrength: "Estimated strength"
        case .effort: "Average recorded RPE"
        }
    }
}
public struct WorkoutReportPoint: Identifiable, Codable {
    public var id: String
    public var sessionID: String
    public var date: Date
    public var value: Double
    public var seriesID: String
    public var context: String
}
public struct WorkoutReportSetup: Identifiable, Codable {
    public var id: String
    public var name: String
    public var context: String
    public var workingSets: Int
    public var recordedVolume: Double?
}
public struct WorkoutEvidenceSnapshot: Codable {
    public var version: Int
    public var fingerprint: String
    public var scope: WorkoutReportScope
    public var updatedAt: Date
    public var sessionIDs: [String]
    public var workingSets: Int
    public var durationSeconds: Double
    public var effortSets: Int
    public var completedLinkedSlots: Int
    public var unassignedSessions: Int
    public var setups: [WorkoutReportSetup]
    public var setsByMuscle: [String: Int]
    public var headline: String {
        sessionIDs.isEmpty ? "No saved evidence in this scope" : "\(sessionIDs.count) saved sessions · \(workingSets) working sets"
    }
}
public enum WorkoutEvidenceReportRules {
    public static func setupKey(_ exercise: RoutineExercise) -> String {
        let movement = exercise.movementIdentity.map { "\($0.ownerID ?? "catalog")|\($0.movementID)|\($0.variantID)" }
            ?? "legacy|\(WorkoutSetMath.normalizedName(exercise.name))"
        let equipment = exercise.loadEquipment
        let implement = equipment?.gymProfile.map { "\($0.profileID)|\($0.implementID)" }
            ?? "\(equipment?.kind.rawValue ?? "unknown")|\(equipment?.name?.lowercased() ?? "unnamed")"
        return "\(movement)|\(exercise.type.rawValue)|\(implement)|\(equipment?.loadingMeaning.rawValue ?? "asLogged")"
    }
    public static func filtered(_ logs: [WorkoutSessionLog], scope: WorkoutReportScope, now: Date = Date()) -> [WorkoutSessionLog] {
        WorkoutSetMath.uniqueSessions(logs).filter { scope.contains($0, now: now) }.sorted { $0.date < $1.date }
    }
    public static func snapshot(logs: [WorkoutSessionLog], scope: WorkoutReportScope, now: Date = Date()) throws -> WorkoutEvidenceSnapshot {
        let selected = filtered(logs, scope: scope, now: now)
        var setups: [String: WorkoutReportSetup] = [:], muscles: [String: Int] = [:]
        var sets = 0, effort = 0
        for log in selected {
            for result in log.completedExercises where scope.setupKey == nil || setupKey(result.exercise) == scope.setupKey {
                if let type = scope.exerciseType, type != result.exercise.type { continue }
                let working = WorkoutSetMath.workingSets(in: result)
                sets += working.count; effort += working.filter { $0.effort != nil }.count
                let key = setupKey(result.exercise)
                let meaning = result.exercise.loadEquipment?.loadingMeaning
                let permitsVolume = result.exercise.type == .strength && meaning != .assistance && meaning != .bodyweightOnly
                var entry = setups[key] ?? WorkoutReportSetup(id: key, name: result.exerciseName,
                    context: WorkoutSetMath.contextLabel(result.exercise), workingSets: 0, recordedVolume: permitsVolume ? 0 : nil)
                entry.workingSets += working.count
                if permitsVolume { entry.recordedVolume = (entry.recordedVolume ?? 0) + WorkoutSetMath.volume(result) }
                setups[key] = entry
                let muscle = ExerciseList.entries.first { $0.name == result.exerciseName }?.category ?? "Custom / unclassified"
                muscles[muscle, default: 0] += working.count
            }
        }
        let ids = selected.map { $0.id ?? "\($0.routineID)|\($0.date.timeIntervalSinceReferenceDate)" }
        struct Basis: Encodable { var scope: WorkoutReportScope; var logs: [WorkoutSessionLog] }
        return WorkoutEvidenceSnapshot(version: 1, fingerprint: try PlanFingerprint.make(Basis(scope: scope, logs: selected)),
            scope: scope, updatedAt: now, sessionIDs: ids, workingSets: sets,
            durationSeconds: selected.reduce(0) { total, log in
                guard let value = log.elapsedSeconds, value.isFinite, (0...86_400).contains(value) else { return total }
                return total + value
            }, effortSets: effort,
            completedLinkedSlots: Set(selected.compactMap { log -> String? in
                guard log.programLinkDecision != .standalone, let context = log.programContext else { return nil }
                return "\(context.programID)|\(context.slotIndex)"
            }).count, unassignedSessions: selected.filter { $0.programContext == nil || $0.programLinkDecision == .standalone }.count,
            setups: setups.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }, setsByMuscle: muscles)
    }
    /// Distinct setup/prescription and a >21-day break each start a separate series.
    public static func points(logs: [WorkoutSessionLog], scope: WorkoutReportScope, setup: String,
                              metric: WorkoutTrendMetric, now: Date = Date()) -> [WorkoutReportPoint] {
        var result: [WorkoutReportPoint] = [], lastDate: Date?, segment = 0
        for log in filtered(logs, scope: scope, now: now) {
            let matches = log.completedExercises.filter { setupKey($0.exercise) == setup }
            guard !matches.isEmpty else { continue }
            let sets = matches.flatMap { WorkoutSetMath.workingSets(in: $0) }.filter { $0.reps > 0 }
            guard !sets.isEmpty, let first = matches.first else { continue }
            let meaning = first.exercise.loadEquipment?.loadingMeaning
            let value: Double?
            switch metric {
            case .load: value = meaning == .bodyweightOnly ? nil : meaning == .assistance ? sets.map(\.weight).min() : sets.map(\.weight).max()
            case .repetitions: value = sets.reduce(0.0) { $0 + Double($1.reps) }
            case .volume: value = meaning == .assistance || meaning == .bodyweightOnly ? nil : matches.reduce(0) { $0 + WorkoutSetMath.volume($1) }
            case .estimatedStrength: value = meaning == .assistance || meaning == .bodyweightOnly ? nil : sets.filter { (1...12).contains($0.reps) }.map(WorkoutSetMath.strengthScore).max()
            case .effort:
                let ratings = sets.compactMap { $0.effort?.normalizedRPE }.filter { $0.isFinite && (1...10).contains($0) }
                value = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
            }
            guard let value, value.isFinite else { continue }
            if lastDate.map({ log.date.timeIntervalSince($0) > 21 * 86_400 }) == true { segment += 1 }
            lastDate = log.date
            let prescription = (try? PlanFingerprint.make(first.exercise.sets.map(\.prescription))) ?? "unknown"
            let id = log.id ?? "\(log.routineID)|\(log.date.timeIntervalSinceReferenceDate)"
            result.append(WorkoutReportPoint(id: id, sessionID: id, date: log.date, value: value,
                seriesID: "\(setup)|\(prescription)|\(segment)", context: WorkoutSetMath.contextLabel(first.exercise)))
        }
        return result
    }
}
