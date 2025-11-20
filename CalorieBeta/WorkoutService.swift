import Foundation
import FirebaseFirestore
import FirebaseAuth

enum WorkoutServiceError: Error, LocalizedError {
    case userNotLoggedIn
    case networkError(Error)
    case firestoreError(Error)
    case decodingError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .userNotLoggedIn:
            return "You must be logged in to perform this action."
        case .networkError:
            return "Could not connect to the server. Please check your internet connection."
        case .firestoreError(let error):
            return "An error occurred with the database: \(error.localizedDescription)"
        case .decodingError:
            return "There was an issue processing the response from the server."
        case .apiError(let message):
            return message
        }
    }
}

@MainActor
class WorkoutService: ObservableObject {
    @Published var userRoutines: [WorkoutRoutine] = []
    @Published var userPrograms: [WorkoutProgram] = []
    @Published var preBuiltPrograms: [WorkoutProgram] = []
    @Published var activeProgram: WorkoutProgram?

    private let db = Firestore.firestore()
    private var routineListener: ListenerRegistration?
    private var programListener: ListenerRegistration?
    private let apiKey = getAPIKey()

    init() {
        loadPreBuiltPrograms()
    }

    private func programsCollectionRef(for userID: String) -> CollectionReference{
        return db.collection("users").document(userID).collection("workoutPrograms")
    }

    private func routinesCollectionRef(for userID: String) -> CollectionReference {
        return db.collection("users").document(userID).collection("workoutRoutines")
    }

    private func sessionLogsCollectionRef(for userID: String) -> CollectionReference {
        return db.collection("users").document(userID).collection("workoutSessionLogs")
    }

    func fetchWorkoutSessionLog(workoutID: String, sessionID: String) async -> Result<WorkoutSessionLog, Error> {
        guard let userID = Auth.auth().currentUser?.uid else {
            return .failure(WorkoutServiceError.userNotLoggedIn)
        }
        do {
            let document = try await sessionLogsCollectionRef(for: userID).document(sessionID).getDocument()
            let sessionLog = try document.data(as: WorkoutSessionLog.self)
            return .success(sessionLog)
        } catch {
            return .failure(error)
        }
    }
    
    func fetchSessionLogs(for program: WorkoutProgram) async -> [WorkoutSessionLog] {
        guard let userID = Auth.auth().currentUser?.uid else { return [] }
        let routineIDs = program.routines.map { $0.id }
        
        let chunks = routineIDs.chunked(into: 30)
        var allLogs: [WorkoutSessionLog] = []

        for chunk in chunks {
            guard !chunk.isEmpty else { continue }
            do {
                let snapshot = try await sessionLogsCollectionRef(for: userID)
                    .whereField("routineID", in: chunk)
                    .getDocuments()
                
                let logs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
                allLogs.append(contentsOf: logs)
            } catch {
                print("Error fetching session log chunk: \(error.localizedDescription)")
            }
        }
        return allLogs
    }

    func fetchRoutinesAndPrograms() {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        self.programListener = programsCollectionRef(for: userID).order(by: "dateCreated", descending: true)
            .addSnapshotListener { querySnapshot, error in
                guard let documents = querySnapshot?.documents else {
                    print("Error fetching user programs: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                self.userPrograms = documents.compactMap { doc -> WorkoutProgram? in
                   try? doc.data(as: WorkoutProgram.self)
                }
                self.activeProgram = self.userPrograms.first
            }

        self.routineListener = routinesCollectionRef(for: userID).order(by: "dateCreated", descending: true)
            .addSnapshotListener { querySnapshot, error in
                guard let documents = querySnapshot?.documents else {
                    print("Error fetching user routines: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                self.userRoutines = documents.compactMap { doc -> WorkoutRoutine? in
                    try? doc.data(as: WorkoutRoutine.self)
                }
            }
    }

    func saveProgram(_ program: WorkoutProgram) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        var programToSave = program
        programToSave.userID = userID

        do {
            let docRef = programToSave.id != nil ?
                programsCollectionRef(for: userID).document(programToSave.id!) :
                programsCollectionRef(for: userID).document()
            programToSave.id = docRef.documentID
            try await docRef.setData(from: programToSave, merge: true)
        } catch {
            print("Error saving program: \(error.localizedDescription)")
        }
    }

    func deleteProgram(_ program: WorkoutProgram) {
        guard let userID = Auth.auth().currentUser?.uid, let programID = program.id else { return }
        programsCollectionRef(for: userID).document(programID).delete { error in
             if let error = error {
                 print("Error deleting program: \(error.localizedDescription)")
             }
        }
    }

    func saveRoutine(_ routine: WorkoutRoutine) async throws {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw WorkoutServiceError.userNotLoggedIn
        }
        var routineToSave = routine
        routineToSave.userID = userID

        do {
            try routinesCollectionRef(for: userID).document(routine.id).setData(from: routineToSave, merge: true)
        } catch {
            throw WorkoutServiceError.firestoreError(error)
        }
    }

