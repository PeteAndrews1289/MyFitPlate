import Foundation
import CoreFoundation
import MyFitPlateCore
import FirebaseFirestore
import FirebaseAuth
import Network
import OSLog

final class FirestoreNutritionRepository: NutritionRepositoryProtocol, @unchecked Sendable {
    private let db: Firestore
    private let currentUserID: () -> String?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private let mutationStore: DailyLogMutationStore
    private let syncQueue = DispatchQueue(label: "MyFitPlate.diary-sync")
    private let networkMonitor = NWPathMonitor()
    private var syncingUsers = Set<String>()
    private var failedUsers = Set<String>()

    init(db: Firestore = Firestore.firestore(), outboxURL: URL? = nil,
         currentUserID: @escaping () -> String? = { Auth.auth().currentUser?.uid }) {
        self.db = db
        self.currentUserID = currentUserID
        mutationStore = DailyLogMutationStore(fileURL: outboxURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("MyFitPlate/diary-outbox.json"))
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied, let userID = self?.currentUserID() else { return }
            self?.retryPendingDailyLogs(userID: userID)
        }
        networkMonitor.start(queue: DispatchQueue(label: "MyFitPlate.diary-network"))
    }

    deinit { networkMonitor.cancel() }

    func dailyLogSyncState(userID: String) -> DailyLogSyncState {
        if syncQueue.sync(execute: { failedUsers.contains(userID) }) { return .failed }
        guard let count = try? mutationStore.pending(userID: userID).count else { return .failed }
        return count == 0 ? .synced : .pending(count)
    }

    func retryPendingDailyLogs(userID: String) {
        syncQueue.async { [weak self] in self?.drainMutations(userID: userID) }
    }

    func discardPendingDailyLogs(userID: String) throws {
        try syncQueue.sync {
            try mutationStore.removeAll(userID: userID)
            failedUsers.remove(userID)
        }
        notifySyncState(userID: userID)
    }

    private func notifySyncState(userID: String, hasNewMutation: Bool = false) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .dailyLogSyncStateChanged, object: userID,
                                            userInfo: ["hasNewMutation": hasNewMutation])
        }
    }

    private func drainMutations(userID: String) {
        guard currentUserID() == userID, !syncingUsers.contains(userID) else { return }
        do {
            guard let mutation = try mutationStore.pending(userID: userID).first else {
                // A view may have missed the final acknowledgement while backgrounded.
                // An empty retry still reconciles its displayed status with durable storage.
                failedUsers.remove(userID)
                notifySyncState(userID: userID)
                return
            }
            guard mutation.after.id != nil else { return }
            syncingUsers.insert(userID)
            commitDiaryAndLinkedInventory(userID: userID, mutation: mutation) { error in
                self.syncQueue.async {
                    self.syncingUsers.remove(userID)
                    do {
                        if let error { throw error }
                        try self.mutationStore.acknowledge(mutation)
                        self.failedUsers.remove(userID)
                        self.notifySyncState(userID: userID)
                        self.drainMutations(userID: userID)
                    } catch {
                        self.failedUsers.insert(userID)
                        self.notifySyncState(userID: userID)
                        let code = (error as NSError).code
                        if [FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue,
                            FirestoreErrorCode.aborted.rawValue].contains(code) {
                            self.syncQueue.asyncAfter(deadline: .now() + 15) { [weak self] in
                                self?.drainMutations(userID: userID)
                            }
                        }
                    }
                }
            }
        } catch {
            failedUsers.insert(userID)
            notifySyncState(userID: userID)
        }
    }

    private func includingPendingChanges(_ log: DailyLog, userID: String) throws -> DailyLog {
        let pending = try mutationStore.pending(userID: userID).filter { $0.after.id == log.id }
        return pending.reduce(log) { $1.applying(to: $0) }.rememberingMutationBase()
    }

    /// Success means durably accepted on this device. Sync state reports server acceptance.
    func updateDailyLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void) {
        guard log.id != nil, currentUserID() == userID else { completion(false); return }
        if log.pendingFoodEdit != nil || !(log.pendingFoodEdits ?? []).isEmpty || log.pendingActivityEdit != nil || NutritionDayReviewRules.requiresCheckedCommit(log) {
            updateCheckedFoodLog(userID: userID, log: log, completion: completion)
            return
        }
        do {
            try mutationStore.append(DailyLogMutation(userID: userID, log: log))
            notifySyncState(userID: userID, hasNewMutation: true)
            completion(true)
            retryPendingDailyLogs(userID: userID)
        } catch {
            completion(false)
        }
    }

    private func updateCheckedFoodLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void) {
        guard log.id != nil, let mutation = try? DailyLogMutation(userID: userID, log: log) else { completion(false); return }
        commitDiaryAndLinkedInventory(userID: userID, mutation: mutation) { error in
            // The local frozen FoodDetail or Undo checkpoint remains retryable until ack.
            completion(error == nil && self.currentUserID() == userID)
        }
    }

    func applyDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult {
        try await performDiaryTransfer(userID: userID, command: command, undo: false)
    }

    func undoDiaryTransfer(userID: String, receipt: DiaryTransferReceipt) async throws -> DiaryTransferResult {
        try receipt.validate()
        return try await performDiaryTransfer(userID: userID, command: receipt.command, undo: true)
    }

    func fetchDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult {
        try await performDiaryTransfer(userID: userID, command: command, undo: false, readOnly: true)
    }

    func cancelDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult? {
        try command.validate()
        guard command.userID == userID, currentUserID() == userID else { throw DiaryTransferError.accountChanged }
        let user = db.collection(FirestoreCollection.users).document(userID)
        let receiptRef = user.collection("diaryTransferReceipts").document(command.id.uuidString)
        let raw = try await db.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                guard currentUserID() == userID else { throw DiaryTransferError.accountChanged }
                let snapshot = try transaction.getDocument(receiptRef)
                if snapshot.exists {
                    let envelope = try snapshot.data(as: DiaryTransferReceiptEnvelope.self)
                    if envelope.kind == .cancelled {
                        _ = try envelope.cancellation(matching: command)
                        return NSNull()
                    }
                    let receipt = try envelope.receipt(matching: command)
                    let sourceSnapshot = try transaction.getDocument(user.collection(FirestoreCollection.dailyLogs).document(command.source.dayKey))
                    let destinationSnapshot = command.isSameDay ? sourceSnapshot
                        : try transaction.getDocument(user.collection(FirestoreCollection.dailyLogs).document(command.destination.dayKey))
                    let source = try sourceSnapshot.data().map { try decodeDailyLog(from: $0, documentID: command.source.dayKey) }
                        ?? DailyLog(id: command.source.dayKey, date: command.source.startOfDay, meals: [])
                    let destination = try destinationSnapshot.data().map { try decodeDailyLog(from: $0, documentID: command.destination.dayKey) }
                        ?? DailyLog(id: command.destination.dayKey, date: command.destination.startOfDay, meals: [])
                    return try JSONEncoder().encode(DiaryTransferResult(receipt: receipt, sourceLog: source, destinationLog: destination, newlyApplied: false))
                }
                guard currentUserID() == userID else { throw DiaryTransferError.accountChanged }
                // The same receipt read participates in every apply transaction. Whichever
                // commits first wins; a late apply retries and sees this permanent fence.
                let envelope = try DiaryTransferReceiptEnvelope(cancellation: DiaryTransferCancellation(command: command))
                transaction.setData(try Firestore.Encoder().encode(envelope), forDocument: receiptRef)
                return NSNull()
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard currentUserID() == userID else { throw DiaryTransferError.accountChanged }
        if raw is NSNull { return nil }
        guard let data = raw as? Data else { throw DiaryTransferError.receiptMismatch }
        return try JSONDecoder().decode(DiaryTransferResult.self, from: data)
    }

    /// Firestore transactions require a server connection. Do not enqueue an optimistic
    /// two-day replacement: the durable editor command remains pending until this ack.
    private func performDiaryTransfer(userID: String, command: DiaryTransferCommand, undo: Bool, readOnly: Bool = false) async throws -> DiaryTransferResult {
        try command.validate()
        guard command.userID == userID, currentUserID() == userID else { throw DiaryTransferError.accountChanged }
        if !readOnly { try requireTransferDaysSynced(userID: userID, command: command) }
        let user = db.collection(FirestoreCollection.users).document(userID)
        let sourceRef = user.collection(FirestoreCollection.dailyLogs).document(command.source.dayKey)
        let destinationRef = user.collection(FirestoreCollection.dailyLogs).document(command.destination.dayKey)
        let receiptRef = user.collection("diaryTransferReceipts").document(command.id.uuidString)
        let raw = try await db.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                guard currentUserID() == userID else { throw DiaryTransferError.accountChanged }
                if !readOnly { try requireTransferDaysSynced(userID: userID, command: command) }
                // Read every affected document and the immutable receipt before writing.
                let receiptSnapshot = try transaction.getDocument(receiptRef)
                let envelope = receiptSnapshot.exists ? try receiptSnapshot.data(as: DiaryTransferReceiptEnvelope.self) : nil
                if let envelope, envelope.kind == .cancelled {
                    _ = try envelope.cancellation(matching: command); throw DiaryTransferError.cancelled
                }
                let sourceSnapshot = try transaction.getDocument(sourceRef)
                let destinationSnapshot = command.isSameDay ? sourceSnapshot : try transaction.getDocument(destinationRef)
                let source = try sourceSnapshot.data().map { try decodeDailyLog(from: $0, documentID: command.source.dayKey) }
                    ?? DailyLog(id: command.source.dayKey, date: command.source.startOfDay, meals: [])
                let destination = try destinationSnapshot.data().map { try decodeDailyLog(from: $0, documentID: command.destination.dayKey) }
                    ?? DailyLog(id: command.destination.dayKey, date: command.destination.startOfDay, meals: [])
                let result: DiaryTransferResult
                if let envelope {
                    let receipt = try envelope.receipt(matching: command)
                    result = undo ? try DiaryTransferRules.undo(receipt, source: source, destination: destination)
                        : DiaryTransferResult(receipt: receipt, sourceLog: source, destinationLog: destination, newlyApplied: false)
                } else {
                    guard !undo, !readOnly else { throw DiaryTransferError.receiptMissing }
                    result = try DiaryTransferRules.apply(command, source: source, destination: destination)
                }
                guard currentUserID() == userID else { throw DiaryTransferError.accountChanged }
                if result.newlyApplied, !readOnly {
                    // Existing optional fields and older-client document shapes stay untouched.
                    // Receipts live outside the day document so ordinary diary writes retain them.
                    let logs = command.isSameDay ? [result.sourceLog]
                        : command.mode == .copy ? [result.destinationLog] : [result.sourceLog, result.destinationLog]
                    for log in logs {
                        guard let key = log.id else { throw DiaryTransferError.invalid }
                        let sourceData = sourceSnapshot.data() ?? [:], destinationData = destinationSnapshot.data() ?? [:]
                        let currentData = key == command.source.dayKey ? sourceData : destinationData
                        var payload: [String: Any] = ["meals": try encodeTransferMeals(log, command: command,
                            sourceData: sourceData, destinationData: destinationData),
                            "date": currentData["date"] ?? Timestamp(date: log.date)]
                        if currentData.isEmpty { payload["id"] = key }
                        transaction.setData(payload, forDocument: user.collection(FirestoreCollection.dailyLogs).document(key), merge: true)
                    }
                    transaction.setData(try Firestore.Encoder().encode(DiaryTransferReceiptEnvelope(receipt: result.receipt)), forDocument: receiptRef)
                }
                return try JSONEncoder().encode(result)
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard currentUserID() == userID else { throw DiaryTransferError.accountChanged }
        guard let data = raw as? Data else { throw DiaryTransferError.receiptMismatch }
        return try JSONDecoder().decode(DiaryTransferResult.self, from: data)
    }

    /// Reuse the original Firestore representation of unchanged/moved snapshots.
    /// Re-encoding a decoded fractional provenance Date can shift its last bit. New
    /// copies encode only their new values while cloning the original provenance map.
    private func encodeTransferMeals(_ log: DailyLog, command: DiaryTransferCommand,
                                     sourceData: [String: Any], destinationData: [String: Any]) throws -> [[String: Any]] {
        let currentData = log.id == command.source.dayKey ? sourceData : destinationData
        let otherData = log.id == command.source.dayKey ? destinationData : sourceData
        let currentMeals = try rawTransferMeals(currentData)
        let currentFoods = try rawTransferFoods(currentData), otherFoods = try rawTransferFoods(otherData)
        let originalFoods = try rawTransferFoods(sourceData)
        return try log.meals.map { meal in
            var result = currentMeals.first { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == meal.id }
                ?? ["id": meal.id.uuidString]
            result["name"] = meal.name
            result["foodItems"] = try meal.foodItems.map { food -> [String: Any] in
                if let raw = currentFoods[food.id], try rawMatchesFood(raw, food) { return raw }
                if command.mode == .move, let raw = otherFoods[food.id], try rawMatchesFood(raw, food) { return raw }
                if command.mode == .copy,
                   let entry = command.entries.first(where: { $0.destinationFood.id == food.id }),
                   FoodEditPrecondition.sameSnapshot(entry.destinationFood, food),
                   let original = originalFoods[entry.originalFood.id], try rawMatchesFood(original, entry.originalFood) {
                    var encoded = try Firestore.Encoder().encode(food)
                    encoded["sourceMetadata"] = original["sourceMetadata"]
                    encoded["portionQuestionReceipt"] = original["portionQuestionReceipt"]
                    return encoded
                }
                throw DiaryTransferError.receiptMismatch
            }
            return result
        }
    }

    private func rawTransferMeals(_ data: [String: Any]) throws -> [[String: Any]] {
        if data.isEmpty { return [] }
        guard let meals = data["meals"] as? [[String: Any]] else { throw DiaryTransferError.receiptMismatch }
        return meals
    }

    private func rawTransferFoods(_ data: [String: Any]) throws -> [String: [String: Any]] {
        var foods: [String: [String: Any]] = [:]
        for meal in try rawTransferMeals(data) {
            guard let items = meal["foodItems"] as? [[String: Any]] else { throw DiaryTransferError.receiptMismatch }
            for item in items {
                guard let id = item["id"] as? String, foods[id] == nil else { throw DiaryTransferError.receiptMismatch }
                foods[id] = item
            }
        }
        return foods
    }

    private func rawMatchesFood(_ raw: [String: Any], _ food: FoodItem) throws -> Bool {
        FoodEditPrecondition.sameSnapshot(try Firestore.Decoder().decode(FoodItem.self, from: raw), food)
    }

    private func requireTransferDaysSynced(userID: String, command: DiaryTransferCommand) throws {
        let keys = Set([command.source.dayKey, command.destination.dayKey])
        guard try !mutationStore.pending(userID: userID).contains(where: { $0.after.id.map(keys.contains) ?? false }) else {
            throw DiaryTransferError.pendingWrites
        }
    }

    func fetchLogInternal(userID: String, day: DiaryDayContext, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        guard day.isOwned(by: userID), currentUserID() == userID else { completion(.failure(DiaryTransferError.accountChanged)); return }
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(day.dayKey)
        ref.getDocument { snapshot, error in
            do {
                guard self.currentUserID() == userID else { throw DiaryTransferError.accountChanged }
                if let error, (error as NSError).code != FirestoreErrorCode.unavailable.rawValue { throw error }
                let log = try snapshot?.data().map { try self.decodeDailyLog(from: $0, documentID: day.dayKey) }
                    ?? DailyLog(id: day.dayKey, date: day.startOfDay, meals: [])
                completion(.success(try self.includingPendingChanges(log, userID: userID)))
                self.retryPendingDailyLogs(userID: userID)
            } catch { completion(.failure(error)) }
        }
    }

    func addLogSnapshotListener(userID: String, day: DiaryDayContext, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any {
        guard day.isOwned(by: userID), currentUserID() == userID else { onChange(.failure(DiaryTransferError.accountChanged)); return UUID() }
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(day.dayKey)
        var latest = DailyLog(id: day.dayKey, date: day.startOfDay, meals: [])
        let publish: () -> Void = {
            guard self.currentUserID() == userID else { return }
            do { onChange(.success(try self.includingPendingChanges(latest, userID: userID))) } catch { onChange(.failure(error)) }
        }
        let observer = NotificationCenter.default.addObserver(forName: .dailyLogSyncStateChanged, object: nil, queue: .main) { note in
            // Preserve the legacy listener's receipt race guard: only a new local
            // mutation republishes its overlay. Remote acknowledgements use the listener.
            if note.object as? String == userID, note.userInfo?["hasNewMutation"] as? Bool == true { publish() }
        }
        let listener = ref.addSnapshotListener { snapshot, error in
            guard self.currentUserID() == userID else { return }
            do {
                if let error { throw error }
                latest = try snapshot?.data().map { try self.decodeDailyLog(from: $0, documentID: day.dayKey) }
                    ?? DailyLog(id: day.dayKey, date: day.startOfDay, meals: [])
                publish()
            } catch { onChange(.failure(error)) }
        }
        retryPendingDailyLogs(userID: userID)
        return DailyLogListenerHandle(listener: listener, observer: observer)
    }

    func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let day = Calendar.current.startOfDay(for: date)
        let dayID = dateFormatter.string(from: day)
        let ref = db.collection(FirestoreCollection.users).document(userID)
            .collection(FirestoreCollection.dailyLogs).document(dayID)
        ref.getDocument { snapshot, error in
            do {
                // An uncached offline day is an ephemeral empty view, never a database write.
                if let error, (error as NSError).code != FirestoreErrorCode.unavailable.rawValue { throw error }
                let log = try snapshot?.data().map { try self.decodeDailyLog(from: $0, documentID: dayID) }
                    ?? DailyLog(id: dayID, date: day, meals: [])
                completion(.success(try self.includingPendingChanges(log, userID: userID)))
                self.retryPendingDailyLogs(userID: userID)
            } catch { completion(.failure(error)) }
        }
    }

    func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any {
        let day = Calendar.current.startOfDay(for: date)
        let dayID = dateFormatter.string(from: day)
        let ref = db.collection(FirestoreCollection.users).document(userID)
            .collection(FirestoreCollection.dailyLogs).document(dayID)
        var latest = DailyLog(id: dayID, date: day, meals: [])
        let publish = {
            do { onChange(.success(try self.includingPendingChanges(latest, userID: userID))) } catch { onChange(.failure(error)) }
        }
        let observer = NotificationCenter.default.addObserver(forName: .dailyLogSyncStateChanged, object: nil, queue: .main) { note in
            // An acknowledgement can arrive before the listener's server snapshot. Only local
            // additions republish the overlay; publishing on acknowledgement could briefly
            // remove the just-saved entry using an older snapshot after its queue receipt is gone.
            if note.object as? String == userID, note.userInfo?["hasNewMutation"] as? Bool == true { publish() }
        }
        let listener = ref.addSnapshotListener { snapshot, error in
            do {
                if let error { throw error }
                latest = try snapshot?.data().map { try self.decodeDailyLog(from: $0, documentID: dayID) }
                    ?? DailyLog(id: dayID, date: day, meals: [])
                publish()
            } catch { onChange(.failure(error)) }
        }
        retryPendingDailyLogs(userID: userID)
        return DailyLogListenerHandle(listener: listener, observer: observer)
    }

    func removeLogSnapshotListener(_ handle: Any) {
        (handle as? DailyLogListenerHandle)?.remove()
    }

    func fetchDailyHistory(userID: String, startDate: Date?, endDate: Date?) async throws -> [DailyLog] {
        try await readDailyHistory(userID: userID, startDate: startDate, endDate: endDate, requireServer: false)
    }

    func fetchDailyHistoryForReview(userID: String, startDate: Date, endDate: Date) async throws -> [DailyLog] {
        try await readDailyHistory(userID: userID, startDate: startDate, endDate: endDate, requireServer: true)
    }

    func fetchExportDailyHistory(userID: String) async throws -> [DailyLog] {
        try await readDailyHistory(userID: userID, startDate: nil, endDate: nil, requireServer: true)
    }

    private func readDailyHistory(userID: String, startDate: Date?, endDate: Date?, requireServer: Bool) async throws -> [DailyLog] {
        var query: Query = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs)
        if let start = startDate { query = query.whereField("date", isGreaterThanOrEqualTo: Timestamp(date: start)) }
        if let end = endDate {
            let endOfQueryDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
            query = query.whereField("date", isLessThan: Timestamp(date: endOfQueryDay))
        }
        query = query.order(by: "date", descending: true)
        
        let snapshot = try await query.getDocuments(source: requireServer ? .server : .default)
        var logs = try snapshot.documents.map { try self.includingPendingChanges(
            self.decodeDailyLog(from: $0.data(), documentID: $0.documentID), userID: userID
        ) }
        for mutation in try mutationStore.pending(userID: userID) where !logs.contains(where: { $0.id == mutation.after.id }) {
            let date = mutation.after.date
            if let startDate, date < startDate { continue }
            if let endDate, Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: endDate) { continue }
            logs.append(try includingPendingChanges(DailyLog(id: mutation.after.id, date: date, meals: []), userID: userID))
        }
        return logs.sorted { $0.date > $1.date }
    }
    
    func fetchRecommendedFoods(userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) else {
            completion(.success([]))
            return
        }

        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField("date", isLessThanOrEqualTo: Timestamp(date: endDate))
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                var foodFrequency: [String: (food: FoodItem, count: Int)] = [:]
                let logs: [DailyLog]
                do {
                    logs = try documents.map {
                        try self.decodeDailyLog(from: $0.data(), documentID: $0.documentID)
                    }
                } catch {
                    completion(.failure(error))
                    return
                }

                for log in logs {
                    if let meal = log.meals.first(where: { $0.name.lowercased() == mealName.lowercased() }) {
                        for food in meal.foodItems {
                            if var entry = foodFrequency[food.name] {
                                entry.count += 1
                                foodFrequency[food.name] = entry
                            } else {
                                foodFrequency[food.name] = (food: food, count: 1)
                            }
                        }
                    }
                }

                let sortedFoods = foodFrequency.values
                    .sorted { $0.count > $1.count }
                    .map { $0.food }

                completion(.success(Array(sortedFoods.prefix(10))))
            }
    }
    
    private func decodeDailyLog(from data: [String: Any], documentID: String) throws -> DailyLog {
        do {
            var log = try Firestore.Decoder().decode(DailyLog.self, from: data)
            log.id = documentID
            return log.rememberingMutationBase()
        } catch {
            AppLog.data.error("Failed to decode DailyLog \(documentID, privacy: .public). Preserving remote document: \(error.localizedDescription, privacy: .public)")
            throw FirestoreNutritionRepositoryError.dailyLogDecodeFailed(documentID: documentID, underlying: error)
        }
    }
    
    func saveDailyLog(userID: String, log: DailyLog) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            updateDailyLog(userID: userID, log: log) { accepted in
                if accepted { continuation.resume() } else { continuation.resume(throwing: CocoaError(.fileWriteUnknown)) }
            }
        }
    }

    // MARK: - Generic Firestore Fetch (Internal)y List
    
    // MARK: - Meal Plans & Grocery List
    
    func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay? {
        let planRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans).document(dateString)
        let document = try await planRef.getDocument()
        guard document.exists else { return nil }

        let payload = try document.data(as: MealPlanPayload.self)
        return MealPlanDay(
            id: payload.id ?? document.documentID,
            date: payload.date.dateValue(),
            meals: payload.meals
        )
    }

    func fetchMealPlansForStockReservations(userID: String) async throws -> [MealPlanDay] {
        guard currentUserID() == userID, !userID.isEmpty else { throw MealPlanChangeReceiptError.accountChanged }
        let collection = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans)
        var cursor: DocumentSnapshot?
        var plans: [MealPlanDay] = []
        repeat {
            var query = collection.order(by: FieldPath.documentID()).limit(to: 100)
            if let cursor { query = query.start(afterDocument: cursor) }
            let page = try await query.getDocuments(source: .server)
            guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
            for document in page.documents {
                let payload = try document.data(as: MealPlanPayload.self)
                guard payload.id == nil || payload.id == document.documentID,
                      DiaryDayContext(userID: userID, date: payload.date.dateValue(), dayKey: document.documentID) != nil else { throw MealPlanChangeReceiptError.invalid }
                plans.append(MealPlanDay(id: document.documentID, date: payload.date.dateValue(), meals: payload.meals))
            }
            cursor = page.documents.count == 100 ? page.documents.last : nil
        } while cursor != nil
        return plans
    }
    
    private struct MealPlanPayload: Codable {
        let id: String?
        let date: Timestamp
        let meals: [PlannedMeal]
    }
    
    func saveMealPlan(userID: String, plan: MealPlanDay) async throws {
        let planID = plan.id
        let planRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans).document(planID)
        let data = try Firestore.Encoder().encode(MealPlanPayload(
            id: planID,
            date: Timestamp(date: plan.date),
            meals: plan.meals
        ))
        try await planRef.setData(data, merge: true)
    }
    
    func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws {
        let batch = db.batch()
        let collectionRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans)
        
        for plan in plans {
            let dayId = plan.id
            let data = try Firestore.Encoder().encode(MealPlanPayload(
                id: dayId,
                date: Timestamp(date: plan.date),
                meals: plan.meals
            ))
            batch.setData(data, forDocument: collectionRef.document(dayId), merge: true)
        }
        
        try await batch.commit()
    }

    func applyMealPlanChange(userID: String, change: MealPlanChange) async throws {
        guard try JSONEncoder().encode(change).count <= 750_000 else { throw MealPlanChangeReceiptError.invalid }
        let result = try await transactMealPlanChange(userID: userID, change: change, action: .apply)
        guard result == .accepted else { throw MealPlanChangeReceiptError.cancelled }
    }

    func resolveMealPlanChange(userID: String, change: MealPlanChange, cancelPending: Bool) async throws -> MealPlanChangeResolution {
        try await transactMealPlanChange(userID: userID, change: change, action: cancelPending ? .cancel : .status)
    }

    private enum MealPlanChangeAction { case apply, status, cancel }

    private func transactMealPlanChange(userID: String, change: MealPlanChange,
                                        action: MealPlanChangeAction) async throws -> MealPlanChangeResolution {
        try MealPlanChangeReceipt.validateEnvelope(userID: userID, change: change)
        if case .apply = action { try MealPlanEditingRules.validate(change) }
        guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
        let user = db.collection(FirestoreCollection.users).document(userID)
        let collection = user.collection(FirestoreCollection.mealPlans)
        let receiptRef = user.collection("mealPlanChangeReceipts").document(change.id.uuidString)
        let accepted = try MealPlanChangeReceipt(userID: userID, change: change, status: .accepted)
        let cancelled = try MealPlanChangeReceipt(userID: userID, change: change, status: .cancelled)
        let acceptedData = try Firestore.Encoder().encode(accepted)
        let cancelledData = try Firestore.Encoder().encode(cancelled)
        let resolution: MealPlanChangeResolution = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ [self] transaction, pointer -> Any? in
                do {
                    guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
                    let receiptDocument = try transaction.getDocument(receiptRef)
                    if receiptDocument.exists {
                        let receipt = try receiptDocument.data(as: MealPlanChangeReceipt.self)
                        try receipt.validate(userID: userID, change: change)
                        // Acceptance is durable evidence even after later edits or deletion.
                        // Replay never reapplies an old payload over the current plans.
                        return receipt.resolution
                    }
                    switch action {
                    case .status: return MealPlanChangeResolution.pending
                    case .cancel:
                        transaction.setData(cancelledData, forDocument: receiptRef)
                        return MealPlanChangeResolution.cancelled
                    case .apply: break
                    }
                    var originalDocuments: [String: (MealPlanDay, [String: Any])] = [:]
                    for day in change.before {
                        let ref = collection.document(MealPlanEditingRules.dayID(day.date))
                        let snapshot = try transaction.getDocument(ref)
                        let payload = snapshot.exists ? try snapshot.data(as: MealPlanPayload.self) : nil
                        let actual = payload.map { MealPlanDay(id: $0.id ?? ref.documentID, date: $0.date.dateValue(), meals: $0.meals) }
                        guard MealPlanEditingRules.matches(actual, expected: day) else { throw MealPlanEditError.changed }
                        if let actual, let raw = snapshot.data() { originalDocuments[ref.documentID] = (actual, raw) }
                    }
                    let cookingWrites = try self.checkedCookingDefinitions(change: change, userID: userID, transaction: transaction)
                    for day in change.after {
                        let key = MealPlanEditingRules.dayID(day.date)
                        let payload = MealPlanPayload(id: key, date: Timestamp(date: day.date), meals: day.meals)
                        var data = try Firestore.Encoder().encode(payload)
                        if let (original, raw) = originalDocuments[key] {
                            data = try self.preservingUnchangedWorkspaceFields(data: data, raw: raw, before: original, after: day)
                        }
                        transaction.setData(data, forDocument: collection.document(key), merge: true)
                    }
                    for (reference, data) in cookingWrites { transaction.setData(data, forDocument: reference, merge: true) }
                    transaction.setData(acceptedData, forDocument: receiptRef)
                    return MealPlanChangeResolution.accepted
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { result, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == MealPlanChangeReceiptError.errorDomain,
                       let known = MealPlanChangeReceiptError(rawValue: failure.code) {
                        continuation.resume(throwing: known)
                    } else { continuation.resume(throwing: error) }
                } else if let result = result as? MealPlanChangeResolution {
                    continuation.resume(returning: result)
                } else { continuation.resume(throwing: MealPlanChangeReceiptError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
        return resolution
    }

    func discardMealPlans(
        userID: String,
        dateStrings: [String],
        retainingGroceryItems: [GroceryListItem]
    ) async throws {
        guard currentUserID() == userID else { throw MealPlanEditError.accountChanged }
        let dates = Set(dateStrings)
        try MealPlanDiscardRules.validate(plans: [], deleting: dates)
        let userRef = db.collection(FirestoreCollection.users).document(userID)
        let planCollection = userRef.collection(FirestoreCollection.mealPlans)
        let groceryRef = userRef.collection(FirestoreCollection.userSettings).document(FirestoreDocument.groceryList)
        _ = try await db.runTransaction { [self] transaction, pointer -> Any? in
            do {
                guard currentUserID() == userID else { throw MealPlanEditError.accountChanged }
                var current: [MealPlanDay] = []
                for key in dates.sorted() {
                    let document = try transaction.getDocument(planCollection.document(key))
                    if document.exists {
                        let payload = try document.data(as: MealPlanPayload.self)
                        current.append(MealPlanDay(id: payload.id ?? key, date: payload.date.dateValue(), meals: payload.meals))
                    }
                }
                let groceryDocument = try transaction.getDocument(groceryRef)
                // Validate the actual transaction snapshots. A simultaneous cross-week
                // allocation changes a read day, so Firestore retries before deletion.
                try MealPlanDiscardRules.validate(plans: current, deleting: dates)
                let rawItems = groceryDocument.data()?["items"]
                guard rawItems == nil || rawItems is [[String: Any]] else { throw GroceryChecklistError.invalid }
                let encodedItems = rawItems as? [[String: Any]] ?? []
                let retained = try encodedItems.filter { raw in
                    let item = try Firestore.Decoder().decode(GroceryListItem.self, from: raw)
                    return !MealPlanDiscardRules.removes(item, deleting: dates)
                }
                for key in dates { transaction.deleteDocument(planCollection.document(key)) }
                // Keep the latest manual/other-week items and raw future fields; the
                // caller's preflight checklist may already be stale or deleted.
                if groceryDocument.exists {
                    transaction.setData(["items": retained, "lastUpdated": Timestamp(date: Date())],
                        forDocument: groceryRef, merge: true)
                }
                return true
            } catch { pointer?.pointee = error as NSError; return nil }
        }
        guard currentUserID() == userID else { throw MealPlanEditError.accountChanged }
    }
    
    func fetchGroceryList(userID: String) async throws -> [GroceryListItem] {
        guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
        let listRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.userSettings).document(FirestoreDocument.groceryList)
        let document = try await listRef.getDocument()
        guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
        guard let data = document.data(), let raw = data["items"] else { return [] }
        guard let rows = raw as? [[String: Any]] else { throw GroceryChecklistError.invalid }
        return try rows.map { try Firestore.Decoder().decode(GroceryListItem.self, from: $0) }
    }

    func saveGroceryList(userID: String, items: [GroceryListItem]) async throws {
        let listRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.userSettings).document(FirestoreDocument.groceryList)
        let listData = try items.map { try Firestore.Encoder().encode($0) }
        try await listRef.setData(["items": listData, "lastUpdated": Timestamp(date: Date())], merge: true)
    }

    func applyGroceryMutation(userID: String, mutation: GroceryListMutation) async throws -> [GroceryListItem] {
        guard try await transactGroceryMutation(userID: userID, mutation: mutation, action: .apply) == .accepted else {
            throw GroceryChecklistError.cancelled
        }
        return try await fetchGroceryList(userID: userID)
    }
    func resolveGroceryMutation(userID: String, mutation: GroceryListMutation, cancelPending: Bool) async throws -> GroceryMutationResolution {
        try await transactGroceryMutation(userID: userID, mutation: mutation, action: cancelPending ? .cancel : .status)
    }

    // MARK: - Pantry
    
    func fetchInventory(userID: String) async throws -> [PantryItem] {
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems).getDocuments()
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        return try snapshot.documents.map { try $0.data(as: PantryItem.self) }
    }

    func fetchInventoryHistory(userID: String) async throws -> [InventoryReceipt] {
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection("inventoryEvents")
            .order(by: "recordedAt", descending: true).limit(to: 100).getDocuments()
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        return try snapshot.documents.map { try $0.data(as: InventoryReceipt.self) }
    }

    func applyInventoryMutation(userID: String, mutation: InventoryMutation) async throws {
        try mutation.validate()
        guard currentUserID() == userID, mutation.userID == userID else { throw InventoryError.accountChanged }
        if let patch = mutation.diary {
            guard try !mutationStore.pending(userID: userID).contains(where: { $0.after.id == patch.day.dayKey }) else { throw DiaryTransferError.pendingWrites }
        }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        let eventRef = owner.collection("inventoryEvents").document(mutation.id.uuidString)
        let receipt = try InventoryReceipt(mutation, status: .accepted)
        let legacy = try await legacyInventoryIntakeSources(userID: userID, foodIDs: Set(mutation.diary.map { [$0.foodID] } ?? []))
        _ = try await db.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                guard currentUserID() == userID else { throw InventoryError.accountChanged }
                let existing = try transaction.getDocument(eventRef)
                if existing.exists {
                    let saved = try existing.data(as: InventoryReceipt.self)
                    try saved.validate(mutation)
                    guard saved.status == .accepted else { throw InventoryError.cancelled }
                    return true
                }
                let sourceRef = try mutation.uniqueSourceKey.map { owner.collection("inventorySourceLocks").document(try PlanFingerprint.make($0)) }
                if let sourceRef, try transaction.getDocument(sourceRef).exists { throw InventoryError.alreadyApplied }
                var oldOperation: InventoryMutation?
                var undoneSourceRef: DocumentReference?
                if let undoing = mutation.undoing {
                    let original = try transaction.getDocument(owner.collection("inventoryEvents").document(undoing.uuidString))
                    guard original.exists else { throw InventoryError.changed }
                    let saved = try original.data(as: InventoryReceipt.self)
                    guard saved.userID == userID, saved.status == .accepted else { throw InventoryError.changed }
                    oldOperation = try saved.mutation()
                    if let originalKey = oldOperation?.uniqueSourceKey {
                        let ref = owner.collection("inventorySourceLocks").document(try PlanFingerprint.make(originalKey))
                        let lock = try transaction.getDocument(ref)
                        guard lock.data()?["operationID"] as? String == undoing.uuidString else { throw InventoryError.changed }
                        undoneSourceRef = ref
                    }
                }
                if mutation.reason == .cook { try self.checkReviewedCookingSource(mutation, userID: userID, transaction: transaction) }
                var current: [PantryItem] = []
                var rawPantryItems: [UUID: [String: Any]] = [:]
                for id in mutation.itemIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                    let snapshot = try transaction.getDocument(owner.collection(FirestoreCollection.pantryItems).document(id.uuidString))
                    if snapshot.exists {
                        current.append(try snapshot.data(as: PantryItem.self)); rawPantryItems[id] = snapshot.data()
                    }
                }
                _ = try mutation.applying(to: current)
                if let oldOperation { try InventoryPlanningRules.validateUndo(mutation, original: oldOperation, current: current) }
                let groceryRef = owner.collection(FirestoreCollection.userSettings).document(FirestoreDocument.groceryList)
                var groceries: [GroceryListItem]?
                var rawGroceryItems: [[String: Any]] = []
                if let patch = mutation.grocery {
                    let snapshot = try transaction.getDocument(groceryRef)
                    let value = snapshot.data()?["items"]
                    guard value == nil || value is [[String: Any]] else { throw InventoryError.invalid }
                    let raw = value as? [[String: Any]] ?? []
                    rawGroceryItems = raw
                    groceries = try patch.applying(to: raw.map { try Firestore.Decoder().decode(GroceryListItem.self, from: $0) })
                }
                var diary: (DocumentReference, [String: Any])?
                var deletedFoodBackup: [String: Any]?
                if let patch = mutation.diary {
                    guard try !mutationStore.pending(userID: userID).contains(where: { $0.after.id == patch.day.dayKey }) else { throw DiaryTransferError.pendingWrites }
                    let ref = owner.collection(FirestoreCollection.dailyLogs).document(patch.day.dayKey)
                    let snapshot = try transaction.getDocument(ref)
                    let raw = snapshot.data() ?? [:]
                    let original = try snapshot.data().map { try decodeDailyLog(from: $0, documentID: patch.day.dayKey) }
                        ?? DailyLog(id: patch.day.dayKey, date: patch.day.startOfDay, meals: [])
                    let projected = try patch.applying(to: original)
                    let rawMeals = try rawTransferMeals(raw)
                    let rawFoods = try rawTransferFoods(raw)
                    if patch.desired == nil, patch.expected != nil {
                        guard let actual = original.meals.flatMap(\.foodItems).first(where: { $0.id == patch.foodID }) else { throw InventoryIntakeError.changed }
                        deletedFoodBackup = try exactRawIntakeFood(raw, food: actual)
                    }
                    let meals: [[String: Any]] = try projected.meals.map { meal in
                        var value = rawMeals.first { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == meal.id } ?? ["id": meal.id.uuidString]
                        value["name"] = meal.name
                        value["foodItems"] = try meal.foodItems.map { food -> [String: Any] in
                            if food.id == patch.foodID, let desired = patch.desired {
                                let fields = try Firestore.Encoder().encode(desired)
                                if let rawFood = rawFoods[food.id], let before = original.meals.flatMap(\.foodItems).first(where: { $0.id == food.id }) {
                                    return try self.preservingUnchangedWorkspaceFields(data: fields, raw: rawFood, before: before, after: desired, allowsDeletes: false)
                                }
                                return fields
                            }
                            guard let preserved = rawFoods[food.id] else { throw InventoryError.changed }
                            return preserved
                        }
                        return value
                    }
                    var payload: [String: Any] = ["meals": meals, "date": raw["date"] ?? Timestamp(date: patch.day.startOfDay)]
                    if raw.isEmpty { payload["id"] = patch.day.dayKey }
                    diary = (ref, payload)
                }
                let intake = try stockMutationIntakeIndex(userID: userID, mutation: mutation, receipt: receipt,
                    legacy: mutation.diary.flatMap { legacy[$0.foodID] }, transaction: transaction)
                guard currentUserID() == userID else { throw InventoryError.accountChanged }
                for item in mutation.after {
                    var encoded = try Firestore.Encoder().encode(item)
                    if let raw = rawPantryItems[item.id], let original = current.first(where: { $0.id == item.id }) {
                        encoded = try self.preservingUnchangedWorkspaceFields(data: encoded, raw: raw, before: original, after: item)
                    }
                    for key in ["quantityUnknown", "quantityVerified", "bestBefore", "preparation", "location", "cookedBatch", "portionFood", "cookedAt", "isArchived", "creationUndone", "recordedPlannedPortions", "productSnapshot", "purchaseEvidence"] where encoded[key] == nil {
                        encoded[key] = FieldValue.delete()
                    }
                    transaction.setData(encoded, forDocument: owner.collection(FirestoreCollection.pantryItems).document(item.id.uuidString), merge: true)
                }
                if let groceries {
                    let encodedItems = try groceries.map { item -> [String: Any] in
                        let fields = try Firestore.Encoder().encode(item)
                        if let raw = rawGroceryItems.first(where: { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == item.id }) {
                            let original = try Firestore.Decoder().decode(GroceryListItem.self, from: raw)
                            return try self.preservingUnchangedWorkspaceFields(data: fields, raw: raw, before: original, after: item, allowsDeletes: false)
                        }
                        return fields
                    }
                    transaction.setData(["items": encodedItems, "lastUpdated": Timestamp(date: Date())], forDocument: groceryRef, merge: true)
                }
                if let diary { transaction.setData(diary.1, forDocument: diary.0, merge: true) }
                var encodedReceipt = try Firestore.Encoder().encode(receipt)
                encodedReceipt["recordedAt"] = Timestamp(date: Date())
                if let deletedFoodBackup {
                    encodedReceipt["beforeFoodBackupSchemaVersion"] = 1
                    encodedReceipt["beforeFoodBackup"] = deletedFoodBackup
                    encodedReceipt["beforeFoodBackupDigest"] = try intakeFoodBackupDigest(deletedFoodBackup)
                }
                transaction.setData(encodedReceipt, forDocument: eventRef)
                if let sourceRef { transaction.setData(["operationID": mutation.id.uuidString], forDocument: sourceRef) }
                if let undoneSourceRef { transaction.deleteDocument(undoneSourceRef) }
                if let intake {
                    transaction.setData(try Firestore.Encoder().encode(intake), forDocument: owner.collection("inventoryIntakeLinks").document(try InventoryIntakeRules.key(foodID: intake.foodID)))
                    if let sourceKey = try intake.source.mutation().uniqueSourceKey {
                        let ref = owner.collection("inventorySourceLocks").document(try PlanFingerprint.make(sourceKey))
                        if intake.currentScale == 0 { transaction.deleteDocument(ref) } else { transaction.setData(["operationID": intake.source.id.uuidString], forDocument: ref) }
                    }
                }
                return true
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        notifySyncState(userID: userID)
    }

    func resolveInventoryMutation(userID: String, mutation: InventoryMutation, cancelPending: Bool) async throws -> InventoryResolution {
        guard currentUserID() == userID, mutation.userID == userID else { throw InventoryError.accountChanged }
        let ref = db.collection(FirestoreCollection.users).document(userID).collection("inventoryEvents").document(mutation.id.uuidString)
        let cancelled = try InventoryReceipt(mutation, status: .cancelled)
        let result = try await db.runTransaction { [self] transaction, errorPointer -> Any? in
            do {
                guard currentUserID() == userID else { throw InventoryError.accountChanged }
                let snapshot = try transaction.getDocument(ref)
                if snapshot.exists {
                    let receipt = try snapshot.data(as: InventoryReceipt.self)
                    try receipt.validate(mutation)
                    return receipt.status.rawValue
                }
                if cancelPending {
                    var encoded = try Firestore.Encoder().encode(cancelled); encoded["recordedAt"] = Timestamp(date: Date())
                    transaction.setData(encoded, forDocument: ref)
                    return "cancelled"
                }
                return "pending"
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        return result as? String == "accepted" ? .accepted : result as? String == "cancelled" ? .cancelled : .pending
    }

    func addPantrySnapshotListener(userID: String, onChange: @escaping (Result<[PantryItem], Error>) -> Void) -> Any {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems)
        return ref.addSnapshotListener { snapshot, error in
            if let error = error {
                onChange(.failure(error))
                return
            }
            guard let documents = snapshot?.documents else { return }
            do { onChange(.success(try documents.map { try $0.data(as: PantryItem.self) })) } catch { onChange(.failure(error)) }
        }
    }
    
    func removePantrySnapshotListener(_ handle: Any) {
        if let registration = handle as? ListenerRegistration {
            registration.remove()
        }
    }
    
    func savePantryItem(userID: String, item: PantryItem) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems).document(item.id.uuidString)
        guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
        try await ref.setData(Firestore.Encoder().encode(item))
    }

    func createPantryReceiptItem(userID: String, receiptID: UUID, item: PantryItem) async throws {
        guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        let itemRef = owner.collection(FirestoreCollection.pantryItems).document(item.id.uuidString)
        let receiptRef = owner.collection("pantryImportReceipts").document("\(receiptID.uuidString)_\(item.id.uuidString)")
        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                guard self.currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
                if try transaction.getDocument(receiptRef).exists { return true }
                guard try !transaction.getDocument(itemRef).exists else { throw GroceryChecklistError.changed }
                transaction.setData(try Firestore.Encoder().encode(item), forDocument: itemRef)
                transaction.setData(["acceptedAt": Timestamp(date: Date())], forDocument: receiptRef)
                return true
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
    }
    
    func deletePantryItem(userID: String, itemID: String) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems).document(itemID)
        try await ref.delete()
    }
    
    // MARK: - Recipes
    
    func fetchRecipes(userID: String) async throws -> [Recipe] {
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        let collection = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes)
        let snapshot = try await collection.getDocuments()
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        return snapshot.documents.compactMap { document in
            guard var recipe = try? document.data(as: Recipe.self) else { return nil }
            if recipe.id == nil { recipe.id = document.documentID }
            return recipe
        }
    }
    
    func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe {
        guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
        let collection = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes)
        var recipeToSave = recipe
        if let id = recipeToSave.id {
            try await collection.document(id).setData(Firestore.Encoder().encode(recipeToSave))
        } else {
            let newDocRef = collection.document()
            recipeToSave.id = newDocRef.documentID
            try await newDocRef.setData(Firestore.Encoder().encode(recipeToSave))
        }
        return recipeToSave
    }

    func saveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID) async throws -> Recipe {
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        try RecipeRevisionRules.validate(expected: expected, updated: updated)
        guard let id = updated.id else { throw RecipeRevisionError.invalid }
        let fingerprint = try RecipeRevisionRules.commandFingerprint(userID: userID, expected: expected, updated: updated, operationID: operationID)
        let reference = db.collection(FirestoreCollection.users).document(userID)
            .collection(FirestoreCollection.recipes).document(id)
        let receipt = db.collection(FirestoreCollection.users).document(userID)
            .collection("recipeRevisionReceipts").document(operationID.uuidString)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.runTransaction({ transaction, pointer -> Any? in
                do {
                    guard self.currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
                    let accepted = try transaction.getDocument(receipt)
                    let document = try transaction.getDocument(reference)
                    let raw = document.data()
                    var latest = try raw.map { try Firestore.Decoder().decode(Recipe.self, from: $0) }
                    if latest?.id == nil { latest?.id = id }
                    if let saved = accepted.data() {
                        guard saved["schemaVersion"] as? Int == 1, saved["userID"] as? String == userID,
                              saved["recipeID"] as? String == id, saved["fingerprint"] as? String == fingerprint else { throw RecipeRevisionError.changed }
                        if saved["status"] as? String == "cancelled" { throw RecipeRevisionError.cancelled }
                        guard saved["status"] as? String == "accepted", document.exists else { throw RecipeRevisionError.changed }
                        // An old accepted command cannot overwrite a later edit or recreate
                        // a deleted recipe. Content versions may repeat; save identities do not.
                        return true
                    }
                    let receiptData: [String: Any] = ["schemaVersion": 1, "userID": userID, "recipeID": id,
                        "fingerprint": fingerprint, "revisionID": updated.revisionID ?? "", "status": "accepted"]
                    switch (expected, latest) {
                    case (nil, nil): break
                    case let (.some(original), .some(current)):
                        guard try RecipeRevisionRules.sameOpeningSnapshot(original, current) else { throw RecipeRevisionError.changed }
                    default: throw RecipeRevisionError.changed
                    }
                    var data = try Firestore.Encoder().encode(updated)
                    // Unchanged ingredient payloads retain raw timestamp precision and future
                    // fields. Editing yield alone must not rewrite the source evidence.
                    for (key, foods, oldFoods) in [
                        ("detailedIngredients", updated.detailedIngredients, latest?.detailedIngredients),
                        ("linkedIngredients", updated.linkedIngredients, latest?.linkedIngredients)
                    ] {
                        guard let foods, let oldFoods, let rawFoods = raw?[key] as? [[String: Any]],
                              rawFoods.count == oldFoods.count else { continue }
                        data[key] = try foods.map { food -> [String: Any] in
                            if let index = oldFoods.firstIndex(where: { FoodEditPrecondition.sameSnapshot($0, food) }) {
                                return rawFoods[index]
                            }
                            return try Firestore.Encoder().encode(food)
                        }
                    }
                    if let latest, let raw {
                        data = try self.preservingUnchangedWorkspaceFields(data: data, raw: raw, before: latest, after: updated, allowsDeletes: false)
                    }
                    try self.writeRecipeVersions(userID: userID, recipeID: id, operationID: operationID,
                        before: raw, after: data, restored: false, transaction: transaction)
                    if document.exists {
                        for key in ["servings", "imageURL", "nutritionBasis", "nutritionOrigin", "unresolvedIngredients",
                                    "detailedIngredients", "linkedIngredients", "nutritionNeedsReview", "cookedWeightGrams", "planningProfile", "importProvenance", "ingredientBasis", "libraryMetadata"] where data[key] == nil {
                            data[key] = FieldValue.delete()
                        }
                        // Top-level map replacement clears intentionally unknown nutrients;
                        // unrelated top-level fields survive this checked edit.
                        let topLevelFields = Dictionary(uniqueKeysWithValues: data.map { (AnyHashable(FieldPath([$0.key])), $0.value) })
                        transaction.updateData(topLevelFields, forDocument: reference)
                    } else {
                        transaction.setData(data, forDocument: reference)
                    }
                    transaction.setData(receiptData, forDocument: receipt)
                    return true
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { _, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == RecipeRevisionError.errorDomain, let known = RecipeRevisionError(rawValue: failure.code) {
                        continuation.resume(throwing: known)
                    } else { continuation.resume(throwing: error) }
                } else { continuation.resume() }
            }
        }
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        // Return the real stored snapshot so the next editor has the exact Firestore
        // timestamp representation. A lost acknowledgement can retry the same revision.
        let saved = try await reference.getDocument(source: .server)
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        guard saved.exists else { throw RecipeRevisionError.changed }
        var canonical = try saved.data(as: Recipe.self)
        if canonical.id == nil { canonical.id = id }
        return canonical
    }

    func resolveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID,
                               cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution {
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        try RecipeRevisionRules.validate(expected: expected, updated: updated)
        guard let id = updated.id else { throw RecipeRevisionError.invalid }
        let fingerprint = try RecipeRevisionRules.commandFingerprint(userID: userID, expected: expected, updated: updated, operationID: operationID)
        let user = db.collection(FirestoreCollection.users).document(userID)
        let reference = user.collection(FirestoreCollection.recipes).document(id)
        let receipt = user.collection("recipeRevisionReceipts").document(operationID.uuidString)
        let result: RecipeRevisionResolution = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, pointer -> Any? in
                do {
                    guard self.currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
                    let saved = try transaction.getDocument(receipt)
                    let current = try transaction.getDocument(reference)
                    if let data = saved.data() {
                        guard data["schemaVersion"] as? Int == 1, data["userID"] as? String == userID,
                              data["recipeID"] as? String == id, data["fingerprint"] as? String == fingerprint else { throw RecipeRevisionError.changed }
                        switch data["status"] as? String {
                        case "cancelled": return RecipeRevisionResolution.cancelled
                        case "accepted":
                            var recipe = try current.data().map { try Firestore.Decoder().decode(Recipe.self, from: $0) }
                            if recipe?.id == nil { recipe?.id = id }
                            return RecipeRevisionResolution.accepted(recipe)
                        default: throw RecipeRevisionError.changed
                        }
                    }
                    guard cancelIfUnaccepted else { return RecipeRevisionResolution.pending }
                    transaction.setData(["schemaVersion": 1, "userID": userID, "recipeID": id,
                        "fingerprint": fingerprint, "revisionID": updated.revisionID ?? "", "status": "cancelled"], forDocument: receipt)
                    return RecipeRevisionResolution.cancelled
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { value, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == RecipeRevisionError.errorDomain, let known = RecipeRevisionError(rawValue: failure.code) {
                        continuation.resume(throwing: known)
                    } else { continuation.resume(throwing: error) }
                } else if let value = value as? RecipeRevisionResolution { continuation.resume(returning: value) } else { continuation.resume(throwing: RecipeRevisionError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        return result
    }
    
    func deleteRecipe(userID: String, recipeID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes).document(recipeID).delete()
    }
    
    // MARK: - Custom Foods
    
    func saveCustomFood(userID: String, foodItem: FoodItem) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection("customFoods").document(foodItem.id)
        // Custom-food edits are complete replacements. Merge would retain cleared optional fields
        // such as saturated fat or barcode associations when Firestore.Encoder omits nil values.
        guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
        try await ref.setData(Firestore.Encoder().encode(foodItem), merge: false)
    }

    func saveCustomFoodReplacingDuplicates(
        userID: String,
        foodItem: FoodItem,
        removingFoodIDs: [String]
    ) async throws {
        let uniqueIDs = Array(Set(removingFoodIDs)).filter { $0 != foodItem.id }
        guard uniqueIDs.count <= 498 else {
            throw NSError(
                domain: "MyFoodsLibrary",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Too many barcode corrections to replace at once."]
            )
        }

        let collection = db.collection(FirestoreCollection.users)
            .document(userID)
            .collection("customFoods")
        let batch = db.batch()
        // The encoded set is a complete replacement so cleared optional nutrients do not survive.
        try batch.setData(from: foodItem, forDocument: collection.document(foodItem.id))
        for foodID in uniqueIDs {
            batch.deleteDocument(collection.document(foodID))
        }
        try await batch.commit()
    }
    
    func deleteCustomFood(userID: String, foodItemID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).collection("customFoods").document(foodItemID).delete()
    }

    func removeCustomFoodBarcode(userID: String, foodItemID: String) async throws {
        let ref = db.collection(FirestoreCollection.users)
            .document(userID)
            .collection("customFoods")
            .document(foodItemID)
        try await ref.updateData(["sourceMetadata.barcode": FieldValue.delete()])
    }

    func mergeCustomFoods(userID: String, keepingFoodID: String, removingFoodIDs: [String]) async throws {
        let uniqueIDs = Array(Set(removingFoodIDs)).filter { $0 != keepingFoodID }
        guard !uniqueIDs.isEmpty else { return }
        guard uniqueIDs.count <= 499 else {
            throw NSError(
                domain: "MyFoodsLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Too many duplicate foods to merge at once."]
            )
        }

        let collection = db.collection(FirestoreCollection.users)
            .document(userID)
            .collection("customFoods")
        let batch = db.batch()
        for foodID in uniqueIDs {
            batch.deleteDocument(collection.document(foodID))
        }
        try await batch.commit()
    }
    
    func fetchCustomFoods(userID: String) async throws -> [FoodItem] {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection("customFoods").order(by: "name").getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FoodItem.self) }
    }
    
    // MARK: - Recent Foods
    
    func saveRecentFood(userID: String, foodItem: FoodItem, source: String, stableID: String) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection("recentFoods").document(stableID)
        var data = try Firestore.Encoder().encode(foodItem)
        data["timestamp"] = Timestamp(date: Date())
        data["source"] = source
        try await ref.setData(data, merge: false)
    }
    
    func fetchRecentFoods(userID: String, limit: Int) async throws -> [FoodItem] {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection("recentFoods")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FoodItem.self) }
    }
}

