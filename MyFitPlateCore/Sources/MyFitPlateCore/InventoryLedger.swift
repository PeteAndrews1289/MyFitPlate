import Foundation

public enum InventoryError: Int, Error, LocalizedError, CustomNSError {
    case invalid = 400, accountChanged = 401, changed = 409, cancelled = 410, alreadyApplied = 412, unavailable = 503
    public static var errorDomain: String { "MyFitPlate.Inventory" }
    public var errorCode: Int { rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "Stock could not be saved."] }
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review the stock amounts and compatible units. No stock has changed."
        case .accountChanged: "Return to the account that opened this stock review."
        case .changed: "This stock or linked food changed. Your review is kept; cancel it and review the current amounts."
        case .cancelled: "This stock operation was cancelled and cannot change your records."
        case .alreadyApplied: "This cooking batch, planned portion or Undo has already been recorded. Reload its current stock."
        case .unavailable: "Stock could not be confirmed. Your exact review is kept; retry or check its status."
        }
    }
}

public enum InventoryQuantityRules {
    public static let units = ["g", "kg", "oz", "lb", "ml", "L", "cup", "tbsp", "tsp", "fl oz", "item", "can", "package", "portion"]
    public static func explicitLeadingAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[•\-]\s+"#, with: "", options: .regularExpression)
        let pattern = #"^((?:\d+\s+)?\d+/\d+|(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|\.\d+|[½⅓⅔¼¾⅛⅜⅝⅞⅕⅖⅗⅘⅙⅚])(?=\s|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range(at: 1), in: trimmed) else { return nil }
        let token = String(trimmed[range])
        let remainder = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if remainder.range(of: #"^(?:[-–—]|to)\s*\d"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let fractions: [String: Double] = ["½": 0.5, "⅓": 1 / 3, "⅔": 2 / 3, "¼": 0.25, "¾": 0.75, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875, "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8, "⅙": 1 / 6, "⅚": 5 / 6]
        if let value = fractions[token] { return value }
        var amount = 0.0
        for part in token.split(whereSeparator: \.isWhitespace) {
            let pieces = part.split(separator: "/")
            if pieces.count == 2 {
                guard let numerator = Double(pieces[0]), let denominator = Double(pieces[1]), denominator > 0 else { return nil }
                amount += numerator / denominator
            } else {
                guard let value = Double(part.replacingOccurrences(of: ",", with: "")) else { return nil }
                amount += value
            }
        }
        return amount.isFinite && amount > 0 ? amount : nil
    }
    public static func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard amount.isFinite, amount >= 0 else { return nil }
        let left = IngredientUnitNormalizer.normalized(from), right = IngredientUnitNormalizer.normalized(to)
        if left == right { return amount }
        let mass: [String: Double] = ["g": 1, "kg": 1_000, "oz": 28.349523125, "lb": 453.59237]
        let volume: [String: Double] = ["ml": 1, "L": 1_000, "cup": 236.5882365, "tbsp": 14.78676478125, "tsp": 4.92892159375, "fl oz": 29.5735295625]
        for factors in [mass, volume] {
            if let first = factors[left], let second = factors[right] { return amount * first / second }
        }
        return nil
    }
    public static func ingredientIdentity(_ name: String) -> String {
        // Raw/cooked/product words matter. Never reuse the fuzzy meal-idea name matcher.
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func usable(_ item: PantryItem, now: Date = Date()) -> Bool {
        item.availableQuantity > 0 && (item.bestBefore.map { $0 >= Calendar.current.startOfDay(for: now) } ?? true)
    }
}

