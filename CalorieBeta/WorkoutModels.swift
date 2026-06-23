import Combine
import Foundation
import FirebaseFirestore

enum ExerciseType: String, Codable, CaseIterable {
    case strength = "Strength"
    case cardio = "Cardio"
    case flexibility = "Flexibility"
}

struct WorkoutProgram: Identifiable, Codable {
    @DocumentID var id: String?
    var userID: String
    var name: String
    var dateCreated: Timestamp
    var routines: [WorkoutRoutine]
    var startDate: Timestamp?
    var daysOfWeek: [Int]?
    var currentProgressIndex: Int? = 0
}

class WorkoutRoutine: Identifiable, ObservableObject, Codable, Hashable {
    var id: String
    var userID: String
    @Published var name: String
    var dateCreated: Timestamp
    @Published var exercises: [RoutineExercise]
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, userID, name, dateCreated, exercises, notes
    }

    init(id: String = UUID().uuidString, userID: String, name: String, dateCreated: Timestamp, exercises: [RoutineExercise] = [], notes: String? = nil) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dateCreated = dateCreated
        self.exercises = exercises
        self.notes = notes
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userID = try container.decode(String.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        dateCreated = try container.decode(Timestamp.self, forKey: .dateCreated)
        exercises = try container.decode([RoutineExercise].self, forKey: .exercises)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(exercises, forKey: .exercises)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: WorkoutRoutine, rhs: WorkoutRoutine) -> Bool {
        lhs.id == rhs.id
    }

    func deepCopy() -> WorkoutRoutine? {
        do {
            let data = try JSONEncoder().encode(self)
            return try JSONDecoder().decode(WorkoutRoutine.self, from: data)
        } catch {
            AppLog.workouts.error("Error deep copying workout routine: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

struct RoutineExercise: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var type: ExerciseType = .strength
    var sets: [ExerciseSet] = []
    var notes: String?
    var restTimeInSeconds: Int = 60
    var alternatives: [String]?
    var targetSets: Int = 3
    var targetReps: String = "8-12"
}

struct ExerciseSet: Identifiable, Codable {
    var id: String = UUID().uuidString
    var isCompleted: Bool = false
    var target: String?
    var previousPerformance: String?
    var isWarmup: Bool = false

    var reps: Int = 0
    var weight: Double = 0.0
    var distance: Double = 0.0
    var durationInSeconds: Int = 0
}

struct WorkoutSessionLog: Identifiable, Codable {
    @DocumentID var id: String?
    var date: Timestamp
    var routineID: String
    var completedExercises: [CompletedExercise]
    var aiInsights: [WorkoutAnalysisInsight]?
}

struct CompletedExercise: Identifiable, Codable {
    var id: String = UUID().uuidString
    var exerciseName: String
    var exercise: RoutineExercise
    var sets: [CompletedSet]
    var date: Date { return Date() }
}

struct CompletedSet: Identifiable, Codable {
    var id: String = UUID().uuidString
    var reps: Int
    var weight: Double
    var distance: Double?
    var durationInSeconds: Int?
}