private enum FirestoreNutritionRepositoryError: LocalizedError {
    case dailyLogDecodeFailed(documentID: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .dailyLogDecodeFailed(let documentID, _):
            return "The daily log for \(documentID) could not be read. Its stored data was left unchanged."
        }
    }
}

private final class DailyLogListenerHandle {
    let listener: ListenerRegistration
    let observer: NSObjectProtocol
    init(listener: ListenerRegistration, observer: NSObjectProtocol) {
        self.listener = listener
        self.observer = observer
    }
    func remove() {
        listener.remove()
        NotificationCenter.default.removeObserver(observer)
    }
    deinit { remove() }
}

// MARK: - Checked planning workspace and library documents
extension FirestoreNutritionRepository {
    private enum WorkspaceAction { case apply, status, cancel }
    private struct WorkspaceReceiptResult<Value: PlanningWorkspaceDocument> {
        let receipt: PlanningWorkspaceReceipt<Value>?
    }

    private func workspaceTransaction<Value>(userID: String, body: @escaping (Transaction) throws -> Value) async throws -> Value {
        guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
        let result: Value = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ [self] transaction, pointer -> Any? in
                do {
                    guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
                    return try body(transaction)
                } catch {
                    if let known = error as? MealPlanEditError {
                        let mapped: MealPlanChangeReceiptError = known == .accountChanged ? .accountChanged : known == .changed ? .changed : .invalid
                        pointer?.pointee = mapped as NSError
                    } else { pointer?.pointee = error as NSError }
                    return nil
                }
            }) { value, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == GroceryChecklistError.errorDomain, let known = GroceryChecklistError(rawValue: failure.code) {
                        continuation.resume(throwing: known)
                    } else if failure.domain == LibraryMutationError.errorDomain, let known = LibraryMutationError(rawValue: failure.code) {
                        continuation.resume(throwing: known)
                    } else if failure.domain == MealPlanChangeReceiptError.errorDomain, let known = MealPlanChangeReceiptError(rawValue: failure.code) {
                        continuation.resume(throwing: known)
                    } else { continuation.resume(throwing: error) }
                } else if let value = value as? Value { continuation.resume(returning: value) } else { continuation.resume(throwing: LibraryMutationError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
        return result
    }

    func fetchSavedMealCompositions(userID: String) async throws -> [SavedMealComposition] {
        try await fetchPlanningDocuments(userID: userID, collection: "savedMealCompositions")
    }
    func fetchSavedMealWeekTemplates(userID: String) async throws -> [SavedMealWeekTemplate] {
        try await fetchPlanningDocuments(userID: userID, collection: "savedMealWeekTemplates")
    }
    private func fetchPlanningDocuments<Value: PlanningWorkspaceDocument>(userID: String, collection: String) async throws -> [Value] {
        guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection(collection).getDocuments()
        let documents: [Value] = try snapshot.documents.map {
            let value = try $0.data(as: Value.self)
            guard value.id == $0.documentID else { throw MealPlanChangeReceiptError.invalid }
            try value.validateStoredSnapshot(); return value
        }
        guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
        return documents
    }
    func saveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal) async throws -> SavedMealComposition {
        let receipt = try await transactPlanningDocument(userID: userID, collection: "savedMealCompositions", proposal: proposal, action: .apply)
        guard let accepted = receipt?.accepted else { throw MealPlanChangeReceiptError.cancelled }
        return accepted
    }
    func saveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal) async throws -> SavedMealWeekTemplate {
        let receipt = try await transactPlanningDocument(userID: userID, collection: "savedMealWeekTemplates", proposal: proposal, action: .apply)
        guard let accepted = receipt?.accepted else { throw MealPlanChangeReceiptError.cancelled }
        return accepted
    }
    func resolveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution {
        try await transactPlanningDocument(userID: userID, collection: "savedMealCompositions", proposal: proposal,
            action: cancelPending ? .cancel : .status)?.resolution ?? .pending
    }
    func resolveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution {
        try await transactPlanningDocument(userID: userID, collection: "savedMealWeekTemplates", proposal: proposal,
            action: cancelPending ? .cancel : .status)?.resolution ?? .pending
    }
    private func transactPlanningDocument<Value: PlanningWorkspaceDocument>(userID: String, collection: String,
                                                                            proposal: PlanningDocumentProposal<Value>, action: WorkspaceAction) async throws -> PlanningWorkspaceReceipt<Value>? {
        guard proposal.userID == userID, currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
        let proposal = try PlanningDocumentRules.canonicalized(proposal)
        if case .apply = action { try proposal.validate() } else { try proposal.validateEnvelope() }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        let document = owner.collection(collection).document(proposal.updated.id)
        let receiptRef = owner.collection(collection + "Receipts").document(proposal.operationID.uuidString)
        let result: WorkspaceReceiptResult<Value> = try await workspaceTransaction(userID: userID) { [self] transaction in
            let receiptDocument = try transaction.getDocument(receiptRef)
            if receiptDocument.exists {
                let receipt = try receiptDocument.data(as: PlanningWorkspaceReceipt<Value>.self)
                try receipt.validate(proposal: proposal); return WorkspaceReceiptResult(receipt: receipt)
            }
            switch action {
            case .status: return WorkspaceReceiptResult(receipt: nil)
            case .cancel:
                let cancelled = try PlanningWorkspaceReceipt(proposal: proposal, resolution: .cancelled)
                transaction.setData(try Firestore.Encoder().encode(cancelled), forDocument: receiptRef)
                return WorkspaceReceiptResult(receipt: cancelled)
            case .apply: break
            }
            let actualDocument = try transaction.getDocument(document)
            let actual = actualDocument.exists ? try PlanningDocumentRules.canonicalized(actualDocument.data(as: Value.self)) : nil
            let updated = try proposal.applying(to: actual)
            let accepted = try PlanningWorkspaceReceipt(proposal: proposal, resolution: .accepted)
            var data = try Firestore.Encoder().encode(updated)
            if let actual, let raw = actualDocument.data() {
                data = try preservingUnchangedWorkspaceFields(data: data, raw: raw, before: actual, after: updated)
            }
            guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
            transaction.setData(data, forDocument: document, merge: true)
            transaction.setData(try Firestore.Encoder().encode(accepted), forDocument: receiptRef)
            return WorkspaceReceiptResult(receipt: accepted)
        }
        return result.receipt
    }
    /// Preserve unknown nested/provider fields when only a name or organization field changed.
    private func preservingUnchangedWorkspaceFields<Value: Encodable>(data: [String: Any], raw: [String: Any], before: Value, after: Value,
                                                                      allowsDeletes: Bool = true) throws -> [String: Any] {
        let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(before)) as? [String: Any] ?? [:]
        let new = try JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? [String: Any] ?? [:]
        func equal(_ a: Any, _ b: Any) -> Bool { NSDictionary(dictionary: ["value": a]).isEqual(to: ["value": b]) }
        func merge(raw: Any?, old: Any?, new: Any, encoded: Any, deletes: Bool) -> Any {
            if let raw, let old, equal(old, new) { return raw }
            if let source = raw as? [String: Any], let prior = old as? [String: Any], let next = new as? [String: Any],
               let fields = encoded as? [String: Any] {
                var result = source
                for key in Set(prior.keys).union(next.keys) {
                    guard let value = next[key], let field = fields[key] else {
                        if deletes { result[key] = FieldValue.delete() } else { result.removeValue(forKey: key) }
                        continue
                    }
                    result[key] = merge(raw: source[key], old: prior[key], new: value, encoded: field, deletes: deletes)
                }
                return result
            }
            if let source = raw as? [Any], let prior = old as? [Any], let next = new as? [Any], let fields = encoded as? [Any], next.count == fields.count {
                return next.enumerated().map { index, value -> Any in
                    let identity = (value as? [String: Any])?["id"]
                    let matching = identity.map { id in prior.indices.filter { candidate in
                        (prior[candidate] as? [String: Any])?["id"].map { equal($0, id) } ?? false
                    } } ?? []
                    let previous = matching.count == 1 ? matching.first : (prior.indices.contains(index) && equal(prior[index], value) ? index : nil)
                    guard let previous, source.indices.contains(previous) else { return fields[index] }
                    return merge(raw: source[previous], old: prior[previous], new: value, encoded: fields[index], deletes: false)
                }
            }
            return encoded
        }
        return merge(raw: raw, old: old, new: new, encoded: data, deletes: allowsDeletes) as? [String: Any] ?? data
    }
    func fetchMealPlanChangeHistory(userID: String, limit: Int) async throws -> [MealPlanChange] {
        guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
        guard (1...500).contains(limit) else { throw MealPlanChangeReceiptError.invalid }
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection("mealPlanChangeReceipts")
            .order(by: "recordedAt", descending: true).limit(to: limit).getDocuments()
        var changes: [MealPlanChange] = []
        for document in snapshot.documents {
            let receipt = try document.data(as: MealPlanChangeReceipt.self)
            guard receipt.userID == userID else { throw MealPlanChangeReceiptError.invalid }
            guard receipt.status == .accepted else { continue }
            if let data = receipt.changeData {
                let change = try JSONDecoder().decode(MealPlanChange.self, from: data)
                try receipt.validate(userID: userID, change: change); changes.append(change)
            }
        }
        guard currentUserID() == userID else { throw MealPlanChangeReceiptError.accountChanged }
        return changes
    }
}

