import Foundation
import Combine

public enum BarcodeBatchResolution: String, Codable { case pending, resolving, found, unmatched, skipped }
public struct BarcodeBatchEntry: Codable, Identifiable {
    public var id: String
    public var code: String
    public var resolution: BarcodeBatchResolution
    public var food: FoodItem?
    public var included: Bool
    public var isRepeatedScan: Bool
}
public struct RapidBarcodeBatchCheckpoint: Codable, Identifiable {
    public let id: UUID
    public let date: Date
    public let mealName: String
    public var entries: [BarcodeBatchEntry]
    public var isSubmitted: Bool
    public var isAccepted: Bool
    public var trainingFuelTarget: TrainingFuelTarget?
}

@MainActor
public final class RapidBarcodeBatchSession: ObservableObject {
    @Published public private(set) var checkpoint: RapidBarcodeBatchCheckpoint
    @Published public private(set) var isResolving = false
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    public let userID: String?
    private let store: EditorDraftStore
    private var unreadable = false
    private static let scope = "rapid-barcode-batch"
    public var foundCount: Int { checkpoint.entries.filter { $0.resolution == .found }.count }
    public var includedFoods: [FoodItem] { checkpoint.entries.filter { $0.resolution == .found && $0.included }.compactMap(\.food) }
    public var unresolvedCount: Int { checkpoint.entries.filter { [.pending, .resolving, .unmatched].contains($0.resolution) }.count }
    public var leftOutCount: Int { checkpoint.entries.count - includedFoods.count - unresolvedCount }

    public static func pending(userID: String?, store: EditorDraftStore = EditorDraftStore()) -> RapidBarcodeBatchCheckpoint? {
        guard let userID else { return nil }
        return try? store.load(RapidBarcodeBatchCheckpoint.self, userID: userID, scope: scope)?.value
    }

    public init(userID: String?, date: Date, mealName: String, store: EditorDraftStore = EditorDraftStore(), trainingFuelTarget: TrainingFuelTarget? = nil) {
        self.userID = userID; self.store = store
        checkpoint = RapidBarcodeBatchCheckpoint(id: UUID(), date: Calendar.current.startOfDay(for: date), mealName: mealName,
            entries: [], isSubmitted: false, isAccepted: false, trainingFuelTarget: trainingFuelTarget)
        guard let userID else { return }
        do {
            if let saved = try store.load(RapidBarcodeBatchCheckpoint.self, userID: userID, scope: Self.scope) { checkpoint = saved.value }
        } catch { unreadable = true; errorMessage = "Your saved barcode tray could not be opened. It is kept on this device." }
    }

    @discardableResult
    public func append(_ code: String) -> Bool {
        guard !checkpoint.isSubmitted, !isResolving else { return false }
        let normalized = BarcodeCorrectionRules.normalizedBarcode(code)
        guard !normalized.isEmpty else { return false }
        var next = checkpoint
        let repeated = next.entries.contains { $0.code == normalized }
        next.entries.append(BarcodeBatchEntry(id: UUID().uuidString, code: normalized, resolution: .pending,
            included: !repeated, isRepeatedScan: repeated))
        return persist(next)
    }

    public func resolve(using lookup: (String) async -> FoodItem?) async {
        guard !isResolving, !checkpoint.isSubmitted, canUseAccount else { return }
        isResolving = true
        defer { isResolving = false }
        for index in checkpoint.entries.indices where [.pending, .resolving, .unmatched].contains(checkpoint.entries[index].resolution) {
            guard canUseAccount else { return }
            var pending = checkpoint; pending.entries[index].resolution = .resolving
            guard persist(pending) else { return }
            let result = await lookup(checkpoint.entries[index].code)
            guard canUseAccount else { return }
            var next = checkpoint
            if var food = result {
                // Provider identity is evidence, never the identity of a logical consumption.
                food.id = next.entries[index].id
                next.entries[index].food = food; next.entries[index].resolution = .found
            } else { next.entries[index].resolution = .unmatched }
            guard persist(next) else { return }
        }
    }

