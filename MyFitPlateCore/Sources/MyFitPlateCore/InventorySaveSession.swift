import Combine
import Foundation

public struct InventoryCheckpoint: Codable {
    public let mutation: InventoryMutation
    public var submitted = false
    public var accepted = false
    public var cancelled = false
    public var trainingFuelTarget: TrainingFuelTarget?
    public init(_ mutation: InventoryMutation) { self.mutation = mutation }
}

@MainActor
public final class InventorySaveSession: ObservableObject, Identifiable {
    public static let scope = "inventory-operation-review"
    public let id = UUID()
    public let userID: String?
    @Published public private(set) var checkpoint: InventoryCheckpoint?
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isUnreadable = false
    private let store: EditorDraftStore
    private let enqueueHealth: (InventoryMutation) -> Bool
    private var expectedFingerprint: String?

    public init(userID: String?, store: EditorDraftStore = EditorDraftStore(), enqueueHealth: ((InventoryMutation) -> Bool)? = nil) {
        self.userID = userID; self.store = store
        self.enqueueHealth = enqueueHealth ?? { InventoryHealthSyncQueue.shared.enqueue($0) }
        guard let userID, DIContainer.shared.authService.currentUserID == userID else { return }
        do {
            if let saved = try store.load(InventoryCheckpoint.self, userID: userID, scope: Self.scope) {
                try saved.value.mutation.validate()
                guard saved.value.mutation.userID == userID else { throw InventoryError.accountChanged }
                checkpoint = saved.value
                expectedFingerprint = try PlanFingerprint.make(saved.value)
            }
        } catch { isUnreadable = true; errorMessage = "Your previous stock review couldn't be read. It is kept on this device; use a compatible version to recover it." }
    }

    @discardableResult
    public func prepare(_ mutation: InventoryMutation, trainingFuelTarget: TrainingFuelTarget? = nil) -> Bool {
        guard canUseAccount, !isWorking, checkpoint == nil, let userID, mutation.userID == userID else { return false }
        do {
            try mutation.validate()
            if let old = try store.load(InventoryCheckpoint.self, userID: userID, scope: Self.scope) {
                checkpoint = old.value; expectedFingerprint = try PlanFingerprint.make(old.value)
                errorMessage = "Finish the stock review already kept on this device before starting another."; return false
            }
            var checkpoint = InventoryCheckpoint(mutation); checkpoint.trainingFuelTarget = trainingFuelTarget
            return persist(checkpoint)
        } catch { errorMessage = "Couldn't keep this stock review on the device. Your fields are still here."; return false }
    }

    @discardableResult public func removeFuelContext() -> Bool {
        guard canUseAccount, !isWorking, var next = checkpoint, !next.submitted, !next.accepted, !next.cancelled else { return false }
        next.trainingFuelTarget = nil
        return persist(next)
    }

    public func save(using repository: NutritionRepositoryProtocol, dailyLogService: DailyLogService? = nil) async {
        guard canUseAccount, !isWorking, let userID, var value = checkpoint, !value.accepted, !value.cancelled else { return }
        if !value.submitted, let target = value.trainingFuelTarget, let diary = value.mutation.diary, let food = diary.desired {
            do {
                guard let dailyLogService, let fuel = dailyLogService.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.stageFoodLink(target: target, foods: [food], date: diary.day.originalDate, using: dailyLogService, userID: userID)
            } catch { errorMessage = error.localizedDescription; return }
        }
        value.submitted = true
        guard persist(value) else { return }
        if let target = value.trainingFuelTarget, let food = value.mutation.diary?.desired {
            do {
                guard let fuel = dailyLogService?.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.authorizeFoodLink(target: target, foods: [food], userID: userID)
            } catch { errorMessage = "Could not prepare the saved fuel link. Retry this review; no new food or stock change was sent."; return }
        }
        isWorking = true; defer { isWorking = false }
        do {
            try await repository.applyInventoryMutation(userID: userID, mutation: value.mutation)
            guard canUseAccount else { throw InventoryError.accountChanged }
            value.accepted = true
            linkAcceptedFuel(value, using: dailyLogService)
            if persist(value), !enqueueHealth(value.mutation) { errorMessage = "Food and stock are saved. Their Health sync intent needs retry; this receipt has been kept." }
        } catch {
            errorMessage = "This exact stock review is kept. Check its saved status or retry. \(error.localizedDescription)"
        }
    }

    public func resolve(using repository: NutritionRepositoryProtocol, cancelPending: Bool, dailyLogService: DailyLogService? = nil) async {
        guard canUseAccount, !isWorking, let userID, var value = checkpoint else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let result = try await repository.resolveInventoryMutation(userID: userID, mutation: value.mutation, cancelPending: cancelPending)
            guard canUseAccount else { throw InventoryError.accountChanged }
            switch result {
            case .accepted:
                value.accepted = true; value.cancelled = false
                linkAcceptedFuel(value, using: dailyLogService)
                if persist(value), !enqueueHealth(value.mutation) { errorMessage = "Food and stock are saved. Their Health sync intent needs retry; this receipt has been kept." }
            case .cancelled: value.cancelled = true; value.accepted = false; _ = persist(value)
            case .pending: errorMessage = "No saved receipt yet. Retry this same operation, or cancel its pending save before making a new review."
            }
        } catch { errorMessage = "Couldn't confirm this stock operation yet. Its review is kept." }
    }

    @discardableResult
    public func finish() -> Bool {
        guard canUseAccount, !isWorking, let value = checkpoint,
              value.accepted || value.cancelled || !value.submitted, let userID else { return false }
        do {
            if value.accepted, !enqueueHealth(value.mutation) {
                errorMessage = "The account save is complete. Keep this receipt until its Health sync intent can be checkpointed."; return false
            }
            guard let expectedFingerprint,
                  try store.removeIfUnchanged(InventoryCheckpoint.self, userID: userID, scope: Self.scope,
                      fingerprint: expectedFingerprint) else { throw InventoryError.changed }
            checkpoint = nil; self.expectedFingerprint = nil; return true
        } catch { errorMessage = "The stock receipt is kept until it can be closed. Try again."; return false }
    }

    private func linkAcceptedFuel(_ value: InventoryCheckpoint, using service: DailyLogService?) {
        guard value.accepted, let target = value.trainingFuelTarget, let food = value.mutation.diary?.desired,
              let userID else { return }
        _ = service?.trainingFuelPlanStore?.acceptFoodLink(target: target, foods: [food], userID: userID)
    }

    private var canUseAccount: Bool { !isUnreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID }
    private func persist(_ value: InventoryCheckpoint) -> Bool {
        guard canUseAccount, let userID else { return false }
        do {
            let current = try store.load(InventoryCheckpoint.self, userID: userID, scope: Self.scope)
            guard try current.map({ try PlanFingerprint.make($0.value) }) == expectedFingerprint,
                  current.map({ $0.value.mutation.id == value.mutation.id }) != false else { throw InventoryError.changed }
            try store.save(value, userID: userID, scope: Self.scope)
            checkpoint = value; expectedFingerprint = try PlanFingerprint.make(value); errorMessage = nil; return true
        } catch { errorMessage = "Couldn't keep this stock change on the device. The last review remains intact."; return false }
    }
}