    func deleteRoutine(_ routine: WorkoutRoutine) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        routinesCollectionRef(for: userID).document(routine.id).delete { error in
             if let error = error {
                 print("Error deleting routine: \(error.localizedDescription)")
             }
        }
    }

    func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        do {
            let docRef = log.id != nil ? sessionLogsCollectionRef(for: userID).document(log.id!) : sessionLogsCollectionRef(for: userID).document()
            var logToSave = log
            logToSave.id = docRef.documentID
            try await docRef.setData(from: logToSave)
        } catch {
            print("Error saving workout session log: \(error.localizedDescription)")
        }
    }

    func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog] {
        guard let userID = Auth.auth().currentUser?.uid else { return [] }

        do {
            let snapshot = try await sessionLogsCollectionRef(for: userID)
                .order(by: "date", descending: true)
                .getDocuments()

            let logs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }

            let filteredLogs = logs.filter { log in
                log.completedExercises.contains { $0.exerciseName == exerciseName }
            }

            return filteredLogs

        } catch {
             print("Error fetching exercise history: \(error.localizedDescription)")
            return []
        }
    }

    func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        guard let userID = Auth.auth().currentUser?.uid else { return nil }
        do {
             let snapshot = try await sessionLogsCollectionRef(for: userID)
                 .order(by: "date", descending: true)
                 .limit(to: 10)
                 .getDocuments()
             let recentLogs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
             for log in recentLogs {
                 if let exercise = log.completedExercises.first(where: { $0.exerciseName == exerciseName }) {
                     return exercise
                 }
             }
             return nil
        } catch {
             print("Error fetching previous performance for \(exerciseName): \(error.localizedDescription)")
            return nil
        }
    }


    /// Generates a workout plan using AI based on enhanced user input.
    func generateAIWorkoutPlan(
        goal: String,
        daysPerWeek: Int,
        fitnessLevel: String,
        equipment: String,
        details: String,
        goalSettings: GoalSettings // Pass the user's goals for context
    ) async -> Result<WorkoutProgram, WorkoutServiceError> {
        
        let exerciseListJSON: String
        do {
            let jsonData = try JSONEncoder().encode(ExerciseList.categorizedExercises)
            exerciseListJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return .failure(.apiError("Failed to load internal exercise list."))
        }

        let detailsString = details.isEmpty ? "No additional details provided." : details

        let prompt = """
        You are an expert kinesiologist and fitness coach. Your task is to create a safe, effective, and well-structured workout program.

        **USER PROFILE:**
        - Age: \(goalSettings.age)
        - Gender: \(goalSettings.gender)
        - Primary Weight Goal: \(goalSettings.goal) (e.g., Lose, Maintain, Gain)
        - Stated Fitness Goal: \(goal)
        - Fitness Level: \(fitnessLevel)
        - Available Equipment: \(equipment)
        - Days Per Week: \(daysPerWeek)
        - Additional Notes: \(detailsString)

        **YOUR RULES (READ CAREFULLY):**

        1.  **EXERCISE SELECTION (CRITICAL):** You MUST ONLY use exercises from the following JSON list. Do NOT invent exercises. If the user's equipment is limited (e.g., 'Bodyweight Only'), only select exercises that match that constraint (e.g., 'Push-up', 'Bodyweight Squat', 'Plank').
            ```json
            \(exerciseListJSON)
            ```

        2.  **PROGRAM STRUCTURE:** Create a logical split that matches the user's days per week.
            - 2 Days: Full Body / Full Body
            - 3 Days: Full Body (A/B/A) OR Push / Pull / Legs
            - 4 Days: Upper / Lower / Upper / Lower
            - 5 Days: Push / Pull / Legs / Upper / Lower
            - 6 Days: Push / Pull / Legs / Push / Pull / Legs
            Each routine must have a MINIMUM of 5 exercises.

        3.  **SETS & REPS:** Tailor volume to the user's level.
            - Beginner: 3 sets per exercise. Reps in 10-15 range.
            - Intermediate: 3-4 sets per exercise. Reps in 8-12 range.
            - Advanced: 4-5 sets per exercise. Use varied rep ranges (e.g., 6-10, 12-15).
            - Cardio/Flexibility: Use time (e.g., "30-60 sec", "20 min").

        4.  **ALTERNATIVES:** The "alternatives" array MUST contain 2 suitable replacement exercises *from the provided JSON list* for the same muscle group.

        5.  **SAFETY:** If the user mentions an injury (e.g., "bad knee"), avoid high-impact exercises (like 'Burpees', 'Jump Squats') and provide low-impact alternatives. Always assume "Beginner" if the fitness level is unclear.

        6.  **RESPONSE FORMAT (CRITICAL):** Your response MUST be a valid JSON object.
            - Root object keys: "programName" (string) and "routines" (array).
            - Routine object keys: "name" (string, e.g., "Push Day") and "exercises" (array).
            - Exercise object keys: "name" (string), "type" (string: "Strength", "Cardio", or "Flexibility"), "sets" (array), "alternatives" (array).
            - Set object key: "target" (string, e.g., "8-12 reps", "60 seconds").
        """

        let responseResult = await fetchAIResponse(prompt: prompt)

        switch responseResult {
        case .success(let responseString):
            guard let jsonData = responseString.data(using: .utf8) else {
                return .failure(.decodingError(NSError(domain: "WorkoutService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert AI response to data."])))
            }
            do {
                if responseString.contains("cannot generate") || responseString.contains("unable to") {
                     struct Refusal: Codable { let programName: String }
                     if let refusal = try? JSONDecoder().decode(Refusal.self, from: jsonData) {
                         return .failure(.apiError(refusal.programName))
                     }
                     return .failure(.apiError("The AI was unable to generate a plan for this request."))
                }
                
                let decodedResponse = try JSONDecoder().decode(AIProgramResponse.self, from: jsonData)
                if decodedResponse.routines.isEmpty && decodedResponse.programName.contains("cannot") {
                    return .failure(.apiError(decodedResponse.programName))
                }
                let program = mapResponseToProgram(decodedResponse)
                return .success(program)
            } catch {
                 print("AI workout decoding error: \(error)")
                 print("--- Failed JSON String ---")
                 print(responseString)
                 print("--- End Failed JSON ---")
                return .failure(.decodingError(error))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    private func mapResponseToProgram(_ response: AIProgramResponse) -> WorkoutProgram {
        guard let userID = Auth.auth().currentUser?.uid else { fatalError("User not logged in.") }

        let routines = response.routines.map { aiRoutine -> WorkoutRoutine in
            let exercises = aiRoutine.exercises.map { aiExercise -> RoutineExercise in
                let sets = aiExercise.sets.map { aiSet -> ExerciseSet in
                    return ExerciseSet(target: aiSet.target)
                }
                let exerciseType = ExerciseType(rawValue: aiExercise.type.rawValue) ?? .strength
                return RoutineExercise(name: aiExercise.name, type: exerciseType, sets: sets, alternatives: aiExercise.alternatives)
            }
            return WorkoutRoutine(id: UUID().uuidString, userID: userID, name: aiRoutine.name, dateCreated: Timestamp(date: Date()), exercises: exercises)
        }

        return WorkoutProgram(userID: userID, name: response.programName, dateCreated: Timestamp(date: Date()), routines: routines)
    }

    private func fetchAIResponse(prompt: String) async -> Result<String, WorkoutServiceError> {
        guard !apiKey.isEmpty, apiKey != "YOUR_API_KEY" else {
            return .failure(.apiError("API Key not configured."))
        }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 4000
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                 let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                 return .failure(.apiError("Received invalid server response (\(statusCode))."))
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return .success(content)
            } else if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let errorDict = errorJson["error"] as? [String: Any],
                      let errorMessage = errorDict["message"] as? String {
                return .failure(.apiError(errorMessage))
            } else {
                return .failure(.decodingError(NSError(domain: "WorkoutService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure from AI."])))
            }
        } catch {
            return .failure(.networkError(error))
        }
    }

    func detachListener(){
        programListener?.remove()
        routineListener?.remove()
    }

    private func loadPreBuiltPrograms() {
        var programs: [WorkoutProgram] = []
        let systemUserID = "system_prebuilt"
        let now = Timestamp(date: Date())

        let sl5x5_A = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Workout A", dateCreated: now, exercises: [RoutineExercise(name: "Barbell Back Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "5 reps"), count: 5), alternatives: ["Leg Press", "Goblet Squat"]), RoutineExercise(name: "Barbell Bench Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "5 reps"), count: 5), alternatives: ["Dumbbell Bench Press", "Push-up"]), RoutineExercise(name: "Barbell Bent-over Row", type: .strength, sets: Array(repeating: ExerciseSet(target: "5 reps"), count: 5), alternatives: ["Dumbbell Row", "Seated Cable Row"])])
        let sl5x5_B = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Workout B", dateCreated: now, exercises: [RoutineExercise(name: "Barbell Back Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "5 reps"), count: 5), alternatives: ["Leg Press", "Goblet Squat"]), RoutineExercise(name: "Barbell Overhead Press (Military Press)", type: .strength, sets: Array(repeating: ExerciseSet(target: "5 reps"), count: 5), alternatives: ["Dumbbell Shoulder Press", "Arnold Press"]), RoutineExercise(name: "Deadlift (Conventional)", type: .strength, sets: [ExerciseSet(target: "5 reps")], alternatives: ["Sumo Deadlift", "Romanian Deadlift (RDL)"])])
        programs.append(WorkoutProgram(userID: systemUserID, name: "StrongLifts 5x5", dateCreated: now, routines: [sl5x5_A, sl5x5_B], daysOfWeek: [2, 4, 6]))
        
        let bw_A = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Full Body Bodyweight A", dateCreated: now, exercises: [RoutineExercise(name: "Push-up", type: .strength, sets: Array(repeating: ExerciseSet(target: "AMRAP"), count: 3), alternatives: ["Incline Barbell Bench Press"]), RoutineExercise(name: "Barbell Back Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3), alternatives: ["Goblet Squat"]), RoutineExercise(name: "Plank", type: .flexibility, sets: Array(repeating: ExerciseSet(target: "60 sec hold"), count: 3), alternatives: ["Crunch"]), RoutineExercise(name: "Lunge (Barbell/Dumbbell)", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-12 reps / side"), count: 3), alternatives: ["Bulgarian Split Squat"]), RoutineExercise(name: "Back Extension (Hyperextension)", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3), alternatives: ["Good Mornings"])])
        let bw_B = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Full Body Bodyweight B", dateCreated: now, exercises: [RoutineExercise(name: "Burpees", type: .cardio, sets: Array(repeating: ExerciseSet(target: "AMRAP in 60s"), count: 3), alternatives: ["Jump Rope"]), RoutineExercise(name: "Hip Thrust", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3), alternatives: ["Good Mornings"]), RoutineExercise(name: "Leg Raise", type: .flexibility, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3), alternatives: ["Hanging Leg Raise"]), RoutineExercise(name: "Push-up", type: .strength, sets: Array(repeating: ExerciseSet(target: "AMRAP"), count: 3), alternatives: ["Dumbbell Bench Press"]), RoutineExercise(name: "Sit-up", type: .flexibility, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3), alternatives: ["Crunch"])])
        programs.append(WorkoutProgram(userID: systemUserID, name: "Beginner Bodyweight", dateCreated: now, routines: [bw_A, bw_B], daysOfWeek: [2, 4, 6]))

        self.preBuiltPrograms = programs
    }


    /// Copies a pre-built program and saves it as a user program
    func selectPreBuiltProgram(_ program: WorkoutProgram) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        var userProgramCopy = program
        userProgramCopy.id = nil
        userProgramCopy.userID = userID
        userProgramCopy.startDate = nil
        userProgramCopy.daysOfWeek = nil
        userProgramCopy.currentProgressIndex = 0
        userProgramCopy.dateCreated = Timestamp(date: Date())

        userProgramCopy.routines = userProgramCopy.routines.map { routine in
            var newRoutine = routine
            newRoutine.id = UUID().uuidString
            newRoutine.userID = userID
            newRoutine.exercises = routine.exercises.map { exercise in
                var newExercise = exercise
                newExercise.id = UUID().uuidString
                newExercise.sets = exercise.sets.map { set in
                    var newSet = set
                    newSet.id = UUID().uuidString
                    return newSet
                }
                return newExercise
            }
            return newRoutine
        }

        await saveProgram(userProgramCopy)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

struct AIProgramResponse: Codable {
    let programName: String
    let routines: [AIRoutine]
}
struct AIRoutine: Codable {
    let name: String
    let exercises: [AIExercise]
}
struct AIExercise: Codable {
    let name: String
    let type: ExerciseType
    let sets: [AISet]
    let alternatives: [String]?
}
struct AISet: Codable {
    let target: String
}