    @discardableResult
    public func toggleIncluded(id: String) -> Bool {
        guard !checkpoint.isSubmitted, !isResolving, let index = checkpoint.entries.firstIndex(where: { $0.id == id && $0.resolution == .found }) else { return false }
        var next = checkpoint; next.entries[index].included.toggle(); return persist(next)
    }

    @discardableResult
    public func updateFood(_ food: FoodItem) -> Bool {
        guard !checkpoint.isSubmitted, let index = checkpoint.entries.firstIndex(where: { $0.id == food.id }) else { return false }
        var next = checkpoint; next.entries[index].food = food; return persist(next)
    }

    @discardableResult public func removeFuelContext() -> Bool {
        guard canUseAccount, !isSaving, !isResolving, !checkpoint.isSubmitted, !checkpoint.isAccepted else { return false }
        var next = checkpoint; next.trainingFuelTarget = nil
        return persist(next)
    }

    public func save(using service: DailyLogService, leavingUnresolvedOut: Bool = false, completion: @escaping (Bool) -> Void) {
        guard !isSaving, !isResolving, !checkpoint.isAccepted, canUseAccount, let userID, service.isActiveAccount(userID) else { completion(false); return }
        var submitted = checkpoint
        if !submitted.isSubmitted {
            guard unresolvedCount == 0 || leavingUnresolvedOut else {
                errorMessage = "Some scanned codes are unresolved. Retry lookup or explicitly leave them out before logging."; completion(false); return
            }
            guard !includedFoods.isEmpty else { errorMessage = "Select at least one matched item to log."; completion(false); return }
            for index in submitted.entries.indices where [.pending, .resolving, .unmatched].contains(submitted.entries[index].resolution) {
                submitted.entries[index].resolution = .skipped; submitted.entries[index].included = false
            }
            if let target = submitted.trainingFuelTarget {
                do {
                    guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                    try fuel.stageFoodLink(target: target, foods: includedFoods, date: submitted.date, using: service, userID: userID)
                } catch { errorMessage = error.localizedDescription; completion(false); return }
            }
            submitted.isSubmitted = true
            guard persist(submitted) else { completion(false); return }
        }
        if let target = checkpoint.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.authorizeFoodLink(target: target, foods: includedFoods, userID: userID)
            } catch { errorMessage = "Could not prepare the saved fuel link. Retry this review; no new food was sent."; completion(false); return }
        }
        isSaving = true
        service.addMealGroupsToLog(for: userID, date: checkpoint.date,
            mealGroups: [(mealName: checkpoint.mealName, foodItems: includedFoods)], source: "barcode_batch", deduplicateFoodIDs: true) { [weak self] accepted in
            guard let self else { completion(false); return }
            self.isSaving = false
            guard self.canUseAccount else { self.errorMessage = "Sign back into the account that opened this barcode tray."; completion(false); return }
            guard accepted else { self.errorMessage = "Could not log this batch. Every scan and the frozen foods are kept for retry."; completion(false); return }
            if let target = self.checkpoint.trainingFuelTarget {
                _ = service.trainingFuelPlanStore?.acceptFoodLink(target: target, foods: self.includedFoods, userID: userID)
            }
            var next = self.checkpoint; next.isAccepted = true
            completion(self.persist(next))
        }
    }

    @discardableResult
    public func clear() -> Bool {
        guard !isSaving, !isResolving, !checkpoint.isSubmitted || checkpoint.isAccepted, canUseAccount, let userID else { return false }
        do {
            try store.remove(userID: userID, scope: Self.scope)
            checkpoint = RapidBarcodeBatchCheckpoint(id: UUID(), date: checkpoint.date, mealName: checkpoint.mealName,
                entries: [], isSubmitted: false, isAccepted: false)
            return true
        } catch { errorMessage = "Could not clear the barcode tray. It is kept on this device."; return false }
    }

    private var canUseAccount: Bool { !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID }
    private func persist(_ next: RapidBarcodeBatchCheckpoint) -> Bool {
        guard canUseAccount, let userID else { return false }
        do { try store.save(next, userID: userID, scope: Self.scope); checkpoint = next; errorMessage = nil; return true } catch {
            errorMessage = "Could not keep this barcode review on the device. Keep it open and retry."; return false
        }
    }
}
