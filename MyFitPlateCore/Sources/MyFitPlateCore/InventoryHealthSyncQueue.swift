import Combine
import Foundation

/// Accepted stock/diary receipts and Health are separate durability boundaries. This
/// queue owns only operation-specific inventory exports, never unrelated Health samples.
@MainActor
public final class InventoryHealthSyncQueue: ObservableObject {
    public static let shared = InventoryHealthSyncQueue()
    public typealias Reader = (DiaryDayContext, @escaping (Result<DailyLog, Error>) -> Void) -> Void
    private struct Job: Codable {
        let operationID: UUID
        let food: FoodItem
        var day: DiaryDayContext
        var mealName: String
        var desiredPresent: Bool
        var attemptedSave = false
        var saveAcknowledged = false
        var complete = false
    }
    private struct Checkpoint: Codable {
        let userID: String
        var jobs: [Job]
    }
    @Published public private(set) var pendingCount = 0
    @Published public private(set) var message: String?
    @Published public private(set) var isWorking = false
    private let store: EditorDraftStore
    private let healthKit: HealthKitManaging
    private let currentUserID: () -> String?
    private let read: Reader
    private let scope = "inventory-health-projection"
    private var values: [String: Checkpoint] = [:]
    private var unreadable = Set<String>()
    private var workers: [String: Task<Void, Never>] = [:]
    private var activeUserID: String?

