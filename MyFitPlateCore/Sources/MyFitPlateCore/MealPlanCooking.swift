import Foundation

public struct MealCookingIngredient: Codable, Equatable, Sendable {
    public let name: String
    public let quantity: Double
    public let unit: String
    public let originalText: String
    public let amountKnown: Bool?
    public var hasKnownAmount: Bool { amountKnown ?? (InventoryQuantityRules.explicitLeadingAmount(originalText) != nil) }

    public init(_ ingredient: ParsedIngredient) {
        name = ingredient.name; quantity = ingredient.quantity
        unit = ingredient.unit; originalText = ingredient.originalString
        amountKnown = InventoryQuantityRules.explicitLeadingAmount(ingredient.originalString) != nil
    }

    public func scaled(by multiplier: Double) -> ParsedIngredient {
        ParsedIngredient(quantity: quantity * multiplier, unit: unit, name: name, originalString: originalText)
    }
}

public struct MealCookingAllocation: Codable, Equatable, Sendable {
    public var mealID: String
    public var date: Date
    public var portions: Double
    public init(mealID: String, date: Date, portions: Double) {
        self.mealID = mealID; self.date = date; self.portions = portions
    }
}

/// A replicated, self-contained planning snapshot, not evidence that food has been cooked.
/// Every allocation retains the ingredient basis even if the original meal is removed.
public struct MealCookingBatch: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: Int
    public var id: String
    public var revisionID: String
    public var sourceMealID: String
    public var cookingDate: Date
    public var name: String
    public var totalPortions: Double
    public var ingredientsPerPortion: [MealCookingIngredient]
    public var instructions: String?
    public var allocations: [MealCookingAllocation]

    public var allocatedPortions: Double { allocations.reduce(0) { $0 + $1.portions } }
    public var unallocatedPortions: Double { max(0, totalPortions - allocatedPortions) }

    public init(id: String = UUID().uuidString, revisionID: String = UUID().uuidString,
                sourceMealID: String, cookingDate: Date, name: String, totalPortions: Double,
                ingredientsPerPortion: [MealCookingIngredient], instructions: String?,
                allocations: [MealCookingAllocation]) {
        schemaVersion = 1; self.id = id; self.revisionID = revisionID; self.sourceMealID = sourceMealID
        self.cookingDate = cookingDate; self.name = name; self.totalPortions = totalPortions
        self.ingredientsPerPortion = ingredientsPerPortion; self.instructions = instructions; self.allocations = allocations
    }
}

public enum MealCookingError: Error, LocalizedError {
    case invalid, overallocated, changed, linkedBatch, destination, alreadyCooked
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review the cooking amount and ingredient quantities before saving."
        case .overallocated: "There aren't enough unallocated portions in this batch. Reduce the leftover amount."
        case .changed: "This cooking plan changed. Close this review and reopen the meal to use its latest batch."
        case .linkedBatch: "This meal shares a cooking batch. Keep its portions unchanged, or make an independent copy to plan a different amount."
        case .destination: "Choose a leftover date on or after the cooking date, within the next seven days."
        case .alreadyCooked: "This batch was already recorded as cooked. Keep its cooking quantity, or make an independent meal to plan another batch. Actual food and stock stay unchanged."
        }
    }
}

public struct MealCookingRequirement {
    public let id: String
    public let date: Date
    public let name: String
    public let ingredients: [ParsedIngredient]
    public let instructions: String?
}

