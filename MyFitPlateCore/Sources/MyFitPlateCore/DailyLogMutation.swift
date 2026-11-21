import Foundation

public enum FoodEditConflict: LocalizedError {
    case changed
    public var errorDescription: String? { "This food changed elsewhere. Your reviewed edit is kept; review the current entry before retrying." }
}

public struct FoodEditPrecondition: Codable {
    public let foodID: String
    public let expected: FoodItem?
    public let desired: FoodItem?
    public let expectedMealID: UUID?
    public let desiredMealID: UUID?

    public init(original: FoodItem, desired: FoodItem) {
        self.init(foodID: original.id, expected: original, desired: desired)
    }

    /// Nil expected/desired snapshots describe creation/deletion, including their Undo.
    public init(foodID: String, expected: FoodItem?, desired: FoodItem?, expectedMealID: UUID? = nil, desiredMealID: UUID? = nil) {
        self.foodID = foodID; self.expected = expected; self.desired = desired
        self.expectedMealID = expectedMealID; self.desiredMealID = desiredMealID
    }

    public static func sameSnapshot(_ first: FoodItem, _ second: FoodItem) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard let left = try? encoder.encode(first), let right = try? encoder.encode(second) else { return false }
        return left == right
    }

    public func validate(in log: DailyLog) throws {
        let matches = log.meals.flatMap { meal in meal.foodItems.filter { $0.id == foodID }.map { (food: $0, mealID: meal.id) } }
        guard !foodID.isEmpty, expected != nil || desired != nil,
              expected.map({ $0.id == foodID }) ?? true, desired.map({ $0.id == foodID }) ?? true,
              matches.count <= 1 else { throw FoodEditConflict.changed }
        let current = matches.first
        let matchesExpected = Self.matches(current?.food, expected) && (expectedMealID == nil || current?.mealID == expectedMealID)
        let matchesDesired = Self.matches(current?.food, desired) && (desiredMealID == nil || current?.mealID == desiredMealID)
        guard matchesExpected || matchesDesired else { throw FoodEditConflict.changed }
    }

    private static func matches(_ first: FoodItem?, _ second: FoodItem?) -> Bool {
        switch (first, second) {
        case (.none, .none): return true
        case let (.some(left), .some(right)): return sameSnapshot(left, right)
        default: return false
        }
    }
}

/// A durable change relative to what the user saw, applied to the latest server day.
/// Independent entries merge. For simultaneous edits of one entry the last commit wins;
/// deletion wins over an edit so stale clients cannot resurrect removed entries.
public struct DailyLogMutation: Codable, Identifiable {
    public let id: String
    public let userID: String
    public let before: DailyLog
    public let after: DailyLog
    public let foodEditPrecondition: FoodEditPrecondition?
    public let foodEditPreconditions: [FoodEditPrecondition]?
    public let activityEditPrecondition: ActivityEditPrecondition?
    public let dayReviewUndo: Bool?

    public init(userID: String, log: DailyLog) throws {
        id = log.pendingMutationID ?? UUID().uuidString
        self.userID = userID
        after = log
        foodEditPrecondition = log.pendingFoodEdit
        foodEditPreconditions = log.pendingFoodEdits
        activityEditPrecondition = log.pendingActivityEdit
        dayReviewUndo = log.pendingDayReviewUndo
        if let data = log.mutationBase {
            before = try JSONDecoder().decode(DailyLog.self, from: data)
        } else {
            before = DailyLog(id: log.id, date: log.date, meals: [])
        }
    }

    /// Checked editors opt in without changing legacy offline add/delete merge policy.
    /// This executes inside the server transaction, after reading its current snapshot.
    public func applying(to latest: DailyLog, checkingFoodEdits: Bool) throws -> DailyLog {
        if !(latest.appliedMutationIDs ?? []).contains(id), checkingFoodEdits {
            try NutritionDayReviewRules.validateChange(before: before, after: after, latest: latest, ownerID: userID, isUndo: dayReviewUndo == true)
            try activityEditPrecondition?.validate(in: latest)
            try foodEditPrecondition?.validate(in: latest)
            for precondition in foodEditPreconditions ?? [] { try precondition.validate(in: latest) }
        }
        return applying(to: latest)
    }