extension FirestoreNutritionRepository {
    func applyRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation) async throws {
        guard try await transactLibraryMutation(userID: userID, operation: .recipes(mutation), action: .apply) == "accepted" else { throw LibraryMutationError.cancelled }
    }
    func applySavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation) async throws {
        guard try await transactLibraryMutation(userID: userID, operation: .foods(mutation), action: .apply) == "accepted" else { throw LibraryMutationError.cancelled }
    }
    func resolveRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation, cancelPending: Bool) async throws -> RecipeLibraryMutationResolution {
        let value = try await transactLibraryMutation(userID: userID, operation: .recipes(mutation), action: cancelPending ? .cancel : .status)
        guard let result = RecipeLibraryMutationResolution(rawValue: value) else { throw LibraryMutationError.invalid }
        return result
    }
    func resolveSavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation, cancelPending: Bool) async throws -> SavedFoodLibraryMutationResolution {
        let value = try await transactLibraryMutation(userID: userID, operation: .foods(mutation), action: cancelPending ? .cancel : .status)
        guard let result = SavedFoodLibraryMutationResolution(rawValue: value) else { throw LibraryMutationError.invalid }
        return result
    }
    private func libraryReceiptCollection(userID: String, operation: LibraryOperation) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection(
            LibraryMutationReceipt.kind(of: operation) == "recipes" ? "recipeLibraryReceipts" : "savedFoodLibraryReceipts")
    }
    private func transactLibraryMutation(userID: String, operation: LibraryOperation, action: WorkspaceAction) async throws -> String {
        guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
        try operation.validate()
        let receipts = libraryReceiptCollection(userID: userID, operation: operation)
        let ref = receipts.document(operation.id.uuidString)
        let accepted = try LibraryMutationReceipt(userID: userID, operation: operation, accepted: true)
        let cancelled = try LibraryMutationReceipt(userID: userID, operation: operation, accepted: false)
        return try await workspaceTransaction(userID: userID) { [self] transaction in
            let existing = try transaction.getDocument(ref)
            if existing.exists {
                let receipt = try existing.data(as: LibraryMutationReceipt.self)
                try receipt.validate(userID: userID, operation: operation)
                if case .apply = action, receipt.status != "accepted" { throw LibraryMutationError.cancelled }
                return receipt.status
            }
            switch action {
            case .status: return "pending"
            case .cancel:
                transaction.setData(try Firestore.Encoder().encode(cancelled), forDocument: ref)
                return "cancelled"
            case .apply: break
            }
            var undoLock: DocumentReference?
            var originalRef: DocumentReference?
            if let originalID = operation.undoingID {
                let original = receipts.document(originalID.uuidString)
                let saved = try transaction.getDocument(original)
                guard saved.exists else { throw LibraryMutationError.changed }
                let receipt = try saved.data(as: LibraryMutationReceipt.self)
                guard receipt.userID == userID, receipt.status == "accepted", let previous = receipt.operation else { throw LibraryMutationError.changed }
                try receipt.validate(userID: userID, operation: previous)
                try LibraryMutationReceipt.validateInverse(operation, original: previous)
                let lock = receipts.document("undo-" + originalID.uuidString)
                guard !(try transaction.getDocument(lock)).exists else { throw LibraryMutationError.changed }
                undoLock = lock; originalRef = original
            }
            switch operation {
            case .recipes(let mutation):
                try applyRecipeMetadata(mutation, userID: userID, transaction: transaction)
            case .foods(let mutation):
                try applySavedFoodMerge(mutation, userID: userID, receiptRef: ref, originalRef: originalRef, transaction: transaction)
            }
            guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
            if let undoLock { transaction.setData(["operationID": operation.id.uuidString, "userID": userID], forDocument: undoLock) }
            transaction.setData(try Firestore.Encoder().encode(accepted), forDocument: ref)
            return "accepted"
        }
    }
    private func applyRecipeMetadata(_ mutation: RecipeLibraryMutation, userID: String, transaction: Transaction) throws {
        let recipes = db.collection(FirestoreCollection.users).document(userID).collection("recipes")
        var current: [Recipe] = []
        for id in mutation.recipeIDs.sorted() {
            let document = try transaction.getDocument(recipes.document(id))
            guard document.exists else { throw LibraryMutationError.changed }
            var recipe = try document.data(as: Recipe.self)
            if recipe.id == nil { recipe.id = id }
            guard recipe.id == id else { throw LibraryMutationError.invalid }
            current.append(recipe)
        }
        _ = try mutation.applying(to: current)
        guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
        for updated in mutation.after {
            guard let id = updated.id else { throw LibraryMutationError.invalid }
            let metadata = try updated.libraryMetadata.map { try Firestore.Encoder().encode($0) } ?? [:]
            var patch: [String: Any] = [:]
            // Write known paths only; future library metadata and every ingredient/source byte survive.
            for key in ["favorite", "tags", "archivedAt", "mergedIntoRecipeID"] {
                if let value = metadata[key] { patch["libraryMetadata." + key] = value } else if key == "favorite" { patch["libraryMetadata.favorite"] = false } else if key == "tags" { patch["libraryMetadata.tags"] = [String]() } else { patch["libraryMetadata." + key] = FieldValue.delete() }
            }
            transaction.updateData(patch, forDocument: recipes.document(id))
        }
    }
    private func applySavedFoodMerge(_ mutation: SavedFoodLibraryMutation, userID: String, receiptRef: DocumentReference,
                                     originalRef: DocumentReference?, transaction: Transaction) throws {
        let foods = db.collection(FirestoreCollection.users).document(userID).collection("customFoods")
        var actual: [FoodItem] = [], raw: [String: [String: Any]] = [:]
        for id in mutation.foodIDs.sorted() {
            let document = try transaction.getDocument(foods.document(id))
            if let data = document.data() {
                let food = try Firestore.Decoder().decode(FoodItem.self, from: data)
                guard food.id == id else { throw LibraryMutationError.invalid }
                actual.append(food); raw[id] = data
            }
        }
        _ = try mutation.applying(to: actual)
        var restoredRaw: [String: [String: Any]] = [:]
        if let originalRef {
            for updated in mutation.upserts where raw[updated.id] == nil {
                let snapshot = try transaction.getDocument(originalRef.collection("beforeFoods").document(updated.id))
                guard let originalRaw = snapshot.data() else { throw LibraryMutationError.changed }
                let original = try Firestore.Decoder().decode(FoodItem.self, from: originalRaw)
                guard try SavedFoodLibraryMutation.snapshotFingerprint(original) == SavedFoodLibraryMutation.snapshotFingerprint(updated) else {
                    throw LibraryMutationError.changed
                }
                restoredRaw[updated.id] = originalRaw
            }
        }
        var writes: [(DocumentReference, [String: Any])] = []
        for updated in mutation.upserts {
            let data: [String: Any]
            if let restored = restoredRaw[updated.id] { data = restored } else if let source = raw[updated.id], let original = actual.first(where: { $0.id == updated.id }) {
                if try SavedFoodLibraryMutation.snapshotFingerprint(original) == SavedFoodLibraryMutation.snapshotFingerprint(updated) {
                    data = source
                } else {
                    data = try preservingUnchangedWorkspaceFields(data: Firestore.Encoder().encode(updated), raw: source, before: original, after: updated)
                }
            } else { data = try Firestore.Encoder().encode(updated) }
            writes.append((foods.document(updated.id), data))
        }
        guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
        // Every read, including restoration backups, precedes every write.
        for id in mutation.foodIDs.sorted() {
            if let backup = raw[id] {
                transaction.setData(backup, forDocument: receiptRef.collection("beforeFoods").document(id))
            }
        }
        for (document, data) in writes { transaction.setData(data, forDocument: document, merge: true) }
        for id in mutation.removedIDs { transaction.deleteDocument(foods.document(id)) }
    }
    func fetchRecipeLibraryHistory(userID: String, limit: Int) async throws -> [RecipeLibraryMutation] {
        try await fetchLibraryHistory(userID: userID, collection: "recipeLibraryReceipts", limit: limit).map {
            guard case .recipes(let value) = $0 else { throw LibraryMutationError.invalid }; return value
        }
    }
    func fetchSavedFoodLibraryHistory(userID: String, limit: Int) async throws -> [SavedFoodLibraryMutation] {
        try await fetchLibraryHistory(userID: userID, collection: "savedFoodLibraryReceipts", limit: limit).map {
            guard case .foods(let value) = $0 else { throw LibraryMutationError.invalid }; return value
        }
    }
    private func fetchLibraryHistory(userID: String, collection: String, limit: Int) async throws -> [LibraryOperation] {
        guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
        guard (1...500).contains(limit) else { throw LibraryMutationError.invalid }
        let base = db.collection(FirestoreCollection.users).document(userID).collection(collection).order(by: "recordedAt", descending: true)
        var cursor: DocumentSnapshot?, operations: [LibraryOperation] = []
        while operations.count < limit {
            guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
            let query = cursor.map { base.start(afterDocument: $0) } ?? base
            let page = try await query.limit(to: min(100, limit - operations.count)).getDocuments()
            for document in page.documents {
                // Single-use inverse locks share the collection but have no recordedAt and are not queried.
                let receipt = try document.data(as: LibraryMutationReceipt.self)
                guard receipt.userID == userID else { throw LibraryMutationError.invalid }
                guard receipt.status == "accepted" else { continue }
                guard let operation = receipt.operation else { throw LibraryMutationError.invalid }
                try receipt.validate(userID: userID, operation: operation); operations.append(operation)
            }
            guard let last = page.documents.last else { break }
            cursor = last
        }
        guard currentUserID() == userID else { throw LibraryMutationError.accountChanged }
        return operations
    }
}