public enum MealPlanCookingRules {
    public static func sameCookingDefinition(_ a: MealCookingBatch, _ b: MealCookingBatch) -> Bool {
        a.totalPortions == b.totalPortions && a.ingredientsPerPortion == b.ingredientsPerPortion && a.cookingDate == b.cookingDate
    }
    public static func changedCookingDefinitions(in change: MealPlanChange) -> Set<String> {
        let before = Dictionary(grouping: change.before.flatMap(\.meals).compactMap(\.cookingBatch), by: \.id)
        let after = Dictionary(grouping: change.after.flatMap(\.meals).compactMap(\.cookingBatch), by: \.id)
        return Set(before.keys).intersection(after.keys).filter { id in
            guard let a = before[id]?.first, let b = after[id]?.first else { return false }
            return !sameCookingDefinition(a, b)
        }
    }
    /// Old plans keep their exact personal-portion ingredient behavior. Explicit batches
    /// appear once, on their cooking date; a later leftover does not create a new purchase.
    public static func requirements(from days: [MealPlanDay], starting windowStart: Date? = nil) -> [MealCookingRequirement] {
        let start = Calendar.current.startOfDay(for: windowStart ?? days.map(\.date).min() ?? Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        var seenBatches = Set<String>()
        var requirements: [MealCookingRequirement] = []
        for day in days.sorted(by: { $0.date < $1.date }) {
            for meal in day.meals {
                if meal.preparedStock != nil { continue }
                if let batch = meal.cookingBatch {
                    guard batch.cookingDate >= start, batch.cookingDate < end,
                          seenBatches.insert(batch.id).inserted else { continue }
                    requirements.append(MealCookingRequirement(id: "batch-\(batch.id)", date: batch.cookingDate, name: batch.name,
                        ingredients: batch.ingredientsPerPortion.map { $0.scaled(by: batch.totalPortions) },
                        instructions: batch.instructions))
                } else {
                    requirements.append(MealCookingRequirement(id: meal.id, date: day.date, name: meal.foodItem?.name ?? meal.mealType,
                        ingredients: meal.plannedIngredients, instructions: meal.instructions))
                }
            }
        }
        return requirements
    }

    public static func summary(for meal: PlannedMeal) -> String? {
        if meal.preparedStock != nil { return "Use recorded prepared portions · availability checked before saving and use" }
        guard let batch = meal.cookingBatch else { return nil }
        let amount = batch.totalPortions.formatted(.number.precision(.fractionLength(0...2)))
        if batch.sourceMealID == meal.id {
            return "Cook \(amount) original portions · \(batch.unallocatedPortions.formatted(.number.precision(.fractionLength(0...2)))) unallocated"
        }
        return "Leftovers · batch planned \(batch.cookingDate.formatted(date: .abbreviated, time: .omitted))"
    }

    public static func configuring(_ meal: PlannedMeal, date: Date, cookingPortions: Double?) throws -> PlannedMeal {
        var result = meal
        guard meal.preparedStock == nil || cookingPortions == nil else { throw MealCookingError.linkedBatch }
        if let old = meal.cookingBatch, old.allocations.count > 1 { throw MealCookingError.linkedBatch }
        guard let amount = cookingPortions else { result.cookingBatch = nil; return result }
        guard amount.isFinite, amount >= meal.portions, amount <= 100, meal.foodItem != nil else { throw MealCookingError.invalid }
        var original = meal; original.portionMultiplier = 1
        let ingredients = original.plannedIngredients.map(MealCookingIngredient.init)
        guard !ingredients.isEmpty, ingredients.allSatisfy({ $0.quantity.isFinite && $0.quantity > 0 }) else { throw MealCookingError.invalid }
        result.cookingBatch = MealCookingBatch(id: meal.cookingBatch?.id ?? UUID().uuidString,
            sourceMealID: meal.id, cookingDate: Calendar.current.startOfDay(for: date),
            name: meal.foodItem?.name ?? meal.mealType, totalPortions: amount,
            ingredientsPerPortion: ingredients, instructions: meal.instructions,
            allocations: [MealCookingAllocation(mealID: meal.id, date: Calendar.current.startOfDay(for: date), portions: meal.portions)])
        return result
    }

    public static func relatedDates(for meal: PlannedMeal) -> [Date] {
        guard let batch = meal.cookingBatch else { return [] }
        return Array(Set(batch.allocations.map { Calendar.current.startOfDay(for: $0.date) })).sorted()
    }

    public static func editingLinked(_ updatedMeal: PlannedMeal, original: PlannedMeal, source: MealPlanDay, relatedDays: [MealPlanDay]) throws -> MealPlanChange {
        guard let batch = original.cookingBatch, updatedMeal.id == original.id,
              let sourceMeal = source.meals.first(where: { $0.id == original.id }),
              try PlanFingerprint.make(sourceMeal) == PlanFingerprint.make(original),
              try PlanFingerprint.make(updatedMeal.foodItem) == PlanFingerprint.make(original.foodItem) else { throw MealCookingError.changed }
        let byID = Dictionary(grouping: relatedDays, by: { MealPlanEditingRules.dayID($0.date) })
        guard byID.values.allSatisfy({ $0.count == 1 }),
              Set(relatedDates(for: original).map { MealPlanEditingRules.dayID($0) }).isSubset(of: Set(byID.keys)),
              relatedDays.flatMap(\.meals).filter({ $0.cookingBatch?.id == batch.id }).allSatisfy({ $0.cookingBatch == batch }) else { throw MealCookingError.changed }
        guard let fetchedSource = relatedDays.first(where: { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(source.date) }),
              try PlanFingerprint.make(fetchedSource.meals) == PlanFingerprint.make(source.meals) else { throw MealCookingError.changed }
        var updated = batch; updated.revisionID = UUID().uuidString
        updated.totalPortions = updatedMeal.cookingBatch?.totalPortions ?? batch.totalPortions
        updated.allocations = batch.allocations.map { allocation in
            var value = allocation; if value.mealID == original.id { value.portions = updatedMeal.portions }; return value
        }
        guard updated.totalPortions.isFinite, updated.totalPortions >= updated.allocatedPortions else { throw MealCookingError.overallocated }
        let before = relatedDays.sorted { $0.date < $1.date }
        let after = before.map { day in
            var value = day
            value.meals = day.meals.map { member in
                guard member.cookingBatch?.id == batch.id else { return member }
                var result = member.id == original.id ? updatedMeal : member; result.cookingBatch = updated; return result
            }; return value
        }
        let change = MealPlanChange(title: "Shared meal quantities changed", before: before, after: after)
        try MealPlanEditingRules.validate(change); return change
    }

    /// Remove one planned allocation and release its capacity without erasing its batch's
    /// other meals. A surviving leftover retains the full, frozen cooking requirement.
    public static func removing(meal: PlannedMeal, source: MealPlanDay, relatedDays: [MealPlanDay]) throws -> MealPlanChange {
        guard let batch = meal.cookingBatch,
              let current = source.meals.first(where: { $0.id == meal.id }),
              try PlanFingerprint.make(current) == PlanFingerprint.make(meal) else { throw MealCookingError.changed }
        let relatedIDs = relatedDays.map { MealPlanEditingRules.dayID($0.date) }
        guard Set(relatedIDs).count == relatedIDs.count else { throw MealCookingError.changed }
        var byDate = Dictionary(uniqueKeysWithValues: zip(relatedIDs, relatedDays))
        byDate[MealPlanEditingRules.dayID(source.date)] = source
        guard Set(relatedDates(for: meal).map { MealPlanEditingRules.dayID($0) }).isSubset(of: Set(byDate.keys)) else {
            throw MealCookingError.changed
        }
        for member in byDate.values.flatMap(\.meals) where member.cookingBatch?.id == batch.id {
            guard member.cookingBatch == batch else { throw MealCookingError.changed }
        }
        var updated = batch
        updated.revisionID = UUID().uuidString
        updated.allocations = byDate.values.flatMap { day in
            day.meals.compactMap { member in
                guard member.cookingBatch?.id == batch.id, member.id != meal.id else { return nil }
                return MealCookingAllocation(mealID: member.id, date: Calendar.current.startOfDay(for: day.date), portions: member.portions)
            }
        }
        if !updated.allocations.isEmpty,
           let cookingWeek = Calendar.current.dateInterval(of: .weekOfYear, for: batch.cookingDate),
           !updated.allocations.contains(where: { $0.date >= cookingWeek.start && $0.date < cookingWeek.end }) {
            // A future-week leftover cannot be the sole query anchor for an earlier
            // cooking week. Keep one allocation in that week until rescheduling exists.
            throw MealCookingError.linkedBatch
        }
        let before = byDate.values.sorted { $0.date < $1.date }
        let after = before.map { day -> MealPlanDay in
            var result = day
            result.meals = day.meals.filter { $0.id != meal.id }.map { member in
                guard member.cookingBatch?.id == batch.id else { return member }
                var value = member; value.cookingBatch = updated; return value
            }
            return result
        }
        let change = MealPlanChange(title: "Planned allocation removed", before: before, after: after)
        try MealPlanEditingRules.validate(change)
        return change
    }

    /// Every known allocation day is re-read and compare-and-set together. Missing meals
    /// release a deleted plan allocation; surviving mismatched snapshots require a reload.
    public static func planningLeftover(from meal: PlannedMeal, source: MealPlanDay, relatedDays: [MealPlanDay], destination: MealPlanDay, mealType: String, portions: Double) throws -> MealPlanChange {
        guard let current = source.meals.first(where: { $0.id == meal.id }),
              try PlanFingerprint.make(current) == PlanFingerprint.make(meal),
              let originalBatch = meal.cookingBatch else { throw MealCookingError.changed }
        let dayDistance = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: originalBatch.cookingDate),
            to: Calendar.current.startOfDay(for: destination.date)).day ?? -1
        guard (0...7).contains(dayDistance) else { throw MealCookingError.destination }
        guard portions.isFinite, (0.25...8).contains(portions),
              !MealPlanEditingRules.canonicalSlot(mealType).isEmpty else { throw MealCookingError.invalid }
        if MealPlanEditingRules.dayID(source.date) == MealPlanEditingRules.dayID(destination.date) {
            guard try PlanFingerprint.make(source.meals) == PlanFingerprint.make(destination.meals) else { throw MealCookingError.changed }
        }
        let relatedIDs = relatedDays.map { MealPlanEditingRules.dayID($0.date) }
        guard Set(relatedIDs).count == relatedIDs.count else { throw MealCookingError.changed }
        var daysByID = Dictionary(uniqueKeysWithValues: zip(relatedIDs, relatedDays))
        daysByID[MealPlanEditingRules.dayID(source.date)] = source
        daysByID[MealPlanEditingRules.dayID(destination.date)] = destination
        guard Set(relatedDates(for: meal).map { MealPlanEditingRules.dayID($0) }).isSubset(of: Set(daysByID.keys)) else {
            throw MealCookingError.changed
        }
        var batch = originalBatch
        let members = daysByID.values.flatMap { day in day.meals.compactMap { member -> MealCookingAllocation? in
            guard member.cookingBatch?.id == batch.id else { return nil }
            return MealCookingAllocation(mealID: member.id, date: Calendar.current.startOfDay(for: day.date), portions: member.portions)
        } }
        for member in daysByID.values.flatMap(\.meals) where member.cookingBatch?.id == batch.id {
            guard member.cookingBatch == originalBatch else { throw MealCookingError.changed }
        }
        guard Set(members.map(\.mealID)).count == members.count else { throw MealCookingError.changed }
        batch.allocations = members
        guard batch.allocatedPortions + portions <= batch.totalPortions + 0.000001 else { throw MealCookingError.overallocated }
        var leftover = MealPlanEditingRules.duplicate(meal)
        leftover.mealType = MealPlanEditingRules.canonicalSlot(mealType); leftover.portionMultiplier = portions
        batch.revisionID = UUID().uuidString
        batch.allocations.append(MealCookingAllocation(mealID: leftover.id, date: Calendar.current.startOfDay(for: destination.date), portions: portions))
        leftover.cookingBatch = batch
        let before = daysByID.values.sorted { $0.date < $1.date }
        var after = before.map { day -> MealPlanDay in
            var result = day
            result.meals = day.meals.map { member in
                guard member.cookingBatch?.id == batch.id else { return member }
                var updated = member; updated.cookingBatch = batch; return updated
            }
            return result
        }
        guard let destinationIndex = after.firstIndex(where: { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(destination.date) }) else {
            throw MealCookingError.changed
        }
        after[destinationIndex].meals.append(leftover)
        after[destinationIndex].meals = MealPlanEditingRules.sorted(after[destinationIndex].meals)
        let change = MealPlanChange(title: "Leftovers planned", before: before, after: after)
        try MealPlanEditingRules.validate(change)
        return change
    }

    public static func validate(_ meal: PlannedMeal, on date: Date) throws {
        if let reference = meal.preparedStock {
            guard meal.cookingBatch == nil, !reference.batchID.isEmpty, reference.reviewedAt.timeIntervalSinceReferenceDate.isFinite,
                  let food = meal.foodItem, reference.foodFingerprint == (try? PreparedMealStockReference.fingerprint(food)) else { throw MealCookingError.invalid }
        }
        guard let batch = meal.cookingBatch else { return }
        guard batch.schemaVersion == 1, !batch.id.isEmpty, !batch.revisionID.isEmpty,
              batch.totalPortions.isFinite, (0.25...100).contains(batch.totalPortions),
              !batch.ingredientsPerPortion.isEmpty,
              batch.ingredientsPerPortion.allSatisfy({ $0.quantity.isFinite && $0.quantity > 0 && !$0.name.isEmpty }),
              !batch.allocations.isEmpty, batch.allocations.count <= 32,
              Set(batch.allocations.map(\.mealID)).count == batch.allocations.count,
              batch.allocations.allSatisfy({ $0.portions.isFinite && (0.25...8).contains($0.portions) }),
              batch.allocatedPortions <= batch.totalPortions + 0.000001,
              let allocation = batch.allocations.first(where: { $0.mealID == meal.id }),
              abs(allocation.portions - meal.portions) < 0.000001,
              MealPlanEditingRules.dayID(allocation.date) == MealPlanEditingRules.dayID(date) else { throw MealCookingError.invalid }
    }

    public static func validateChanges(_ change: MealPlanChange) throws {
        let changedDates = Set(change.before.map { MealPlanEditingRules.dayID($0.date) })
        let oldMembers = change.before.flatMap(\.meals)
        let newMembers = change.after.flatMap(\.meals)
        for oldMeal in oldMembers {
            guard let oldBatch = oldMeal.cookingBatch else { continue }
            let replacement = newMembers.first { $0.id == oldMeal.id }
            let membershipChanged = replacement?.cookingBatch?.id != oldBatch.id
            let batchChanged = replacement?.cookingBatch != oldBatch
            guard membershipChanged || batchChanged else { continue }
            guard Set(oldBatch.allocations.map { MealPlanEditingRules.dayID($0.date) }).isSubset(of: changedDates) else {
                throw MealCookingError.linkedBatch
            }
            let survivors = newMembers.filter { $0.cookingBatch?.id == oldBatch.id }
            if let snapshot = survivors.first?.cookingBatch {
                guard Set(snapshot.allocations.map(\.mealID)) == Set(survivors.map(\.id)) else {
                    throw MealCookingError.linkedBatch
                }
            }
        }
        for meal in newMembers {
            guard let batch = meal.cookingBatch,
                  let previous = oldMembers.first(where: { $0.cookingBatch?.id == batch.id })?.cookingBatch,
                  previous != batch else { continue }
            guard Set(previous.allocations.map { MealPlanEditingRules.dayID($0.date) }).isSubset(of: changedDates) else {
                throw MealCookingError.linkedBatch
            }
        }
        for batch in newMembers.compactMap(\.cookingBatch) {
            let members = newMembers.filter { $0.cookingBatch?.id == batch.id }
            guard members.allSatisfy({ $0.cookingBatch == batch }) else { throw MealCookingError.changed }
        }
    }
}