public struct InventoryDiaryPatch: Codable {
    public var day: DiaryDayContext
    public var mealName: String
    public var mealID: UUID
    public var expected: FoodItem?
    public var desired: FoodItem?
    public init(day: DiaryDayContext, mealName: String, expected: FoodItem? = nil, desired: FoodItem?) {
        self.day = day; self.mealName = mealName; self.mealID = UUID(); self.expected = expected; self.desired = desired
    }
    public var foodID: String { desired?.id ?? expected?.id ?? "" }
    public func applying(to original: DailyLog) throws -> DailyLog {
        guard !foodID.isEmpty, !mealName.isEmpty, !day.isFuture() else { throw InventoryError.invalid }
        if expected == nil, desired != nil, original.meals.flatMap(\.foodItems).contains(where: { $0.id == foodID }) {
            // Idempotence belongs to the inventory receipt, not to an unrelated diary
            // entry that happened to use this planned occurrence ID already.
            throw InventoryError.changed
        }
        let matches = original.meals.flatMap(\.foodItems).filter { $0.id == foodID }
        guard matches.count <= 1 else { throw InventoryError.changed }
        if let expected, let actual = matches.first {
            guard original.meals.first(where: { $0.foodItems.contains(where: { $0.id == foodID }) })?.name.caseInsensitiveCompare(mealName) == .orderedSame else { throw InventoryError.changed }
            guard try InventorySnapshotRules.fingerprint(expected) == InventorySnapshotRules.fingerprint(actual) else { throw InventoryError.changed }
        } else if expected != nil, !matches.isEmpty || desired != nil { throw InventoryError.changed }
        var result = original
        for index in result.meals.indices { result.meals[index].foodItems.removeAll { $0.id == foodID } }
        result.meals.removeAll { $0.foodItems.isEmpty }
        if let desired {
            if let index = result.meals.firstIndex(where: { $0.name.caseInsensitiveCompare(mealName) == .orderedSame }) {
                result.meals[index].foodItems.append(desired)
            } else { result.meals.append(Meal(id: mealID, name: mealName, foodItems: [desired])) }
        }
        return result
    }
}

public struct InventoryMutation: Codable, Identifiable {
    public enum Reason: String, Codable, CaseIterable { case purchase, correction, cook, consume, waste, undo }
    public var id: UUID
    public var userID: String
    public var createdAt: Date
    public var title: String
    public var reason: Reason
    public var before: [PantryItem]
    public var after: [PantryItem]
    public var uniqueSourceKey: String?
    public var undoing: UUID?
    public var diary: InventoryDiaryPatch?
    public var grocery: GroceryListMutation?
    public init(id: UUID = UUID(), userID: String, title: String, reason: Reason, before: [PantryItem], after: [PantryItem], uniqueSourceKey: String? = nil, undoing: UUID? = nil, diary: InventoryDiaryPatch? = nil, grocery: GroceryListMutation? = nil, now: Date = Date()) {
        self.id = id; self.userID = userID; self.createdAt = now; self.title = title; self.reason = reason
        self.before = before; self.after = after; self.uniqueSourceKey = uniqueSourceKey; self.undoing = undoing; self.diary = diary; self.grocery = grocery
    }
    public var itemIDs: Set<UUID> { Set(before.map(\.id)).union(after.map(\.id)) }
    public func fingerprint() throws -> String { try PlanFingerprint.make(self) }
    public func validate() throws {
        guard !userID.isEmpty, !title.isEmpty, !after.isEmpty || grocery != nil, itemIDs.count <= 80,
              Set(before.map(\.id)).count == before.count, Set(after.map(\.id)).count == after.count,
              Set(before.map(\.id)).isSubset(of: Set(after.map(\.id))),
              after.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.unit.isEmpty && $0.quantity.isFinite && $0.quantity >= 0 && $0.quantity <= 1_000_000_000 }),
              after.allSatisfy({ item in item.cookedBatch.map { batch in item.unit == "portion" && item.portionFood != nil && item.quantity <= batch.totalPortions + 0.000001 } ?? true }),
              diary.map({ $0.day.userID == userID && !$0.day.isFuture() && !$0.foodID.isEmpty }) ?? true,
              diary?.desired.map({ [$0.calories, $0.protein, $0.carbs, $0.fats].allSatisfy { $0.isFinite && $0 >= 0 } }) ?? true,
              (try JSONEncoder().encode(self)).count < 500_000 else { throw InventoryError.invalid }
    }
    public func applying(to current: [PantryItem]) throws -> [PantryItem] {
        try validate()
        var result = current
        guard Set(current.map(\.id)).count == current.count else { throw InventoryError.invalid }
        for id in itemIDs {
            let expected = before.first { $0.id == id }, actual = current.first { $0.id == id }
            guard try PlanFingerprint.make(expected) == PlanFingerprint.make(actual) else { throw InventoryError.changed }
            guard let desired = after.first(where: { $0.id == id }) else { throw InventoryError.invalid }
            if let index = result.firstIndex(where: { $0.id == id }) { result[index] = desired } else { result.append(desired) }
        }
        return result
    }
}

