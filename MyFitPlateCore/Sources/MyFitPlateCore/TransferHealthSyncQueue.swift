import Combine
import Foundation

public struct TransferHealthSyncStatus: Equatable {
    public let pendingCount: Int
    public let isWorking: Bool
    public let message: String?
}

/// A local durable side-effect queue. Diary acceptance never depends on Health permission.
/// Fresh COPY samples use HealthKit sync identities; MOVE only relocates existing copy checks. A single
/// account worker orders save callbacks before Undo deletion, including after a crash.
@MainActor
public final class TransferHealthSyncQueue: ObservableObject {
    public static let shared = TransferHealthSyncQueue()
    public typealias DestinationReader = (DiaryDayContext, @escaping (Result<DailyLog, Error>) -> Void) -> Void

    private struct PlacementOverride: Codable, Equatable {
        let moveID: UUID
        let undoneAt: Date?
        let day: DiaryDayContext
        let mealID: UUID
        let mealName: String
    }
    private struct Job: Codable {
        let operationID: UUID
        let foodID: String
        var desiredPresent: Bool
        var attemptedSave = false
        var saveAcknowledged = false
        var deleteAcknowledged = false
        var placementOverride: PlacementOverride?
        var requiresPlacementEvidence: Bool?
        var isPending: Bool { desiredPresent ? !saveAcknowledged || requiresPlacementEvidence == true : !deleteAcknowledged }
    }
    private struct Checkpoint: Codable {
        let userID: String
        var receipts: [DiaryTransferReceipt] = []
        var jobs: [Job] = []
        var moves: [DiaryTransferReceipt]?
    }

    @Published public private(set) var status = TransferHealthSyncStatus(pendingCount: 0, isWorking: false, message: nil)
    private let store: EditorDraftStore
    private let healthKit: HealthKitManaging
    private let currentUserID: () -> String?
    private let readDestination: DestinationReader
    private let scope = "diary-transfer-health"
    private var activeUserID: String?
    private var checkpoints: [String: Checkpoint] = [:]
    private var unreadableAccounts = Set<String>()
    private var workers: [String: Task<Void, Never>] = [:]
    private var errors: [String: String] = [:]

    public init(store: EditorDraftStore = EditorDraftStore(), healthKit: HealthKitManaging = HealthKitManager.shared,
                currentUserID: (() -> String?)? = nil, readDestination: DestinationReader? = nil) {
        self.store = store; self.healthKit = healthKit
        self.currentUserID = currentUserID ?? { DIContainer.shared.authService.currentUserID }
        self.readDestination = readDestination ?? { day, completion in
            DIContainer.shared.nutritionRepository.fetchLogInternal(userID: day.userID, day: day, completion: completion)
        }
    }

    public func activateAccount(_ userID: String?) {
        activeUserID = userID
        guard let userID, currentUserID() == userID else { refreshStatus(); return }
        _ = load(userID)
        retryPending(userID: userID)
    }

    /// Returns only whether the Health side-effect intent was checkpointed locally. The
    /// caller must retain its accepted diary receipt and must not roll back diary acceptance.
    @discardableResult
    public func reconcile(result: DiaryTransferResult, userID: String) -> Bool {
        guard currentUserID() == userID, result.receipt.command.userID == userID else { return false }
        activeUserID = userID
        if result.receipt.command.mode == .move { return reconcileMove(result: result, userID: userID) }
        do {
            try result.receipt.validate()
            let command = result.receipt.command
            guard result.destinationLog.id == command.destination.dayKey,
                  result.sourceLog.id == command.source.dayKey, var next = load(userID) else { return false }
            guard !(next.moves ?? []).contains(where: { $0.id == result.receipt.id }) else { throw DiaryTransferError.receiptMismatch }
            if let prior = next.receipts.first(where: { $0.id == result.receipt.id }) {
                guard prior.commandFingerprint == result.receipt.commandFingerprint else { throw DiaryTransferError.receiptMismatch }
                // An older accepted response cannot resurrect an already-undone copy.
                if prior.undoneAt != nil && result.receipt.undoneAt == nil {
                    guard persist(next) else { return false }
                    startWorker(userID); return true
                }
                next.receipts.removeAll { $0.id == prior.id }
            }
            next.receipts.append(result.receipt)
            for placement in result.receipt.placements {
                let matchingJob = next.jobs.firstIndex { $0.foodID == placement.destinationFood.id }
                if let matchingJob, next.jobs[matchingJob].operationID != result.receipt.id { throw DiaryTransferError.receiptMismatch }
                let shouldExist = result.receipt.undoneAt == nil && Self.contains(placement, in: result.destinationLog)
                if let matchingJob {
                    // A COPY replay still reads its original destination. A later MOVE
                    // owns the verification location until it is itself undone.
                    // Absence alone may be an unreported MOVE from another client or
                    // an acknowledgement lost before its location was checkpointed.
                    // Only an explicit Undo authorizes cleanup here.
                    if result.receipt.undoneAt != nil {
                        next.jobs[matchingJob].desiredPresent = false
                    } else if shouldExist {
                        next.jobs[matchingJob].requiresPlacementEvidence = false
                    }
                } else {
                    var job = Job(operationID: result.receipt.id, foodID: placement.destinationFood.id,
                                  desiredPresent: result.receipt.undoneAt == nil)
                    job.requiresPlacementEvidence = result.receipt.undoneAt == nil && !shouldExist
                    next.jobs.append(job)
                }
            }
            guard persist(next) else { return false }
            errors[userID] = nil
            startWorker(userID)
            return true
        } catch {
            errors[userID] = "Food was saved. Apple Health sync is pending because its copy receipt couldn't be verified."
            refreshStatus(); return false
        }
    }