extension FirestoreNutritionRepository {
    /// A small canonical definition joins plan changes and physical cooking atomically.
    /// Existing calendar documents/logs are never rewritten to create this registry.
    private func checkedCookingDefinitions(change: MealPlanChange, userID: String, transaction: Transaction) throws -> [(DocumentReference, [String: Any])] {
        let before = Dictionary(grouping: change.before.flatMap(\.meals).compactMap(\.cookingBatch), by: \.id)
        let after = Dictionary(grouping: change.after.flatMap(\.meals).compactMap(\.cookingBatch), by: \.id)
        let identifiers = Set(before.keys).union(after.keys)
        guard identifiers.count <= 80 else { throw MealPlanChangeReceiptError.invalid }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        var writes: [(DocumentReference, [String: Any])] = []
        for id in identifiers.sorted() {
            guard PlanningDocumentRules.validID(id) else { throw MealPlanChangeReceiptError.invalid }
            let ref = owner.collection("mealCookingDefinitions").document(id)
            let current = try transaction.getDocument(ref)
            if let proposed = after[id]?.first {
                if current.data()?["active"] as? Bool == true, let previous = before[id]?.first {
                    guard let raw = current.data()?["batch"] as? [String: Any] else { throw MealPlanChangeReceiptError.invalid }
                    let live = try Firestore.Decoder().decode(MealCookingBatch.self, from: raw)
                    guard MealPlanCookingRules.sameCookingDefinition(live, previous) else { throw MealCookingError.changed }
                }
                let lockRef = owner.collection("inventorySourceLocks").document(try PlanFingerprint.make("cook-" + id))
                let lock = try transaction.getDocument(lockRef)
                if lock.exists {
                    guard let operation = lock.data()?["operationID"] as? String else { throw MealCookingError.changed }
                    let recorded = try transaction.getDocument(owner.collection("inventoryEvents").document(operation))
                    let receipt = try recorded.data(as: InventoryReceipt.self)
                    guard receipt.userID == userID, receipt.status == .accepted,
                          let actual = try receipt.mutation().after.compactMap(\.cookedBatch).first(where: { $0.id == id }),
                          MealPlanCookingRules.sameCookingDefinition(actual, proposed) else { throw MealCookingError.alreadyCooked }
                }
                writes.append((ref, ["schemaVersion": 1, "active": true, "batch": try Firestore.Encoder().encode(proposed)]))
            } else if before[id] != nil {
                // Physical cooking may deliberately proceed from a frozen review after plan removal.
                writes.append((ref, ["schemaVersion": 1, "active": false]))
            }
        }
        return writes
    }
    private func checkReviewedCookingSource(_ mutation: InventoryMutation, userID: String, transaction: Transaction) throws {
        let batches = mutation.after.compactMap(\.cookedBatch).filter { batch in
            !mutation.before.contains { $0.cookedBatch?.id == batch.id }
        }
        guard batches.count == 1, let reviewed = batches.first,
              mutation.uniqueSourceKey == "cook-" + reviewed.id, PlanningDocumentRules.validID(reviewed.id) else { throw InventoryError.invalid }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        let definition = try transaction.getDocument(owner.collection("mealCookingDefinitions").document(reviewed.id))
        if definition.data()?["active"] as? Bool == true {
            guard let raw = definition.data()?["batch"] as? [String: Any] else { throw InventoryError.changed }
            let actual = try Firestore.Decoder().decode(MealCookingBatch.self, from: raw)
            guard MealPlanCookingRules.sameCookingDefinition(reviewed, actual) else { throw MealCookingError.changed }
        }
        // Also cover old calendar data and an independent explicit cook after a plan was removed.
        let keys = Set(reviewed.allocations.map { MealPlanEditingRules.dayID($0.date) } + [MealPlanEditingRules.dayID(reviewed.cookingDate)])
        guard keys.count <= 9 else { throw InventoryError.invalid }
        for key in keys.sorted() {
            let document = try transaction.getDocument(owner.collection(FirestoreCollection.mealPlans).document(key))
            if document.exists {
                let actual = try document.data(as: MealPlanPayload.self)
                for batch in actual.meals.compactMap(\.cookingBatch) where batch.id == reviewed.id {
                    guard MealPlanCookingRules.sameCookingDefinition(reviewed, batch) else { throw MealCookingError.changed }
                }
            }
        }
    }
}

