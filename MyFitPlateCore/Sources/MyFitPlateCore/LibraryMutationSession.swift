import Combine
import Foundation

public enum LibraryOperation: Codable, Sendable, Identifiable {
    case recipes(RecipeLibraryMutation)
    case foods(SavedFoodLibraryMutation)
    public var id: UUID {
        switch self {
        case .recipes(let value): value.id
        case .foods(let value): value.id
        }
    }
    public var title: String {
        switch self {
        case .recipes(let value): value.title
        case .foods(let value): value.title
        }
    }
    public var undoingID: UUID? {
        switch self {
        case .recipes(let value): value.undoingID
        case .foods(let value): value.undoingID
        }
    }
    public var affectedIDs: Set<String> {
        switch self {
        case .recipes(let value): Set(value.recipeIDs.map { "recipe:\($0)" })
        case .foods(let value): Set(value.foodIDs.map { "food:\($0)" })
        }
    }
    public func inverse() -> Self {
        switch self {
        case .recipes(let value): .recipes(value.inverse())
        case .foods(let value): .foods(value.inverse())
        }
    }
    public func validate() throws {
        switch self {
        case .recipes(let value): try value.validate()
        case .foods(let value): try value.validate()
        }
    }
}

public struct LibraryHistoryEntry: Codable, Sendable, Identifiable {
    public let operation: LibraryOperation
    public let acceptedAt: Date?
    public var undoneBy: UUID?
    public var id: UUID { operation.id }
}

public struct LibraryMaintenanceCheckpoint: Codable {
    public var queue: [LibraryOperation] = []
    public var history: [LibraryHistoryEntry] = []
}