    private func reconcileMove(result: DiaryTransferResult, userID: String) -> Bool {
        do {
            try result.receipt.validate()
            let command = result.receipt.command
            guard result.sourceLog.id == command.source.dayKey, result.destinationLog.id == command.destination.dayKey,
                  var next = load(userID) else { return false }
            let affected = next.jobs.indices.filter { index in
                next.jobs[index].desiredPresent && result.receipt.placements.contains { $0.destinationFood.id == next.jobs[index].foodID }
            }
            // A normal MOVE has no nutrition export or cleanup of its own.
            guard !affected.isEmpty else { refreshStatus(); return true }
            guard !next.receipts.contains(where: { $0.id == result.receipt.id }) else { throw DiaryTransferError.receiptMismatch }
            if let previous = next.moves?.first(where: { $0.id == result.receipt.id }) {
                guard previous.commandFingerprint == result.receipt.commandFingerprint else { throw DiaryTransferError.receiptMismatch }
                if previous.undoneAt != nil && result.receipt.undoneAt == nil {
                    guard persist(next) else { return false }
                    startWorker(userID); return true
                }
                // Replaying an old MOVE must not replace a newer MOVE's placement.
                if previous.undoneAt == result.receipt.undoneAt {
                    guard persist(next) else { return false }
                    startWorker(userID); return true
                }
            }
            var updated = false
            for index in affected {
                let job = next.jobs[index]
                guard let copy = next.receipts.first(where: { $0.id == job.operationID }),
                      let original = copy.placements.first(where: { $0.destinationFood.id == job.foodID }),
                      let moved = result.receipt.placements.first(where: { $0.destinationFood.id == job.foodID }),
                      FoodEditPrecondition.sameSnapshot(original.destinationFood, moved.originalFood) else { continue }
                let location = Self.override(for: result.receipt, placement: moved)
                let current = result.receipt.undoneAt == nil ? result.destinationLog : result.sourceLog
                guard Self.contains(original.destinationFood, mealID: location.mealID, mealName: location.mealName, in: current) else { continue }
                next.jobs[index].placementOverride = location
                next.jobs[index].requiresPlacementEvidence = false
                updated = true
            }
            guard updated else { refreshStatus(); return true }
            // A receipt's Undo phase also updates references on cancelled jobs. Their
            // cleanup remains terminal, but its persisted receipt must stay consistent.
            for index in next.jobs.indices where next.jobs[index].placementOverride?.moveID == result.receipt.id {
                if let placement = result.receipt.placements.first(where: { $0.destinationFood.id == next.jobs[index].foodID }) {
                    next.jobs[index].placementOverride = Self.override(for: result.receipt, placement: placement)
                }
            }
            next.moves = (next.moves ?? []).filter { $0.id != result.receipt.id } + [result.receipt]
            guard persist(next) else { return false }
            errors[userID] = nil
            startWorker(userID)
            return true
        } catch {
            errors[userID] = "The diary move was saved. Apple Health sync is pending because its copied entry couldn't be verified."
            refreshStatus(); return false
        }
    }

    private static func override(for receipt: DiaryTransferReceipt, placement: DiaryTransferReceipt.Placement) -> PlacementOverride {
        let undone = receipt.undoneAt != nil
        return PlacementOverride(moveID: receipt.id, undoneAt: receipt.undoneAt,
            day: undone ? receipt.command.source : receipt.command.destination,
            mealID: undone ? placement.originalMealID : placement.destinationMealID,
            mealName: undone ? placement.originalMealName : placement.destinationMealName)
    }