extension FirestoreNutritionRepository {
    private func transactGroceryMutation(userID: String, mutation: GroceryListMutation, action: WorkspaceAction) async throws -> GroceryMutationResolution {
        guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
        _ = try mutation.applying(to: mutation.before, checkingConflicts: false)
        let user = db.collection(FirestoreCollection.users).document(userID)
        let listRef = user.collection(FirestoreCollection.userSettings).document(FirestoreDocument.groceryList)
        let receiptRef = user.collection("groceryMutationReceipts").document(mutation.id.uuidString)
        let accepted = try GroceryMutationReceipt(userID: userID, mutation: mutation, status: .accepted)
        let cancelled = try GroceryMutationReceipt(userID: userID, mutation: mutation, status: .cancelled)
        return try await workspaceTransaction(userID: userID) { [self] transaction in
            let existing = try transaction.getDocument(receiptRef)
            if existing.exists {
                if existing.data()?["schemaVersion"] as? Int == 2 {
                    let receipt = try existing.data(as: GroceryMutationReceipt.self)
                    try receipt.validate(userID: userID, mutation: mutation)
                    if case .apply = action, receipt.status == .cancelled { throw GroceryChecklistError.cancelled }
                    return receipt.status
                }
                // Old ID-only receipts retain their deployed read-only retry behavior.
                // They cannot supply a fabricated historical payload or be undone as a new command.
                return .accepted
            }
            switch action {
            case .status: return .pending
            case .cancel:
                transaction.setData(try Firestore.Encoder().encode(cancelled), forDocument: receiptRef)
                return .cancelled
            case .apply: break
            }
            var originalReceipt: DocumentReference?, undoLock: DocumentReference?
            if let originalID = mutation.undoingID {
                let originalRef = user.collection("groceryMutationReceipts").document(originalID.uuidString)
                let original = try transaction.getDocument(originalRef)
                guard original.data()?["schemaVersion"] as? Int == 2 else { throw GroceryChecklistError.changed }
                let receipt = try original.data(as: GroceryMutationReceipt.self)
                let command = try receipt.mutation()
                try receipt.validate(userID: userID, mutation: command)
                try mutation.validateInverse(of: command)
                let lock = user.collection("groceryUndoLocks").document(originalID.uuidString)
                guard !(try transaction.getDocument(lock)).exists else { throw GroceryChecklistError.changed }
                originalReceipt = originalRef; undoLock = lock
            }
            let snapshot = try transaction.getDocument(listRef)
            let payload = snapshot.data()?["items"]
            guard payload == nil || payload is [[String: Any]] else { throw GroceryChecklistError.invalid }
            let originals = payload as? [[String: Any]] ?? []
            let current = try originals.map { try Firestore.Decoder().decode(GroceryListItem.self, from: $0) }
            let merged = try mutation.applying(to: current)
            var restoration: [UUID: [String: Any]] = [:]
            if let originalReceipt {
                for item in mutation.upserts where !current.contains(where: { $0.id == item.id }) {
                    let backup = try transaction.getDocument(originalReceipt.collection("beforeRows").document(item.id.uuidString))
                    guard var raw = backup.data() else { throw GroceryChecklistError.changed }
                    var saved = try Firestore.Decoder().decode(GroceryListItem.self, from: raw)
                    saved.revisionID = item.revisionID
                    guard saved == item else { throw GroceryChecklistError.changed }
                    raw["revisionID"] = item.revisionID
                    restoration[item.id] = raw
                }
            }
            let encoded = try merged.map { item -> [String: Any] in
                let previous = originals.first { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == item.id }
                if !mutation.itemIDs.contains(item.id), let previous { return previous }
                if let restored = restoration[item.id] { return restored }
                var data = try Firestore.Encoder().encode(item)
                if let previous, let original = current.first(where: { $0.id == item.id }) {
                    data = try preservingUnchangedWorkspaceFields(data: data, raw: previous, before: original, after: item, allowsDeletes: false)
                }
                return data
            }
            guard currentUserID() == userID else { throw GroceryChecklistError.accountChanged }
            for original in originals {
                guard let id = (original["id"] as? String).flatMap(UUID.init(uuidString:)), mutation.itemIDs.contains(id) else { continue }
                transaction.setData(original, forDocument: receiptRef.collection("beforeRows").document(id.uuidString))
            }
            transaction.setData(["items": encoded, "lastUpdated": Timestamp(date: Date())], forDocument: listRef, merge: true)
            if let undoLock { transaction.setData(["operationID": mutation.id.uuidString, "userID": userID], forDocument: undoLock) }
            transaction.setData(try Firestore.Encoder().encode(accepted), forDocument: receiptRef)
            return .accepted
        }
    }
}

