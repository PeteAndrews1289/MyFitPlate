import Foundation

/// A bounded copy of one recently logged meal that a paired Watch can offer to repeat.
/// The paired-device payload intentionally carries no account identifier.
public struct WatchMealSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let mealName: String
    public let foodItems: [FoodItem]
    public let capturedAt: Date

    public init(
        id: String = UUID().uuidString,
        mealName: String,
        foodItems: [FoodItem],
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.mealName = mealName
        self.foodItems = foodItems
        self.capturedAt = capturedAt
    }

    public var totalCalories: Int {
        Int(foodItems.reduce(0) { $0 + $1.calories }.rounded())
    }
}

public struct WatchMealRepeatRequest: Codable, Equatable, Sendable {
    public let id: String
    public let accountScope: String
    public let snapshot: WatchMealSnapshot
    public let requestedAt: Date

    public init(
        id: String = UUID().uuidString,
        accountScope: String,
        snapshot: WatchMealSnapshot,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.accountScope = accountScope
        self.snapshot = snapshot
        self.requestedAt = requestedAt
    }
}

public enum WatchQuickActionPayload {
    public static let schemaVersion = "watch_context_v2"
    public static let schema = "watchContextSchema"
    public static let generatedAt = "watchContextGeneratedAt"
    public static let syncRequest = "requestWatchContextSync"
    public static let accountScope = "accountScope"
    public static let nextAction = "nextActionData"
    public static let recentMeal = "recentMealData"
    public static let repeatMealRequest = "repeatMealRequestData"
    public static let clearAccount = "clearAccount"
}

public enum WatchQuickActionRules {
    public static let maximumFoodItems = 24

    /// Chooses the meal containing the most recently timestamped item. Meals without item
    /// timestamps retain diary order as a deterministic fallback.
    public static func recentMeal(from log: DailyLog?, now: Date = Date()) -> WatchMealSnapshot? {
        guard let log else { return nil }

        let candidates = log.meals.enumerated().compactMap { index, meal -> (Int, Date?, Meal)? in
            guard !meal.foodItems.isEmpty,
                  meal.foodItems.count <= maximumFoodItems,
                  meal.foodItems.allSatisfy(isRepeatable) else { return nil }
            return (
                index,
                meal.foodItems.compactMap(\.timestamp).max(),
                Meal(name: meal.name, foodItems: meal.foodItems)
            )
        }
        guard let selected = candidates.max(by: { lhs, rhs in
            switch (lhs.1, rhs.1) {
            case let (left?, right?):
                return left == right ? lhs.0 < rhs.0 : left < right
            case (nil, nil):
                return lhs.0 < rhs.0
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            }
        }) else { return nil }

        let name = selected.2.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return WatchMealSnapshot(
            mealName: name.isEmpty ? "Meal" : String(name.prefix(48)),
            foodItems: selected.2.foodItems,
            capturedAt: now
        )
    }

    /// Repeating a meal must create new food identities and current timestamps. Reusing the
    /// original IDs would make later edits or deletes ambiguous.
    public static func itemsForLogging(
        from snapshot: WatchMealSnapshot,
        at date: Date = Date()
    ) -> [FoodItem] {
        guard !snapshot.foodItems.isEmpty,
              snapshot.foodItems.count <= maximumFoodItems,
              snapshot.foodItems.allSatisfy(isRepeatable) else { return [] }
        return snapshot.foodItems.map { original in
            var copy = original
            copy.id = UUID().uuidString
            copy.timestamp = date
            return copy
        }
    }

    private static func isRepeatable(_ item: FoodItem) -> Bool {
        !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            item.calories.isFinite && item.calories >= 0 &&
            item.protein.isFinite && item.protein >= 0 &&
            item.carbs.isFinite && item.carbs >= 0 &&
            item.fats.isFinite && item.fats >= 0
    }
}

/// Generates a stable random scope per local account. Only the random scope crosses to Watch;
/// Firebase IDs and email addresses never enter WatchConnectivity payloads.
public final class WatchAccountScopeStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, storageKey: String = "watchAccountScopes.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func scope(for userID: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        var scopes = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        if let existing = scopes[userID], !existing.isEmpty { return existing }
        let scope = UUID().uuidString
        scopes[userID] = scope
        defaults.set(scopes, forKey: storageKey)
        return scope
    }
}

/// Durable, idempotent inbox for Watch actions. A request remains pending until the diary write
/// succeeds, and handled IDs are retained in a small rolling window to reject duplicate delivery.
public final class WatchMealRepeatInbox: @unchecked Sendable {
    private struct State: Codable {
        var pending: [WatchMealRepeatRequest] = []
        var handledIDs: [String] = []
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private let maximumPending = 20
    private let maximumHandled = 100

    public init(defaults: UserDefaults = .standard, storageKey: String = "watchMealRepeatInbox.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    @discardableResult
    public func enqueue(_ request: WatchMealRepeatRequest) -> Bool {
        withState { state in
            guard !state.handledIDs.contains(request.id),
                  !state.pending.contains(where: { $0.id == request.id }) else { return false }
            state.pending.append(request)
            if state.pending.count > maximumPending {
                state.pending.removeFirst(state.pending.count - maximumPending)
            }
            return true
        }
    }

    public func nextRequest(accountScope: String) -> WatchMealRepeatRequest? {
        withState { state in
            state.pending.first(where: { $0.accountScope == accountScope })
        }
    }

    public func markHandled(id: String) {
        withState { state in
            state.pending.removeAll { $0.id == id }
            if !state.handledIDs.contains(id) { state.handledIDs.append(id) }
            if state.handledIDs.count > maximumHandled {
                state.handledIDs.removeFirst(state.handledIDs.count - maximumHandled)
            }
        }
    }

    public func discardRequests(exceptAccountScope accountScope: String?) {
        withState { state in
            state.pending.removeAll { request in
                guard let accountScope else { return true }
                return request.accountScope != accountScope
            }
        }
    }

    public var pendingCount: Int {
        withState { $0.pending.count }
    }

    @discardableResult
    private func withState<Result>(_ operation: (inout State) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        var state = loadState()
        let result = operation(&state)
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: storageKey)
        }
        return result
    }

    private func loadState() -> State {
        guard let data = defaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }
}