/// Opaque JSON preserves exact reviewed Date precision for retry and historical Undo.
public struct InventoryReceipt: Codable, Identifiable {
    public enum Status: String, Codable { case accepted, cancelled }
    public let schemaVersion: Int
    public let userID: String
    public let id: UUID
    public let fingerprint: String
    public let status: Status
    public let payload: Data
    public init(_ mutation: InventoryMutation, status: Status) throws {
        try mutation.validate(); schemaVersion = 1; userID = mutation.userID; id = mutation.id
        fingerprint = try mutation.fingerprint(); self.status = status; payload = try JSONEncoder().encode(mutation)
    }
    public func mutation() throws -> InventoryMutation {
        let value = try JSONDecoder().decode(InventoryMutation.self, from: payload)
        try validate(value); return value
    }
    public func validate(_ value: InventoryMutation) throws {
        guard schemaVersion == 1, id == value.id, userID == value.userID, fingerprint == (try value.fingerprint()) else { throw InventoryError.changed }
    }
}

public enum InventoryResolution: Equatable { case pending, accepted, cancelled }

public struct GroceryStockCoverage: Identifiable {
    public let item: GroceryListItem
    public let available: Double
    public let needToBuy: Double
    public var id: UUID { item.id }
}

public enum InventoryPlanningRules {
    public static func coverage(items: [GroceryListItem], stock: [PantryItem], now: Date = Date()) -> [GroceryStockCoverage] {
        var remaining = Dictionary(uniqueKeysWithValues: stock.map { ($0.id, InventoryQuantityRules.usable($0, now: now) && !$0.isCookedBatch ? $0.availableQuantity : 0) })
        return items.map { item in
            guard item.quantityUnknown != true else { return GroceryStockCoverage(item: item, available: 0, needToBuy: 0) }
            var needed = item.quantity, covered = 0.0
            if item.source == "mealPlan" {
                for lot in stock where InventoryQuantityRules.ingredientIdentity(lot.name) == InventoryQuantityRules.ingredientIdentity(item.name) {
                    guard lot.preparation != nil, lot.preparation != "Unknown",
                          lot.preparation != "Cooked" || InventoryQuantityRules.ingredientIdentity(item.name).contains("cooked") else { continue }
                    guard let inRequiredUnit = InventoryQuantityRules.convert(remaining[lot.id] ?? 0, from: lot.unit, to: item.unit),
                          let usedLotUnit = InventoryQuantityRules.convert(min(needed, inRequiredUnit), from: item.unit, to: lot.unit) else { continue }
                    let used = min(needed, inRequiredUnit)
                    remaining[lot.id, default: 0] -= usedLotUnit; needed -= used; covered += used
                    if needed <= 0 { break }
                }
            }
            // Transferred purchases already contribute through physical stock above.
            // A reviewed bought-only amount fulfils shopping without inventing a lot.
            let boughtOutsideStock = max(0, (item.purchasedQuantity ?? 0) - (item.transferredToPantryQuantity ?? 0))
            let remainingNeed = item.skippedForPlan == true || item.isCompleted ? 0 : max(0, needed - boughtOutsideStock)
            return GroceryStockCoverage(item: item, available: covered, needToBuy: remainingNeed)
        }
    }

