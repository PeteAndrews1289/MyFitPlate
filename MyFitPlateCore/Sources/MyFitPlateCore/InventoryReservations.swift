import Foundation

public struct PlannedStockRequirement: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case planned, alreadyCooked, needsReview }
    public var id: String
    public var batchID: String?
    public var cookingBatch: MealCookingBatch?
    public var sourceMealID: String
    public var dayID: String
    public var name: String
    public var ingredients: [MealCookingIngredient]
    public var state: State
    public var note: String?
}

public struct PlannedStockAllocation: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var requirementID: String
    public var ingredientIndex: Int
    public var lotID: UUID
    /// Kept in the physical lot's unit; no density or package-size inference.
    public var lotQuantity: Double
    public var requiredQuantity: Double
}

public struct PlannedStockShortage: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var requirementID: String
    public var ingredientIndex: Int
    public var name: String
    public var unit: String
    public var required: Double?
    public var unallocated: Double?
    public var reason: String
}

public struct InventoryReservationSnapshot: Codable, Equatable, Sendable {
    public var referenceDayID: String
    public var generatedAt: Date
    public var requirements: [PlannedStockRequirement]
    public var allocations: [PlannedStockAllocation]
    public var shortages: [PlannedStockShortage]
    public var physicalStock: [PantryItem]
    public var sourceFingerprint: String
    public var excludedPastMeals: Int
    public var targetedBatchID: String?
    public func reserved(in lotID: UUID, excluding requirementID: String? = nil) -> Double {
        allocations.filter { $0.lotID == lotID && $0.requirementID != requirementID }.reduce(0) { $0 + $1.lotQuantity }
    }
    public func available(in lotID: UUID, for requirementID: String? = nil) -> Double? {
        guard let lot = physicalStock.first(where: { $0.id == lotID }), lot.quantityUnknown != true, lot.quantityVerified == true else { return nil }
        return max(0, lot.availableQuantity - reserved(in: lotID, excluding: requirementID))
    }
}

public enum InventoryReservationError: Error, LocalizedError {
    case invalidSources, reservedElsewhere
    public var errorDescription: String? {
        switch self {
        case .invalidSources: "Some saved plans or stock cannot establish a consistent reservation. Their source data is kept; refresh or review it before relying on availability."
        case .reservedElsewhere: "This amount includes stock planned for another cooking batch. Review those plans or explicitly review reallocation before cooking."
        }
    }
}