    public func applying(to latest: DailyLog) -> DailyLog {
        guard !(latest.appliedMutationIDs ?? []).contains(id) else { return latest }
        var result = latest
        for oldMeal in before.meals where !after.meals.contains(where: { $0.id == oldMeal.id }) {
            // Only remove entries this client actually saw; preserve concurrently added food.
            if let index = result.meals.firstIndex(where: { $0.id == oldMeal.id })
                ?? result.meals.firstIndex(where: { $0.name.caseInsensitiveCompare(oldMeal.name) == .orderedSame }) {
                let removed = Set(oldMeal.foodItems.map(\.id))
                result.meals[index].foodItems.removeAll { removed.contains($0.id) }
                if result.meals[index].foodItems.isEmpty { result.meals.remove(at: index) }
            }
        }
        for meal in after.meals {
            let old = before.meals.first { $0.id == meal.id }
            let index = result.meals.firstIndex { $0.id == meal.id }
                ?? result.meals.firstIndex { $0.name.caseInsensitiveCompare(old?.name ?? meal.name) == .orderedSame }
            if let index {
                result.meals[index].foodItems = Self.merge(
                    before: old?.foodItems ?? [], after: meal.foodItems, latest: result.meals[index].foodItems
                )
                if let old, old.name != meal.name { result.meals[index].name = meal.name }
            } else {
                // A removed meal stays removed, except for genuinely new entries added to it.
                let additions = meal.foodItems.filter { item in !(old?.foodItems.contains { $0.id == item.id } ?? false) }
                if old == nil || !additions.isEmpty {
                    result.meals.append(Meal(id: meal.id, name: meal.name, foodItems: additions))
                }
            }
        }
        result.exercises = Self.merge(before: before.exercises ?? [], after: after.exercises ?? [], latest: latest.exercises ?? [])
        result.journalEntries = Self.merge(before: before.journalEntries ?? [], after: after.journalEntries ?? [], latest: latest.journalEntries ?? [])
        if before.totalCaloriesOverride != after.totalCaloriesOverride {
            result.totalCaloriesOverride = after.totalCaloriesOverride
        }
        if before.nutritionDayStatus != after.nutritionDayStatus {
            result.nutritionDayStatus = after.nutritionDayStatus
        }
        if before.nutritionDayReview != after.nutritionDayReview {
            result.nutritionDayReview = after.nutritionDayReview
        }
        let waterDelta = (after.waterTracker?.totalOunces ?? 0) - (before.waterTracker?.totalOunces ?? 0)
        if waterDelta != 0 || before.waterTracker?.goalOunces != after.waterTracker?.goalOunces {
            result.waterTracker = WaterTracker(
                totalOunces: max(0, (latest.waterTracker?.totalOunces ?? 0) + waterDelta),
                goalOunces: after.waterTracker?.goalOunces ?? latest.waterTracker?.goalOunces ?? 64,
                date: latest.date
            )
        }
        result.appliedMutationIDs = (latest.appliedMutationIDs ?? []) + [id]
        return result
    }

    private static func contentDiffers<Item: Encodable>(_ lhs: Item, _ rhs: Item) -> Bool {
        // FoodItem and LoggedExercise equality deliberately compares identity only.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(lhs)) != (try? encoder.encode(rhs))
    }

    private static func merge<Item: Identifiable & Encodable>(before: [Item], after: [Item], latest: [Item]) -> [Item] {
        let removed = Set(before.map(\.id)).subtracting(after.map(\.id))
        var result = latest.filter { !removed.contains($0.id) }
        // A legacy repeated ID is ambiguous to edit, but unchanged repeated groups
        // must survive independent water, notes and other unique-entry changes.
        let oldGroups = Dictionary(grouping: before, by: \.id), newGroups = Dictionary(grouping: after, by: \.id)
        let unchangedRepeatedIDs = Set(oldGroups.keys.filter { id in
            let old = oldGroups[id] ?? [], new = newGroups[id] ?? []
            return old.count > 1 && old.count == new.count && zip(old, new).allSatisfy { !contentDiffers($0, $1) }
        })
        for item in after {
            if unchangedRepeatedIDs.contains(item.id) { continue }
            if let old = before.first(where: { $0.id == item.id }) {
                if contentDiffers(old, item), let index = result.firstIndex(where: { $0.id == item.id }) { result[index] = item }
            } else if !result.contains(where: { $0.id == item.id }) {
                result.append(item)
            }
        }
        return result
    }
}

/// Atomic file replacement means acceptance survives process termination. Never discard a
/// corrupt queue or acknowledge an operation whose disk write failed.
public final class DailyLogMutationStore: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func pending(userID: String) throws -> [DailyLogMutation] {
        lock.lock()
        defer { lock.unlock() }
        return try read().filter { $0.userID == userID }
    }

    public func append(_ mutation: DailyLogMutation) throws {
        lock.lock()
        defer { lock.unlock() }
        var items = try read()
        guard !items.contains(where: { $0.id == mutation.id && $0.userID == mutation.userID }) else { return }
        items.append(mutation)
        try write(items)
    }

    public func acknowledge(_ mutation: DailyLogMutation) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(read().filter { $0.id != mutation.id || $0.userID != mutation.userID })
    }

    public func removeAll(userID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(read().filter { $0.userID != userID })
    }

    private func read() throws -> [DailyLogMutation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([DailyLogMutation].self, from: Data(contentsOf: fileURL))
    }

    private func write(_ items: [DailyLogMutation]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
    }
}

public enum DailyLogSyncState: Equatable {
    case synced
    case pending(Int)
    case failed
}

public extension Notification.Name {
    static let dailyLogSyncStateChanged = Notification.Name("dailyLogSyncStateChanged")
}