/// Frozen account-local reviews plus remote permanent receipts. Independent records may queue;
/// conditional inverses never replace an entire library or rewrite a diary snapshot.
@MainActor
public final class LibraryMutationSession: ObservableObject {
    @Published public private(set) var checkpoint = LibraryMaintenanceCheckpoint()
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastOutcome: String?
    @Published public private(set) var isLoadingHistory = false
    @Published public private(set) var historyLimit = 20
    @Published public private(set) var hasMoreHistory = false
    public let userID: String?
    private let store: EditorDraftStore
    private let scope = "library-maintenance-v1"
    private var expectedFingerprint: String?
    private var unreadable = false
    public var pending: LibraryOperation? { checkpoint.queue.first }
    public init(userID: String?, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.store = store
        guard let userID else { return }
        do {
            if let saved = try store.load(LibraryMaintenanceCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = saved.value; expectedFingerprint = try PlanFingerprint.make(saved.value)
            }
        } catch { unreadable = true; errorMessage = "Your saved library review could not be opened. It has been kept on this device." }
    }
    public func isPending(recipeID: String) -> Bool { checkpoint.queue.contains { $0.affectedIDs.contains("recipe:\(recipeID)") } }
    public func isPending(foodID: String) -> Bool { checkpoint.queue.contains { $0.affectedIDs.contains("food:\(foodID)") } }
    @discardableResult public func prepare(_ operation: LibraryOperation) -> Bool {
        do {
            try operation.validate()
            guard !checkpoint.queue.contains(where: { !$0.affectedIDs.isDisjoint(with: operation.affectedIDs) }),
                  checkpoint.queue.count < 30 else { throw LibraryMutationError.changed }
            var next = checkpoint; next.queue.append(operation)
            return persist(next)
        } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult public func undo(_ entry: LibraryHistoryEntry) -> Bool {
        guard let current = checkpoint.history.first(where: { $0.id == entry.id }), current.undoneBy == nil else { return false }
        return prepare(current.operation.inverse())
    }
    public func submit(using repository: NutritionRepositoryProtocol) async {
        guard !isWorking, canUseAccount, let userID else { return }
        isWorking = true; defer { isWorking = false }
        while let operation = pending {
            do {
                switch operation {
                case .recipes(let mutation): try await repository.applyRecipeLibraryMutation(userID: userID, mutation: mutation)
                case .foods(let mutation): try await repository.applySavedFoodLibraryMutation(userID: userID, mutation: mutation)
                }
                guard canUseAccount else { throw LibraryMutationError.accountChanged }
                guard acknowledge(operation) else { return }
            } catch { errorMessage = "Your exact library change is kept for retry. " + error.localizedDescription; return }
        }
    }
    public func resolve(using repository: NutritionRepositoryProtocol, cancelPending: Bool) async {
        guard !isWorking, canUseAccount, let userID, let operation = pending else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let resolution: String
            switch operation {
            case .recipes(let mutation): resolution = try await repository.resolveRecipeLibraryMutation(userID: userID, mutation: mutation, cancelPending: cancelPending).rawValue
            case .foods(let mutation): resolution = try await repository.resolveSavedFoodLibraryMutation(userID: userID, mutation: mutation, cancelPending: cancelPending).rawValue
            }
            guard canUseAccount else { throw LibraryMutationError.accountChanged }
            if resolution == "accepted" { _ = acknowledge(operation) } else if resolution == "cancelled" {
                var next = checkpoint; next.queue.removeAll { $0.id == operation.id }
                if persist(next) { lastOutcome = "The unaccepted library change was cancelled. Your records stay as saved." }
            } else { errorMessage = "This change has no accepted receipt yet. Retry it or cancel the pending operation." }
        } catch { errorMessage = error.localizedDescription }
    }
    public func reloadCheckpoint() {
        guard !isWorking, canUseAccount, let userID else { return }
        do {
            let current = try store.load(LibraryMaintenanceCheckpoint.self, userID: userID, scope: scope)?.value
            checkpoint = current ?? LibraryMaintenanceCheckpoint()
            expectedFingerprint = try current.map(PlanFingerprint.make); errorMessage = nil
        } catch { errorMessage = "The saved library review could not be refreshed. Its file is still kept." }
    }
    public func loadHistory(using repository: NutritionRepositoryProtocol, limit: Int = 20) async {
        guard !isWorking, !isLoadingHistory, canUseAccount, let userID else { return }
        reloadCheckpoint()
        let limit = min(200, max(20, limit))
        isLoadingHistory = true; defer { isLoadingHistory = false }
        do {
            async let recipes = repository.fetchRecipeLibraryHistory(userID: userID, limit: limit)
            async let foods = repository.fetchSavedFoodLibraryHistory(userID: userID, limit: limit)
            let (recipeHistory, foodHistory) = try await (recipes, foods)
            guard canUseAccount else { throw LibraryMutationError.accountChanged }
            var next = checkpoint
            let known = Set(next.history.map(\.id))
            let remote = recipeHistory.map(LibraryOperation.recipes) + foodHistory.map(LibraryOperation.foods)
            for operation in remote where !known.contains(operation.id) {
                next.history.insert(LibraryHistoryEntry(operation: operation, acceptedAt: nil), at: 0)
            }
            for operation in next.history.map(\.operation) {
                if let original = operation.undoingID, let index = next.history.firstIndex(where: { $0.id == original }) {
                    next.history[index].undoneBy = operation.id
                }
            }
            if persist(next) {
                historyLimit = limit
                hasMoreHistory = limit < 200 && (recipeHistory.count == limit || foodHistory.count == limit)
            }
        } catch { errorMessage = "The accepted changes saved on this device are still available. Account history could not be refreshed. " + error.localizedDescription }
    }
    private var canUseAccount: Bool { !unreadable && userID != nil && userID == DIContainer.shared.authService.currentUserID }
    private func acknowledge(_ operation: LibraryOperation) -> Bool {
        var next = checkpoint; next.queue.removeAll { $0.id == operation.id }
        if !next.history.contains(where: { $0.id == operation.id }) {
            next.history.append(LibraryHistoryEntry(operation: operation, acceptedAt: Date()))
            if let inverseOf = operation.undoingID, let index = next.history.firstIndex(where: { $0.id == inverseOf }) { next.history[index].undoneBy = operation.id }
            next.history = Array(next.history.suffix(100))
        }
        guard persist(next) else { return false }
        lastOutcome = operation.title + " saved to your account."
        return true
    }
    private func persist(_ next: LibraryMaintenanceCheckpoint) -> Bool {
        guard canUseAccount, let userID else { errorMessage = LibraryMutationError.accountChanged.localizedDescription; return false }
        do {
            let current = try store.load(LibraryMaintenanceCheckpoint.self, userID: userID, scope: scope)?.value
            guard try current.map(PlanFingerprint.make) == expectedFingerprint else { throw LibraryMutationError.changed }
            try store.save(next, userID: userID, scope: scope)
            checkpoint = next; expectedFingerprint = try PlanFingerprint.make(next); errorMessage = nil
            return true
        } catch { errorMessage = "The previous library checkpoint is kept. " + error.localizedDescription; return false }
    }
}
