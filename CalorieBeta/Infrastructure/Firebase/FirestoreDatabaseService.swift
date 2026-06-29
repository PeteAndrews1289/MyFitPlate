import Foundation
import MyFitPlateCore
import FirebaseFirestore

final class FirestoreDatabaseService: DatabaseServiceProtocol, @unchecked Sendable {
    private let db: Firestore
    
    init() {
        let db = Firestore.firestore()
        let settings = db.settings
        // Firebase 10+ uses PersistentCacheSettings
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024 as NSNumber) // 100MB
        db.settings = settings
        self.db = db
    }

    func loadDarkModePreference(userID: String) async throws -> Bool {
        let document = try await db.collection(FirestoreCollection.users).document(userID).getDocument()
        guard document.exists, let data = document.data(), let darkMode = data["darkMode"] as? Bool else {
            return false
        }
        return darkMode
    }
    
    func saveDarkModePreference(userID: String, isEnabled: Bool) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).setData(["darkMode": isEnabled], merge: true)
    }
    
    func recordLastLogin(userID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).setData(["lastLoginDate": Timestamp(date: Date())], merge: true)
    }

    func deleteUserAllData(userID: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            deleteUserFirestoreData(userID: userID, db: self.db) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private let userScopedCollections = [
        FirestoreCollection.dailyLogs,
        FirestoreCollection.weightHistory,
        FirestoreCollection.calorieHistory,
        FirestoreCollection.userSettings,
        FirestoreCollection.workoutSessionLogs,
        FirestoreCollection.workoutRoutines,
        FirestoreCollection.workoutPrograms,
        FirestoreCollection.dailySummaries
    ]

    private func deleteUserFirestoreData(userID: String, db: Firestore, completion: @escaping (Result<Void, Error>) -> Void) {
        let userRef = db.collection(FirestoreCollection.users).document(userID)
        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?

        func recordError(_ error: Error) {
            lock.lock()
            if firstError == nil { firstError = error }
            lock.unlock()
        }

        for collectionName in userScopedCollections {
            group.enter()
            deleteCollection(userRef.collection(collectionName), db: db) { error in
                if let error = error { recordError(error) }
                group.leave()
            }
        }

        let topLevelQueries: [Query] = [
            db.collection(FirestoreCollection.groupMemberships).whereField("userID", isEqualTo: userID),
            db.collection(FirestoreCollection.groupMemberships).whereField("userId", isEqualTo: userID),
            db.collection(FirestoreCollection.groups).whereField("creatorID", isEqualTo: userID),
            db.collection(FirestoreCollection.groups).whereField("creatorId", isEqualTo: userID),
            db.collection(FirestoreCollection.posts).whereField("authorID", isEqualTo: userID),
            db.collection(FirestoreCollection.posts).whereField("authorId", isEqualTo: userID)
        ]

        for query in topLevelQueries {
            group.enter()
            deleteQueryResults(query, db: db) { error in
                if let error = error { recordError(error) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError = firstError {
                completion(.failure(firstError))
                return
            }
            userRef.delete { error in
                if let error = error { completion(.failure(error)) } else { completion(.success(())) }
            }
        }
    }

    private func deleteCollection(_ collection: CollectionReference, db: Firestore, batchSize: Int = 100, completion: @escaping (Error?) -> Void) {
        collection.limit(to: batchSize).getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                completion(nil)
                return
            }
            let batch = db.batch()
            documents.forEach { batch.deleteDocument($0.reference) }
            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    self.deleteCollection(collection, db: db, batchSize: batchSize, completion: completion)
                }
            }
        }
    }

    private func deleteQueryResults(_ query: Query, db: Firestore, batchSize: Int = 100, completion: @escaping (Error?) -> Void) {
        query.limit(to: batchSize).getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                completion(nil)
                return
            }
            let batch = db.batch()
            documents.forEach { batch.deleteDocument($0.reference) }
            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    self.deleteQueryResults(query, db: db, batchSize: batchSize, completion: completion)
                }
            }
        }
    }
}
