import Foundation
import MyFitPlateCore
import FirebaseFirestore
import Combine

class FirestoreAchievementRepository: AchievementRepositoryProtocol {
    private let db = Firestore.firestore()
    
    func userProfilePublisher(userID: String) -> AnyPublisher<(points: Int, level: Int)?, Never> {
        let subject = PassthroughSubject<(points: Int, level: Int)?, Never>()
        let listener = db.collection(FirestoreCollection.users).document(userID)
            .addSnapshotListener { documentSnapshot, _ in
                guard let document = documentSnapshot, document.exists else {
                    subject.send(nil)
                    return
                }
                let points = document.data()?["totalAchievementPoints"] as? Int ?? 0
                let level = document.data()?["userLevel"] as? Int ?? 1
                subject.send((points, level))
            }
        
        return subject.handleEvents(receiveCancel: {
            listener.remove()
        }).eraseToAnyPublisher()
    }
    
    func userStatusesPublisher(userID: String) -> AnyPublisher<[UserAchievementStatus], Error> {
        let subject = PassthroughSubject<[UserAchievementStatus], Error>()
        let listener = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.achievementStatus)
            .addSnapshotListener { snap, err in
                if let err = err {
                    subject.send(completion: .failure(err))
                    return
                }
                guard let docs = snap?.documents else {
                    subject.send([])
                    return
                }
                var statuses: [UserAchievementStatus] = []
                for doc in docs {
                    if var status = try? doc.data(as: UserAchievementStatus.self) {
                        status.id = doc.documentID
                        statuses.append(status)
                    }
                }
                subject.send(statuses)
            }
        
        return subject.handleEvents(receiveCancel: {
            listener.remove()
        }).eraseToAnyPublisher()
    }
    
    func activeChallengesPublisher(userID: String) -> AnyPublisher<[Challenge], Error> {
        let subject = PassthroughSubject<[Challenge], Error>()
        let listener = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.activeChallenges)
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .addSnapshotListener { snap, err in
                if let err = err {
                    subject.send(completion: .failure(err))
                    return
                }
                guard let docs = snap?.documents else {
                    subject.send([])
                    return
                }
                var challenges: [Challenge] = []
                for doc in docs {
                    if let challenge = try? doc.data(as: Challenge.self) {
                        challenges.append(challenge)
                    }
                }
                subject.send(challenges)
            }
        
        return subject.handleEvents(receiveCancel: {
            listener.remove()
        }).eraseToAnyPublisher()
    }
    
    func saveUserStatus(userID: String, status: UserAchievementStatus) async throws {
        guard let statusDocID = status.id else { return }
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.achievementStatus).document(statusDocID)
        try ref.setData(from: status, merge: true)
    }
    
    func awardPointsAndCheckLevel(userID: String, points: Int, levelThresholds: [Int]) async throws -> (newPoints: Int, newLevel: Int) {
        let userRef = db.collection(FirestoreCollection.users).document(userID)
        
        return try await withCheckedThrowingContinuation { continuation in
            db.runTransaction { (transaction, errorPointer) -> Any? in
                let userDocument: DocumentSnapshot
                do {
                    try userDocument = transaction.getDocument(userRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                let oldPoints = userDocument.data()?["totalAchievementPoints"] as? Int ?? 0
                let newPoints = oldPoints + points
                
                var newLevel = 1
                for (index, threshold) in levelThresholds.enumerated().reversed() where newPoints >= threshold {
                    newLevel = index + 1
                    break
                }
                if newLevel < 1 { newLevel = 1 }

                transaction.updateData(["totalAchievementPoints": newPoints, "userLevel": newLevel], forDocument: userRef)
                return ["newPoints": newPoints, "newLevel": newLevel]
            } completion: { (object, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = object as? [String: Int], let np = result["newPoints"], let nl = result["newLevel"] {
                    continuation.resume(returning: (np, nl))
                } else {
                    continuation.resume(throwing: NSError(domain: "FirestoreAchievementRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction failed."]))
                }
            }
        }
    }
    
    func fetchRecipeCount(userID: String) async throws -> Int {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes).count.getAggregation(source: .server)
        return snapshot.count.intValue
    }
    
    func fetchWorkoutCount(userID: String) async throws -> Int {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs).count.getAggregation(source: .server)
        return snapshot.count.intValue
    }
    
    func generateWeeklyChallenges(userID: String, challengesToSet: [Challenge]) async throws {
        let challengesRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.activeChallenges)
        let snapshot = try await challengesRef.whereField("expiresAt", isGreaterThan: Timestamp(date: Date())).getDocuments()
        guard snapshot.documents.isEmpty else { return }

        let batch = db.batch()
        for challenge in challengesToSet {
            let newDocRef = challengesRef.document()
            try batch.setData(from: challenge, forDocument: newDocRef)
        }
        try await batch.commit()
    }
    
    func fetchActiveChallenges(userID: String, type: ChallengeType) async throws -> [Challenge] {
        let challengesRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.activeChallenges)
        let snapshot = try await challengesRef
            .whereField("type", isEqualTo: type.rawValue)
            .whereField("isCompleted", isEqualTo: false)
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .getDocuments()
        
        var results: [Challenge] = []
        for doc in snapshot.documents {
            if var challenge = try? doc.data(as: Challenge.self) {
                challenge.id = doc.documentID
                results.append(challenge)
            }
        }
        return results
    }
    
    func updateChallenge(userID: String, challenge: Challenge) async throws {
        guard let id = challenge.id else { return }
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.activeChallenges).document(id)
        try ref.setData(from: challenge, merge: true)
    }
}
