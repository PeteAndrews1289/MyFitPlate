import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class WorkoutService: ObservableObject {
    @Published var userRoutines: [WorkoutRoutine] = []
    @Published var userPrograms: [WorkoutProgram] = []
    @Published var activeProgram: WorkoutProgram?
    
    private let db = Firestore.firestore()
    private var routineListener: ListenerRegistration?
    private var programListener: ListenerRegistration?
    private let apiKey = getAPIKey()
    
    private func programsCollectionRef(for userID: String) -> CollectionReference{
        return db.collection("users").document(userID).collection("workoutPrograms")
    }
    
    private func routinesCollectionRef(for userID: String) -> CollectionReference {
        return db.collection("users").document(userID).collection("workoutRoutines")
    }
    
    private func sessionLogsCollectionRef(for userID: String) -> CollectionReference {
        return db.collection("users").document(userID).collection("workoutSessionLogs")
    }

    func fetchRoutinesAndPrograms() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        self.programListener = programsCollectionRef(for: userID).order(by: "dateCreated", descending: true)
            .addSnapshotListener { querySnapshot, error in
                guard let documents = querySnapshot?.documents else { return }
                self.userPrograms = documents.compactMap { try? $0.data(as: WorkoutProgram.self) }
                self.activeProgram = self.userPrograms.first
            }

        self.routineListener = routinesCollectionRef(for: userID).order(by: "dateCreated", descending: true)
            .addSnapshotListener { querySnapshot, error in
                guard let documents = querySnapshot?.documents else { return }
                self.userRoutines = documents.compactMap { try? $0.data(as: WorkoutRoutine.self) }
            }
    }

    func saveProgram(_ program: WorkoutProgram) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        var programToSave = program
        programToSave.userID = userID
        
        do {
            try await programsCollectionRef(for: userID).document(program.id ?? UUID().uuidString).setData(from: programToSave)
        } catch {
            print("Error saving program: \(error.localizedDescription)")
        }
    }
    
    func deleteProgram(_ program: WorkoutProgram) {
        guard let userID = Auth.auth().currentUser?.uid, let programID = program.id else { return }
        programsCollectionRef(for: userID).document(programID).delete()
    }

    func saveRoutine(_ routine: WorkoutRoutine) async throws {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "WorkoutServiceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in."])
        }
        var routineToSave = routine
        routineToSave.userID = userID
        
        do {
            try routinesCollectionRef(for: userID).document(routine.id).setData(from: routineToSave, merge: true)
        } catch {
            print("Error saving routine: \(error.localizedDescription)")
            throw error
        }
    }

    func deleteRoutine(_ routine: WorkoutRoutine) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        routinesCollectionRef(for: userID).document(routine.id).delete()
    }
    
    func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        do {
            try sessionLogsCollectionRef(for: userID).addDocument(from: log)
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
            print("Error fetching workout history: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        guard let userID = Auth.auth().currentUser?.uid else { return nil }
        do {
            let snapshot = try await sessionLogsCollectionRef(for: userID)
                .order(by: "date", descending: true)
                .limit(to: 1)
                .getDocuments()
            
            if let log = snapshot.documents.compactMap({ try? $0.data(as: WorkoutSessionLog.self) }).first {
                return log.completedExercises.first { $0.exerciseName == exerciseName }
            }
            return nil
        } catch {
            print("Error fetching previous performance: \(error.localizedDescription)")
            return nil
        }
    }

    func generateAIWorkoutPlan(goal: String, daysPerWeek: Int, details: String) async -> WorkoutProgram? {
        let detailsString = details.isEmpty ? "No additional details provided." : details
        
        let prompt = """
        You are an expert fitness coach. Create a comprehensive, named workout program based on the user's specifications.
        - User's Primary Goal: \(goal)
        - Workout Days Per Week: \(daysPerWeek)
        - Additional Details (Equipment, Preferences, Current Fitness Level, etc.): \(detailsString)

        RULES:
        - Your response MUST be a valid JSON object.
        - **Critical Safety Guardrail**: You MUST tailor the intensity and volume of the program to the user's fitness level. If the user does not specify a fitness level, assume they are a beginner and start with very low intensity.
        - **Guardrail**: If the user's goal is unrelated to fitness, respond with a JSON where 'programName' is a polite refusal and 'routines' is an empty array.
        - The root object must have keys: "programName" and "routines".
        - Each routine object needs a "name" and an "exercises" array.
        - Each exercise object must have a "name", "type", "sets" array, and "alternatives" array.
        - The "type" key MUST be one of three strings: "Strength", "Cardio", or "Flexibility".
        - The "alternatives" array should contain 2 suitable replacement exercises that target the same muscle group and are not duplicates of other primary exercises in the plan.
        - Each set object must have a single key: "target".

        **Strength Program Rules**:
        - If the user's goal is strength or muscle building, adhere to these specific rules.
        - Each routine must have 5-6 exercises.
        - Each exercise must have exactly 3 sets.
        - For heavy compound exercises (like squats, deadlifts, bench press), the 'target' for each set must be in the '5-8 reps' range.
        - For accessory or isolation exercises (like bicep curls, leg extensions), the 'target' must be in the '8-12 reps' range.

        **Cardio/Flexibility Rules**:
        - For "Cardio" exercises, the target should be a duration or distance (e.g., "target": "Run 2 miles").
        - For "Flexibility" exercises, the target should be a duration to hold a pose (e.g., "target": "Hold for 30 seconds").
        """

        guard let responseString = await fetchAIResponse(prompt: prompt) else { return nil }
        guard let jsonData = responseString.data(using: .utf8) else { return nil }

        do {
            let decodedResponse = try JSONDecoder().decode(AIProgramResponse.self, from: jsonData)
            if decodedResponse.routines.isEmpty {
                return WorkoutProgram(userID: "", name: decodedResponse.programName, dateCreated: Timestamp(date: Date()), routines: [])
            }
            let program = mapResponseToProgram(decodedResponse)
            return program
        } catch {
            print("Error decoding AI workout plan: \(error)")
            return nil
        }
    }

    private func mapResponseToProgram(_ response: AIProgramResponse) -> WorkoutProgram {
        guard let userID = Auth.auth().currentUser?.uid else { fatalError("User not logged in.") }
        
        let routines = response.routines.map { aiRoutine -> WorkoutRoutine in
            let exercises = aiRoutine.exercises.map { aiExercise -> RoutineExercise in
                let sets = aiExercise.sets.map { aiSet -> ExerciseSet in
                    return ExerciseSet(target: aiSet.target)
                }
                return RoutineExercise(name: aiExercise.name, type: aiExercise.type, sets: sets, alternatives: aiExercise.alternatives)
            }
            return WorkoutRoutine(userID: userID, name: aiRoutine.name, dateCreated: Timestamp(date: Date()), exercises: exercises)
        }
        
        return WorkoutProgram(id: UUID().uuidString, userID: userID, name: response.programName, dateCreated: Timestamp(date: Date()), routines: routines)
    }
    
    private func fetchAIResponse(prompt: String) async -> String? {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
        } catch {
            print("AI fetch error: \(error.localizedDescription)")
        }
        return nil
    }
    
    func detachListener(){
        programListener?.remove()
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