    public static func cooked(batch: MealCookingBatch, originalMeal: PlannedMeal, stock: [PantryItem], selectedLots: [Int: UUID], userID: String, bestBefore: Date?, now: Date = Date()) throws -> InventoryMutation {
        guard originalMeal.cookingBatch == batch, originalMeal.foodItem != nil,
              batch.totalPortions.isFinite, (0.25...100).contains(batch.totalPortions) else { throw InventoryError.changed }
        var touched: [UUID: PantryItem] = [:], updated: [UUID: PantryItem] = [:]
        for (index, ingredient) in batch.ingredientsPerPortion.enumerated() {
            guard let selected = selectedLots[index] else { continue } // Explicitly reviewed purchased/untracked ingredients remain unmodified.
            guard ingredient.hasKnownAmount, let lot = stock.first(where: { $0.id == selected }), !lot.isCookedBatch,
                  lot.quantityUnknown != true, lot.quantityVerified == true, lot.isArchived != true,
                  lot.preparation != "Cooked" || InventoryQuantityRules.ingredientIdentity(ingredient.name).contains("cooked"),
                  let amount = InventoryQuantityRules.convert(ingredient.quantity * batch.totalPortions, from: ingredient.unit, to: lot.unit) else { throw InventoryError.invalid }
            touched[selected] = lot
            var value = updated[selected] ?? lot
            guard value.quantity + 0.000001 >= amount else { throw InventoryError.changed }
            value.quantity = max(0, value.quantity - amount); value.revisionID = UUID().uuidString
            updated[selected] = value
        }
        var cooked = PantryItem(name: batch.name, quantity: batch.totalPortions, unit: "portion", category: "Cooked batches", dateAdded: now)
        cooked.cookedBatch = batch; cooked.portionFood = originalMeal.foodItem; cooked.cookedAt = now
        cooked.quantityVerified = true
        cooked.bestBefore = bestBefore; cooked.preparation = "Cooked"; cooked.revisionID = UUID().uuidString
        return InventoryMutation(userID: userID, title: "Cooked \(batch.name)", reason: .cook,
            before: Array(touched.values).sorted { $0.id.uuidString < $1.id.uuidString },
            after: (Array(updated.values) + [cooked]).sorted { $0.id.uuidString < $1.id.uuidString }, uniqueSourceKey: "cook-\(batch.id)", now: now)
    }

    public static func reducing(item: PantryItem, amount: Double, reason: InventoryMutation.Reason, userID: String, plannedMeal: PlannedMeal? = nil, date: Date = Date(), mealName: String = "Lunch", alsoLog: Bool = false) throws -> InventoryMutation {
        guard [.consume, .waste].contains(reason), amount.isFinite, amount > 0,
              item.quantityUnknown != true, item.quantityVerified == true, item.isArchived != true, amount <= item.quantity + 0.000001 else { throw InventoryError.invalid }
        let id = UUID()
        var result = item; result.quantity = max(0, item.quantity - amount); result.revisionID = UUID().uuidString
        var patch: InventoryDiaryPatch?
        var sourceKey: String?
        if let plannedMeal {
            let matchesBatch = plannedMeal.cookingBatch.map { $0.id == item.cookedBatch?.id } ?? false
            let matchesPrepared = plannedMeal.preparedStock?.matches(item, meal: plannedMeal) == true
            guard matchesBatch || matchesPrepared, abs(plannedMeal.portions - amount) < 0.000001 else { throw InventoryError.invalid }
            let key = "consume-\(item.cookedBatch?.id ?? "")-\(PlannedMealLoggingRules.entryID(for: plannedMeal, date: date))"
            sourceKey = key
            guard !(item.recordedPlannedPortions ?? []).contains(key) else { throw InventoryError.alreadyApplied }
            result.recordedPlannedPortions = (item.recordedPlannedPortions ?? []) + [key]
        }
        if alsoLog {
            guard reason == .consume, let base = item.portionFood,
                  var food = FoodRepeatRules.adjusting(base, by: amount), let day = DiaryDayContext(userID: userID, date: date), !day.isFuture() else { throw InventoryError.invalid }
            food.id = plannedMeal.map { PlannedMealLoggingRules.entryID(for: $0, date: date) } ?? "stock-\(id.uuidString)"
            food.timestamp = date
            patch = InventoryDiaryPatch(day: day, mealName: mealName, desired: food)
        }
        return InventoryMutation(id: id, userID: userID, title: "\(reason == .waste ? "Wrote off" : "Used") \(amount.formatted()) \(item.unit) \(item.name)", reason: reason, before: [item], after: [result], uniqueSourceKey: sourceKey, diary: patch)
    }

