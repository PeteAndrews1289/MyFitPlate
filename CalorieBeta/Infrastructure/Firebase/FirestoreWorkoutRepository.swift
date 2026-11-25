import MyFitPlateCore

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Network
import OSLog

final class FirestoreWorkoutRepository: WorkoutRepositoryProtocol, @unchecked Sendable {
    private let db: Firestore
    private let currentUserID: () -> String?
    private let outbox: WorkoutOutbox
    private let libraryCache: EditorDraftStore
    private let syncQueue = DispatchQueue(label: "MyFitPlate.workout-sync")
    private let networkMonitor = NWPathMonitor()
    private var syncingUsers = Set<String>()
    private var failedUsers = Set<String>()
    private var editingProgramBlocks = Set<String>()

    init(db: Firestore = Firestore.firestore(), outboxURL: URL? = nil,
         currentUserID: @escaping () -> String? = { Auth.auth().currentUser?.uid }, monitorNetwork: Bool = true) {
        self.db = db
        self.currentUserID = currentUserID
        outbox = WorkoutOutbox(fileURL: outboxURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("MyFitPlate/workout-outbox.json"))
        let libraryDirectory = (outboxURL?.deletingLastPathComponent() ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("MyFitPlate")).appendingPathComponent("workout-library")
        libraryCache = EditorDraftStore(directory: libraryDirectory)
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied, let userID = self?.currentUserID() else { return }
            self?.retryPendingWorkouts(userID: userID)
        }
        if monitorNetwork { networkMonitor.start(queue: DispatchQueue(label: "MyFitPlate.workout-network")) }
    }

    deinit { networkMonitor.cancel() }

    func workoutSyncState(userID: String) -> WorkoutSyncState {
        if syncQueue.sync(execute: { failedUsers.contains(userID) }) { return .failed }
        guard let count = try? outbox.pending(userID: userID).count else { return .failed }
        return count == 0 ? .synced : .pending(count)
    }

    func retryPendingWorkouts(userID: String) {
        syncQueue.async { [weak self] in self?.drain(userID: userID) }
    }

    func discardPendingWorkouts(userID: String) throws {
        try syncQueue.sync {
            try outbox.removeAll(userID: userID)
            try libraryCache.removeAll(userID: userID)
            failedUsers.remove(userID)
        }
        notify(userID: userID)
    }

    private func accept(_ write: WorkoutPendingWrite) throws {
        guard currentUserID() == write.userID else { throw WorkoutServiceError.userNotLoggedIn }
        try syncQueue.sync {
            if write.collection == .programs, write.programProgressCommand == nil,
               editingProgramBlocks.contains("\(write.userID):\(write.documentID)") { throw WorkoutBlockError.pendingSync }
            try outbox.append(write)
        }
        notify(userID: write.userID, changed: true)
        retryPendingWorkouts(userID: write.userID)
    }

    private func notify(userID: String, changed: Bool = false) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .workoutSyncStateChanged, object: userID, userInfo: ["changed": changed])
        }
    }

    private func drain(userID: String) {
        guard currentUserID() == userID, !syncingUsers.contains(userID) else { return }
        do {
            guard let write = try outbox.pending(userID: userID).first else { return }
            let ref = db.collection(FirestoreCollection.users).document(userID)
                .collection(write.collection.rawValue).document(write.documentID)
            let data = try firestoreData(write)
            syncingUsers.insert(userID)
            let completion: (Error?) -> Void = { error in
                self.syncQueue.async {
                    self.syncingUsers.remove(userID)
                    do {
                        if let error { throw error }
                        try self.outbox.acknowledge(write)
                        self.failedUsers.remove(userID)
                        self.notify(userID: userID)
                        self.drain(userID: userID)
                    } catch {
                        self.failedUsers.insert(userID)
                        self.notify(userID: userID)
                        // Firestore retains offline writes itself; failed acknowledgements keep
                        // our receipt too. Replaying set/delete by stable document ID is safe.
                        let code = (error as NSError).code
                        if [FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue,
                            FirestoreErrorCode.aborted.rawValue].contains(code) {
                            self.syncQueue.asyncAfter(deadline: .now() + 15) { [weak self] in self?.drain(userID: userID) }
                        }
                    }
                }
            }
            if let commandData = write.programProgressCommand {
                let command = try JSONDecoder().decode(WorkoutProgramProgressCommand.self, from: commandData)
                Task {
                    do {
                        _ = try await self.transactProgramProgress(userID: userID, command: command, action: "commit")
                        completion(nil)
                    } catch { completion(error) }
                }
            } else if let data, write.collection == .sessions, let payload = write.payload {
                // Creating a linked receipt fences progress reviews in the same transaction.
                // Its pointer is reconciled separately; replay never changes an existing session.
                let queuedLog = try JSONDecoder().decode(WorkoutSessionLog.self, from: payload)
                db.runTransaction({ transaction, pointer in
                    do {
                        guard self.currentUserID() == userID else { throw WorkoutServiceError.userNotLoggedIn }
                        guard try !transaction.getDocument(ref).exists else { return true }
                        var linkedProgram: DocumentReference?
                        if queuedLog.programLinkDecision != .standalone, let context = queuedLog.programContext,
                           !context.programID.isEmpty, !context.programID.contains("/"), context.programID.utf8.count <= 1_500,
                           queuedLog.date.timeIntervalSinceReferenceDate.isFinite, queuedLog.date <= Date() {
                            let candidate = self.programsCollectionRef(for: userID).document(context.programID)
                            if let program = try self.decodedBlockProgram(transaction.getDocument(candidate)),
                               program.userID == userID, (0..<program.totalSlots).contains(context.slotIndex) { linkedProgram = candidate }
                        }
                        // All reads precede both writes; no template or progress pointer is replaced.
                        transaction.setData(data, forDocument: ref)
                        if let linkedProgram {
                            let epoch = try WorkoutProgramProgressCommand.historySaveEpoch(ownerID: userID, sessionID: write.documentID)
                            transaction.setData(["progressEpoch": epoch], forDocument: linkedProgram, merge: true)
                        }
                        return true
                    } catch { pointer?.pointee = error as NSError; return nil }
                }) { _, error in completion(error) }
            } else if let data, write.collection == .programs, let payload = write.payload {
                let queued = try JSONDecoder().decode(WorkoutProgram.self, from: payload)
                db.runTransaction({ transaction, pointer -> Any? in
                    do {
                        guard self.currentUserID() == userID else { throw WorkoutServiceError.userNotLoggedIn }
                        let snapshot = try transaction.getDocument(ref)
                        var mergedData = data
                        if snapshot.exists {
                            let latest = try self.decode(snapshot, as: WorkoutProgram.self)
                            if write.programArchiveIntent == true {
                                mergedData = ["archivedAt": data["archivedAt"] ?? NSNull()]
                            } else {
                                var merged = try WorkoutLibraryRules.mergingQueuedProgram(queued, with: latest)
                                merged.archivedAt = latest.archivedAt
                                mergedData = try self.firestoreData(WorkoutPendingWrite(userID: userID, collection: .programs,
                                    documentID: write.documentID, value: merged)) ?? data
                                let raw = snapshot.data() ?? [:]
                                mergedData["dateCreated"] = raw["dateCreated"] ?? mergedData["dateCreated"]
                                if merged.startDate == latest.startDate { mergedData["startDate"] = raw["startDate"] ?? mergedData["startDate"] }
                                if try WorkoutBlockRules.fingerprint(merged.routines) == WorkoutBlockRules.fingerprint(latest.routines) {
                                    mergedData["routines"] = raw["routines"] ?? mergedData["routines"]
                                }
                                if merged.lineage == latest.lineage { mergedData["lineage"] = raw["lineage"] ?? mergedData["lineage"] }
                            }
                        } else if write.programArchiveIntent == true { throw WorkoutLibraryEditError.changed } else if queued.trainingBlock != nil {
                            // Initial creation owns its frozen block. Only later writes require
                            // the dedicated block CAS and must never replace authored weeks.
                            guard queued.userID == userID else { throw WorkoutBlockError.accountChanged }
                            try WorkoutBlockRules.validate(queued)
                            mergedData["trainingBlock"] = try Firestore.Encoder().encode(queued)["trainingBlock"]
                        }
                        transaction.setData(mergedData, forDocument: ref, merge: true)
                        return true
                    } catch { pointer?.pointee = error as NSError; return nil }
                }) { _, error in completion(error) }
            } else if let data { ref.setData(data, merge: true, completion: completion) } else { ref.delete(completion: completion) }
        } catch {
            failedUsers.insert(userID)
            notify(userID: userID)
        }
    }

    private func firestoreData(_ write: WorkoutPendingWrite) throws -> [String: Any]? {
        guard let payload = write.payload else { return nil }
        let decoder = JSONDecoder()
        let encoder = Firestore.Encoder()
        switch write.collection {
        case .programs:
            var data = try encoder.encode(decoder.decode(WorkoutProgram.self, from: payload))
            // Only the checked block transaction owns authored weeks. A delayed ordinary
            // progress/schedule write must not replace a newer block revision.
            data.removeValue(forKey: "trainingBlock")
            for key in ["startDate", "daysOfWeek", "skippedIndices", "weekRescue", "archivedAt"] where data[key] == nil { data[key] = NSNull() }
            return data
        case .routines:
            var data = try encoder.encode(decoder.decode(WorkoutRoutine.self, from: payload))
            if data["notes"] == nil { data["notes"] = NSNull() }
            return data
        case .sessions:
            var data = try encoder.encode(decoder.decode(WorkoutSessionLog.self, from: payload))
            if data["aiInsights"] == nil { data["aiInsights"] = NSNull() }
            return data
        }
    }

    private func programsCollectionRef(for userID: String) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutPrograms)
    }

    private func routinesCollectionRef(for userID: String) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutRoutines)
    }

    private func sessionLogsCollectionRef(for userID: String) -> CollectionReference {
        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs)
    }

    private func decode<Value: Decodable>(_ document: DocumentSnapshot, as type: Value.Type) throws -> Value {
        guard var data = document.data() else { throw CocoaError(.coderValueNotFound) }
        // Old documents did not always duplicate their Firestore ID inside the body.
        // Use the real document identity so reading then saving cannot create another copy.
        data["id"] = document.documentID
        return try Firestore.Decoder().decode(type, from: data)
    }

    func fetchWorkoutSessionLog(userID: String, sessionID: String) async throws -> WorkoutSessionLog {
        if let pending = try pendingSessions([], userID: userID).first(where: { $0.id == sessionID }) { return pending }
        let document = try await sessionLogsCollectionRef(for: userID).document(sessionID).getDocument()
        return try decode(document, as: WorkoutSessionLog.self)
    }

    func fetchSessionLogs(userID: String, routineIDs: [String]) async throws -> [WorkoutSessionLog] {
        let chunks = routineIDs.chunked(into: 10)
        var allLogs: [WorkoutSessionLog] = []

        for chunk in chunks {
            guard !chunk.isEmpty else { continue }
            let snapshot = try await sessionLogsCollectionRef(for: userID)
                .whereField("routineID", in: chunk)
                .getDocuments()

            let logs = try snapshot.documents.map { try decode($0, as: WorkoutSessionLog.self) }
            allLogs.append(contentsOf: logs)
        }
        return try pendingSessions(allLogs, userID: userID).filter { routineIDs.contains($0.routineID) }
    }

    func fetchRecentSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog] {
        let startDate = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date()) ?? Date()
        let snapshot = try await sessionLogsCollectionRef(for: userID)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .getDocuments()
        return try pendingSessions(snapshot.documents.map { try decode($0, as: WorkoutSessionLog.self) }, userID: userID)
            .filter { $0.date >= startDate }
    }

    func fetchExportSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog] {
        let startDate = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date()) ?? Date()
        let snapshot = try await sessionLogsCollectionRef(for: userID)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .getDocuments(source: .server)
        return try pendingSessions(snapshot.documents.map { try decode($0, as: WorkoutSessionLog.self) }, userID: userID)
            .filter { $0.date >= startDate }
    }

    func addProgramsSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Any {
        addProgramLibraryListener(userID: userID) { onUpdate($0.map(\.values)) }
    }

    func addProgramLibraryListener(userID: String, onUpdate: @escaping (Result<WorkoutLibrarySnapshot<WorkoutProgram>, Error>) -> Void) -> Any {
        listen(userID: userID, collection: .programs, query: programsCollectionRef(for: userID),
               id: { $0.id }, reconcileOverlay: { canonical, pending in
                   pending.map { value in
                       var visible = value
                       if let serverOrCached = canonical.first(where: { $0.id == value.id }) {
                           visible.trainingBlock = serverOrCached.trainingBlock
                       }
                       return visible
                   }
               }, onUpdate: onUpdate)
    }

    func addRoutinesSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Any {
        addRoutineLibraryListener(userID: userID) { onUpdate($0.map(\.values)) }
    }

    func addRoutineLibraryListener(userID: String, onUpdate: @escaping (Result<WorkoutLibrarySnapshot<WorkoutRoutine>, Error>) -> Void) -> Any {
        listen(userID: userID, collection: .routines, query: routinesCollectionRef(for: userID),
               id: { $0.id }, onUpdate: onUpdate)
    }

    private func listen<Value: Codable>(
        userID: String, collection: WorkoutPendingWrite.Collection, query: Query,
        id: @escaping (Value) -> String?, reconcileOverlay: (([Value], [Value]) -> [Value])? = nil,
        onUpdate: @escaping (Result<WorkoutLibrarySnapshot<Value>, Error>) -> Void
    ) -> Any {
        let scope = collection.rawValue
        var latest = WorkoutLibrarySnapshot<Value>(values: [], isFromCache: true)
        do {
            if let saved = try libraryCache.load(WorkoutLibrarySnapshot<Value>.self, userID: userID, scope: scope) {
                latest = saved.value
                latest.isFromCache = true
            }
        } catch { onUpdate(.failure(error)) }
        let publish = {
            guard self.currentUserID() == userID else { return }
            do {
                var visible = latest
                visible.values = try self.outbox.overlay(latest.values, userID: userID, collection: collection, id: id)
                if let reconcileOverlay { visible.values = reconcileOverlay(latest.values, visible.values) }
                let pendingIDs = Set(try self.outbox.pending(userID: userID).filter { $0.collection == collection }.map(\.documentID))
                visible.unreadableIDs.subtract(pendingIDs)
                onUpdate(.success(visible))
            } catch { onUpdate(.failure(error)) }
        }
        if !latest.values.isEmpty || !latest.unreadableIDs.isEmpty { publish() }
        // Do not republish an old snapshot on acknowledgement: the corresponding server
        // snapshot can arrive after the queue entry has been removed.
        let observer = NotificationCenter.default.addObserver(forName: .workoutSyncStateChanged, object: nil, queue: .main) { note in
            if note.object as? String == userID, note.userInfo?["changed"] as? Bool == true { publish() }
        }
        let listener = query.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            do {
                guard self.currentUserID() == userID else { return }
                if let error { throw error }
                guard let snapshot else { throw CocoaError(.coderValueNotFound) }
                if snapshot.metadata.isFromCache && snapshot.documents.isEmpty {
                    // A cold/offline cache cannot establish that a saved program was deleted.
                    // Wait for the server, while still showing locally accepted pending changes.
                    let hasPendingChanges = try self.outbox.pending(userID: userID).contains { $0.collection == collection }
                    if !latest.values.isEmpty || !latest.unreadableIDs.isEmpty || hasPendingChanges {
                        publish()
                    }
                    return
                }
                var values: [Value] = []
                var unreadable = Set<String>()
                for document in snapshot.documents {
                    do { values.append(try self.decode(document, as: Value.self)) } catch { unreadable.insert(document.documentID) }
                }
                latest = WorkoutLibrarySnapshot(values: values, unreadableIDs: unreadable, isFromCache: snapshot.metadata.isFromCache)
                    .retainingLastGood(latest.values, id: id)
                do { try self.libraryCache.save(latest, userID: userID, scope: scope) } catch { latest.cacheWriteFailed = true }
                publish()
            } catch { onUpdate(.failure(error)) }
        }
        retryPendingWorkouts(userID: userID)
        return WorkoutListenerHandle(listener: listener, observer: observer)
    }

    private func pendingSessions(_ logs: [WorkoutSessionLog], userID: String) throws -> [WorkoutSessionLog] {
        try outbox.overlay(logs, userID: userID, collection: .sessions, id: { $0.id })
            .sorted { $0.date > $1.date }
    }

    func removeListener(_ handle: Any) {
        (handle as? WorkoutListenerHandle)?.remove()
    }

    func pendingProgramProgress(userID: String, programID: String) throws -> [WorkoutProgramProgressCommand] {
        guard currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
        return try outbox.pending(userID: userID).filter { $0.documentID == programID }.compactMap { write in
            guard let data = write.programProgressCommand else { return nil }
            return try JSONDecoder().decode(WorkoutProgramProgressCommand.self, from: data)
        }
    }
    func enqueueProgramProgress(userID: String, command: WorkoutProgramProgressCommand, locallyVerifiedLogs: [WorkoutSessionLog]) async throws -> WorkoutProgram {
        guard currentUserID() == userID, command.ownerID == userID else { throw WorkoutBlockError.accountChanged }
        try command.validateIdentity()
        let expected = try command.expected()
        if let cached = try libraryCache.load(WorkoutProgramProgressOperationReceipt.self, userID: userID, scope: "progress-receipt-\(command.id)")?.value {
            guard cached.fingerprint == (try command.fingerprint()) else { throw WorkoutBlockError.changed }
            if cached.status == .cancelled { throw WorkoutBlockError.cancelled }
            do {
                let status = try await resolveProgramProgress(userID: userID, command: command, cancelPending: false)
                if case .accepted(let current) = status { guard let current else { throw WorkoutBlockError.unavailable }; return current }
            } catch let error as WorkoutBlockError { throw error } catch { /* Accepted local receipt remains proof while offline. */ }
            return expected
        }
        if let pending = try outbox.pending(userID: userID).first(where: { write in
            guard let data = write.programProgressCommand, let stored = try? JSONDecoder().decode(WorkoutProgramProgressCommand.self, from: data) else { return false }
            return stored.id == command.id
        }), let data = pending.programProgressCommand, let payload = pending.payload {
            let stored = try JSONDecoder().decode(WorkoutProgramProgressCommand.self, from: data)
            guard try stored.fingerprint() == command.fingerprint() else { throw WorkoutBlockError.changed }
            return try stored.overlay(proposed: JSONDecoder().decode(WorkoutProgram.self, from: payload), on: expected)
        }
        let proposed = try command.applying(to: expected, verifiedLogs: locallyVerifiedLogs, trustStoredProofsForLocalProjection: command.kind == .completion)
        try accept(WorkoutPendingWrite(progress: command, proposed: proposed))
        return proposed
    }
    func resolveProgramProgress(userID: String, command: WorkoutProgramProgressCommand, cancelPending: Bool) async throws -> WorkoutProgramProgressResolution {
        if cancelPending && command.kind == .completion { throw WorkoutBlockError.invalid }
        let result = try await transactProgramProgress(userID: userID, command: command, action: cancelPending ? "cancel" : "status")
        switch result {
        case .accepted, .cancelled:
            try syncQueue.sync {
                for write in try outbox.pending(userID: userID) {
                    guard let data = write.programProgressCommand, let stored = try? JSONDecoder().decode(WorkoutProgramProgressCommand.self, from: data), stored.id == command.id else { continue }
                    guard try stored.fingerprint() == command.fingerprint() else { throw WorkoutBlockError.changed }
                    try outbox.acknowledge(write)
                }
                if try outbox.pending(userID: userID).isEmpty { failedUsers.remove(userID) }
            }
            notify(userID: userID, changed: true)
        case .pending: break
        }
        switch result {
        case .accepted(let current): return .accepted(try overlayBlockProgram(current, userID: userID, programID: command.programID))
        case .cancelled(let current): return .cancelled(try overlayBlockProgram(current, userID: userID, programID: command.programID))
        case .pending: return .pending
        }
    }
    private func transactProgramProgress(userID: String, command: WorkoutProgramProgressCommand, action: String) async throws -> WorkoutProgramProgressResolution {
        guard currentUserID() == userID, command.ownerID == userID else { throw WorkoutBlockError.accountChanged }
        try command.validateIdentity()
        let user = db.collection(FirestoreCollection.users).document(userID)
        let programRef = programsCollectionRef(for: userID).document(command.programID)
        let receiptRef = user.collection("programProgressOperations").document(command.id)
        let fingerprint = try command.fingerprint()
        let result: WorkoutProgramProgressResolution = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, pointer -> Any? in
                do {
                    guard self.currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
                    let existing = try transaction.getDocument(receiptRef)
                    if existing.exists {
                        let receipt = try existing.data(as: WorkoutProgramProgressOperationReceipt.self)
                        guard receipt.id == command.id, receipt.programID == command.programID, receipt.fingerprint == fingerprint else { throw WorkoutBlockError.changed }
                        let current = try self.decodedBlockProgram(transaction.getDocument(programRef))
                        return receipt.status == .accepted ? WorkoutProgramProgressResolution.accepted(current) : WorkoutProgramProgressResolution.cancelled(current)
                    }
                    if action == "status" { return WorkoutProgramProgressResolution.pending }
                    let document = try transaction.getDocument(programRef)
                    let latest = try self.decodedBlockProgram(document)
                    let receipt = WorkoutProgramProgressOperationReceipt(id: command.id, fingerprint: fingerprint, programID: command.programID, status: action == "cancel" ? .cancelled : .accepted)
                    let receiptData = try Firestore.Encoder().encode(receipt)
                    if action == "cancel" {
                        transaction.setData(receiptData, forDocument: receiptRef)
                        return WorkoutProgramProgressResolution.cancelled(latest)
                    }
                    guard let latest else {
                        if command.kind == .completion {
                            transaction.setData(receiptData, forDocument: receiptRef)
                            return WorkoutProgramProgressResolution.accepted(nil)
                        }
                        throw WorkoutBlockError.unavailable
                    }
                    let ids = Set(command.proofSessionIDs + (latest.slotCompletionProofs ?? []).map(\.sessionID))
                    guard ids.count <= 368 else { throw WorkoutBlockError.invalid }
                    var verified: [WorkoutSessionLog] = []
                    for id in ids.sorted() {
                        let snapshot = try transaction.getDocument(user.collection("workoutSessionLogs").document(id))
                        if snapshot.exists {
                            var log = try snapshot.data(as: WorkoutSessionLog.self); log.id = snapshot.documentID
                            verified.append(log)
                        }
                    }
                    let updated = try command.applying(to: latest, verifiedLogs: verified)
                    let encoded = try Firestore.Encoder().encode(updated)
                    var patch: [String: Any] = [:]
                    for key in ["currentProgressIndex", "skippedIndices", "progressEpoch", "slotCompletionProofs", "lastSkipReceipt"] { patch[key] = encoded[key] ?? NSNull() }
                    transaction.setData(patch, forDocument: programRef, merge: true)
                    transaction.setData(receiptData, forDocument: receiptRef)
                    return WorkoutProgramProgressResolution.accepted(updated)
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { value, error in
                if let error { continuation.resume(throwing: error) } else if let value = value as? WorkoutProgramProgressResolution { continuation.resume(returning: value) } else { continuation.resume(throwing: WorkoutBlockError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
        let status: WorkoutProgramProgressOperationReceipt.Status?
        switch result {
        case .accepted: status = .accepted
        case .cancelled: status = .cancelled
        case .pending: status = nil
        }
        if let status {
            try libraryCache.save(WorkoutProgramProgressOperationReceipt(id: command.id, fingerprint: fingerprint, programID: command.programID, status: status),
                userID: userID, scope: "progress-receipt-\(command.id)")
        }
        return result
    }

    func commitProgramEdit(userID: String, command: WorkoutProgramEditCommand) async throws -> WorkoutProgram? {
        let status = try await resolveProgramEdit(userID: userID, command: command, cancelPending: false)
        switch status {
        case .accepted(let program): return program
        case .cancelled: throw WorkoutBlockError.cancelled
        case .pending: break
        }
        let gate = "\(userID):\(command.programID)"
        try syncQueue.sync {
            guard !editingProgramBlocks.contains(gate),
                  try !outbox.pending(userID: userID).contains(where: { $0.collection == .programs && $0.documentID == command.programID }) else { throw WorkoutBlockError.pendingSync }
            editingProgramBlocks.insert(gate)
        }
        defer { _ = syncQueue.sync { editingProgramBlocks.remove(gate) } }
        switch try await transactProgramEdit(userID: userID, command: command, action: "commit") {
        case .accepted(let program): return program
        case .cancelled: throw WorkoutBlockError.cancelled
        case .pending: throw WorkoutBlockError.unavailable
        }
    }
    func resolveProgramEdit(userID: String, command: WorkoutProgramEditCommand, cancelPending: Bool) async throws -> WorkoutProgramEditResolution {
        try await transactProgramEdit(userID: userID, command: command, action: cancelPending ? "cancel" : "status")
    }
    private func transactProgramEdit(userID: String, command: WorkoutProgramEditCommand, action: String) async throws -> WorkoutProgramEditResolution {
        guard currentUserID() == userID, command.ownerID == userID,
              !command.programID.isEmpty, !command.programID.contains("/"), !command.id.isEmpty, !command.id.contains("/") else { throw WorkoutBlockError.accountChanged }
        let programRef = programsCollectionRef(for: userID).document(command.programID)
        let receiptRef = db.collection(FirestoreCollection.users).document(userID).collection("programEditOperations").document(command.id)
        let fingerprint = try command.fingerprint()
        let resolution: WorkoutProgramEditResolution = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, pointer -> Any? in
                do {
                    guard self.currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
                    let receiptDocument = try transaction.getDocument(receiptRef)
                    if receiptDocument.exists {
                        let receipt = try receiptDocument.data(as: WorkoutProgramEditOperationReceipt.self)
                        guard receipt.id == command.id, receipt.programID == command.programID, receipt.fingerprint == fingerprint else { throw WorkoutBlockError.changed }
                        if receipt.status == .cancelled { return WorkoutProgramEditResolution.cancelled }
                        return WorkoutProgramEditResolution.accepted(try self.decodedBlockProgram(transaction.getDocument(programRef)))
                    }
                    if action == "status" { return WorkoutProgramEditResolution.pending }
                    let receipt = WorkoutProgramEditOperationReceipt(id: command.id, fingerprint: fingerprint, programID: command.programID, status: action == "cancel" ? .cancelled : .accepted)
                    let receiptData = try Firestore.Encoder().encode(receipt)
                    if action == "cancel" {
                        transaction.setData(receiptData, forDocument: receiptRef)
                        return WorkoutProgramEditResolution.cancelled
                    }
                    let document = try transaction.getDocument(programRef)
                    guard let latest = try self.decodedBlockProgram(document) else { throw WorkoutBlockError.unavailable }
                    let updated = try command.applying(to: latest)
                    let encoded = try Firestore.Encoder().encode(updated)
                    var patch: [String: Any] = [:]
                    let keys = command.kind == .weekRescue ? ["weekRescue", "slotDateSnapshots", "scheduleAnchorDay"]
                        : ["name", "routines", "startDate", "daysOfWeek", "slotDateSnapshots", "scheduleAnchorDay"]
                    for key in keys { patch[key] = encoded[key] ?? NSNull() }
                    let raw = document.data() ?? [:]
                    if command.kind == nil {
                        if try WorkoutBlockRules.fingerprint(updated.routines) == WorkoutBlockRules.fingerprint(latest.routines) { patch["routines"] = raw["routines"] ?? patch["routines"] }
                        if updated.startDate == latest.startDate { patch["startDate"] = raw["startDate"] ?? patch["startDate"] }
                    }
                    transaction.setData(patch, forDocument: programRef, merge: true)
                    transaction.setData(receiptData, forDocument: receiptRef)
                    return WorkoutProgramEditResolution.accepted(updated)
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { result, error in
                if let error { continuation.resume(throwing: error) } else if let result = result as? WorkoutProgramEditResolution { continuation.resume(returning: result) } else { continuation.resume(throwing: WorkoutBlockError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
        notify(userID: userID, changed: action != "status")
        return resolution
    }

    func saveProgramArchive(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram {
        guard program.userID == userID, let id = program.id, !id.isEmpty, !id.contains("/"), id.utf8.count <= 1_500 else { throw WorkoutLibraryEditError.changed }
        try accept(WorkoutPendingWrite(userID: userID, collection: .programs, documentID: id,
            value: program, programArchiveIntent: true))
        return program
    }

    func saveProgram(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram {
        var programToSave = program
        programToSave.userID = userID

        let id = programToSave.id ?? UUID().uuidString
        programToSave.id = id
        try accept(WorkoutPendingWrite(userID: userID, collection: .programs, documentID: id, value: programToSave))
        return programToSave
    }

    func deleteProgram(userID: String, programID: String) async throws {
        try accept(WorkoutPendingWrite(userID: userID, deleting: .programs, documentID: programID))
    }

    func commitProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock,
                            protectedSlots: Set<Int>) async throws -> WorkoutProgram? {
        guard currentUserID() == userID, expected.userID == userID, let id = expected.id, !id.isEmpty else {
            throw WorkoutBlockError.accountChanged
        }
        var proposal = expected; proposal.trainingBlock = block
        try WorkoutBlockRules.validate(proposal)
        let gate = "\(userID):\(id)"
        try syncQueue.sync {
            guard !editingProgramBlocks.contains(gate),
                  try !outbox.pending(userID: userID).contains(where: { $0.collection == .programs && $0.documentID == id }) else {
                throw WorkoutBlockError.pendingSync
            }
            editingProgramBlocks.insert(gate)
        }
        defer { _ = syncQueue.sync { editingProgramBlocks.remove(gate) } }
        let resolution = try await transactProgramBlock(userID: userID, expected: expected, block: block,
                                                        protectedSlots: protectedSlots, cancel: false)
        switch resolution {
        case .accepted(let program): return try overlayBlockProgram(program, userID: userID, programID: id)
        case .cancelled: throw WorkoutBlockError.cancelled
        }
    }

    func resolveProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock,
                             cancelPending: Bool) async throws -> WorkoutBlockResolution? {
        guard currentUserID() == userID, expected.userID == userID, let id = expected.id,
              !id.isEmpty, !block.revisionID.contains("/"), !block.revisionID.isEmpty else {
            throw WorkoutBlockError.accountChanged
        }
        let resolution: WorkoutBlockResolution
        if cancelPending {
            resolution = try await transactProgramBlock(userID: userID, expected: expected, block: block,
                                                        protectedSlots: [], cancel: true)
        } else {
            let user = db.collection(FirestoreCollection.users).document(userID)
            let receiptSnapshot = try await user.collection("programBlockOperations").document(block.revisionID).getDocument(source: .server)
            guard receiptSnapshot.exists else { return nil }
            let receipt = try receiptSnapshot.data(as: WorkoutBlockOperationReceipt.self)
            try receipt.validate(expected: expected, block: block)
            if receipt.status == .cancelled { resolution = .cancelled } else {
                let snapshot = try await programsCollectionRef(for: userID).document(id).getDocument(source: .server)
                resolution = .accepted(try decodedBlockProgram(snapshot))
            }
        }
        guard currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
        if case .accepted(let program) = resolution { return .accepted(try overlayBlockProgram(program, userID: userID, programID: id)) }
        return resolution
    }

    func createProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand) async throws -> WorkoutProgram? {
        guard currentUserID() == userID, command.userID == userID else { throw WorkoutSuccessorError.accountChanged }
        let ids = [command.sourceProgramID, command.destinationProgramID]
        let hasPendingProgramWrites = try syncQueue.sync {
            guard ids.allSatisfy({ !editingProgramBlocks.contains("\(userID):\($0)") }) else { throw WorkoutSuccessorError.pendingSync }
            let pending = try outbox.pending(userID: userID).contains { $0.collection == .programs && ids.contains($0.documentID) }
            for id in ids { editingProgramBlocks.insert("\(userID):\(id)") }
            return pending
        }
        defer { syncQueue.sync { for id in ids { editingProgramBlocks.remove("\(userID):\(id)") } } }
        let resolution = try await transactProgramSuccessor(userID: userID, command: command, action: .create, hasPendingProgramWrites: hasPendingProgramWrites)
        switch resolution {
        case .accepted(let program): return try overlayBlockProgram(program, userID: userID, programID: command.destinationProgramID)
        case .cancelled: throw WorkoutSuccessorError.cancelled
        case .pending: throw WorkoutSuccessorError.unavailable
        }
    }

    func resolveProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand,
                                 cancelPending: Bool) async throws -> WorkoutProgramSuccessorResolution {
        let result = try await transactProgramSuccessor(userID: userID, command: command, action: cancelPending ? .cancel : .status)
        if case .accepted(let program) = result {
            return .accepted(try overlayBlockProgram(program, userID: userID, programID: command.destinationProgramID))
        }
        return result
    }

    private enum SuccessorAction { case create, status, cancel }

    private func transactProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand,
                                          action: SuccessorAction, hasPendingProgramWrites: Bool = false) async throws -> WorkoutProgramSuccessorResolution {
        guard currentUserID() == userID, command.userID == userID else { throw WorkoutSuccessorError.accountChanged }
        try WorkoutProgramSuccessorRules.validate(command)
        let user = db.collection(FirestoreCollection.users).document(userID)
        let source = programsCollectionRef(for: userID).document(command.sourceProgramID)
        let destination = programsCollectionRef(for: userID).document(command.destinationProgramID)
        let receiptRef = user.collection("programSuccessorOperations").document(command.operationID.uuidString)
        let accepted = try Firestore.Encoder().encode(WorkoutProgramSuccessorReceipt(command: command, status: .accepted))
        let cancelled = try Firestore.Encoder().encode(WorkoutProgramSuccessorReceipt(command: command, status: .cancelled))
        let payload = try Firestore.Encoder().encode(command.destination())
        let result: WorkoutProgramSuccessorResolution = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ [self] transaction, pointer -> Any? in
                do {
                    guard currentUserID() == userID else { throw WorkoutSuccessorError.accountChanged }
                    let receiptDocument = try transaction.getDocument(receiptRef)
                    if receiptDocument.exists {
                        let receipt = try receiptDocument.data(as: WorkoutProgramSuccessorReceipt.self)
                        try receipt.validate(command)
                        if receipt.status == .cancelled { return WorkoutProgramSuccessorResolution.cancelled }
                        let current = try transaction.getDocument(destination)
                        return WorkoutProgramSuccessorResolution.accepted(try decodedBlockProgram(current))
                    }
                    switch action {
                    case .status: return WorkoutProgramSuccessorResolution.pending
                    case .cancel:
                        transaction.setData(cancelled, forDocument: receiptRef)
                        return WorkoutProgramSuccessorResolution.cancelled
                    case .create:
                        guard !hasPendingProgramWrites else { throw WorkoutSuccessorError.pendingSync }
                    }
                    let sourceDocument = try transaction.getDocument(source)
                    let destinationDocument = try transaction.getDocument(destination)
                    try WorkoutProgramSuccessorRules.verifySource(decodedBlockProgram(sourceDocument), for: command)
                    guard !destinationDocument.exists else { throw WorkoutSuccessorError.changed }
                    transaction.setData(payload, forDocument: destination)
                    transaction.setData(accepted, forDocument: receiptRef)
                    return WorkoutProgramSuccessorResolution.accepted(try command.destination())
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { result, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == WorkoutSuccessorError.errorDomain, let known = WorkoutSuccessorError(rawValue: failure.code) {
                        continuation.resume(throwing: known)
                    } else { continuation.resume(throwing: error) }
                } else if let result = result as? WorkoutProgramSuccessorResolution { continuation.resume(returning: result) } else { continuation.resume(throwing: WorkoutSuccessorError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw WorkoutSuccessorError.accountChanged }
        notify(userID: userID, changed: true)
        return result
    }

    private func decodedBlockProgram(_ snapshot: DocumentSnapshot) throws -> WorkoutProgram? {
        guard snapshot.exists else { return nil }
        var program = try snapshot.data(as: WorkoutProgram.self); program.id = snapshot.documentID
        return program
    }

    private func overlayBlockProgram(_ canonical: WorkoutProgram?, userID: String, programID: String) throws -> WorkoutProgram? {
        let pending = try outbox.overlay(canonical.map { [$0] } ?? [], userID: userID, collection: .programs, id: { $0.id })
        guard var visible = pending.first(where: { $0.id == programID }) else { return nil }
        // Ordinary queued writes never own the authored block field.
        visible.trainingBlock = canonical?.trainingBlock
        return visible
    }

    private func transactProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock,
                                      protectedSlots: Set<Int>, cancel: Bool) async throws -> WorkoutBlockResolution {
        guard let id = expected.id, currentUserID() == userID, expected.userID == userID,
              !block.revisionID.contains("/"), !block.revisionID.isEmpty else { throw WorkoutBlockError.accountChanged }
        let user = db.collection(FirestoreCollection.users).document(userID)
        let reference = programsCollectionRef(for: userID).document(id)
        let receiptReference = user.collection("programBlockOperations").document(block.revisionID)
        let receipt = try WorkoutBlockOperationReceipt(expected: expected, block: block, status: cancel ? .cancelled : .accepted)
        let receiptData = try Firestore.Encoder().encode(receipt)
        let blockData = try Firestore.Encoder().encode(block)
        let resolution: WorkoutBlockResolution = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, pointer -> Any? in
                do {
                    guard self.currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
                    let receiptDocument = try transaction.getDocument(receiptReference)
                    if receiptDocument.exists {
                        let stored = try receiptDocument.data(as: WorkoutBlockOperationReceipt.self)
                        try stored.validate(expected: expected, block: block)
                        if stored.status == .cancelled { return WorkoutBlockResolution.cancelled }
                        let document = try transaction.getDocument(reference)
                        return WorkoutBlockResolution.accepted(try self.decodedBlockProgram(document))
                    }
                    if cancel {
                        transaction.setData(receiptData, forDocument: receiptReference)
                        return WorkoutBlockResolution.cancelled
                    }
                    let document = try transaction.getDocument(reference)
                    let latest = try self.decodedBlockProgram(document)
                    guard let latest else { throw WorkoutBlockError.unavailable }
                    let updated = try WorkoutBlockRules.applying(block, to: latest, expected: expected, protectedSlots: protectedSlots)
                    transaction.setData(["trainingBlock": blockData], forDocument: reference, merge: true)
                    transaction.setData(receiptData, forDocument: receiptReference)
                    if let migration = receipt.legacyMigration {
                        let migrationReference = reference.collection("legacyMigrations").document(migration.id)
                        transaction.setData(try Firestore.Encoder().encode(migration), forDocument: migrationReference)
                    }
                    return WorkoutBlockResolution.accepted(updated)
                } catch let error as WorkoutBlockError {
                    let code: Int
                    switch error {
                    case .changed: code = 409
                    case .progressChanged: code = 412
                    case .accountChanged: code = 401
                    case .unavailable: code = 404
                    default: code = 422
                    }
                    pointer?.pointee = NSError(domain: "MyFitPlate.ProgramBlock", code: code,
                                               userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                    return nil
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { result, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == "MyFitPlate.ProgramBlock" {
                        switch failure.code {
                        case 409: continuation.resume(throwing: WorkoutBlockError.changed)
                        case 412: continuation.resume(throwing: WorkoutBlockError.progressChanged)
                        case 401: continuation.resume(throwing: WorkoutBlockError.accountChanged)
                        case 404: continuation.resume(throwing: WorkoutBlockError.unavailable)
                        default: continuation.resume(throwing: WorkoutBlockError.invalid)
                        }
                    } else { continuation.resume(throwing: error) }
                } else if let result = result as? WorkoutBlockResolution { continuation.resume(returning: result) } else { continuation.resume(throwing: WorkoutBlockError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw WorkoutBlockError.accountChanged }
        notify(userID: userID, changed: true)
        return resolution
    }

    func saveRoutine(userID: String, routine: WorkoutRoutine) async throws {
        guard let routineToSave = routine.deepCopy() else { throw CocoaError(.coderInvalidValue) }
        routineToSave.userID = userID
        try accept(WorkoutPendingWrite(userID: userID, collection: .routines, documentID: routineToSave.id, value: routineToSave))
    }

    func deleteRoutine(userID: String, routineID: String) async throws {
        try accept(WorkoutPendingWrite(userID: userID, deleting: .routines, documentID: routineID))
    }

    func saveWorkoutSessionLog(userID: String, log: WorkoutSessionLog) async throws {
        var logToSave = log
        let id = log.id ?? UUID().uuidString
        logToSave.id = id
        try accept(WorkoutPendingWrite(userID: userID, collection: .sessions, documentID: id, value: logToSave))
    }

    func commitWorkoutCorrection(userID: String, expected: WorkoutSessionLog, updated: WorkoutSessionLog) async throws {
        guard currentUserID() == userID else { throw WorkoutCorrectionError.accountChanged }
        guard let id = expected.id, updated.id == id, let revision = updated.correctionRevisionID else { throw WorkoutCorrectionError.invalid }
        // A completion still waiting in the durable outbox must finish first. The
        // correction receipt stays local and can retry after initial synchronization.
        guard try !outbox.pending(userID: userID).contains(where: { $0.collection == .sessions && $0.documentID == id }) else {
            retryPendingWorkouts(userID: userID)
            throw WorkoutCorrectionError.historyUnavailable
        }
        let reference = sessionLogsCollectionRef(for: userID).document(id)
        let expectedFingerprint = try WorkoutCorrectionRevisionRules.fingerprint(expected)
        var data = try Firestore.Encoder().encode(updated)
        if updated.aiInsights == nil { data["aiInsights"] = FieldValue.delete() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.runTransaction({ transaction, pointer in
                do {
                    guard self.currentUserID() == userID else { throw WorkoutCorrectionError.accountChanged }
                    let document = try transaction.getDocument(reference)
                    guard document.exists else { throw WorkoutCorrectionError.historyUnavailable }
                    var latest = try document.data(as: WorkoutSessionLog.self)
                    latest.id = id
                    if latest.correctionRevisionID == revision { return true }
                    guard try WorkoutCorrectionRevisionRules.fingerprint(latest) == expectedFingerprint else {
                        pointer?.pointee = NSError(domain: "MyFitPlate.WorkoutCorrection", code: 409)
                        return nil
                    }
                    transaction.setData(data, forDocument: reference, merge: true)
                    return true
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { _, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == "MyFitPlate.WorkoutCorrection", failure.code == 409 {
                        continuation.resume(throwing: WorkoutCorrectionError.conflict)
                    } else { continuation.resume(throwing: error) }
                } else { continuation.resume() }
            }
        }
        guard currentUserID() == userID else { throw WorkoutCorrectionError.accountChanged }
        notify(userID: userID, changed: true)
    }

    func fetchHistory(userID: String, exerciseName: String) async throws -> [WorkoutSessionLog] {
        let snapshot = try await sessionLogsCollectionRef(for: userID)
            .order(by: "date", descending: true)
            .getDocuments()

        let logs = try pendingSessions(snapshot.documents.map { try decode($0, as: WorkoutSessionLog.self) }, userID: userID)
        return logs.filter { log in
            log.completedExercises.contains { $0.exerciseName == exerciseName }
        }
    }

    func fetchPreviousPerformance(userID: String, exerciseName: String) async throws -> CompletedExercise? {
        guard currentUserID() == userID else { throw WorkoutHistoryReadError.accountChanged }
        let now = Date()
        let snapshot = try await sessionLogsCollectionRef(for: userID)
            .whereField("date", isLessThanOrEqualTo: Timestamp(date: now))
            .order(by: "date", descending: true).getDocuments()
        guard currentUserID() == userID else { throw WorkoutHistoryReadError.accountChanged }
        let recentLogs = try pendingSessions(snapshot.documents.map { try decode($0, as: WorkoutSessionLog.self) }, userID: userID)
        for log in recentLogs where log.date.timeIntervalSinceReferenceDate.isFinite && log.date <= now {
            if let performance = log.completedExercises.first(where: { $0.exerciseName == exerciseName }) { return performance }
        }
        return nil
    }

    // MARK: - Analytics

    func saveWorkoutInsights(userID: String, sessionID: String, insights: [[String: Any]]) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs).document(sessionID)
        try await ref.updateData(["aiInsights": insights])
    }

    func fetchWorkoutHistoryPage(userID: String, cursor: WorkoutHistoryCursor?, pageSize: Int) async throws -> WorkoutHistoryPage {
        guard currentUserID() == userID else { throw WorkoutHistoryReadError.accountChanged }
        guard (1...200).contains(pageSize) else { throw WorkoutHistoryReadError.invalidCursor }
        if let cursor { try cursor.validate(userID: userID) }
        let collection = sessionLogsCollectionRef(for: userID)
        let upperBound = cursor?.upperBound ?? Date.distantFuture
        var query = collection.whereField("date", isLessThanOrEqualTo: Timestamp(date: upperBound))
            .order(by: "date", descending: true).order(by: FieldPath.documentID(), descending: true)
        if let cursor {
            query = query.start(after: [Timestamp(seconds: cursor.lastSeconds, nanoseconds: cursor.lastNanoseconds),
                                        cursor.lastDocumentID])
        }
        let snapshot = try await query.limit(to: pageSize + 1).getDocuments()
        guard currentUserID() == userID else { throw WorkoutHistoryReadError.accountChanged }
        let documents = Array(snapshot.documents.prefix(pageSize))
        let serverLogs = try documents.map { try decode($0, as: WorkoutSessionLog.self) }
        let visible = try pendingSessions(serverLogs, userID: userID).filter { $0.date <= upperBound }
        var next: WorkoutHistoryCursor?
        if snapshot.documents.count > pageSize, let last = documents.last {
            guard let date = last.data()["date"] as? Timestamp else { throw WorkoutHistoryReadError.invalidCursor }
            next = try WorkoutHistoryCursor(userID: userID, upperBound: upperBound,
                lastSeconds: date.seconds, lastNanoseconds: date.nanoseconds, lastDocumentID: last.documentID)
        }
        return WorkoutHistoryPage(logs: visible, nextCursor: next, isFromCache: snapshot.metadata.isFromCache)
    }

    func fetchWorkoutHistory(userID: String, limit: Int) async throws -> [WorkoutSessionLog] {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs)
            .order(by: "date", descending: true)
            .limit(to: limit)
        let snapshot = try await ref.getDocuments()
        return Array(try pendingSessions(snapshot.documents.map { try decode($0, as: WorkoutSessionLog.self) }, userID: userID).prefix(limit))
    }

    func fetchWorkoutHistory(userID: String, routineID: String, limit: Int) async throws -> [WorkoutSessionLog] {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.workoutSessionLogs)
            .whereField("routineID", isEqualTo: routineID)
            .order(by: "date", descending: true)
            .limit(to: limit)
        let snapshot = try await ref.getDocuments()
        return Array(try pendingSessions(snapshot.documents.map { try decode($0, as: WorkoutSessionLog.self) }, userID: userID)
            .filter { $0.routineID == routineID }.prefix(limit))
    }
}

extension FirestoreWorkoutRepository {
    func fetchLegacyMigrations(userID: String, programID: String) async throws -> [WorkoutLegacyMigrationRecord] {
        guard currentUserID() == userID, !programID.isEmpty, !programID.contains("/") else { throw WorkoutMigrationError.accountChanged }
        let collection = programsCollectionRef(for: userID).document(programID).collection("legacyMigrations")
        var cursor: DocumentSnapshot?
        var records: [WorkoutLegacyMigrationRecord] = []
        while true {
            var query: Query = collection.order(by: FieldPath.documentID()).limit(to: 100)
            if let cursor { query = query.start(afterDocument: cursor) }
            let page = try await query.getDocuments(source: .server)
            guard currentUserID() == userID else { throw WorkoutMigrationError.accountChanged }
            for document in page.documents {
                let record = try document.data(as: WorkoutLegacyMigrationRecord.self)
                try record.validate()
                guard record.userID == userID, record.programID == programID, record.id == document.documentID else { throw WorkoutMigrationError.invalid }
                records.append(record)
            }
            guard page.documents.count == 100, let last = page.documents.last else { break }
            cursor = last
        }
        return records.sorted { $0.recordedAt == $1.recordedAt ? $0.id < $1.id : $0.recordedAt > $1.recordedAt }
    }

    func commitMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, protectedSlots: Set<Int>) async throws -> WorkoutProgram? {
        guard currentUserID() == userID, command.userID == userID else { throw WorkoutMigrationError.accountChanged }
        try command.validate()
        let gate = "\(userID):\(command.programID)"
        try syncQueue.sync {
            guard !editingProgramBlocks.contains(gate),
                  try !outbox.pending(userID: userID).contains(where: { $0.collection == .programs && $0.documentID == command.programID }) else { throw WorkoutBlockError.pendingSync }
            editingProgramBlocks.insert(gate)
        }
        defer { _ = syncQueue.sync { editingProgramBlocks.remove(gate) } }
        switch try await transactMigrationRollback(command, protectedSlots: protectedSlots, cancel: false) {
        case .accepted(let saved): return try overlayBlockProgram(saved, userID: userID, programID: command.programID)
        case .cancelled: throw WorkoutMigrationError.cancelled
        case .pending: throw WorkoutMigrationError.unavailable
        }
    }

    func resolveMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, cancelPending: Bool) async throws -> WorkoutMigrationRollbackResolution {
        guard currentUserID() == userID, command.userID == userID else { throw WorkoutMigrationError.accountChanged }
        if cancelPending {
            let resolution = try await transactMigrationRollback(command, protectedSlots: [], cancel: true)
            if case .accepted(let saved) = resolution {
                return .accepted(try overlayBlockProgram(saved, userID: userID, programID: command.programID))
            }
            return resolution
        }
        let user = db.collection(FirestoreCollection.users).document(userID)
        let document = try await user.collection("programMigrationRollbacks").document(command.id.uuidString).getDocument(source: .server)
        guard currentUserID() == userID else { throw WorkoutMigrationError.accountChanged }
        guard document.exists else { return .pending }
        let receipt = try document.data(as: WorkoutMigrationRollbackReceipt.self); try receipt.validate(command)
        if receipt.status == .cancelled { return .cancelled }
        let saved = try await programsCollectionRef(for: userID).document(command.programID).getDocument(source: .server)
        guard currentUserID() == userID else { throw WorkoutMigrationError.accountChanged }
        return .accepted(try overlayBlockProgram(decodedBlockProgram(saved), userID: userID, programID: command.programID))
    }

    private func transactMigrationRollback(_ command: WorkoutMigrationRollbackCommand, protectedSlots: Set<Int>, cancel: Bool) async throws -> WorkoutMigrationRollbackResolution {
        try command.validate()
        let userID = command.userID
        let user = db.collection(FirestoreCollection.users).document(userID)
        let program = programsCollectionRef(for: userID).document(command.programID)
        let receiptRef = user.collection("programMigrationRollbacks").document(command.id.uuidString)
        let migrationRef = program.collection("legacyMigrations").document(command.migration.id)
        let adoptionRef = user.collection("programBlockOperations").document(command.migration.id)
        let receipt = try WorkoutMigrationRollbackReceipt(command: command, status: cancel ? .cancelled : .accepted)
        let receiptData = try Firestore.Encoder().encode(receipt)
        let result: WorkoutMigrationRollbackResolution = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, pointer -> Any? in
                do {
                    guard self.currentUserID() == userID else { throw WorkoutMigrationError.accountChanged }
                    let previous = try transaction.getDocument(receiptRef)
                    if previous.exists {
                        let stored = try previous.data(as: WorkoutMigrationRollbackReceipt.self); try stored.validate(command)
                        if stored.status == .cancelled { return WorkoutMigrationRollbackResolution.cancelled }
                        return WorkoutMigrationRollbackResolution.accepted(try self.decodedBlockProgram(transaction.getDocument(program)))
                    }
                    if cancel {
                        transaction.setData(receiptData, forDocument: receiptRef)
                        return WorkoutMigrationRollbackResolution.cancelled
                    }
                    let current = try transaction.getDocument(program)
                    let migrationDocument = try transaction.getDocument(migrationRef)
                    let adoptionDocument = try transaction.getDocument(adoptionRef)
                    guard let latest = try self.decodedBlockProgram(current), migrationDocument.exists, adoptionDocument.exists else { throw WorkoutMigrationError.unavailable }
                    let record = try migrationDocument.data(as: WorkoutLegacyMigrationRecord.self)
                    let adoption = try adoptionDocument.data(as: WorkoutBlockOperationReceipt.self)
                    guard adoption.status == .accepted, let acceptedRecord = adoption.legacyMigration,
                          try acceptedRecord.fingerprint == record.fingerprint else { throw WorkoutMigrationError.changed }
                    let restored = try WorkoutMigrationRollbackRules.applying(command, to: latest, record: record, protectedSlots: protectedSlots)
                    transaction.updateData(["trainingBlock": FieldValue.delete()], forDocument: program)
                    transaction.updateData(["restoredByOperationID": command.id.uuidString], forDocument: migrationRef)
                    transaction.setData(receiptData, forDocument: receiptRef)
                    return WorkoutMigrationRollbackResolution.accepted(restored)
                } catch { pointer?.pointee = error as NSError; return nil }
            }) { value, error in
                if let error {
                    let failure = error as NSError
                    if failure.domain == WorkoutMigrationError.errorDomain, let typed = WorkoutMigrationError(rawValue: failure.code) { continuation.resume(throwing: typed) } else { continuation.resume(throwing: error) }
                } else if let value = value as? WorkoutMigrationRollbackResolution { continuation.resume(returning: value) } else { continuation.resume(throwing: WorkoutMigrationError.unavailable) }
            }
        }
        guard currentUserID() == userID else { throw WorkoutMigrationError.accountChanged }
        notify(userID: userID, changed: true)
        return result
    }
}

private final class WorkoutListenerHandle {
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
}
