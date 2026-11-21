import CryptoKit
import Foundation

public enum InventoryIntakeError: LocalizedError {
    case invalid, changed, quantityReview, unavailableStock
    public var errorDescription: String? {
        switch self {
        case .invalid: "The linked stock receipt could not be verified. Your diary and stock have not changed."
        case .changed: "This intake or its linked stock changed. Reload the current entry before retrying; later purchases and intake are kept."
        case .quantityReview: "This serving cannot be converted to its original stock quantity. Keep a compatible serving or review the linked stock amount before saving."
        case .unavailableStock: "The additional linked stock is no longer available. Reduce the amount or review the current stock; nothing was deducted."
        }
    }
}

/// Exact link to an accepted consumption event. No food-name matching or retrospective
/// inference creates these links. The source receipt remains immutable.
public struct InventoryIntakeLink: Codable {
    public var schemaVersion: Int
    public var userID: String
    public var foodID: String
    public var source: InventoryReceipt
    public var currentScale: Double
    public var revisionID: String
    public init(source: InventoryReceipt, currentScale: Double = 1, revisionID: String? = nil) throws {
        let operation = try source.mutation()
        guard source.status == .accepted, operation.reason == .consume, let foodID = operation.diary?.desired?.id else { throw InventoryIntakeError.invalid }
        schemaVersion = 1; userID = operation.userID; self.foodID = foodID; self.source = source
        self.currentScale = currentScale; self.revisionID = revisionID ?? operation.id.uuidString
        try validate()
    }
    public func validate() throws {
        let operation = try source.mutation()
        guard schemaVersion == 1, source.status == .accepted, source.userID == userID, !userID.isEmpty,
              operation.reason == .consume, operation.diary?.expected == nil,
              operation.diary?.desired?.id == foodID, !foodID.isEmpty, foodID.utf8.count <= 1_500,
              currentScale.isFinite, (0...1_000_000).contains(currentScale), !revisionID.isEmpty,
              operation.before.count == operation.after.count, !operation.before.isEmpty,
              Set(operation.before.map(\.id)) == Set(operation.after.map(\.id)),
              operation.before.allSatisfy({ before in
                  guard let after = operation.after.first(where: { $0.id == before.id }) else { return false }
                  return before.unit == after.unit && before.cookedBatch?.id == after.cookedBatch?.id && before.quantity > after.quantity
              }) else { throw InventoryIntakeError.invalid }
    }
    public var stockIDs: [UUID] { (try? source.mutation().before.map(\.id).sorted { $0.uuidString < $1.uuidString }) ?? [] }
    public func originalFood() throws -> FoodItem {
        guard let food = try source.mutation().diary?.desired else { throw InventoryIntakeError.invalid }; return food
    }
}

public struct InventoryIntakeRevisionReceipt: Codable {
    public var schemaVersion = 1
    public var id: String
    public var userID: String
    public var intentFingerprint: String
    public var inventoryEventIDs: [UUID]
    public init(id: String, userID: String, intentFingerprint: String, inventoryEventIDs: [UUID]) {
        self.id = id; self.userID = userID; self.intentFingerprint = intentFingerprint
        self.inventoryEventIDs = inventoryEventIDs.sorted { $0.uuidString < $1.uuidString }
    }
}

public struct InventoryIntakeProjection {
    public var link: InventoryIntakeLink
    public var before: [PantryItem]
    public var after: [PantryItem]
    public var event: InventoryMutation
    public init(link: InventoryIntakeLink, before: [PantryItem], after: [PantryItem], event: InventoryMutation) {
        self.link = link; self.before = before; self.after = after; self.event = event
    }
}