// MARK: - Immutable recipe versions and checked restoration
extension FirestoreNutritionRepository {
    private func recipeVersions(userID: String, recipeID: String) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection("recipeVersionHistory").document(recipeID).collection("versions")
    }
    /// Firestore commits timestamps at microsecond precision. Snapshot fingerprints
    /// describe the exact representation that the raw payload document will retain.
    private func recipeVersionServerRaw(_ value: Any) -> Any {
        if let timestamp = value as? Timestamp { return Timestamp(seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds / 1_000 * 1_000) }
        if let date = value as? Date { return recipeVersionServerRaw(Timestamp(date: date)) }
        if let values = value as? [String: Any] { return values.mapValues(recipeVersionServerRaw) }
        if let values = value as? [Any] { return values.map(recipeVersionServerRaw) }
        return value
    }
    private func writeRecipeVersions(userID: String, recipeID: String, operationID: UUID, before: [String: Any]?,
                                     after: [String: Any], restored: Bool, transaction: Transaction) throws {
        let collection = recipeVersions(userID: userID, recipeID: recipeID)
        let recordedAt = Date()
        let versionPrefix = (restored ? "restore-" : "edit-") + operationID.uuidString
        var snapshots: [(String, RecipeVersionRecord.Phase, [String: Any])] = []
        if let before { snapshots.append(("-before", .before, before)) }
        snapshots.append(("-after", restored ? .restored : .saved, after))
        for (suffix, phase, original) in snapshots {
            let raw = recipeVersionServerRaw(original) as? [String: Any] ?? original
            var recipe = try Firestore.Decoder().decode(Recipe.self, from: raw)
            if recipe.id == nil { recipe.id = recipeID }
            let version = try RecipeVersionRecord(id: versionPrefix + suffix, recipeID: recipeID,
                operationID: operationID, phase: phase, recordedAt: recordedAt, snapshot: recipe)
            let reference = collection.document(version.id)
            transaction.setData(["schemaVersion": 1, "userID": userID, "recipeID": recipeID,
                "operationID": operationID.uuidString, "phase": phase.rawValue, "recordedAt": Timestamp(date: recordedAt),
                "snapshotFingerprint": version.snapshotFingerprint], forDocument: reference)
            // Keep the original document body separately: no doubled recipe payload
            // or wrapper can push a valid recipe over Firestore's document limit.
            transaction.setData(raw, forDocument: reference.collection("payload").document("recipe"))
        }
        transaction.setData(["schemaVersion": 1, "recipeID": recipeID],
            forDocument: collection.parent!, merge: true)
    }
    private func readRecipeVersion(header: DocumentSnapshot, raw: [String: Any], userID: String, recipeID: String) throws -> RecipeVersionRecord {
        guard let data = header.data(), data["schemaVersion"] as? Int == 1, data["userID"] as? String == userID,
              data["recipeID"] as? String == recipeID,
              let operation = (data["operationID"] as? String).flatMap(UUID.init(uuidString:)),
              let phase = (data["phase"] as? String).flatMap(RecipeVersionRecord.Phase.init(rawValue:)),
              let date = data["recordedAt"] as? Timestamp else { throw RecipeRevisionError.invalid }
        var recipe = try Firestore.Decoder().decode(Recipe.self, from: raw)
        if recipe.id == nil { recipe.id = recipeID }
        let version = try RecipeVersionRecord(id: header.documentID, recipeID: recipeID, operationID: operation,
            phase: phase, recordedAt: date.dateValue(), snapshot: recipe)
        guard version.snapshotFingerprint == data["snapshotFingerprint"] as? String else { throw RecipeRevisionError.changed }
        return version
    }
    func fetchRecipeVersionHistory(userID: String, recipeID: String, limit: Int) async throws -> [RecipeVersionRecord] {
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        guard PlanningDocumentRules.validID(recipeID), (1...200).contains(limit) else { throw RecipeRevisionError.invalid }
        let query = try await recipeVersions(userID: userID, recipeID: recipeID).order(by: "recordedAt", descending: true).limit(to: limit).getDocuments(source: .server)
        var versions: [RecipeVersionRecord] = []
        for header in query.documents {
            guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
            let payload = try await header.reference.collection("payload").document("recipe").getDocument(source: .server)
            guard let raw = payload.data() else { throw RecipeRevisionError.invalid }
            versions.append(try readRecipeVersion(header: header, raw: raw, userID: userID, recipeID: recipeID))
        }
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }; return versions
    }
    func restoreRecipeVersion(userID: String, proposal: RecipeVersionRestoreProposal) async throws -> Recipe {
        let result = try await transactRecipeRestore(userID: userID, proposal: proposal, action: .apply)
        guard case .accepted = result else { throw RecipeRevisionError.cancelled }
        let document = try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes).document(proposal.version.recipeID).getDocument(source: .server)
        guard currentUserID() == userID else { throw RecipeRevisionError.accountChanged }
        guard document.exists else { throw RecipeRevisionError.changed }
        var recipe = try document.data(as: Recipe.self); if recipe.id == nil { recipe.id = proposal.version.recipeID }; return recipe
    }
    func resolveRecipeVersionRestore(userID: String, proposal: RecipeVersionRestoreProposal, cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution {
        try await transactRecipeRestore(userID: userID, proposal: proposal, action: cancelIfUnaccepted ? .cancel : .status)
    }
    private func transactRecipeRestore(userID: String, proposal: RecipeVersionRestoreProposal, action: WorkspaceAction) async throws -> RecipeRevisionResolution {
        guard currentUserID() == userID, proposal.userID == userID else { throw RecipeRevisionError.accountChanged }
        try proposal.validate(); let fingerprint = try proposal.fingerprint
        let user = db.collection(FirestoreCollection.users).document(userID)
        let recipeID = proposal.version.recipeID
        let reference = user.collection(FirestoreCollection.recipes).document(recipeID)
        let receipt = user.collection("recipeVersionRestoreReceipts").document(proposal.id.uuidString)
        do {
            return try await workspaceTransaction(userID: userID) { [self] transaction in
                let existing = try transaction.getDocument(receipt)
                if let data = existing.data() {
                    guard data["schemaVersion"] as? Int == 1, data["userID"] as? String == userID,
                          data["recipeID"] as? String == recipeID, data["fingerprint"] as? String == fingerprint else { throw RecipeRevisionError.changed }
                    if data["status"] as? String == "cancelled" {
                        if case .apply = action { throw RecipeRevisionError.cancelled }; return .cancelled
                    }
                    guard data["status"] as? String == "accepted" else { throw RecipeRevisionError.changed }
                    let current = try transaction.getDocument(reference)
                    var recipe = try current.data().map { try Firestore.Decoder().decode(Recipe.self, from: $0) }
                    if recipe?.id == nil { recipe?.id = recipeID }; return .accepted(recipe)
                }
                let receiptData: [String: Any] = ["schemaVersion": 1, "userID": userID, "recipeID": recipeID,
                    "fingerprint": fingerprint, "status": "cancelled", "versionID": proposal.version.id, "recordedAt": Timestamp(date: Date())]
                switch action {
                case .status: return .pending
                case .cancel: transaction.setData(receiptData, forDocument: receipt); return .cancelled
                case .apply: break
                }
                let versionRef = recipeVersions(userID: userID, recipeID: recipeID).document(proposal.version.id)
                let header = try transaction.getDocument(versionRef)
                let historical = try transaction.getDocument(versionRef.collection("payload").document("recipe"))
                let current = try transaction.getDocument(reference)
                guard let selectedRaw = historical.data(), let currentRaw = current.data() else { throw RecipeRevisionError.changed }
                let version = try readRecipeVersion(header: header, raw: selectedRaw, userID: userID, recipeID: recipeID)
                guard try PlanFingerprint.make(version) == PlanFingerprint.make(proposal.version) else { throw RecipeRevisionError.changed }
                var actual = try current.data(as: Recipe.self); if actual.id == nil { actual.id = recipeID }
                guard try RecipeRevisionRules.sameOpeningSnapshot(actual, proposal.expected) else { throw RecipeRevisionError.changed }
                let updated = try proposal.updated
                var raw = try preservingUnchangedWorkspaceFields(data: Firestore.Encoder().encode(updated), raw: selectedRaw,
                    before: version.snapshot, after: updated, allowsDeletes: false)
                raw = try preservingCurrentRecipeUnknownFields(currentRaw: currentRaw, current: actual, restoredRaw: raw, restored: updated)
                try writeRecipeVersions(userID: userID, recipeID: recipeID, operationID: proposal.id, before: currentRaw, after: raw, restored: true, transaction: transaction)
                var accepted = receiptData; accepted["status"] = "accepted"
                transaction.setData(raw, forDocument: reference)
                transaction.setData(accepted, forDocument: receipt)
                return .accepted(updated)
            }
        } catch {
            let failure = error as NSError
            if failure.domain == RecipeRevisionError.errorDomain, let known = RecipeRevisionError(rawValue: failure.code) { throw known }
            throw error
        }
    }
    /// Restore known content and historical source bytes; merge currently unknown
    /// fields by stable nested identity so a newer client extension is never erased.
    private func preservingCurrentRecipeUnknownFields(currentRaw: [String: Any], current: Recipe, restoredRaw: [String: Any], restored: Recipe) throws -> [String: Any] {
        let previous = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current))
        let next = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored))
        func merge(current: Any, known: Any?, target: Any, next: Any?) -> Any {
            if let values = current as? [String: Any], let target = target as? [String: Any] {
                let known = known as? [String: Any] ?? [:], next = next as? [String: Any] ?? [:]
                let knownKeys = Set(known.keys).union(next.keys)
                var result = target
                for (key, value) in values {
                    if !knownKeys.contains(key) { result[key] = value } else if let proposed = target[key] {
                        result[key] = merge(current: value, known: known[key], target: proposed, next: next[key])
                    }
                }
                return result
            }
            if let values = current as? [[String: Any]], let target = target as? [[String: Any]] {
                let known = known as? [[String: Any]] ?? [], next = next as? [[String: Any]] ?? []
                return target.enumerated().map { index, row in
                    guard let id = row["id"] as? String, let original = values.first(where: { $0["id"] as? String == id }) else { return row }
                    return merge(current: original, known: known.first(where: { $0["id"] as? String == id }), target: row,
                        next: next.indices.contains(index) ? next[index] : nil) as? [String: Any] ?? row
                }
            }
            return target
        }
        return merge(current: currentRaw, known: previous, target: restoredRaw, next: next) as? [String: Any] ?? restoredRaw
    }
}