    public static func undoing(_ operation: InventoryMutation, current: [PantryItem], groceries: [GroceryListItem] = []) throws -> InventoryMutation {
        var before: [PantryItem] = [], after: [PantryItem] = []
        for originalAfter in operation.after {
            guard let actual = current.first(where: { $0.id == originalAfter.id }), actual.unit == originalAfter.unit,
                  actual.cookedBatch?.id == originalAfter.cookedBatch?.id,
                  actual.quantityUnknown == originalAfter.quantityUnknown else { throw InventoryError.changed }
            let old = operation.before.first { $0.id == actual.id }
            var inverse = actual
            let delta = originalAfter.quantity - (old?.quantity ?? 0)
            let nextAmount = actual.quantity - delta
            guard nextAmount >= -0.000001 else { throw InventoryError.changed }
            inverse.quantity = max(0, nextAmount); inverse.revisionID = UUID().uuidString
            if let old, try metadataFingerprint(actual) == metadataFingerprint(originalAfter) {
                let quantity = inverse.quantity
                inverse = old; inverse.quantity = quantity; inverse.revisionID = UUID().uuidString
            } else if old != nil, try metadataFingerprint(actual) != metadataFingerprint(originalAfter) {
                throw InventoryError.changed
            }
            if old == nil, inverse.quantity == 0 { inverse.isArchived = true; inverse.creationUndone = true }
            let oldKeys = Set(old?.recordedPlannedPortions ?? [])
            let appliedKeys = Set(originalAfter.recordedPlannedPortions ?? [])
            let currentKeys = Set(actual.recordedPlannedPortions ?? [])
            let restoredKeys = currentKeys.subtracting(appliedKeys.subtracting(oldKeys)).union(oldKeys.subtracting(appliedKeys))
            inverse.recordedPlannedPortions = restoredKeys.isEmpty ? nil : restoredKeys.sorted()
            before.append(actual); after.append(inverse)
        }
        var diary = operation.diary
        if var patch = diary { let old = patch.expected; patch.expected = patch.desired; patch.desired = old; diary = patch }
        var groceryPatch: GroceryListMutation?
        if let originalPatch = operation.grocery {
            var originals: [GroceryListItem] = [], reversals: [GroceryListItem] = []
            for transferred in originalPatch.upserts {
                guard let actual = groceries.first(where: { $0.id == transferred.id }) else { throw InventoryError.changed }
                let old = originalPatch.before.first { $0.id == transferred.id }
                let delta = (transferred.transferredToPantryQuantity ?? 0) - (old?.transferredToPantryQuantity ?? 0)
                var value = actual
                guard (actual.transferredToPantryQuantity ?? 0) + 0.000001 >= delta else { throw InventoryError.changed }
                value.transferredToPantryQuantity = max(0, (actual.transferredToPantryQuantity ?? 0) - delta)
                if operation.after.isEmpty {
                    let boughtDelta = (transferred.purchasedQuantity ?? 0) - (old?.purchasedQuantity ?? 0)
                    guard (actual.purchasedQuantity ?? 0) - boughtDelta >= -0.000001 else { throw InventoryError.changed }
                    value.purchasedQuantity = max(0, (actual.purchasedQuantity ?? 0) - boughtDelta)
                    value.isCompleted = (value.purchasedQuantity ?? 0) + 0.000001 >= value.quantity
                }
                originals.append(actual); reversals.append(value)
            }
            groceryPatch = GroceryListMutation(before: originals, upserts: reversals, removedIDs: [])
        }
        let title = operation.grocery != nil && !operation.after.isEmpty ? "Undo stock transfer · \(operation.title)" : "Undo \(operation.title)"
        return InventoryMutation(userID: operation.userID, title: title, reason: .undo,
            before: before, after: after, uniqueSourceKey: "undo-\(operation.id.uuidString)", undoing: operation.id, diary: diary, grocery: groceryPatch)
    }