    public func retryPending(userID: String) {
        guard currentUserID() == userID else { return }
        activeUserID = userID
        guard load(userID) != nil else { return }
        if checkpoints[userID]?.jobs.contains(where: \.isPending) == true { errors[userID] = nil }
        startWorker(userID)
    }

    /// Call before a normal edit/delete's legacy Health side effect. This owns only
    /// already-known copied samples, so a late initial copy save cannot reappear after
    /// the edit/delete. Replacement samples without the copied marker stay untouched.
    @discardableResult
    public func invalidateCopiedFoods(ids: Set<String>, userID: String) -> Bool {
        guard currentUserID() == userID, var next = load(userID) else { return false }
        activeUserID = userID
        guard next.jobs.contains(where: { ids.contains($0.foodID) && $0.desiredPresent }) else { return true }
        for index in next.jobs.indices where ids.contains(next.jobs[index].foodID) {
            next.jobs[index].desiredPresent = false
        }
        guard persist(next) else { return false }
        errors[userID] = nil
        startWorker(userID)
        return true
    }

    private static func contains(_ placement: DiaryTransferReceipt.Placement, in log: DailyLog) -> Bool {
        contains(placement.destinationFood, mealID: placement.destinationMealID, mealName: placement.destinationMealName, in: log)
    }

    private static func contains(_ food: FoodItem, mealID: UUID, mealName: String, in log: DailyLog) -> Bool {
        let matches = log.meals.flatMap { meal in
            meal.foodItems.filter { $0.id == food.id }.map { (meal, $0) }
        }
        return matches.count == 1 && matches[0].0.id == mealID && matches[0].0.name == mealName
            && FoodEditPrecondition.sameSnapshot(matches[0].1, food)
    }

    private func load(_ userID: String) -> Checkpoint? {
        guard !unreadableAccounts.contains(userID) else { return nil }
        if let existing = checkpoints[userID] { return existing }
        do {
            let value = try store.load(Checkpoint.self, userID: userID, scope: scope)?.value ?? Checkpoint(userID: userID)
            try validate(value)
            checkpoints[userID] = value
            return value
        } catch {
            unreadableAccounts.insert(userID)
            errors[userID] = "Food was saved. The Apple Health sync checkpoint couldn't be opened and has been kept unchanged."
            refreshStatus(); return nil
        }
    }

    private func validate(_ checkpoint: Checkpoint) throws {
        guard Set(checkpoint.receipts.map(\.id)).count == checkpoint.receipts.count,
              Set(checkpoint.jobs.map(\.foodID)).count == checkpoint.jobs.count,
              Set((checkpoint.moves ?? []).map(\.id) + checkpoint.receipts.map(\.id)).count == (checkpoint.moves?.count ?? 0) + checkpoint.receipts.count else {
            throw DiaryTransferError.receiptMismatch
        }
        for receipt in checkpoint.receipts {
            try receipt.validate()
            guard receipt.command.userID == checkpoint.userID, receipt.command.mode == .copy else { throw DiaryTransferError.receiptMismatch }
        }
        for move in checkpoint.moves ?? [] {
            try move.validate()
            guard move.command.userID == checkpoint.userID, move.command.mode == .move else { throw DiaryTransferError.receiptMismatch }
        }
        for job in checkpoint.jobs {
            guard let receipt = checkpoint.receipts.first(where: { $0.id == job.operationID }),
                  receipt.placements.contains(where: { $0.destinationFood.id == job.foodID }),
                  receipt.undoneAt == nil || !job.desiredPresent else { throw DiaryTransferError.receiptMismatch }
            if let location = job.placementOverride {
                guard let move = checkpoint.moves?.first(where: { $0.id == location.moveID }),
                      let moved = move.placements.first(where: { $0.destinationFood.id == job.foodID }),
                      let copied = receipt.placements.first(where: { $0.destinationFood.id == job.foodID }),
                      FoodEditPrecondition.sameSnapshot(copied.destinationFood, moved.originalFood),
                      location == Self.override(for: move, placement: moved) else { throw DiaryTransferError.receiptMismatch }
            }
        }
    }

    @discardableResult
    private func persist(_ checkpoint: Checkpoint) -> Bool {
        do {
            try validate(checkpoint)
            // Keep the most recent intent visible to an already-running callback even
            // if storage fails. No subsequent Health command starts until it is durable.
            checkpoints[checkpoint.userID] = checkpoint
            try store.save(checkpoint, userID: checkpoint.userID, scope: scope)
            refreshStatus(); return true
        } catch {
            errors[checkpoint.userID] = "Food was saved. Apple Health sync is pending until its checkpoint can be saved on this device."
            refreshStatus(); return false
        }
    }

