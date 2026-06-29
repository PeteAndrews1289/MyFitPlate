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

    public init(id: String = UUID().uuidString, name: String, type: ExerciseType = .strength, sets: [ExerciseSet] = [], notes: String? = nil, restTimeInSeconds: Int = 60, alternatives: [String]? = nil, targetSets: Int = 3, targetReps: String = "8-12") {
        self.id = id
        self.name = name
        self.type = type
        self.sets = sets
        self.notes = notes
        self.restTimeInSeconds = restTimeInSeconds
        self.alternatives = alternatives
        self.targetSets = targetSets
        self.targetReps = targetReps
    }
}

public struct ExerciseSet: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var isCompleted: Bool = false
    public var target: String?
    public var previousPerformance: String?
    public var isWarmup: Bool = false

    public var reps: Int = 0
    public var weight: Double = 0.0
    public var distance: Double = 0.0
    public var durationInSeconds: Int = 0

    public init(id: String = UUID().uuidString, isCompleted: Bool = false, target: String? = nil, previousPerformance: String? = nil, isWarmup: Bool = false, reps: Int = 0, weight: Double = 0.0, distance: Double = 0.0, durationInSeconds: Int = 0) {
        self.id = id
        self.isCompleted = isCompleted
        self.target = target
        self.previousPerformance = previousPerformance
        self.isWarmup = isWarmup
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

    public init(id: String = UUID().uuidString, reps: Int, weight: Double, distance: Double? = nil, durationInSeconds: Int? = nil) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.durationInSeconds = durationInSeconds
    }
}