    private static func metadataFingerprint(_ item: PantryItem) throws -> String {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "quantity"); object.removeValue(forKey: "revisionID")
        object.removeValue(forKey: "recordedPlannedPortions")
        return try PlanFingerprint.make(JSONSerialization.data(withJSONObject: InventorySnapshotRules.normalized(object), options: .sortedKeys))
    }

    public static func validateUndo(_ inverse: InventoryMutation, original: InventoryMutation, current: [PantryItem]) throws {
        guard inverse.reason == .undo, inverse.undoing == original.id,
              inverse.uniqueSourceKey == "undo-\(original.id.uuidString)",
              Set(inverse.after.map(\.id)) == Set(original.after.map(\.id)) else { throw InventoryError.invalid }
        for oldAfter in original.after {
            guard let actual = current.first(where: { $0.id == oldAfter.id }),
                  let desired = inverse.after.first(where: { $0.id == oldAfter.id }) else { throw InventoryError.invalid }
            let oldBefore = original.before.first { $0.id == oldAfter.id }
            let expected = actual.quantity - oldAfter.quantity + (oldBefore?.quantity ?? 0)
            guard expected >= -0.000001, abs(desired.quantity - max(0, expected)) < 0.000001 else { throw InventoryError.invalid }
        }
        if let diary = original.diary {
            guard let reverse = inverse.diary, reverse.day == diary.day,
                  try PlanFingerprint.make(reverse.expected) == PlanFingerprint.make(diary.desired),
                  try PlanFingerprint.make(reverse.desired) == PlanFingerprint.make(diary.expected) else { throw InventoryError.invalid }
        } else if inverse.diary != nil { throw InventoryError.invalid }
    }
}

/// Firestore's timestamp bridge may shift the final Date bit. Snapshot comparisons
/// retain nutrient/quantity precision and canonicalize only typed timestamp fields.
enum InventorySnapshotRules {
    static func fingerprint<Value: Encodable>(_ value: Value) throws -> String {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
        return try PlanFingerprint.make(JSONSerialization.data(withJSONObject: normalized(object), options: [.sortedKeys, .fragmentsAllowed]))
    }
    static func normalized(_ object: Any, key: String = "") -> Any {
        if let values = object as? [String: Any] { return values.reduce(into: [String: Any]()) { result, pair in result[pair.key] = normalized(pair.value, key: pair.key) } }
        if let values = object as? [Any] { return values.map { normalized($0) } }
        let dates: Set<String> = ["timestamp", "dateAdded", "bestBefore", "cookedAt", "createdAt", "sourceObservedAt", "sourceUpdatedAt", "observedAt"]
        if dates.contains(key), let value = object as? Double { return (value * 1_000).rounded() / 1_000 }
        return object
    }
}

public extension InventoryPlanningRules {
    static func purchasing(item: GroceryListItem, totalBought: Double, transferAmount: Double, userID: String, now: Date = Date()) throws -> InventoryMutation {
        let transferred = item.transferredToPantryQuantity ?? 0
        guard totalBought.isFinite, transferAmount.isFinite, totalBought >= 0, transferAmount >= 0,
              item.quantityUnknown != true || totalBought > 0,
              transferred + transferAmount <= totalBought + 0.000001 else { throw InventoryError.invalid }
        var updated = item
        updated.purchasedQuantity = totalBought; updated.transferredToPantryQuantity = transferred + transferAmount
        updated.isCompleted = item.quantityUnknown == true ? item.isCompleted : totalBought + 0.000001 >= item.quantity
        var lot = PantryItem(name: item.name, quantity: transferAmount, unit: item.unit, category: item.category, dateAdded: now)
        lot.productSnapshot = item.productSnapshot
        lot.quantityVerified = true; lot.preparation = "As purchased"; lot.revisionID = UUID().uuidString
        return InventoryMutation(userID: userID, title: "Bought \(totalBought.formatted()) \(item.unit) \(item.name) · \(transferAmount.formatted()) to stock", reason: .purchase,
            before: [], after: transferAmount > 0 ? [lot] : [], grocery: GroceryListMutation(before: [item], upserts: [updated], removedIDs: []), now: now)
    }
}
