import Foundation

@MainActor
public struct SavedFoodDuplicateDecisionStore {
    public let userID: String?
    private let store: EditorDraftStore
    private let scope = "my-foods-duplicate-decisions"
    public init(userID: String?, store: EditorDraftStore = EditorDraftStore()) { self.userID = userID; self.store = store }
    public static func key(_ foods: [FoodItem]) throws -> String {
        try PlanFingerprint.make(foods.map { try SavedFoodLibraryMutation.snapshotFingerprint($0) }.sorted())
    }
    public func decisions() throws -> Set<String> {
        guard let userID, userID == DIContainer.shared.authService.currentUserID else { throw LibraryMutationError.accountChanged }
        return try store.load(Set<String>.self, userID: userID, scope: scope)?.value ?? []
    }
    public func keepSeparate(_ foods: [FoodItem]) throws {
        guard let userID else { throw LibraryMutationError.accountChanged }
        var next = try decisions(); next.insert(try Self.key(foods))
        guard next.count <= 2_000 else { throw LibraryMutationError.invalid }
        try store.save(next, userID: userID, scope: scope)
    }
}