    private func startWorker(_ userID: String) {
        guard currentUserID() == userID, workers[userID] == nil, !unreadableAccounts.contains(userID),
              checkpoints[userID]?.jobs.contains(where: \.isPending) == true else { refreshStatus(); return }
        guard let checkpoint = checkpoints[userID], persist(checkpoint) else { return }
        workers[userID] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.process(userID)
            self.workers[userID] = nil
            self.refreshStatus()
        }
        refreshStatus()
    }

    private func process(_ userID: String) async {
        while currentUserID() == userID, let checkpoint = checkpoints[userID],
              let job = checkpoint.jobs.first(where: \.isPending),
              let receipt = checkpoint.receipts.first(where: { $0.id == job.operationID }),
              let placement = receipt.placements.first(where: { $0.destinationFood.id == job.foodID }) {
            if job.desiredPresent {
                guard job.requiresPlacementEvidence != true else {
                    errors[userID] = "Apple Health sync is pending because the copied diary entry couldn't be confirmed. Review your food changes, then retry."
                    return
                }
                guard healthKit.canSaveCopiedNutrition(for: placement.destinationFood) else {
                    errors[userID] = "Food was saved. Apple Health sync is pending; allow nutrition access in Health to continue."
                    return
                }
                let expectedDay = job.placementOverride?.day ?? receipt.command.destination
                let expectedMealID = job.placementOverride?.mealID ?? placement.destinationMealID
                let expectedMealName = job.placementOverride?.mealName ?? placement.destinationMealName
                let latest: Result<DailyLog, Error> = await withCheckedContinuation { continuation in
                    readDestination(expectedDay) { continuation.resume(returning: $0) }
                }
                guard currentUserID() == userID else { return }
                // Undo or MOVE may have arrived while this location was being read.
                guard var next = checkpoints[userID], let index = next.jobs.firstIndex(where: { $0.foodID == job.foodID }) else { return }
                if !next.jobs[index].desiredPresent { continue }
                guard next.jobs[index].placementOverride == job.placementOverride else { continue }
                guard case .success(let log) = latest, log.id == expectedDay.dayKey else {
                    errors[userID] = "Food was saved. Apple Health sync is waiting to verify the copied diary entry."
                    return
                }
                if !Self.contains(placement.destinationFood, mealID: expectedMealID, mealName: expectedMealName, in: log) {
                    errors[userID] = "Apple Health sync is pending because the copied diary entry couldn't be confirmed. Review your food changes, then retry."
                    return
                }
                next.jobs[index].attemptedSave = true
                guard persist(next) else { return }
                guard currentUserID() == userID else { return }
                let success: Bool = await withCheckedContinuation { continuation in
                    healthKit.saveCopiedNutrition(for: placement.destinationFood, userID: userID) { continuation.resume(returning: $0) }
                }
                // Record the callback for its original account, even if it signed out.
                guard var completed = checkpoints[userID], let index = completed.jobs.firstIndex(where: { $0.foodID == job.foodID }) else { return }
                if success { completed.jobs[index].saveAcknowledged = true }
                guard persist(completed) else { return }
                if !success && completed.jobs[index].desiredPresent {
                    errors[userID] = "Food was saved. Apple Health couldn't sync its copy yet; retry when access is available."
                    return
                }
            } else {
                let success: Bool = await withCheckedContinuation { continuation in
                    healthKit.deleteCopiedNutrition(for: placement.destinationFood, userID: userID) { continuation.resume(returning: $0) }
                }
                guard var completed = checkpoints[userID], let index = completed.jobs.firstIndex(where: { $0.foodID == job.foodID }) else { return }
                if success { completed.jobs[index].deleteAcknowledged = true }
                guard persist(completed) else { return }
                if !success {
                    errors[userID] = "Undo was saved. Apple Health cleanup is pending; retry when access is available."
                    return
                }
            }
        }
    }

    private func refreshStatus() {
        guard let activeUserID, currentUserID() == activeUserID else {
            status = TransferHealthSyncStatus(pendingCount: 0, isWorking: false, message: nil); return
        }
        let count = checkpoints[activeUserID]?.jobs.filter(\.isPending).count ?? 0
        status = TransferHealthSyncStatus(pendingCount: count, isWorking: workers[activeUserID] != nil,
            message: errors[activeUserID] ?? (count > 0 ? "Food was saved. Apple Health sync is pending." : nil))
    }
}
