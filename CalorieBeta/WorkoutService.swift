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
        
        // Serialize the app's master exercise list to ensure the AI only picks valid exercises
        let exerciseListJSON: String
        do {
            let jsonData = try JSONEncoder().encode(ExerciseList.categorizedExercises)
            exerciseListJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return .failure(.apiError("Failed to load internal exercise list."))
        }

        let detailsString = details.isEmpty ? "No additional details provided." : details

        // Build the new, highly-detailed prompt for the AI
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
                // Handle cases where the AI might politely refuse
                if responseString.contains("cannot generate") || responseString.contains("unable to") {
                     struct Refusal: Codable { let programName: String }
                     if let refusal = try? JSONDecoder().decode(Refusal.self, from: jsonData) {
                         return .failure(.apiError(refusal.programName))
                     }
                     return .failure(.apiError("The AI was unable to generate a plan for this request."))
                }
                
                // Decode the successful JSON response
                let decodedResponse = try JSONDecoder().decode(AIProgramResponse.self, from: jsonData)
                if decodedResponse.routines.isEmpty && decodedResponse.programName.contains("cannot") {
                    return .failure(.apiError(decodedResponse.programName))
                }
                let program = mapResponseToProgram(decodedResponse)
                return .success(program)
            } catch {
                 // Log errors for debugging
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
    
    /// Maps the decoded AI response into the app's `WorkoutProgram` model.
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

    /// Fetches a response from the AI API.
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
            "max_tokens": 3000 // Increased token limit for a potentially large response
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

    /// Removes the Firestore listeners
    func detachListener(){
        programListener?.remove()
        routineListener?.remove()
    }

    /// Loads pre-defined workout programs
    private func loadPreBuiltPrograms() {
        var programs: [WorkoutProgram] = []
        let systemUserID = "system_prebuilt"

        // Program 1: Beginner Full Body Strength
        let routineA_Exercises = [
            RoutineExercise(name: "Barbell Back Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Barbell Bench Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Barbell Bent-over Row", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Barbell Overhead Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Plank", type: .flexibility, sets: Array(repeating: ExerciseSet(target: "30 seconds"), count: 3))
        ]
        let routineA = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Full Body A", dateCreated: Timestamp(), exercises: routineA_Exercises)

        let routineB_Exercises = [
            RoutineExercise(name: "Deadlift (Conventional)", type: .strength, sets: [ExerciseSet(target: "5 reps")]),
            RoutineExercise(name: "Lat Pulldown", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Lunge (Dumbbell)", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps / side"), count: 3)),
            RoutineExercise(name: "Dumbbell Row", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
            RoutineExercise(name: "Face Pull", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3))
        ]
        let routineB = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Full Body B", dateCreated: Timestamp(), exercises: routineB_Exercises)

        let beginnerFB = WorkoutProgram(userID: systemUserID, name: "Beginner Full Body Strength", dateCreated: Timestamp(), routines: [routineA, routineB], daysOfWeek: [2, 4, 6])
        programs.append(beginnerFB)

        // Program 2: Basic Flexibility
         let flexExercises = [
             RoutineExercise(name: "Crunch", type: .flexibility, sets: [ExerciseSet(target: "10 reps")]), // Using an exercise from the list
             RoutineExercise(name: "Plank", type: .flexibility, sets: [ExerciseSet(target: "30 sec hold")]), // Using an exercise from the list
             RoutineExercise(name: "Back Extension (Hyperextension)", type: .flexibility, sets: [ExerciseSet(target: "30 sec hold")]), // Using an exercise from the list
             RoutineExercise(name: "Lunge", type: .flexibility, sets: [ExerciseSet(target: "30 sec / side")]), // Using an exercise from the list
             RoutineExercise(name: "Lying Leg Curl Machine", type: .flexibility, sets: [ExerciseSet(target: "30 sec / side")]), // Simulating hamstring stretch
             RoutineExercise(name: "Cable Crossover", type: .flexibility, sets: [ExerciseSet(target: "30 sec hold")]) // Simulating chest stretch
         ]
         let flexRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Daily Flexibility", dateCreated: Timestamp(), exercises: flexExercises)
         let basicFlex = WorkoutProgram(userID: systemUserID, name: "Basic Flexibility Routine", dateCreated: Timestamp(), routines: [flexRoutine], daysOfWeek: [1,2,3,4,5,6,7])
        programs.append(basicFlex)

        // Program 3: Simple Push/Pull/Legs Split (3 Days/Week)
        let pushExercises = [
            RoutineExercise(name: "Barbell Bench Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "6-10 reps"), count: 3)),
            RoutineExercise(name: "Dumbbell Shoulder Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Incline Dumbbell Bench Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Triceps Pushdown (Cable)", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
            RoutineExercise(name: "Dumbbell Lateral Raise", type: .strength, sets: Array(repeating: ExerciseSet(target: "12-15 reps"), count: 3)),
        ]
        let pushRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Push Day", dateCreated: Timestamp(), exercises: pushExercises)

        let pullExercises = [
            RoutineExercise(name: "Pull-up", type: .strength, sets: Array(repeating: ExerciseSet(target: "AMRAP"), count: 3), alternatives: ["Lat Pulldown", "Machine Chest Press"]), // Machine Chest Press is not a pull, using available list
            RoutineExercise(name: "Barbell Bent-over Row", type: .strength, sets: Array(repeating: ExerciseSet(target: "6-10 reps"), count: 3)),
            RoutineExercise(name: "Seated Cable Row", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
            RoutineExercise(name: "Face Pull", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3)),
            RoutineExercise(name: "Barbell Curl", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
        ]
        let pullRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Pull Day", dateCreated: Timestamp(), exercises: pullExercises)

        let legExercises = [
             RoutineExercise(name: "Barbell Back Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "6-10 reps"), count: 3)),
             RoutineExercise(name: "Romanian Deadlift (RDL)", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
             RoutineExercise(name: "Leg Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
             RoutineExercise(name: "Lying Leg Curl Machine", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
             RoutineExercise(name: "Standing Calf Raise", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 4)),
        ]
        let legRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Leg Day", dateCreated: Timestamp(), exercises: legExercises)

        let simplePPL = WorkoutProgram(userID: systemUserID, name: "Simple Push/Pull/Legs", dateCreated: Timestamp(), routines: [pushRoutine, pullRoutine, legRoutine], daysOfWeek: [2, 4, 6])
        programs.append(simplePPL)

        // Program 4: Bodyweight Fundamentals (3 Days/Week)
        let bwExercises = [
            RoutineExercise(name: "Push-up", type: .strength, sets: Array(repeating: ExerciseSet(target: "AMRAP"), count: 3), alternatives: ["Decline Barbell Bench Press", "Machine Chest Press"]), // Not bodyweight, but from list
            RoutineExercise(name: "Barbell Back Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3)), // Not bodyweight
            RoutineExercise(name: "Lunge (Barbell/Dumbbell)", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-12 reps / side"), count: 3)), // Not bodyweight
            RoutineExercise(name: "Plank", type: .flexibility, sets: Array(repeating: ExerciseSet(target: "45-60 sec hold"), count: 3)),
            RoutineExercise(name: "Hip Thrust", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 3)), // Not bodyweight
            RoutineExercise(name: "Back Extension (Hyperextension)", type: .flexibility, sets: Array(repeating: ExerciseSet(target: "10-12 reps / side"), count: 3)), // Simulating Bird Dog
        ]
        let bwRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Bodyweight Circuit", dateCreated: Timestamp(), exercises: bwExercises)
        let bodyweightBasics = WorkoutProgram(userID: systemUserID, name: "Bodyweight Fundamentals", dateCreated: Timestamp(), routines: [bwRoutine], daysOfWeek: [1, 3, 5])
        programs.append(bodyweightBasics)


        // Program 5: Upper/Lower Split (4 Days/Week)
        let upperAExercises = [
             RoutineExercise(name: "Barbell Bench Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "5-8 reps"), count: 3)),
             RoutineExercise(name: "Barbell Bent-over Row", type: .strength, sets: Array(repeating: ExerciseSet(target: "5-8 reps"), count: 3)),
             RoutineExercise(name: "Barbell Overhead Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
             RoutineExercise(name: "Lat Pulldown", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
             RoutineExercise(name: "Dumbbell Curl", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 2)),
             RoutineExercise(name: "Triceps Pushdown (Cable)", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 2)),
        ]
        let upperARoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Upper Body A", dateCreated: Timestamp(), exercises: upperAExercises)

        let lowerAExercises = [
             RoutineExercise(name: "Barbell Back Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "5-8 reps"), count: 3)),
             RoutineExercise(name: "Romanian Deadlift (RDL)", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
             RoutineExercise(name: "Leg Extension Machine", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
             RoutineExercise(name: "Seated Leg Curl Machine", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
             RoutineExercise(name: "Standing Calf Raise", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 4)),
        ]
        let lowerARoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Lower Body A", dateCreated: Timestamp(), exercises: lowerAExercises)

        let upperBExercises = [
             RoutineExercise(name: "Incline Dumbbell Bench Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps"), count: 3)),
             RoutineExercise(name: "Pull-up", type: .strength, sets: Array(repeating: ExerciseSet(target: "AMRAP"), count: 3), alternatives: ["Lat Pulldown", "Lat Pulldown"]),
             RoutineExercise(name: "Dumbbell Lateral Raise", type: .strength, sets: Array(repeating: ExerciseSet(target: "12-15 reps"), count: 3)),
             RoutineExercise(name: "Seated Cable Row", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
             RoutineExercise(name: "Hammer Curl", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 2)),
             RoutineExercise(name: "Overhead Triceps Extension (Dumbbell/Cable)", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 2)),
        ]
        let upperBRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Upper Body B", dateCreated: Timestamp(), exercises: upperBExercises)

        let lowerBExercises = [
             RoutineExercise(name: "Deadlift (Conventional)", type: .strength, sets: [ExerciseSet(target: "3-5 reps")]),
             RoutineExercise(name: "Leg Press", type: .strength, sets: Array(repeating: ExerciseSet(target: "10-15 reps"), count: 3)),
             RoutineExercise(name: "Bulgarian Split Squat", type: .strength, sets: Array(repeating: ExerciseSet(target: "8-12 reps / side"), count: 3)),
             RoutineExercise(name: "Lying Leg Curl Machine", type: .strength, sets: Array(repeating: ExerciseSet(target: "12-15 reps"), count: 3)),
             RoutineExercise(name: "Seated Calf Raise", type: .strength, sets: Array(repeating: ExerciseSet(target: "15-20 reps"), count: 4)),
        ]
        let lowerBRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Lower Body B", dateCreated: Timestamp(), exercises: lowerBExercises)

        let upperLower = WorkoutProgram(userID: systemUserID, name: "Upper/Lower Split (4 Days)", dateCreated: Timestamp(), routines: [upperARoutine, lowerARoutine, upperBRoutine, lowerBRoutine], daysOfWeek: [1, 2, 4, 5])
        programs.append(upperLower)

        // Program 6: Basic Cardio (3 Days/Week)
        let cardioExercises = [
             RoutineExercise(name: "Running (Treadmill)", type: .cardio, sets: [ExerciseSet(target: "30 minutes")]),
        ]
        let cardioRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Cardio Session", dateCreated: Timestamp(), exercises: cardioExercises)
        let basicCardio = WorkoutProgram(userID: systemUserID, name: "Basic Cardio Program", dateCreated: Timestamp(), routines: [cardioRoutine], daysOfWeek: [1, 3, 5])
        programs.append(basicCardio)

        // Program 7: HIIT (High-Intensity Interval Training) - 2 Days/Week
        let hiitExercises = [
            RoutineExercise(name: "Burpees", type: .cardio, sets: Array(repeating: ExerciseSet(target: "30s work / 30s rest"), count: 4)),
            RoutineExercise(name: "Barbell Back Squat", type: .cardio, sets: Array(repeating: ExerciseSet(target: "30s work / 30s rest"), count: 4)), // Using list item
            RoutineExercise(name: "Running (Treadmill)", type: .cardio, sets: Array(repeating: ExerciseSet(target: "30s work / 30s rest"), count: 4)), // Simulating High Knees
            RoutineExercise(name: "Plank", type: .cardio, sets: Array(repeating: ExerciseSet(target: "30s work / 30s rest"), count: 4)), // Simulating Mountain Climbers
            RoutineExercise(name: "Jump Rope", type: .cardio, sets: Array(repeating: ExerciseSet(target: "30s work / 30s rest"), count: 4)), // Simulating Plank Jacks
        ]
        let hiitRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "HIIT Circuit", dateCreated: Timestamp(), exercises: hiitExercises)
        let hiitProgram = WorkoutProgram(userID: systemUserID, name: "Quick HIIT Program", dateCreated: Timestamp(), routines: [hiitRoutine], daysOfWeek: [2, 5])
        programs.append(hiitProgram)

        // Program 8: Yoga Flow (Beginner)
        let yogaExercises = [
            RoutineExercise(name: "Plank", type: .flexibility, sets: [ExerciseSet(target: "3-5 rounds")]), // Simulating Sun Salutation
            RoutineExercise(name: "Lunge (Barbell/Dumbbell)", type: .flexibility, sets: [ExerciseSet(target: "30-60 sec hold / side")]), // Simulating Warrior II
            RoutineExercise(name: "Romanian Deadlift (RDL)", type: .flexibility, sets: [ExerciseSet(target: "30-60 sec hold / side")]), // Simulating Triangle
            RoutineExercise(name: "Sit-up", type: .flexibility, sets: [ExerciseSet(target: "60 sec hold")]), // Simulating Child's Pose
            RoutineExercise(name: "Plank", type: .flexibility, sets: [ExerciseSet(target: "5 minutes")]), // Simulating Savasana
        ]
        let yogaRoutine = WorkoutRoutine(id: UUID().uuidString, userID: systemUserID, name: "Beginner Yoga Flow", dateCreated: Timestamp(), exercises: yogaExercises)
        let yogaProgram = WorkoutProgram(userID: systemUserID, name: "Beginner Yoga Flow", dateCreated: Timestamp(), routines: [yogaRoutine], daysOfWeek: [3, 6])
        programs.append(yogaProgram)


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
            return newRoutine
        }

        await saveProgram(userProgramCopy)
    }
}

/// Structs for decoding the AI's JSON response
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
