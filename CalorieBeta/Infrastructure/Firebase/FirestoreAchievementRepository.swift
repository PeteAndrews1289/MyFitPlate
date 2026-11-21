import Foundation
import MyFitPlateCore
import FirebaseFirestore
import FirebaseAuth
import Combine

class FirestoreAchievementRepository: AchievementRepositoryProtocol {
    private let db: Firestore
    private let currentUserID: () -> String?
    init(db: Firestore = Firestore.firestore(), currentUserID: @escaping () -> String? = { Auth.auth().currentUser?.uid }) {
        self.db = db; self.currentUserID = currentUserID
    }
    
    func userProfilePublisher(userID: String) -> AnyPublisher<(points: Int, level: Int)?, Never> {
        let subject = PassthroughSubject<(points: Int, level: Int)?, Never>()
        let listener = db.collection(FirestoreCollection.users).document(userID)
            .addSnapshotListener { documentSnapshot, _ in
                guard let document = documentSnapshot, document.exists else {
                    subject.send(nil)
                    return
                }
                guard let points = document.data()?["totalAchievementPoints"] as? Int, points >= 0,
                      let level = document.data()?["userLevel"] as? Int, level >= 1 else { subject.send(nil); return }
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
                    do {
                        var status = try doc.data(as: UserAchievementStatus.self)
                        guard status.currentProgress.isFinite, status.currentProgress >= 0 else { throw AchievementAwardError.invalid }
                        status.id = doc.documentID
                        statuses.append(status)
                    } catch { subject.send(completion: .failure(error)); return }
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
    
    func preserveLegacyPointBalance(userID: String) async throws -> LegacyAchievementBalanceReceipt {
        guard currentUserID() == userID, !userID.isEmpty else { throw AchievementAwardError.accountChanged }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        let reference = owner.collection("achievementMigrations").document(LegacyAchievementBalanceReceipt.migrationID)
        let object = try await db.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                guard currentUserID() == userID else { throw AchievementAwardError.accountChanged }
                let profile = try transaction.getDocument(owner)
                let snapshot = try transaction.getDocument(reference)
                guard let points = profile.data()?["totalAchievementPoints"] as? Int else { throw AchievementAwardError.invalid }
                let existing = snapshot.exists ? try snapshot.data(as: LegacyAchievementBalanceReceipt.self) : nil
                let receipt = try LegacyAchievementBalanceReceipt.preserving(existing, ownerID: userID, profilePoints: points)
                guard currentUserID() == userID else { throw AchievementAwardError.accountChanged }
                if !snapshot.exists { transaction.setData(try Firestore.Encoder().encode(receipt), forDocument: reference) }
                return try JSONEncoder().encode(receipt)
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard currentUserID() == userID else { throw AchievementAwardError.accountChanged }
        guard let data = object as? Data else { throw AchievementAwardError.invalid }
        return try JSONDecoder().decode(LegacyAchievementBalanceReceipt.self, from: data)
    }

    func acceptAward(_ command: AchievementAwardCommand, levelThresholds: [Int]) async throws -> AchievementAwardResult {
        try command.validate(currentUserID: currentUserID())
        let owner = db.collection(FirestoreCollection.users).document(command.ownerID)
        let statuses = owner.collection(FirestoreCollection.achievementStatus)
        let canonical = statuses.document(command.achievementID)
        let receipt = owner.collection("achievementAwardReceipts").document(command.achievementID)
        let migrationReference = owner.collection("achievementMigrations").document(LegacyAchievementBalanceReceipt.migrationID)
        // Old clients sometimes used a different status document ID. Read those
        // aliases again inside the transaction before deciding any points are due.
        let aliases = try await statuses.whereField("achievementID", isEqualTo: command.achievementID).getDocuments(source: .server).documents.map(\.reference)
        let checkedCount: Int?
        switch command.evidence.kind {
        case "server_recipe_count": checkedCount = try await fetchRecipeCount(userID: command.ownerID)
        case "server_workout_count": checkedCount = try await fetchWorkoutCount(userID: command.ownerID)
        default: checkedCount = nil
        }
        let object: Any?
        do {
            object = try await db.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                try command.validate(currentUserID: currentUserID())
                let profile = try transaction.getDocument(owner)
                guard let profileData = profile.data(), let oldPoints = profileData["totalAchievementPoints"] as? Int,
                      oldPoints >= 0, oldPoints <= Int.max - command.points else { throw AchievementAwardError.invalid }
                let migrationSnapshot = try transaction.getDocument(migrationReference)
                let existingMigration = migrationSnapshot.exists ? try migrationSnapshot.data(as: LegacyAchievementBalanceReceipt.self) : nil
                let migration = try LegacyAchievementBalanceReceipt.preserving(existingMigration,
                    ownerID: command.ownerID, profilePoints: oldPoints)
                let current = try transaction.getDocument(canonical)
                let receiptSnapshot = try transaction.getDocument(receipt)
                var known: [UserAchievementStatus] = []
                if current.exists { known.append(try checkedStatus(current, achievementID: command.achievementID)) }
                for reference in aliases where reference.path != canonical.path {
                    let snapshot = try transaction.getDocument(reference)
                    if snapshot.exists { known.append(try checkedStatus(snapshot, achievementID: command.achievementID)) }
                }
                if receiptSnapshot.exists {
                    let accepted: AchievementAwardReceipt
                    do { accepted = try receiptSnapshot.data(as: AchievementAwardReceipt.self) } catch { throw AchievementAwardError.invalid }
                    guard accepted.command.ownerID == command.ownerID, accepted.command.achievementID == command.achievementID,
                          let status = known.first(where: \.isUnlocked) else { throw AchievementAwardError.invalid }
                    try accepted.command.validate(currentUserID: currentUserID())
                    if !migrationSnapshot.exists { transaction.setData(try Firestore.Encoder().encode(migration), forDocument: migrationReference) }
                    return try JSONEncoder().encode(AchievementAwardResult(status: status, totalPoints: oldPoints,
                        level: AchievementRules.level(for: oldPoints, thresholds: levelThresholds), awardedNow: false))
                }
                var status = command.status
                let awardsNow = !known.contains(where: \.isUnlocked)
                if var legacy = known.first(where: \.isUnlocked) {
                    if legacy.awardEvidence == nil { legacy.legacyAwardPreserved = true }
                    legacy.id = command.achievementID; status = legacy
                } else {
                    do { try validateEvidence(command, profile: profileData, owner: owner, transaction: transaction, checkedCount: checkedCount) } catch AchievementAwardError.invalid {
                        throw AchievementAwardError.evidenceUnavailable
                    }
                }
                let points = oldPoints + (awardsNow ? command.points : 0)
                let result = AchievementAwardResult(status: status, totalPoints: points,
                    level: AchievementRules.level(for: points, thresholds: levelThresholds), awardedNow: awardsNow)
                let encoded = try JSONEncoder().encode(result)
                let statusData = try Firestore.Encoder().encode(status)
                let receiptData = try Firestore.Encoder().encode(AchievementAwardReceipt(command: command, result: result))
                try command.validate(currentUserID: currentUserID())
                // Capture the carried-forward balance before the new award. All reads,
                // including exact source evidence, finish before any transaction write.
                if !migrationSnapshot.exists { transaction.setData(try Firestore.Encoder().encode(migration), forDocument: migrationReference) }
                // Status, points and immutable evidence receipt are accepted together.
                transaction.setData(statusData, forDocument: canonical, merge: true)
                if awardsNow { transaction.setData(["totalAchievementPoints": points, "userLevel": result.level], forDocument: owner, merge: true) }
                transaction.setData(receiptData, forDocument: receipt)
                return encoded
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        } catch {
            if let known = AchievementAwardError.identifying(error) { throw known }
            throw error
        }
        guard currentUserID() == command.ownerID, let data = object as? Data else { throw AchievementAwardError.accountChanged }
        return try JSONDecoder().decode(AchievementAwardResult.self, from: data)
    }

    private func checkedStatus(_ snapshot: DocumentSnapshot, achievementID: String) throws -> UserAchievementStatus {
        var status: UserAchievementStatus
        do { status = try snapshot.data(as: UserAchievementStatus.self) } catch { throw AchievementAwardError.invalid }
        guard status.achievementID == achievementID, status.currentProgress.isFinite, status.currentProgress >= 0 else { throw AchievementAwardError.invalid }
        status.id = snapshot.documentID
        return status
    }

    private func validateEvidence(_ command: AchievementAwardCommand, profile: [String: Any], owner: DocumentReference,
                                  transaction: Transaction, checkedCount: Int?) throws {
        let evidence = command.evidence
        guard !evidence.sourceID.contains("/"), evidence.recordedAt <= Date().addingTimeInterval(1),
              let definition = AchievementRules.defaultDefinitions().first(where: { $0.id == command.achievementID }) else { throw AchievementAwardError.invalid }
        func number(_ key: String) throws -> Double {
            guard let text = evidence.facts?[key], let value = Double(text), value.isFinite else { throw AchievementAwardError.invalid }; return value
        }
        func diary(_ key: String) throws -> DailyLog {
            guard !key.isEmpty, !key.contains("/") else { throw AchievementAwardError.invalid }
            let snapshot = try transaction.getDocument(owner.collection(FirestoreCollection.dailyLogs).document(key))
            guard snapshot.exists else { throw AchievementAwardError.evidenceNoLongerEligible }
            var log: DailyLog
            do { log = try snapshot.data(as: DailyLog.self) } catch { throw AchievementAwardError.evidenceUnavailable }
            log.id = key
            return log
        }
        func hasFood(_ log: DailyLog) -> Bool {
            log.meals.flatMap(\.foodItems).contains { !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.calories.isFinite && $0.calories >= 0 && $0.servingWeight.isFinite && $0.servingWeight > 0 }
        }
        switch evidence.kind {
        case "food_entry":
            let log = try diary(evidence.sourceID)
            guard let foodID = evidence.facts?["foodID"] else { throw AchievementAwardError.invalid }
            let matches = log.meals.flatMap(\.foodItems).filter { $0.id == foodID }
            guard !matches.isEmpty else { throw AchievementAwardError.evidenceNoLongerEligible }
            guard matches.count == 1, let food = matches.first, !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  food.calories.isFinite, food.calories >= 0, food.servingWeight.isFinite, food.servingWeight > 0 else { throw AchievementAwardError.invalid }
        case "diary_goals":
            let log = try diary(evidence.sourceID)
            let calories = try number("calories"), protein = try number("protein"), carbs = try number("carbs"), fats = try number("fats")
            let checked = AchievementRules.evaluateDailyGoals(dailyLog: log,
                targets: .init(calorieGoal: calories, protein: protein, carbs: carbs, fats: fats))
            let eligible: Bool
            switch command.achievementID {
            case "calorie_target_hit": eligible = hasFood(log) && calories > 0 && checked.calorieHit
            case "macro_master": eligible = hasFood(log) && protein > 0 && carbs > 0 && fats > 0 && checked.macroMasterHit
            case "hydration_hero": eligible = (log.waterTracker?.goalOunces ?? 0) > 0 && checked.hydrationHit
            default: eligible = false
            }
            guard eligible else { throw AchievementAwardError.evidenceNoLongerEligible }
        case "saved_goals":
            for key in ["calories", "protein", "carbs", "fats"] {
                guard let value = profile[key] as? Double, value.isFinite, value > 0 else { throw AchievementAwardError.evidenceUnavailable }
                guard abs(value - (try number(key))) < 0.001 else { throw AchievementAwardError.evidenceNoLongerEligible }
            }
        case "weight_entry", "weight_change":
            let measurement = try transaction.getDocument(owner.collection(FirestoreCollection.weightHistory).document(evidence.sourceID))
            guard measurement.exists else { throw AchievementAwardError.evidenceNoLongerEligible }
            guard let data = measurement.data(), let value = data["weight"] as? Double, value.isFinite, value > 0,
                  let timestamp = data["timestamp"] as? Timestamp, timestamp.dateValue() <= Date() else { throw AchievementAwardError.invalid }
            guard abs(value - (try number("weight"))) < 0.001 else { throw AchievementAwardError.evidenceNoLongerEligible }
            if command.achievementID == "first_5_lbs" {
                guard let initialID = evidence.facts?["initialID"], !initialID.contains("/"), initialID != evidence.sourceID else { throw AchievementAwardError.invalid }
                let first = try transaction.getDocument(owner.collection(FirestoreCollection.weightHistory).document(initialID))
                guard first.exists else { throw AchievementAwardError.evidenceNoLongerEligible }
                guard let weight = first.data()?["weight"] as? Double, weight.isFinite else { throw AchievementAwardError.invalid }
                guard abs(value - weight) >= definition.criteriaValue else { throw AchievementAwardError.evidenceNoLongerEligible }
            } else if command.achievementID == "target_reached" {
                guard let target = profile["targetWeight"] as? Double, target > 0, target.isFinite,
                      AchievementRules.hasReachedTargetWeight(currentWeight: value, targetWeight: target) else { throw AchievementAwardError.evidenceNoLongerEligible }
            }
        case "logging_days":
            let keys = evidence.facts?["dayKeys"]?.split(separator: ",").map(String.init) ?? []
            guard Set(keys).count == keys.count, Double(keys.count) >= definition.criteriaValue, keys.count <= 7 else { throw AchievementAwardError.invalid }
            let logs = try keys.map(diary)
            guard logs.allSatisfy(hasFood) else { throw AchievementAwardError.evidenceNoLongerEligible }
            let dates = logs.compactMap { LoggingHabitRules.civilDate(for: $0) }.sorted()
            guard dates.count == keys.count else { throw AchievementAwardError.evidenceUnavailable }
            for index in 1..<dates.count {
                guard Calendar.current.dateComponents([.day], from: dates[index - 1], to: dates[index]).day == 1 else { throw AchievementAwardError.invalid }
            }
        case "server_recipe_count", "server_workout_count":
            guard let count = checkedCount, count >= 0, (try number("count")) >= definition.criteriaValue else { throw AchievementAwardError.invalid }
            guard Double(count) >= definition.criteriaValue else { throw AchievementAwardError.evidenceNoLongerEligible }
        default: throw AchievementAwardError.invalid
        }
    }

    func saveUserStatus(userID: String, status: UserAchievementStatus) async throws {
        guard currentUserID() == userID, !status.isUnlocked, status.currentProgress.isFinite, status.currentProgress >= 0,
              AchievementRules.defaultDefinitions().contains(where: { $0.id == status.achievementID }) else { throw AchievementAwardError.invalid }
        let statuses = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.achievementStatus)
        let ref = statuses.document(status.achievementID)
        let aliases = try await statuses.whereField("achievementID", isEqualTo: status.achievementID).getDocuments(source: .server).documents.map(\.reference)
        _ = try await db.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                guard currentUserID() == userID else { throw AchievementAwardError.accountChanged }
                let snapshot = try transaction.getDocument(ref)
                let existing = snapshot.exists ? try checkedStatus(snapshot, achievementID: status.achievementID) : nil
                if existing?.isUnlocked == true { return true }
                for alias in aliases where alias.path != ref.path {
                    let snapshot = try transaction.getDocument(alias)
                    if snapshot.exists, try checkedStatus(snapshot, achievementID: status.achievementID).isUnlocked { return true }
                }
                var next = status; next.id = status.achievementID
                next.currentProgress = max(existing?.currentProgress ?? 0, status.currentProgress)
                transaction.setData(try Firestore.Encoder().encode(next), forDocument: ref, merge: true)
                return true
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
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
