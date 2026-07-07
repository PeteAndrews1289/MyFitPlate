import Combine
import Foundation
public enum ExerciseType: String, Codable, CaseIterable {
    case strength = "Strength"
    case cardio = "Cardio"
    case flexibility = "Flexibility"
}

public struct WorkoutProgram: Identifiable, Codable {
    public var id: String?
    public var userID: String
    public var name: String
    public var dateCreated: Date
    public var routines: [WorkoutRoutine]
    public var startDate: Date?
    public var daysOfWeek: [Int]?
    public var currentProgressIndex: Int? = 0
    /// Slot indices the user explicitly skipped (advanced past without training). Kept so the
    /// calendar can mark them "Skipped" — distinct from completed days, which have a session log.
    public var skippedIndices: [Int]? = nil

    public init(id: String? = nil, userID: String, name: String, dateCreated: Date = Date(), routines: [WorkoutRoutine] = [], startDate: Date? = nil, daysOfWeek: [Int]? = nil, currentProgressIndex: Int? = 0, skippedIndices: [Int]? = nil) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dateCreated = dateCreated
        self.routines = routines
        self.startDate = startDate
        self.daysOfWeek = daysOfWeek
        self.currentProgressIndex = currentProgressIndex
        self.skippedIndices = skippedIndices
    }
}

public class WorkoutRoutine: Identifiable, ObservableObject, Codable, Hashable {
    public var id: String
    public var userID: String
    @Published public var name: String
    public var dateCreated: Date
    @Published public var exercises: [RoutineExercise]
    public var notes: String?

    public enum CodingKeys: String, CodingKey {
        case id, userID, name, dateCreated, exercises, notes
    }

    public init(id: String = UUID().uuidString, userID: String, name: String, dateCreated: Date, exercises: [RoutineExercise] = [], notes: String? = nil) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dateCreated = dateCreated
        self.exercises = exercises
        self.notes = notes
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userID = try container.decode(String.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        exercises = try container.decode([RoutineExercise].self, forKey: .exercises)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(exercises, forKey: .exercises)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: WorkoutRoutine, rhs: WorkoutRoutine) -> Bool {
        lhs.id == rhs.id
    }