public enum InventoryIntakeRules {
    public struct FoodChange {
        public var id: String
        public var before: FoodItem?
        public var after: FoodItem?
    }
    public static func key(foodID: String) throws -> String {
        guard !foodID.isEmpty, foodID.utf8.count <= 1_500 else { throw InventoryIntakeError.invalid }
        return try PlanFingerprint.make(foodID)
    }
    public static func eventID(userID: String, operationID: String, foodID: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("intake|\(userID)|\(operationID)|\(foodID)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    public static func changes(before: DailyLog, after: DailyLog) throws -> [FoodChange] {
        let left = Dictionary(grouping: before.meals.flatMap(\.foodItems), by: \.id)
        let right = Dictionary(grouping: after.meals.flatMap(\.foodItems), by: \.id)
        var result: [FoodChange] = []
        for id in Set(left.keys).union(right.keys).sorted() {
            let old = left[id] ?? [], new = right[id] ?? []
            let unchanged = old.count == new.count && zip(old, new).allSatisfy { FoodEditPrecondition.sameSnapshot($0, $1) }
            if unchanged { continue }
            guard old.count <= 1, new.count <= 1 else { throw InventoryIntakeError.invalid }
            result.append(FoodChange(id: id, before: old.first, after: new.first))
        }
        return result
    }
    public static func intentFingerprint(_ mutation: DailyLogMutation) throws -> String {
        // Checked FoodDetail retries may refresh their day read hint after a lost ack.
        // Their immutable original/desired edit remains the full food intent.
        let checked = (mutation.foodEditPrecondition.map { [$0] } ?? []) + (mutation.foodEditPreconditions ?? [])
        let edits = checked.isEmpty ? try changes(before: mutation.before, after: mutation.after).map {
            FoodEditPrecondition(foodID: $0.id, expected: $0.before, desired: $0.after)
        } : checked
        struct Intent: Encodable { var owner: String; var id: String; var day: String?; var edits: [FoodEditPrecondition] }
        return try PlanFingerprint.make(Intent(owner: mutation.userID, id: mutation.id, day: mutation.after.id,
            edits: edits.sorted { $0.foodID < $1.foodID }))
    }
    public static func scale(food: FoodItem?, link: InventoryIntakeLink) throws -> Double {
        guard let food else { return 0 }
        try link.validate()
        let original = try link.originalFood()
        guard food.id == link.foodID else { throw InventoryIntakeError.invalid }
        let old = servingQuantity(original), new = servingQuantity(food)
        let ratio: Double
        if old.unit == new.unit, !old.unit.isEmpty, old.amount > 0, new.amount > 0 {
            ratio = new.amount / old.amount
        } else {
            let source = try link.source.mutation()
            let massUnits: Set<String> = ["g", "kg", "oz", "lb"]
            let hasMassBasis = massUnits.contains(old.unit) || original.recipePortionSnapshot?.cookedGrams != nil || original.servingWeight > 1
            guard hasMassBasis, original.servingWeight.isFinite, original.servingWeight > 0,
                  food.servingWeight.isFinite, food.servingWeight > 0 else { throw InventoryIntakeError.quantityReview }
            guard source.before.allSatisfy({ $0.quantityVerified == true && $0.quantityUnknown != true }) else { throw InventoryIntakeError.quantityReview }
            ratio = food.servingWeight / original.servingWeight
        }
        guard ratio.isFinite, ratio > 0, ratio <= 1_000_000 else { throw InventoryIntakeError.quantityReview }
        // A weight edit with unchanged source wording is still an explicit quantity edit.
        if food.servingWeight.isFinite, original.servingWeight > 0, food.servingWeight > 0,
           abs(food.servingWeight / original.servingWeight - ratio) > 0.000001 {
            guard old.unit != new.unit || abs(new.amount - old.amount) < 0.000001 else { throw InventoryIntakeError.quantityReview }
            let weightRatio = food.servingWeight / original.servingWeight
            guard weightRatio.isFinite, weightRatio > 0, weightRatio <= 1_000_000 else { throw InventoryIntakeError.quantityReview }
            return weightRatio
        }
        return ratio
    }
    private static func servingQuantity(_ food: FoodItem) -> (amount: Double, unit: String) {
        let parsed = ServingNutritionCalculator.parseQuantity(from: food.servingSize)
        var unit = IngredientUnitNormalizer.normalized(food.servingUnit ?? parsed.baseDescription)
        if unit.hasPrefix("1 ") { unit = String(unit.dropFirst(2)) }
        if unit == "servings" { unit = "serving" }; if unit == "portions" { unit = "portion" }
        return (food.quantityValue ?? parsed.quantity, unit)
    }
    public static func projecting(link: InventoryIntakeLink, before food: FoodItem?, after desired: FoodItem?, current: [PantryItem],
                                  day: DiaryDayContext, mealName: String, operationID: String, now: Date = Date()) throws -> InventoryIntakeProjection {
        try link.validate()
        guard day.userID == link.userID, !day.isFuture(), !operationID.isEmpty else { throw InventoryIntakeError.invalid }
        let expectedScale = try scale(food: food, link: link), targetScale = try scale(food: desired, link: link)
        guard abs(expectedScale - link.currentScale) <= 0.000001 else { throw InventoryIntakeError.changed }
        let source = try link.source.mutation()
        var before: [PantryItem] = [], after: [PantryItem] = []
        for original in source.before.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let consumed = source.after.first(where: { $0.id == original.id }), let actual = current.first(where: { $0.id == original.id }),
                  actual.quantityVerified == true, actual.quantityUnknown != true, actual.cookedBatch?.id == original.cookedBatch?.id,
                  let amount = InventoryQuantityRules.convert(original.quantity - consumed.quantity, from: original.unit, to: actual.unit) else { throw InventoryIntakeError.changed }
            let difference = amount * (expectedScale - targetScale)
            if difference < 0, actual.isArchived == true { throw InventoryIntakeError.unavailableStock }
            let quantity = actual.quantity + difference
            guard quantity.isFinite, quantity >= -0.000001, quantity <= 1_000_000_000,
                  actual.cookedBatch.map({ quantity <= $0.totalPortions + 0.000001 }) ?? true else { throw InventoryIntakeError.unavailableStock }
            var updated = actual; updated.quantity = max(0, quantity)
            updated.revisionID = "intake-" + eventID(userID: link.userID, operationID: operationID, foodID: link.foodID).uuidString
            if let sourceKey = source.uniqueSourceKey {
                var keys = Set(updated.recordedPlannedPortions ?? [])
                if targetScale == 0 { keys.remove(sourceKey) } else { keys.insert(sourceKey) }
                updated.recordedPlannedPortions = keys.isEmpty ? nil : keys.sorted()
            }
            before.append(actual); after.append(updated)
        }
        var next = link; next.currentScale = targetScale; next.revisionID = operationID
        let action = desired == nil ? "Removed intake" : food == nil ? "Restored intake" : "Edited intake"
        let event = InventoryMutation(id: eventID(userID: link.userID, operationID: operationID, foodID: link.foodID), userID: link.userID,
            title: "\(action) · linked stock adjusted", reason: .correction, before: before, after: after,
            diary: InventoryDiaryPatch(day: day, mealName: mealName, expected: food, desired: desired), now: now)
        try event.validate()
        return InventoryIntakeProjection(link: next, before: before, after: after, event: event)
    }
}
