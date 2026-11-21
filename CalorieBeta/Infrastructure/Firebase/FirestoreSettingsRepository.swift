import Foundation
import MyFitPlateCore
import FirebaseFirestore
import FirebaseAuth
import Combine

class FirestoreSettingsRepository: SettingsRepositoryProtocol {
    private let db: Firestore
    private let currentUserID: () -> String?
    init(db: Firestore = Firestore.firestore(), currentUserID: @escaping () -> String? = { Auth.auth().currentUser?.uid }) {
        self.db = db
        self.currentUserID = currentUserID
    }

    func fetchAccountProfile(userID: String, requireServer: Bool, completion: @escaping (Result<[String: Any]?, Error>) -> Void) {
        db.collection(FirestoreCollection.users).document(userID)
            .getDocument(source: requireServer ? .server : .default) { document, error in
                if let error {
                    completion(.failure(error))
                } else if let document, document.exists, let data = document.data() {
                    completion(.success(self.normalizedGoalDates(in: data)))
                } else if let document, !document.metadata.isFromCache {
                    completion(.success(nil))
                } else {
                    completion(.failure(URLError(.notConnectedToInternet)))
                }
            }
    }

    func fetchUserGoals(userID: String, completion: @escaping ([String: Any]?) -> Void) {
        let docRef = db.collection(FirestoreCollection.users).document(userID)
        docRef.getDocument { document, _ in
            if let doc = document, doc.exists, var data = doc.data() {
                data = self.normalizedGoalDates(in: data)
                completion(data)
            } else {
                docRef.getDocument(source: .cache) { cachedDoc, _ in
                    if let doc = cachedDoc, doc.exists, var data = doc.data() {
                        data = self.normalizedGoalDates(in: data)
                        completion(data)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    private func normalizedGoalDates(in rawData: [String: Any]) -> [String: Any] {
        var data = rawData
        if let ts = data["goalSettingsUpdatedAt"] as? Timestamp {
            data["goalSettingsUpdatedAt"] = ts.dateValue()
        }
        if var goals = data["goals"] as? [String: Any] {
            if let ts = goals["lastCheckInDate"] as? Timestamp {
                goals["lastCheckInDate"] = ts.dateValue()
            }
            if let ts = goals["updatedAt"] as? Timestamp {
                goals["updatedAt"] = ts.dateValue()
            }
            data["goals"] = goals
        }
        return data
    }

    func saveOnboardingGoals(userID: String, data: [String: Any]) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                guard OnboardingStateRules.requiresSetup(profile: snapshot.data()) else {
                    throw NSError(domain: "AccountSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "This account already has a plan. Reload your profile."])
                }
                transaction.setData(data, forDocument: ref, merge: true)
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
    }

    func saveUserGoals(userID: String, data: [String: Any]) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).setData(data, merge: true)
    }

    func saveWeeklyTargetDecision(_ decision: WeeklyTargetDecision) async throws -> WeeklyTargetDecision {
        let owner = decision.proposal.userID
        guard currentUserID() == owner else { throw WeeklyTargetReviewError.accountChanged }
        let profile = db.collection(FirestoreCollection.users).document(owner)
        let receipt = profile.collection("weeklyTargetDecisions").document(decision.id.uuidString)
        let payload = try JSONEncoder().encode(decision)
        let fingerprint = try PlanFingerprint.make(decision)
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                guard self.currentUserID() == owner else { throw WeeklyTargetReviewError.accountChanged }
                // Read the receipt before staleness/baseline checks. A response lost after a
                // successful commit must be recoverable without applying the decision twice.
                let existing = try transaction.getDocument(receipt)
                if let data = existing.data() {
                    guard data["fingerprint"] as? String == fingerprint,
                          let stored = data["payload"] as? Data,
                          try JSONDecoder().decode(WeeklyTargetDecision.self, from: stored) == decision else {
                        throw WeeklyTargetReviewError.changed
                    }
                    return stored
                }
                try decision.validateForNewCommit()
                let snapshot = try transaction.getDocument(profile)
                guard let current = snapshot.data(), decision.proposal.matchesPersistedTargets(current) else {
                    throw WeeklyTargetReviewError.changed
                }
                // Preserve the only legacy fact we know. No target recommendation is invented.
                let legacy = profile.collection("weeklyTargetDecisions").document("legacy-completion")
                let legacySnapshot = try transaction.getDocument(legacy)
                let goals = current["goals"] as? [String: Any] ?? [:]
                let priorDate = (goals["lastCheckInDate"] as? Timestamp)?.dateValue()
                    ?? (current["lastCheckInDate"] as? Timestamp)?.dateValue()
                if !legacySnapshot.exists, let priorDate {
                    transaction.setData(["kind": "legacyCompletion", "completedAt": Timestamp(date: priorDate)], forDocument: legacy)
                }
                if !decision.profilePatch.isEmpty { transaction.setData(decision.profilePatch, forDocument: profile, merge: true) }
                transaction.setData(["kind": "decision", "payload": payload, "fingerprint": fingerprint,
                                     "decidedAt": Timestamp(date: decision.decidedAt)], forDocument: receipt)
                return payload
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard let data = result as? Data else { throw WeeklyTargetReviewError.unavailable }
        return try JSONDecoder().decode(WeeklyTargetDecision.self, from: data)
    }

    func fetchWeeklyTargetDecisions(userID: String) async throws -> [WeeklyTargetDecision] {
        guard currentUserID() == userID else { throw WeeklyTargetReviewError.accountChanged }
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID)
            .collection("weeklyTargetDecisions").getDocuments(source: .server)
        let result = try snapshot.documents.compactMap { document -> WeeklyTargetDecision? in
            let data = document.data()
            if data["kind"] as? String == "legacyCompletion" { return nil }
            guard let payload = data["payload"] as? Data else { throw WeeklyTargetReviewError.invalid }
            let value = try JSONDecoder().decode(WeeklyTargetDecision.self, from: payload)
            guard value.proposal.userID == userID, document.documentID == value.id.uuidString,
                  try PlanFingerprint.make(value) == data["fingerprint"] as? String else { throw WeeklyTargetReviewError.invalid }
            return value
        }
        guard currentUserID() == userID else { throw WeeklyTargetReviewError.accountChanged }
        return result.sorted { $0.decidedAt > $1.decidedAt }
    }

    func fetchLegacyWeeklyCompletion(userID: String) async throws -> Date? {
        guard currentUserID() == userID else { throw WeeklyTargetReviewError.accountChanged }
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID)
            .collection("weeklyTargetDecisions").document("legacy-completion").getDocument(source: .server)
        guard currentUserID() == userID else { throw WeeklyTargetReviewError.accountChanged }
        return (snapshot.data()?["completedAt"] as? Timestamp)?.dateValue()
    }

    func saveGoalEditorChange(userID: String, baseline: GoalEditorDraft, data: [String: Any]) async throws {
        guard currentUserID() == userID else { throw GoalEditorError.accountChanged }
        let ref = db.collection(FirestoreCollection.users).document(userID)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                guard self.currentUserID() == userID else { throw GoalEditorError.accountChanged }
                let snapshot = try transaction.getDocument(ref)
                guard let current = snapshot.data(), baseline.matchesPersistedInputs(current) else { throw GoalEditorError.changed }
                transaction.setData(data, forDocument: ref, merge: true)
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
    }

    func saveWaterGoalChange(userID: String, baseline: Double, goal: Double) async throws {
        guard currentUserID() == userID else { throw GoalEditorError.accountChanged }
        guard goal.isFinite, (1...512).contains(goal) else { throw GoalEditorError.invalid }
        let ref = db.collection(FirestoreCollection.users).document(userID)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                guard self.currentUserID() == userID else { throw GoalEditorError.accountChanged }
                let snapshot = try transaction.getDocument(ref)
                guard let current = snapshot.data() else { throw GoalEditorError.changed }
                let goals = current["goals"] as? [String: Any] ?? [:]
                if let stored = goals["waterGoal"] {
                    guard let value = stored as? NSNumber,
                          abs(value.doubleValue - baseline) < 0.0001 || abs(value.doubleValue - goal) < 0.0001 else { throw GoalEditorError.changed }
                }
                transaction.updateData(["goals.waterGoal": goal, "goals.updatedAt": Date()], forDocument: ref)
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
    }

    func saveFoodPreferencesChange(userID: String, baseline: FoodPreferencesDraft, draft: FoodPreferencesDraft) async throws {
        guard currentUserID() == userID else { throw FoodPreferencesError.accountChanged }
        let accepted = try draft.validated()
        let ref = db.collection(FirestoreCollection.users).document(userID)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                guard self.currentUserID() == userID else { throw FoodPreferencesError.accountChanged }
                let snapshot = try transaction.getDocument(ref)
                guard let current = snapshot.data(),
                      baseline.matchesPersistedPreferences(current) || accepted.matchesPersistedPreferences(current) else {
                    throw FoodPreferencesError.changed
                }
                transaction.updateData(accepted.profilePatch(updatedAt: Date()), forDocument: ref)
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
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
        _ = try await saveWeightMeasurement(userID: userID, entryID: UUID().uuidString, weight: weight, date: date)
    }

    func saveWeightMeasurement(userID: String, entryID: String, weight: Double, date: Date) async throws -> Bool {
        guard currentUserID() == userID, weight.isFinite, weight > 0,
              !entryID.isEmpty, !entryID.contains("/"), date.timeIntervalSince1970.isFinite else { throw GoalEditorError.invalid }
        let userRef = db.collection(FirestoreCollection.users).document(userID)
        let entry = userRef.collection(FirestoreCollection.weightHistory).document(entryID)
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                guard self.currentUserID() == userID else { throw GoalEditorError.accountChanged }
                let existing = try transaction.getDocument(entry)
                if let data = existing.data() {
                    guard data["weight"] as? Double == weight,
                          let timestamp = data["timestamp"] as? Timestamp,
                          abs(timestamp.dateValue().timeIntervalSince(date)) < 0.001 else { throw GoalEditorError.changed }
                    return false
                }
                transaction.setData(["weight": weight, "timestamp": Timestamp(date: date)], forDocument: entry)
                if Calendar.current.isDateInToday(date) { transaction.setData(["weight": weight], forDocument: userRef, merge: true) }
                return true
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        return result as? Bool ?? false
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

    func fetchWeightHistoryForReview(userID: String) async throws -> [(id: String, date: Date, weight: Double)] {
        guard currentUserID() == userID else { throw WeeklyTargetReviewError.accountChanged }
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID)
            .collection(FirestoreCollection.weightHistory).order(by: "timestamp", descending: false)
            .getDocuments(source: .server)
        guard currentUserID() == userID else { throw WeeklyTargetReviewError.accountChanged }
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let weight = data["weight"] as? Double, let timestamp = data["timestamp"] as? Timestamp else { return nil }
            return (document.documentID, timestamp.dateValue(), weight)
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
        
        let ref = db.collection(FirestoreCollection.users).document(userID)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                if try !transaction.getDocument(ref).exists {
                    transaction.setData(userData, forDocument: ref)
                    transaction.setData(["date": Timestamp(date: Date()), "calories": 0.0],
                                        forDocument: ref.collection(FirestoreCollection.calorieHistory).document("initial"))
                }
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
    }
}

@MainActor
final class FirestoreMealExperimentRepository: MealExperimentRepository {
    private let db: Firestore
    init(db: Firestore = Firestore.firestore()) { self.db = db }

    func merge(_ state: MealExperimentCloudState, userID: String) async throws -> MealExperimentCloudState {
        guard DIContainer.shared.authService.currentUserID == userID else { throw MealExperimentError.noAccount }
        let ref = db.collection(FirestoreCollection.users).document(userID).collection("adaptiveTools").document("mealComparisons")
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(ref)
                let remote: MealExperimentCloudState
                if snapshot.exists {
                    guard snapshot.data()?["version"] as? Int == 1, let data = snapshot.data()?["payload"] as? Data else {
                        throw CocoaError(.coderReadCorrupt)
                    }
                    remote = try JSONDecoder().decode(MealExperimentCloudState.self, from: data)
                } else { remote = MealExperimentCloudState() }
                let merged = remote.merging(state)
                let payload = try JSONEncoder().encode(merged)
                guard payload.count < 900_000 else { throw CocoaError(.fileWriteOutOfSpace) }
                transaction.setData(["version": 1, "payload": payload, "updatedAt": FieldValue.serverTimestamp()], forDocument: ref)
                return payload
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard let payload = result as? Data else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(MealExperimentCloudState.self, from: payload)
    }
}