/// A durable projection of saved plans, never a physical-stock mutation. Recomputing
/// from canonical documents releases removed/changed plans and accepted cooked batches
/// without requiring a second, potentially inconsistent reservation database.
public enum InventoryReservationRules {
    public static func snapshot(plans: [MealPlanDay], stock: [PantryItem], referenceDayID: String,
                                now: Date = Date(), includingBatchID: String? = nil) throws -> InventoryReservationSnapshot {
        guard validDay(referenceDayID), Set(plans.map(\.id)).count == plans.count,
              Set(stock.map(\.id)).count == stock.count,
              plans.allSatisfy({ validDay($0.id) && $0.date.timeIntervalSinceReferenceDate.isFinite &&
                  Set($0.meals.map(\.id)).count == $0.meals.count && $0.meals.allSatisfy { $0.cookingBatch?.cookingDate.timeIntervalSinceReferenceDate.isFinite != false } }) else { throw InventoryReservationError.invalidSources }
        let cookedIDs = Set(stock.filter { $0.cookedBatch != nil && $0.creationUndone != true }.compactMap { $0.cookedBatch?.id })
        let allMeals = plans.sorted { $0.id < $1.id }.flatMap { day in day.meals.map { (day.id, $0) } }
        var requirements: [PlannedStockRequirement] = [], seen = Set<String>(), excludedPast = 0
        for (dayID, meal) in allMeals {
            if meal.preparedStock != nil { continue }
            if let batch = meal.cookingBatch {
                guard seen.insert(batch.id).inserted else { continue }
                let copies = allMeals.filter { $0.1.cookingBatch?.id == batch.id }
                let sourceDay = copies.first(where: { $0.1.id == batch.sourceMealID })?.0
                    ?? MealPlanEditingRules.dayID(batch.cookingDate)
                guard sourceDay >= referenceDayID || batch.id == includingBatchID else { excludedPast += copies.count; continue }
                let consistent = copies.allSatisfy { $0.1.cookingBatch.map { MealPlanCookingRules.sameCookingDefinition($0, batch) } == true }
                let ingredients = batch.ingredientsPerPortion.map { MealCookingIngredient($0.scaled(by: batch.totalPortions)) }
                let state: PlannedStockRequirement.State = cookedIDs.contains(batch.id) ? .alreadyCooked
                    : consistent && batch.totalPortions.isFinite && batch.totalPortions > 0 ? .planned : .needsReview
                requirements.append(.init(id: "batch-" + batch.id, batchID: batch.id, cookingBatch: batch, sourceMealID: batch.sourceMealID,
                    dayID: sourceDay, name: batch.name, ingredients: ingredients, state: state,
                    note: state == .alreadyCooked ? "Already recorded as cooked; no raw ingredients are reserved again."
                        : state == .needsReview ? "Linked copies disagree about the cooking requirement." : nil))
            } else {
                guard dayID >= referenceDayID else { excludedPast += 1; continue }
                requirements.append(.init(id: "meal-\(dayID)-\(meal.id)", sourceMealID: meal.id, dayID: dayID,
                    name: meal.foodItem?.name ?? meal.mealType, ingredients: meal.plannedIngredients.map(MealCookingIngredient.init),
                    state: .planned))
            }
        }
        requirements.sort { $0.dayID == $1.dayID ? $0.id < $1.id : $0.dayID < $1.dayID }
        let orderedStock = stock.sorted { left, right in
            let leftDate = left.bestBefore ?? .distantFuture, rightDate = right.bestBefore ?? .distantFuture
            return leftDate == rightDate ? left.id.uuidString < right.id.uuidString : leftDate < rightDate
        }
        var remaining = Dictionary(uniqueKeysWithValues: orderedStock.map { ($0.id, max(0, $0.availableQuantity)) })
        var allocations: [PlannedStockAllocation] = [], shortages: [PlannedStockShortage] = []
        for requirement in requirements where requirement.state != .alreadyCooked {
            if requirement.ingredients.isEmpty {
                shortages.append(.init(id: requirement.id + "-unmapped", requirementID: requirement.id, ingredientIndex: -1,
                    name: requirement.name, unit: "", required: nil, unallocated: nil, reason: "No mapped raw ingredients; stock coverage is unknown."))
            }
            for (index, ingredient) in requirement.ingredients.enumerated() {
                let id = "\(requirement.id)-\(index)"
                guard requirement.state == .planned, ingredient.hasKnownAmount, ingredient.quantity.isFinite, ingredient.quantity > 0 else {
                    shortages.append(.init(id: id, requirementID: requirement.id, ingredientIndex: index, name: ingredient.name,
                        unit: ingredient.unit, required: nil, unallocated: nil, reason: "Unconfirmed amount or conflicting source; no stock is reserved.")); continue
                }
                var need = ingredient.quantity
                let date = dayDate(requirement.dayID) ?? now
                for lot in orderedStock where compatible(lot, ingredient: ingredient, on: max(now, date)) {
                    guard let capacity = InventoryQuantityRules.convert(remaining[lot.id] ?? 0, from: lot.unit, to: ingredient.unit), capacity > 0,
                          let used = InventoryQuantityRules.convert(min(need, capacity), from: ingredient.unit, to: lot.unit) else { continue }
                    let covered = min(need, capacity)
                    allocations.append(.init(id: "\(id)-\(lot.id.uuidString)", requirementID: requirement.id, ingredientIndex: index,
                        lotID: lot.id, lotQuantity: used, requiredQuantity: covered))
                    remaining[lot.id, default: 0] = max(0, (remaining[lot.id] ?? 0) - used); need -= covered
                    if need <= 0.000001 { break }
                }
                if need > 0.000001 { shortages.append(.init(id: id, requirementID: requirement.id, ingredientIndex: index,
                    name: ingredient.name, unit: ingredient.unit, required: ingredient.quantity, unallocated: need,
                    reason: "Insufficient compatible, confirmed stock by the planned cooking date; unknown, expired or differently prepared lots cannot cover this amount.")) }
            }
        }
        struct Source: Encodable { let plans: [MealPlanDay]; let stock: [PantryItem]; let day: String; let target: String? }
        return .init(referenceDayID: referenceDayID, generatedAt: now, requirements: requirements, allocations: allocations,
            shortages: shortages, physicalStock: orderedStock,
            sourceFingerprint: try PlanFingerprint.make(Source(plans: plans.sorted { $0.id < $1.id }, stock: orderedStock, day: referenceDayID, target: includingBatchID)),
            excludedPastMeals: excludedPast, targetedBatchID: includingBatchID)
    }
    public static func validateCooking(batch: MealCookingBatch, selectedLots: [Int: UUID],
                                       snapshot: InventoryReservationSnapshot, stock: [PantryItem], allowReallocation: Bool = false) throws {
        guard Set(stock.map(\.id)).count == stock.count,
              try PlanFingerprint.make(stock.sorted { $0.id.uuidString < $1.id.uuidString }) == PlanFingerprint.make(snapshot.physicalStock.sorted { $0.id.uuidString < $1.id.uuidString }) else { throw InventoryReservationError.invalidSources }
        let ownID = "batch-" + batch.id
        if snapshot.requirements.first(where: { $0.id == ownID })?.state == .alreadyCooked { throw InventoryError.alreadyApplied }
        guard let own = snapshot.requirements.first(where: { $0.id == ownID }), own.state == .planned,
              let currentBatch = own.cookingBatch, MealPlanCookingRules.sameCookingDefinition(currentBatch, batch) else { throw InventoryReservationError.invalidSources }
        var used: [UUID: Double] = [:]
        for (index, ingredient) in batch.ingredientsPerPortion.enumerated() {
            guard let id = selectedLots[index] else { continue }
            guard let lot = stock.first(where: { $0.id == id }),
                  ingredient.hasKnownAmount, InventoryQuantityRules.usable(lot, now: snapshot.generatedAt), !lot.isCookedBatch,
                  lot.preparation != nil, lot.preparation != "Unknown",
                  lot.preparation != "Cooked" || InventoryQuantityRules.ingredientIdentity(ingredient.name).contains("cooked"),
                  let amount = InventoryQuantityRules.convert(ingredient.quantity * batch.totalPortions, from: ingredient.unit, to: lot.unit) else { throw InventoryReservationError.invalidSources }
            used[id, default: 0] += amount
            guard used[id, default: 0] <= lot.availableQuantity + 0.000001 else { throw InventoryError.changed }
            if !allowReallocation, used[id, default: 0] > (snapshot.available(in: id, for: ownID) ?? 0) + 0.000001 { throw InventoryReservationError.reservedElsewhere }
        }
    }
    private static func compatible(_ lot: PantryItem, ingredient: MealCookingIngredient, on date: Date) -> Bool {
        !lot.isCookedBatch && InventoryQuantityRules.usable(lot, now: date) && lot.preparation != nil && lot.preparation != "Unknown" &&
            (lot.preparation != "Cooked" || InventoryQuantityRules.ingredientIdentity(ingredient.name).contains("cooked")) &&
            InventoryQuantityRules.ingredientIdentity(lot.name) == InventoryQuantityRules.ingredientIdentity(ingredient.name)
    }
    private static func validDay(_ text: String) -> Bool {
        // A saved civil key stays valid after travel, including a date that did not
        // occur in the device's new zone (for example Apia 2011-12-30).
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return false }; return true
    }
    private static func dayDate(_ text: String) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }; return date
    }
}