    public func deepCopy() -> WorkoutRoutine? {
        do {
            let data = try JSONEncoder().encode(self)
            return try JSONDecoder().decode(WorkoutRoutine.self, from: data)
        } catch {
            AppLog.workouts.error("Error deep copying workout routine: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

public struct RoutineExercise: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var name: String
    public var type: ExerciseType = .strength
    public var sets: [ExerciseSet] = []
    public var notes: String?
    public var restTimeInSeconds: Int = 60
    public var alternatives: [String]?
    public var targetSets: Int = 3
    public var targetReps: String = "8-12"

    /// Exercises that share the same non-nil id (and sit next to each other in the
    /// routine) form a superset: you alternate through them and only rest after the
    /// last one. Optional so routines saved before supersets existed decode unchanged.
    public var supersetGroupID: String?

    public init(id: String = UUID().uuidString, name: String, type: ExerciseType = .strength, sets: [ExerciseSet] = [], notes: String? = nil, restTimeInSeconds: Int = 60, alternatives: [String]? = nil, targetSets: Int = 3, targetReps: String = "8-12", supersetGroupID: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.sets = sets
        self.notes = notes
        self.restTimeInSeconds = restTimeInSeconds
        self.alternatives = alternatives
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.supersetGroupID = supersetGroupID
    }
}

/// The role of a set within an exercise. Only working sets (`normal`/`drop`/`failure`)
/// count toward volume, 1RM, and PRs; `warmup` sets are excluded from that math.
public enum SetType: String, Codable, CaseIterable, Sendable {
    case warmup, normal, drop, failure

    public var shortLabel: String {
        switch self {
        case .warmup: return "W"
        case .normal: return ""
        case .drop: return "D"
        case .failure: return "F"
        }
    }
}

/// A single effort rating on a set. The user chooses in Settings whether they log
/// RPE or RIR; we store exactly what they entered plus which scale it was on (honest
/// to the app's trust ethos), and normalize to RPE only when analytics need one axis.
public struct SetEffort: Codable, Equatable, Sendable {
    public enum Scale: String, Codable, Sendable { case rpe, rir }
    public var scale: Scale
    public var value: Double

    public init(scale: Scale, value: Double) {
        self.scale = scale
        self.value = value
    }

    /// RPE-6…10 equivalent. RIR maps as RPE = 10 − RIR; both clamp to a sane band.
    public var normalizedRPE: Double {
        switch scale {
        case .rpe: return min(10, max(1, value))
        case .rir: return min(10, max(1, 10 - value))
        }
    }
}

public enum SupersetRules {
    /// Where an exercise sits inside its superset group.
    public struct Position: Equatable, Sendable {
        public let isInSuperset: Bool
        public let isFirstInGroup: Bool
        public let isLastInGroup: Bool
        /// "A", "B", … assigned per distinct group in order of appearance; nil when standalone.
        public let groupLabel: String?

        public static let standalone = Position(isInSuperset: false, isFirstInGroup: false, isLastInGroup: false, groupLabel: nil)
    }

    /// Superset positions for a routine. A group is a run of 2+ *adjacent* exercises that
    /// share the same non-nil `supersetGroupID`; a lone tagged exercise is treated as standalone.
    public static func positions(for exercises: [RoutineExercise]) -> [Position] {
        var labels: [String: String] = [:]
        var nextLabel = 0
        func label(for gid: String) -> String {
            if let existing = labels[gid] { return existing }
            let letter = String(UnicodeScalar(65 + (nextLabel % 26))!)
            labels[gid] = letter
            nextLabel += 1
            return letter
        }

        return exercises.indices.map { i in
            guard let gid = exercises[i].supersetGroupID else { return Position.standalone }
            let prevSame = i > 0 && exercises[i - 1].supersetGroupID == gid
            let nextSame = i < exercises.count - 1 && exercises[i + 1].supersetGroupID == gid
            guard prevSame || nextSame else { return Position.standalone }
            return Position(
                isInSuperset: true,
                isFirstInGroup: !prevSame,
                isLastInGroup: !nextSame,
                groupLabel: label(for: gid)
            )
        }
    }
}

public struct ExerciseSet: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var isCompleted: Bool = false
    public var target: String?
    public var previousPerformance: String?
    public var isWarmup: Bool = false

    /// Richer set role (drop/failure). Optional so legacy docs — which only carried
    /// `isWarmup` — still decode; nil falls back to the `isWarmup` bridge below.
    public var setType: SetType?
    /// RPE or RIR as the user entered it. Optional/nil when they logged no effort.
    public var effort: SetEffort?

    public var reps: Int = 0
    public var weight: Double = 0.0
    public var distance: Double = 0.0
    public var durationInSeconds: Int = 0

    /// Effective role, reconciling the new `setType` with the legacy `isWarmup` flag.
    public var resolvedSetType: SetType { setType ?? (isWarmup ? .warmup : .normal) }
    /// Working sets are everything that isn't a warmup; only these count in analytics.
    public var isWorkingSet: Bool { resolvedSetType != .warmup }

    /// Set the role and keep the legacy `isWarmup` flag in sync so older UI/queries stay correct.
    public mutating func setKind(_ kind: SetType) {
        setType = kind
        isWarmup = (kind == .warmup)
    }

    public init(id: String = UUID().uuidString, isCompleted: Bool = false, target: String? = nil, previousPerformance: String? = nil, isWarmup: Bool = false, setType: SetType? = nil, effort: SetEffort? = nil, reps: Int = 0, weight: Double = 0.0, distance: Double = 0.0, durationInSeconds: Int = 0) {
        self.id = id
        self.isCompleted = isCompleted
        self.target = target
        self.previousPerformance = previousPerformance
        self.isWarmup = isWarmup
        self.setType = setType
        self.effort = effort
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.durationInSeconds = durationInSeconds
    }
}

public struct WorkoutSessionLog: Identifiable, Codable {
    public var id: String?
    public var date: Date
    public var routineID: String
    public var completedExercises: [CompletedExercise]
    public var aiInsights: [WorkoutAnalysisInsight]?

    public init(id: String? = nil, date: Date, routineID: String, completedExercises: [CompletedExercise], aiInsights: [WorkoutAnalysisInsight]? = nil) {
        self.id = id
        self.date = date
        self.routineID = routineID
        self.completedExercises = completedExercises
        self.aiInsights = aiInsights
    }
}

public struct CompletedExercise: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var exerciseName: String
    public var exercise: RoutineExercise
    public var sets: [CompletedSet]
    public var date: Date { return Date() }

    public init(id: String = UUID().uuidString, exerciseName: String, exercise: RoutineExercise, sets: [CompletedSet]) {
        self.id = id
        self.exerciseName = exerciseName
        self.exercise = exercise
        self.sets = sets
    }
}

public struct CompletedSet: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var reps: Int
    public var weight: Double
    public var distance: Double?
    public var durationInSeconds: Int?

    /// Persisted set role. Optional so pre-existing history (which never stored it) decodes;
    /// legacy sets resolve to `.normal` and stay counted, exactly as before.
    public var setType: SetType?
    /// Persisted effort (RPE/RIR) as entered.
    public var effort: SetEffort?

    public var resolvedSetType: SetType { setType ?? .normal }
    /// Only working sets count toward volume, 1RM, and PRs.
    public var isWorkingSet: Bool { resolvedSetType != .warmup }

    public init(id: String = UUID().uuidString, reps: Int, weight: Double, distance: Double? = nil, durationInSeconds: Int? = nil, setType: SetType? = nil, effort: SetEffort? = nil) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.durationInSeconds = durationInSeconds
        self.setType = setType
        self.effort = effort
    }
}
