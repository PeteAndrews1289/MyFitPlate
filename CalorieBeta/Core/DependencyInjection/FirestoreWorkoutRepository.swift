import Foundation
import FirebaseFirestore
import OSLog

class FirestoreWorkoutRepository: WorkoutRepositoryProtocol {
    private let db = Firestore.firestore()
    
    private func programsCollectionRef(for userID: String) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutPrograms)
    }
    
    private func routinesCollectionRef(for userID: String) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutRoutines)
    }
    
    private func sessionLogsCollectionRef(for userID: String) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs)
    }
    
    func fetchWorkoutSessionLog(userID: String, sessionID: String) async throws -> WorkoutSessionLog {
        let document = try await sessionLogsCollectionRef(for: userID).document(sessionID).getDocument()
        return try document.data(as: WorkoutSessionLog.self)
    }
    
    func fetchSessionLogs(userID: String, routineIDs: [String]) async throws -> [WorkoutSessionLog] {
        let chunks = routineIDs.chunked(into: 10)
        var allLogs: [WorkoutSessionLog] = []

        for chunk in chunks {
            guard !chunk.isEmpty else { continue }
            let snapshot = try await sessionLogsCollectionRef(for: userID)
                .whereField("routineID", in: chunk)
                .getDocuments()
            
            let logs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
            allLogs.append(contentsOf: logs)
        }
        return allLogs
    }
    
    func fetchRecentSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog] {
        let startDate = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date()) ?? Date()
        let snapshot = try await sessionLogsCollectionRef(for: userID)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
    }
    
    func addProgramsSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Any {
        return programsCollectionRef(for: userID).order(by: "dateCreated", descending: true)
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    onUpdate(.failure(error))
                    return
                }
                guard let documents = querySnapshot?.documents else {
                    onUpdate(.success([]))
                    return
                }
                let programs = documents.compactMap { try? $0.data(as: WorkoutProgram.self) }
                onUpdate(.success(programs))
            }
    }
    
    func addRoutinesSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Any {
        return routinesCollectionRef(for: userID).order(by: "dateCreated", descending: true)
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    onUpdate(.failure(error))
                    return
                }
                guard let documents = querySnapshot?.documents else {
                    onUpdate(.success([]))
                    return
                }
                let routines = documents.compactMap { try? $0.data(as: WorkoutRoutine.self) }
                onUpdate(.success(routines))
            }
    }
    
    func removeListener(_ handle: Any) {
        if let listener = handle as? ListenerRegistration {
            listener.remove()
        }
    }
    
    func saveProgram(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram {
        var programToSave = program
        programToSave.userID = userID
        
        let docRef: DocumentReference
        if let programID = programToSave.id {
            docRef = programsCollectionRef(for: userID).document(programID)
        } else {
            docRef = programsCollectionRef(for: userID).document()
        }
        programToSave.id = docRef.documentID
        try docRef.setData(from: programToSave, merge: true)
        return programToSave
    }
    
    func deleteProgram(userID: String, programID: String) async throws {
        try await programsCollectionRef(for: userID).document(programID).delete()
    }
    
    func saveRoutine(userID: String, routine: WorkoutRoutine) async throws {
        var routineToSave = routine
        routineToSave.userID = userID
        try routinesCollectionRef(for: userID).document(routineToSave.id).setData(from: routineToSave, merge: true)
    }
    
    func deleteRoutine(userID: String, routineID: String) async throws {
        try await routinesCollectionRef(for: userID).document(routineID).delete()
    }
    
    func saveWorkoutSessionLog(userID: String, log: WorkoutSessionLog) async throws {
        let docRef: DocumentReference
        if let logID = log.id {
            docRef = sessionLogsCollectionRef(for: userID).document(logID)
        } else {
            docRef = sessionLogsCollectionRef(for: userID).document()
        }
        var logToSave = log
        logToSave.id = docRef.documentID
        try docRef.setData(from: logToSave)
    }
    
    func fetchHistory(userID: String, exerciseName: String) async throws -> [WorkoutSessionLog] {
        let snapshot = try await sessionLogsCollectionRef(for: userID)
            .order(by: "date", descending: true)
            .getDocuments()
        
        let logs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
        return logs.filter { log in
            log.completedExercises.contains { $0.exerciseName == exerciseName }
        }
    }
    
    func fetchPreviousPerformance(userID: String, exerciseName: String) async throws -> CompletedExercise? {
        let snapshot = try await sessionLogsCollectionRef(for: userID)
            .order(by: "date", descending: true)
            .limit(to: 10)
            .getDocuments()
        let recentLogs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
        for previousLog in recentLogs {
            if let lastExercise = previousLog.completedExercises.first(where: { $0.exerciseName == exerciseName }) {
                return lastExercise
            }
        }
        
        return nil
    }
    
    // MARK: - Analytics
    
    func saveWorkoutInsights(userID: String, sessionID: String, insights: [[String: Any]]) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs).document(sessionID)
        try await ref.updateData(["aiInsights": insights])
    }
    
    func fetchWorkoutHistory(userID: String, limit: Int) async throws -> [WorkoutSessionLog] {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs)
            .order(by: "date", descending: true)
            .limit(to: limit)
        let snapshot = try await ref.getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
    }
    
    func fetchWorkoutHistory(userID: String, routineID: String, limit: Int) async throws -> [WorkoutSessionLog] {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs)
            .whereField("routineID", isEqualTo: routineID)
            .order(by: "date", descending: true)
            .limit(to: limit)
        let snapshot = try await ref.getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
    }
}
