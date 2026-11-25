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
    /// Earlier exported reports contain the sum but omit its coverage.
    public var timedSessionCount: Int?
    public var effortSets: Int
    public var completedLinkedSlots: Int
    public var unassignedSessions: Int
    public var setups: [WorkoutReportSetup]
    public var setsByMuscle: [String: Int]
    public var headline: String {
        sessionIDs.isEmpty ? "No saved evidence in this scope" : "\(sessionIDs.count) saved sessions · \(workingSets) working sets"
    }
    public var durationSummary: String {
        guard !sessionIDs.isEmpty, (0...(86_400 * Double(sessionIDs.count))).contains(durationSeconds),
              timedSessionCount.map({ $0 > 0 }) ?? (durationSeconds > 0) else { return "Duration unavailable" }
        let time = Duration.seconds(durationSeconds).formattedWorkoutTime + " recorded"
        guard let timedSessionCount else { return time + " · timing coverage unknown" }
        if timedSessionCount == sessionIDs.count { return time }
        return time + " · \(timedSessionCount) of \(sessionIDs.count) sessions timed"
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
        let selected = filtered(logs, scope: scope, now: now).map { log in
            // A nonfinite legacy timer cannot be encoded in the report fingerprint.
            guard log.elapsedSeconds?.isFinite == false else { return log }
            var copy = log
            copy.elapsedSeconds = nil
            return copy
        }
        let durations = selected.compactMap(\.recordedDurationSeconds)
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
            durationSeconds: durations.reduce(0, +), timedSessionCount: durations.count, effortSets: effort,
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

public struct StrengthPeriodComparison {
    public struct Period {
        public let dates: ClosedRange<Date>
        public let trainingDays: Int
        public let workingSets: Int
        fileprivate let setups: Set<String>
        fileprivate let programs: Set<String>
    }

    public let current: Period
    public let previous: Period
    public let includesPartialDay: Bool

    public var programMixChanged: Bool {
        current.workingSets > 0 && previous.workingSets > 0 && current.programs != previous.programs
    }
    public var exerciseMixChanged: Bool {
        current.workingSets > 0 && previous.workingSets > 0 && current.setups != previous.setups
    }

    public static func make(logs: [WorkoutSessionLog], scope: WorkoutReportScope, now: Date,
                            calendar: Calendar = .current) -> Self? {
        guard let selectedStart = scope.startDate, let selectedEnd = scope.endDate,
              selectedStart <= min(selectedEnd, now), scope.exerciseType == nil || scope.exerciseType == .strength else { return nil }
        let start = calendar.startOfDay(for: selectedStart)
        let end = min(selectedEnd, now)
        let lastDay = calendar.startOfDay(for: end)
        let count = (calendar.dateComponents([.day], from: start, to: lastDay).day ?? 0) + 1
        guard let previousStart = calendar.date(byAdding: .day, value: -count, to: start),
              let previousEnd = calendar.date(byAdding: .day, value: -count, to: end) else { return nil }
        func period(_ dates: ClosedRange<Date>) -> Period {
            var selection = scope
            selection.startDate = dates.lowerBound
            selection.endDate = dates.upperBound
            selection.exerciseType = .strength
            var days = Set<Date>()
            var sets = 0
            var setups = Set<String>(), programs = Set<String>()
            for log in WorkoutEvidenceReportRules.filtered(logs, scope: selection, now: now) {
                let matches = log.completedExercises.filter {
                    $0.exercise.type == .strength && (scope.setupKey == nil || WorkoutEvidenceReportRules.setupKey($0.exercise) == scope.setupKey)
                }
                for exercise in matches {
                    let count = WorkoutSetMath.workingSets(in: exercise).count
                    guard count > 0 else { continue }
                    sets += count
                    days.insert(calendar.startOfDay(for: log.date))
                    setups.insert(WorkoutEvidenceReportRules.setupKey(exercise.exercise))
                    if log.programLinkDecision != .standalone, let program = log.programContext?.programID {
                        programs.insert(program)
                    }
                }
            }
            return Period(dates: dates, trainingDays: days.count, workingSets: sets, setups: setups, programs: programs)
        }
        return Self(current: period(start...end), previous: period(previousStart...previousEnd),
                    includesPartialDay: calendar.isDate(end, inSameDayAs: now))
    }
}
