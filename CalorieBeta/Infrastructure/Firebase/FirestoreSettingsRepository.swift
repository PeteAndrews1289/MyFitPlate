import Foundation
import MyFitPlateCore
import FirebaseFirestore
import Combine

class FirestoreSettingsRepository: SettingsRepositoryProtocol {
    private let db = Firestore.firestore()

    func fetchUserGoals(userID: String, completion: @escaping ([String: Any]?) -> Void) {
        db.collection(FirestoreCollection.users).document(userID).getDocument { document, _ in
            if let doc = document, doc.exists, var data = doc.data() {
                if var goals = data["goals"] as? [String: Any], let ts = goals["lastCheckInDate"] as? Timestamp {
                    goals["lastCheckInDate"] = ts.dateValue()
                    data["goals"] = goals
                }
                completion(data)
            } else {
                completion(nil)
            }
        }
    }

    func saveUserGoals(userID: String, data: [String: Any]) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).setData(data, merge: true)
    }

    func weightHistoryPublisher(userID: String) -> AnyPublisher<[(id: String, date: Date, weight: Double)], Error> {
        let subject = PassthroughSubject<[(id: String, date: Date, weight: Double)], Error>()
        
        let listener = db.collection(FirestoreCollection.users).document(userID)
            .collection(FirestoreCollection.weightHistory)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snap, err in
                if let err = err {
                    subject.send(completion: .failure(err))
                    return
                }
                
                guard let docs = snap?.documents else {
                    subject.send([])
                    return
                }
                
                let history = docs.compactMap { d -> (id: String, date: Date, weight: Double)? in
                    let data = d.data()
                    if let weight = data["weight"] as? Double, let timestamp = data["timestamp"] as? Timestamp {
                        return (id: d.documentID, date: timestamp.dateValue(), weight: weight)
                    }
                    return nil
                }
                
                subject.send(history)
            }
            
        return subject.handleEvents(receiveCancel: {
            listener.remove()
        }).eraseToAnyPublisher()
    }

    func saveWeightEntry(userID: String, weight: Double, date: Date) async throws {
        let userRef = db.collection(FirestoreCollection.users).document(userID)
        
        if Calendar.current.isDateInToday(date) {
            try await userRef.setData(["weight": weight], merge: true)
        }
        
        let weightData: [String: Any] = ["weight": weight, "timestamp": Timestamp(date: date)]
        _ = try await userRef.collection(FirestoreCollection.weightHistory).addDocument(data: weightData)
    }

    func deleteWeightEntry(userID: String, entryID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID)
            .collection(FirestoreCollection.weightHistory)
            .document(entryID)
            .delete()
    }

    func fetchWeightHistory(userID: String) async throws -> [(id: String, date: Date, weight: Double)] {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID)
            .collection(FirestoreCollection.weightHistory)
            .order(by: "timestamp", descending: false)
            .getDocuments()
            
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            if let weight = data["weight"] as? Double, let timestamp = data["timestamp"] as? Timestamp {
                return (id: doc.documentID, date: timestamp.dateValue(), weight: weight)
            }
            return nil
        }
    }

    func updateUserAsOnboarded(userID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).setData(["isFirstLogin": false], merge: true)
    }

    func createInitialUserData(userID: String, email: String, username: String) async throws {
        let userData: [String: Any] = [
            "email": email,
            "userID": userID,
            "username": username,
            "goals": [
                "calories": 2000,
                "protein": 150,
                "fats": 70,
                "carbs": 250,
                "proteinPercentage": 30.0,
                "carbsPercentage": 50.0,
                "fatsPercentage": 20.0,
                "activityLevel": 1.2,
                "goal": "Maintain",
                "targetWeight": NSNull(),
                "waterGoal": 64.0
            ],
            "weight": 150.0,
            "height": 170.0,
            "age": 25,
            "gender": "Male",
            "isFirstLogin": true,
            "calorieGoalMethod": "mifflinWithActivity",
            "totalAchievementPoints": 0,
            "userLevel": 1
        ]
        
        try await db.collection(FirestoreCollection.users).document(userID).setData(userData)
        try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.calorieHistory).addDocument(data: [
            "date": Timestamp(date: Date()),
            "calories": 0.0
        ])
    }
}