// MARK: - Checked intake-linked stock amendments
private struct LegacyInventoryIntakeSource {
    var link: InventoryIntakeLink
    var last: InventoryReceipt
}
private struct InventoryIntakeTransactionEffect {
    var replay = false
    var links: [InventoryIntakeLink] = []
    var stock: [UUID: PantryItem] = [:]
    var events: [InventoryReceipt] = []
    var sourceLocks: [String: String?] = [:]
    var receipt: InventoryIntakeRevisionReceipt?
    var deletedFoodBackups: [UUID: [String: Any]] = [:]
    var restoredFoodBackups: [String: [String: Any]] = [:]
}

extension FirestoreNutritionRepository {
    func fetchInventoryIntakeLink(userID: String, foodID: String) async throws -> InventoryIntakeLink? {
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        let key = try InventoryIntakeRules.key(foodID: foodID)
        let document = try await db.collection(FirestoreCollection.users).document(userID).collection("inventoryIntakeLinks").document(key).getDocument(source: .server)
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        if document.exists {
            let link = try document.data(as: InventoryIntakeLink.self); try link.validate()
            guard link.userID == userID, link.foodID == foodID else { throw InventoryIntakeError.invalid }
            return link
        }
        return try await legacyInventoryIntakeSources(userID: userID, foodIDs: [foodID])[foodID]?.link
    }

    /// Only explicit old stock/planned occurrence IDs trigger the compatibility scan.
    /// Every match still comes from an actual accepted ledger payload, never its name.
    private func legacyInventoryIntakeSources(userID: String, foodIDs: Set<String>) async throws -> [String: LegacyInventoryIntakeSource] {
        let candidateIDs = foodIDs.filter { $0.hasPrefix("stock-") || $0.hasPrefix("planned-") }
        guard !candidateIDs.isEmpty else { return [:] }
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        var missing = Set<String>()
        for foodID in candidateIDs {
            let snapshot = try await owner.collection("inventoryIntakeLinks").document(InventoryIntakeRules.key(foodID: foodID)).getDocument(source: .server)
            if !snapshot.exists { missing.insert(foodID) }
        }
        guard !missing.isEmpty else { return [:] }
        let snapshots = try await owner.collection("inventoryEvents").getDocuments(source: .server)
        let events = try snapshots.documents.compactMap { document -> (InventoryReceipt, InventoryMutation, Date)? in
            let receipt = try document.data(as: InventoryReceipt.self)
            guard receipt.userID == userID, receipt.status == .accepted else { return nil }
            let operation = try receipt.mutation()
            guard let patch = operation.diary, missing.contains(patch.foodID) else { return nil }
            return (receipt, operation, (document.data()["recordedAt"] as? Timestamp)?.dateValue() ?? operation.createdAt)
        }.sorted { $0.2 == $1.2 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.2 < $1.2 }
        var result: [String: LegacyInventoryIntakeSource] = [:]
        for foodID in missing {
            guard let originalIndex = events.lastIndex(where: { $0.1.reason == .consume && $0.1.diary?.desired?.id == foodID && $0.1.diary?.expected == nil }) else { continue }
            let original = events[originalIndex]
            var link = try InventoryIntakeLink(source: original.0)
            let candidates = events[originalIndex...].filter { $0.1.diary?.foodID == foodID && Set($0.1.before.map(\.id)) == Set(link.stockIDs) }
            let last = candidates.last ?? original
            link.currentScale = try InventoryIntakeRules.scale(food: last.1.diary?.desired, link: link)
            link.revisionID = last.0.id.uuidString
            result[foodID] = LegacyInventoryIntakeSource(link: link, last: last.0)
        }
        guard currentUserID() == userID else { throw InventoryError.accountChanged }
        return result
    }