    public init(store: EditorDraftStore = EditorDraftStore(), healthKit: HealthKitManaging = HealthKitManager.shared,
                currentUserID: (() -> String?)? = nil, reader: Reader? = nil) {
        self.store = store; self.healthKit = healthKit
        self.currentUserID = currentUserID ?? { DIContainer.shared.authService.currentUserID }
        read = reader ?? { day, completion in DIContainer.shared.nutritionRepository.fetchLogInternal(userID: day.userID, day: day, completion: completion) }
    }
    public func activateAccount(_ userID: String?) {
        activeUserID = userID
        guard let userID, currentUserID() == userID else { refreshStatus(); return }
        _ = load(userID)
        if let accepted = try? store.load(InventoryCheckpoint.self, userID: userID, scope: InventorySaveSession.scope)?.value,
           accepted.accepted { _ = enqueue(accepted.mutation) }
        retry(userID: userID)
    }
    @discardableResult
    public func enqueue(_ mutation: InventoryMutation) -> Bool {
        guard currentUserID() == mutation.userID else { return false }
        guard let patch = mutation.diary else { return true }
        activeUserID = mutation.userID
        guard var next = load(mutation.userID) else { return false }
        let targetID: UUID
        let food: FoodItem
        let present: Bool
        if let desired = patch.desired, patch.expected == nil {
            targetID = mutation.id; food = desired; present = true
        } else if let expected = patch.expected, patch.desired == nil, let original = mutation.undoing {
            targetID = original; food = expected; present = false
        } else { return false }
        if let index = next.jobs.firstIndex(where: { $0.operationID == targetID }) {
            guard (try? InventorySnapshotRules.fingerprint(next.jobs[index].food)) == (try? InventorySnapshotRules.fingerprint(food)) else { return false }
            if !present, next.jobs[index].desiredPresent {
                next.jobs[index].desiredPresent = false; next.jobs[index].complete = false
            }
            // Accepted old-consume replay cannot resurrect an already-undone export.
        } else {
            var job = Job(operationID: targetID, food: food, day: patch.day, mealName: patch.mealName, desiredPresent: present)
            if !present { job.attemptedSave = true } // Undo may arrive on another device after an earlier export.
            next.jobs.append(job)
        }
        guard persist(next) else { return false }
        retry(userID: mutation.userID); return true
    }
    public func retry(userID: String) {
        guard currentUserID() == userID, load(userID) != nil else { return }
        activeUserID = userID
        guard workers[userID] == nil else { refreshStatus(); return }
        workers[userID] = Task { [weak self] in await self?.run(userID) }
        refreshStatus()
    }
    /// MOVE changes where to verify an existing sample, not its original nutrition time.
    public func reconcileMove(_ result: DiaryTransferResult, userID: String) {
        guard result.receipt.command.mode == .move, currentUserID() == userID,
              result.receipt.command.userID == userID,
              var next = load(userID) else { return }
        let undo = result.receipt.undoneAt != nil
        let canonical = undo ? result.sourceLog : result.destinationLog
        for placement in result.receipt.placements {
            let name = undo ? placement.originalMealName : placement.destinationMealName
            guard canonical.meals.filter({ $0.name.caseInsensitiveCompare(name) == .orderedSame })
                .flatMap(\.foodItems).contains(where: { $0.id == placement.destinationFood.id }) else { continue }
            for index in next.jobs.indices where next.jobs[index].food.id == placement.destinationFood.id {
                next.jobs[index].day = undo ? result.receipt.command.source : result.receipt.command.destination
                next.jobs[index].mealName = undo ? placement.originalMealName : placement.destinationMealName
            }
        }
        if persist(next) { retry(userID: userID) }
    }
    private func run(_ userID: String) async {
        defer { workers[userID] = nil; refreshStatus() }
        while currentUserID() == userID, let checkpoint = values[userID],
              let index = checkpoint.jobs.firstIndex(where: { !$0.complete }) {
            let job = checkpoint.jobs[index]
            if !job.desiredPresent {
                if !job.attemptedSave {
                    guard update(userID, id: job.operationID, { $0.complete = true }) else { return }
                    continue
                }
                let deleted = await withCheckedContinuation { continuation in
                    healthKit.deleteInventoryNutrition(for: job.food, userID: userID, operationID: job.operationID) { continuation.resume(returning: $0) }
                }
                guard currentUserID() == userID else { return }
                guard deleted else { message = "Food and stock are saved. Apple Health cleanup is pending; retry after checking Health access."; return }
                guard update(userID, id: job.operationID, { $0.complete = true }) else { return }
                continue
            }
            let matches: Bool
            do { matches = try await matchesDiary(job) } catch {
                message = "Food and stock are saved. Apple Health sync is pending until the diary can be checked."; return
            }
            guard currentUserID() == userID else { return }
            guard let latest = values[userID]?.jobs.first(where: { $0.operationID == job.operationID }) else { return }
            if !latest.desiredPresent || latest.day != job.day || latest.mealName != job.mealName { continue }
            if !matches {
                if job.attemptedSave {
                    guard update(userID, id: job.operationID, { $0.desiredPresent = false }) else { return }
                } else { guard update(userID, id: job.operationID, { $0.complete = true }) else { return } }
                continue
            }
            if job.saveAcknowledged {
                guard update(userID, id: job.operationID, { if $0.desiredPresent { $0.complete = true } }) else { return }
                continue
            }
            guard healthKit.canSaveInventoryNutrition(for: job.food, userID: userID, operationID: job.operationID) else {
                message = "Food and stock are saved. Apple Health sync is pending until nutrition sharing is available."; return
            }
            guard update(userID, id: job.operationID, { $0.attemptedSave = true }) else { return }
            let saved = await withCheckedContinuation { continuation in
                healthKit.saveInventoryNutrition(for: job.food, userID: userID, operationID: job.operationID) { continuation.resume(returning: $0) }
            }
            guard currentUserID() == userID else { return }
            guard saved else {
                if values[userID]?.jobs.first(where: { $0.operationID == job.operationID })?.desiredPresent == false { continue }
                message = "Food and stock are saved. Apple Health export needs retry."; return
            }
            guard update(userID, id: job.operationID, { $0.saveAcknowledged = true }) else { return }
            guard let current = values[userID]?.jobs.first(where: { $0.operationID == job.operationID }) else { return }
            if !current.desiredPresent { continue }
            do {
                if try await matchesDiary(current) {
                    guard update(userID, id: job.operationID, { if $0.desiredPresent { $0.complete = true } }) else { return }
                } else { guard update(userID, id: job.operationID, { $0.desiredPresent = false }) else { return } }
            } catch { message = "Food and stock are saved. Apple Health needs a diary readback before export is confirmed."; return }
        }
        message = nil
    }
    private func matchesDiary(_ job: Job) async throws -> Bool {
        let log: DailyLog = try await withCheckedThrowingContinuation { continuation in read(job.day) { continuation.resume(with: $0) } }
        let matching = log.meals.filter { $0.name.caseInsensitiveCompare(job.mealName) == .orderedSame }
            .flatMap(\.foodItems).filter { $0.id == job.food.id }
        guard matching.count == 1 else { return false }
        return try InventorySnapshotRules.fingerprint(matching[0]) == InventorySnapshotRules.fingerprint(job.food)
    }
    private func update(_ userID: String, id: UUID, _ mutate: (inout Job) -> Void) -> Bool {
        guard var next = values[userID], let index = next.jobs.firstIndex(where: { $0.operationID == id }) else { return false }
        mutate(&next.jobs[index]); return persist(next)
    }
    private func load(_ userID: String) -> Checkpoint? {
        guard currentUserID() == userID, !unreadable.contains(userID) else { return nil }
        if let existing = values[userID] { return existing }
        do {
            let value = try store.load(Checkpoint.self, userID: userID, scope: scope)?.value ?? Checkpoint(userID: userID, jobs: [])
            guard value.userID == userID, Set(value.jobs.map(\.operationID)).count == value.jobs.count,
                  value.jobs.allSatisfy({ $0.day.userID == userID && !$0.food.id.isEmpty }) else { throw InventoryError.invalid }
            values[userID] = value; return value
        } catch { unreadable.insert(userID); message = "Food and stock are saved. Previous inventory Health sync is kept on this device and needs recovery."; return nil }
    }
    private func persist(_ value: Checkpoint) -> Bool {
        guard currentUserID() == value.userID, !unreadable.contains(value.userID) else { return false }
        do { try store.save(value, userID: value.userID, scope: scope); values[value.userID] = value; refreshStatus(); return true } catch {
            message = "Food and stock are saved. The Health sync intent could not be kept; leave its stock receipt available and retry."; return false
        }
    }
    private func refreshStatus() {
        guard let user = activeUserID, user == currentUserID() else { pendingCount = 0; isWorking = false; return }
        pendingCount = values[user]?.jobs.filter { !$0.complete }.count ?? 0
        isWorking = workers[user] != nil
    }
}