    private func commitDiaryAndLinkedInventory(userID: String, mutation: DailyLogMutation, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                let intended = try InventoryIntakeRules.changes(before: mutation.before, after: mutation.after)
                let legacy = try await legacyInventoryIntakeSources(userID: userID, foodIDs: Set(intended.map(\.id)))
                guard currentUserID() == userID, let logID = mutation.after.id else { throw InventoryError.accountChanged }
                let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(logID)
                db.runTransaction({ [self] transaction, errorPointer -> Any? in
                    do {
                        guard currentUserID() == userID else { throw InventoryError.accountChanged }
                        let snapshot = try transaction.getDocument(ref)
                        let raw = snapshot.data() ?? [:]
                        let current = try snapshot.data().map { try decodeDailyLog(from: $0, documentID: logID) }
                            ?? DailyLog(id: logID, date: mutation.after.date, meals: [])
                        if try acceptedInventoryIntakeRevision(userID: userID, mutation: mutation, transaction: transaction) { return true }
                        let merged = try mutation.applying(to: current, checkingFoodEdits: true)
                        let effect = try checkedInventoryIntakeEffect(userID: userID, mutation: mutation, before: current, after: merged, rawBefore: raw, legacy: legacy, transaction: transaction)
                        if effect.replay { return true }
                        var data = try Firestore.Encoder().encode(merged)
                        data = try preservingUnchangedWorkspaceFields(data: data, raw: raw, before: current, after: merged)
                        data = try restoringDeletedIntakeFoods(data: data, backups: effect.restoredFoodBackups, desired: merged)
                        for key in ["totalCaloriesOverride", "waterTracker", "exercises", "journalEntries", "nutritionDayStatus", "nutritionDayReview"] where data[key] == nil { data[key] = NSNull() }
                        guard currentUserID() == userID else { throw InventoryError.accountChanged }
                        // All receipt, link, source-lock and lot reads precede every write.
                        try writeInventoryIntakeEffect(effect, userID: userID, transaction: transaction)
                        transaction.setData(data, forDocument: ref, merge: true)
                        return true
                    } catch { errorPointer?.pointee = error as NSError; return nil }
                }) { _, error in completion(error) }
            } catch { completion(error) }
        }
    }

    private func acceptedInventoryIntakeRevision(userID: String, mutation: DailyLogMutation, transaction: Transaction) throws -> Bool {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection("inventoryIntakeRevisions").document(try PlanFingerprint.make(mutation.id))
        let existing = try transaction.getDocument(ref)
        guard existing.exists else { return false }
        let receipt = try existing.data(as: InventoryIntakeRevisionReceipt.self)
        guard receipt.schemaVersion == 1, receipt.id == mutation.id, receipt.userID == userID,
              receipt.intentFingerprint == (try InventoryIntakeRules.intentFingerprint(mutation)) else { throw InventoryIntakeError.changed }
        return true
    }

    private func checkedInventoryIntakeEffect(userID: String, mutation: DailyLogMutation, before: DailyLog, after: DailyLog, rawBefore: [String: Any],
                                              legacy: [String: LegacyInventoryIntakeSource], transaction: Transaction) throws -> InventoryIntakeTransactionEffect {
        let owner = db.collection(FirestoreCollection.users).document(userID)
        let fingerprint = try InventoryIntakeRules.intentFingerprint(mutation)
        let changes = try InventoryIntakeRules.changes(before: before, after: after)
        guard changes.count <= 100 else { throw InventoryIntakeError.invalid }
        var effect = InventoryIntakeTransactionEffect()
        var readStock: [UUID: PantryItem] = [:]
        for change in changes {
            let linkRef = owner.collection("inventoryIntakeLinks").document(try InventoryIntakeRules.key(foodID: change.id))
            let indexed = try transaction.getDocument(linkRef)
            let link: InventoryIntakeLink
            if indexed.exists { link = try indexed.data(as: InventoryIntakeLink.self) } else if let old = legacy[change.id] {
                for receipt in [old.link.source, old.last] {
                    let current = try transaction.getDocument(owner.collection("inventoryEvents").document(receipt.id.uuidString))
                    guard current.exists else { throw InventoryIntakeError.changed }
                    let actual = try current.data(as: InventoryReceipt.self)
                    guard actual.status == .accepted, actual.userID == userID, actual.fingerprint == receipt.fingerprint else { throw InventoryIntakeError.changed }
                }
                link = old.link
            } else { continue }
            try link.validate()
            guard link.userID == userID, link.foodID == change.id else { throw InventoryIntakeError.invalid }
            for id in link.stockIDs where readStock[id] == nil {
                let lot = try transaction.getDocument(owner.collection(FirestoreCollection.pantryItems).document(id.uuidString))
                guard lot.exists else { throw InventoryIntakeError.changed }
                readStock[id] = try lot.data(as: PantryItem.self)
            }
            let source = try link.source.mutation()
            if let sourceKey = source.uniqueSourceKey {
                let lockRef = owner.collection("inventorySourceLocks").document(try PlanFingerprint.make(sourceKey))
                let lock = try transaction.getDocument(lockRef)
                guard !lock.exists || lock.data()?["operationID"] as? String == source.id.uuidString else { throw InventoryIntakeError.changed }
            }
            guard let day = DiaryDayContext(userID: userID, date: mutation.after.date, dayKey: mutation.after.id) else { throw InventoryIntakeError.invalid }
            let name = after.meals.first { $0.foodItems.contains { $0.id == change.id } }?.name
                ?? before.meals.first { $0.foodItems.contains { $0.id == change.id } }?.name ?? "Lunch"
            let projection = try InventoryIntakeRules.projecting(link: link, before: change.before, after: change.after,
                current: Array(readStock.values), day: day, mealName: name, operationID: mutation.id)
            let event = try InventoryReceipt(projection.event, status: .accepted)
            let eventRef = owner.collection("inventoryEvents").document(event.id.uuidString)
            guard try !transaction.getDocument(eventRef).exists else { throw InventoryIntakeError.changed }
            for lot in projection.after { readStock[lot.id] = lot; effect.stock[lot.id] = lot }
            effect.links.append(projection.link); effect.events.append(event)
            if change.after == nil, let food = change.before {
                effect.deletedFoodBackups[event.id] = try exactRawIntakeFood(rawBefore, food: food)
            } else if change.before == nil, let food = change.after {
                let checked = (mutation.foodEditPrecondition.map { [$0] } ?? []) + (mutation.foodEditPreconditions ?? [])
                if checked.contains(where: { edit in
                    guard edit.foodID == change.id, edit.expected == nil, let reviewed = edit.desired else { return false }
                    return FoodEditPrecondition.sameSnapshot(reviewed, food)
                }),
                   let backup = try deletedIntakeFoodBackup(userID: userID, link: link, desired: food, transaction: transaction) {
                    effect.restoredFoodBackups[food.id] = backup
                }
            }
            if let sourceKey = source.uniqueSourceKey { effect.sourceLocks[sourceKey] = projection.link.currentScale == 0 ? .some(nil) : .some(source.id.uuidString) }
        }
        if !effect.links.isEmpty {
            effect.receipt = InventoryIntakeRevisionReceipt(id: mutation.id, userID: userID, intentFingerprint: fingerprint, inventoryEventIDs: effect.events.map(\.id))
        }
        return effect
    }

    private func writeInventoryIntakeEffect(_ effect: InventoryIntakeTransactionEffect, userID: String, transaction: Transaction) throws {
        let owner = db.collection(FirestoreCollection.users).document(userID)
        for lot in effect.stock.values {
            var patch: [String: Any] = ["quantity": lot.quantity, "revisionID": lot.revisionID ?? ""]
            patch["recordedPlannedPortions"] = lot.recordedPlannedPortions ?? NSNull()
            transaction.setData(patch, forDocument: owner.collection(FirestoreCollection.pantryItems).document(lot.id.uuidString), merge: true)
        }
        for link in effect.links {
            transaction.setData(try Firestore.Encoder().encode(link), forDocument: owner.collection("inventoryIntakeLinks").document(try InventoryIntakeRules.key(foodID: link.foodID)))
        }
        for event in effect.events {
            var fields = try Firestore.Encoder().encode(event); fields["recordedAt"] = Timestamp(date: Date())
            if let backup = effect.deletedFoodBackups[event.id] {
                fields["beforeFoodBackupSchemaVersion"] = 1
                fields["beforeFoodBackup"] = backup
                fields["beforeFoodBackupDigest"] = try intakeFoodBackupDigest(backup)
            }
            transaction.setData(fields, forDocument: owner.collection("inventoryEvents").document(event.id.uuidString))
        }
        for (key, operationID) in effect.sourceLocks {
            let ref = owner.collection("inventorySourceLocks").document(try PlanFingerprint.make(key))
            if let operationID { transaction.setData(["operationID": operationID], forDocument: ref) } else { transaction.deleteDocument(ref) }
        }
        if let receipt = effect.receipt {
            var fields = try Firestore.Encoder().encode(receipt); fields["recordedAt"] = Timestamp(date: Date())
            transaction.setData(fields, forDocument: owner.collection("inventoryIntakeRevisions").document(try PlanFingerprint.make(receipt.id)))
        }
    }
}

extension FirestoreNutritionRepository {
    private func exactRawIntakeFood(_ raw: [String: Any], food: FoodItem) throws -> [String: Any] {
        let matches = try rawTransferMeals(raw).flatMap { meal -> [[String: Any]] in
            guard let foods = meal["foodItems"] as? [[String: Any]] else { throw InventoryIntakeError.changed }
            return foods.filter { $0["id"] as? String == food.id }
        }
        guard matches.count == 1, let value = matches.first,
              FoodEditPrecondition.sameSnapshot(try Firestore.Decoder().decode(FoodItem.self, from: value), food) else { throw InventoryIntakeError.changed }
        _ = try intakeFoodBackupDigest(value)
        return value
    }

    private func deletedIntakeFoodBackup(userID: String, link: InventoryIntakeLink, desired: FoodItem, transaction: Transaction) throws -> [String: Any]? {
        guard link.currentScale == 0 else { throw InventoryIntakeError.changed }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        // Diary corrections derive their permanent event ID from the exact frozen
        // revision. Stock-history deletion receipts already use their own UUID.
        let derived = InventoryIntakeRules.eventID(userID: userID, operationID: link.revisionID, foodID: link.foodID)
        var IDs = [derived]
        if let direct = UUID(uuidString: link.revisionID), direct != derived { IDs.append(direct) }
        for id in IDs {
            let document = try transaction.getDocument(owner.collection("inventoryEvents").document(id.uuidString))
            guard document.exists, let fields = document.data() else { continue }
            guard fields["beforeFoodBackupSchemaVersion"] != nil || fields["beforeFoodBackup"] != nil || fields["beforeFoodBackupDigest"] != nil else { continue }
            guard fields["beforeFoodBackupSchemaVersion"] as? Int == 1, let raw = fields["beforeFoodBackup"] as? [String: Any] else { throw InventoryIntakeError.changed }
            let receipt = try document.data(as: InventoryReceipt.self), deletion = try receipt.mutation()
            guard receipt.status == .accepted, receipt.userID == userID, deletion.id == id,
                  deletion.diary?.foodID == link.foodID, deletion.diary?.desired == nil,
                  let deletedFood = deletion.diary?.expected, try sameIntakeStockSnapshot(deletedFood, desired),
                  Set(deletion.before.map(\.id)) == Set(link.stockIDs),
                  fields["beforeFoodBackupDigest"] as? String == (try intakeFoodBackupDigest(raw)),
                  try sameIntakeStockSnapshot(Firestore.Decoder().decode(FoodItem.self, from: raw), desired) else { throw InventoryIntakeError.changed }
            return raw
        }
        // Older deletion receipts have no raw backup. Their existing typed Undo
        // remains available, without inventing provider extension fields.
        return nil
    }

    private func restoringDeletedIntakeFoods(data: [String: Any], backups: [String: [String: Any]], desired: DailyLog) throws -> [String: Any] {
        guard !backups.isEmpty else { return data }
        var result = data
        guard var meals = data["meals"] as? [[String: Any]] else { throw InventoryIntakeError.changed }
        for index in meals.indices {
            guard var foods = meals[index]["foodItems"] as? [[String: Any]] else { throw InventoryIntakeError.changed }
            for position in foods.indices {
                guard let id = foods[position]["id"] as? String, let raw = backups[id],
                      let food = desired.meals.flatMap(\.foodItems).first(where: { $0.id == id }) else { continue }
                let before = try Firestore.Decoder().decode(FoodItem.self, from: raw)
                guard try sameIntakeStockSnapshot(before, food) else { throw InventoryIntakeError.changed }
                // No authored field changed: use the exact server backup, including
                // timestamp precision that a typed Date bridge may not represent.
                foods[position] = raw
            }
            meals[index]["foodItems"] = foods
        }
        result["meals"] = meals
        return result
    }

    /// Match the existing stock diary/Undo snapshot rule at its Date bridge only.
    /// Quantity, nutrients, IDs and every other reviewed typed field remain exact.
    private func sameIntakeStockSnapshot(_ first: FoodItem, _ second: FoodItem) throws -> Bool {
        func canonical(_ object: Any, key: String = "") -> Any {
            if let values = object as? [String: Any] { return values.reduce(into: [String: Any]()) { result, pair in result[pair.key] = canonical(pair.value, key: pair.key) } }
            if let values = object as? [Any] { return values.map { canonical($0) } }
            let dates: Set<String> = ["timestamp", "dateAdded", "bestBefore", "cookedAt", "createdAt", "sourceObservedAt", "sourceUpdatedAt", "observedAt"]
            if dates.contains(key), let value = object as? Double { return (value * 1_000).rounded() / 1_000 }
            return object
        }
        func snapshot(_ value: FoodItem) throws -> Data {
            let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            return try JSONSerialization.data(withJSONObject: canonical(raw), options: .sortedKeys)
        }
        return try snapshot(first) == snapshot(second)
    }

    private func intakeFoodBackupDigest(_ raw: [String: Any]) throws -> String {
        let value = try IntakeFirestoreBackupValue(raw)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= 400_000 else { throw InventoryIntakeError.invalid }
        return try PlanFingerprint.make(data)
    }

    private func stockMutationIntakeIndex(userID: String, mutation: InventoryMutation, receipt: InventoryReceipt,
                                          legacy: LegacyInventoryIntakeSource?, transaction: Transaction) throws -> InventoryIntakeLink? {
        guard let patch = mutation.diary else { return nil }
        let owner = db.collection(FirestoreCollection.users).document(userID)
        let ref = owner.collection("inventoryIntakeLinks").document(try InventoryIntakeRules.key(foodID: patch.foodID))
        let indexed = try transaction.getDocument(ref)
        let existing: InventoryIntakeLink?
        if indexed.exists { existing = try indexed.data(as: InventoryIntakeLink.self) } else if let legacy {
            for event in [legacy.link.source, legacy.last] {
                let document = try transaction.getDocument(owner.collection("inventoryEvents").document(event.id.uuidString))
                guard document.exists else { throw InventoryIntakeError.changed }
                let accepted = try document.data(as: InventoryReceipt.self)
                guard accepted.status == .accepted, accepted.userID == userID, accepted.fingerprint == event.fingerprint else { throw InventoryIntakeError.changed }
            }
            existing = legacy.link
        } else { existing = nil }
        if mutation.reason == .consume, patch.expected == nil, patch.desired != nil {
            guard (existing?.currentScale ?? 0) == 0 else { throw InventoryError.alreadyApplied }
            return try InventoryIntakeLink(source: receipt)
        }
        guard var link = existing else { return nil }
        try link.validate()
        guard link.userID == userID, link.foodID == patch.foodID, mutation.itemIDs == Set(link.stockIDs) else { throw InventoryIntakeError.invalid }
        let beforeScale = try InventoryIntakeRules.scale(food: patch.expected, link: link)
        let afterScale = try InventoryIntakeRules.scale(food: patch.desired, link: link)
        guard abs(link.currentScale - beforeScale) <= 0.000001 else { throw InventoryIntakeError.changed }
        let source = try link.source.mutation()
        for original in source.before {
            guard let consumed = source.after.first(where: { $0.id == original.id }),
                  let before = mutation.before.first(where: { $0.id == original.id }), let after = mutation.after.first(where: { $0.id == original.id }),
                  let difference = InventoryQuantityRules.convert((original.quantity - consumed.quantity) * (beforeScale - afterScale), from: original.unit, to: before.unit),
                  abs(after.quantity - before.quantity - difference) <= 0.000001 else { throw InventoryIntakeError.changed }
        }
        if let sourceKey = source.uniqueSourceKey {
            let lock = try transaction.getDocument(owner.collection("inventorySourceLocks").document(try PlanFingerprint.make(sourceKey)))
            guard !lock.exists || lock.data()?["operationID"] as? String == source.id.uuidString else { throw InventoryIntakeError.changed }
        }
        link.currentScale = afterScale; link.revisionID = mutation.id.uuidString
        return link
    }
}

/// Stable type-tagged digest input for arbitrary values returned by Firestore.
/// Raw backups themselves retain the original native values, including timestamp nanos.
private indirect enum IntakeFirestoreBackupValue: Encodable {
    case null, boolean(Bool), string(String), integer(String), floatingBits(String)
    case timestamp(Int64, Int32), point(String, String), reference(String, String), blob(Data)
    case array([IntakeFirestoreBackupValue]), map([String: IntakeFirestoreBackupValue]), vector([String])
    init(_ value: Any) throws {
        if value is NSNull {
            self = .null
        } else if let value = value as? Timestamp {
            self = .timestamp(value.seconds, value.nanoseconds)
        } else if let value = value as? GeoPoint {
            self = .point(String(value.latitude.bitPattern), String(value.longitude.bitPattern))
        } else if let value = value as? DocumentReference {
            self = .reference(value.firestore.app.options.projectID ?? "", value.path)
        } else if let value = value as? VectorValue {
            self = .vector(value.array.map { String($0.bitPattern) })
        } else if let value = value as? Data {
            self = .blob(value)
        } else if let value = value as? String {
            self = .string(value)
        } else if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .boolean(value.boolValue)
            } else if ["f", "d"].contains(String(cString: value.objCType)) {
                self = .floatingBits(String(value.doubleValue.bitPattern))
            } else {
                self = .integer(value.stringValue)
            }
        } else if let value = value as? [String: Any] {
            self = .map(try value.mapValues { try Self($0) })
        } else if let value = value as? [Any] {
            self = .array(try value.map { try Self($0) })
        } else {
            throw InventoryIntakeError.invalid
        }
    }
}
