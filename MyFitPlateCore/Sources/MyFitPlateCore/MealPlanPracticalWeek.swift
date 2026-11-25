import Foundation

/// Offsets are relative to the explicitly reviewed starting date, never locale weekday numbers.
public struct MealPlanningDayBrief: Codable, Equatable, Sendable, Identifiable {
    public var offset: Int
    public var cookingMinutes: Int
    public var openMealTypes: [String]
    public var id: Int { offset }
    public init(offset: Int, cookingMinutes: Int = 60, openMealTypes: [String] = []) {
        self.offset = offset; self.cookingMinutes = cookingMinutes; self.openMealTypes = openMealTypes
    }
}

public struct MealPlanningWeekBrief: Codable, Equatable, Sendable {
    public var mealTypes: [String]
    public var days: [MealPlanningDayBrief]
    public var repeatMeals: Bool
    public var usePreparedStock: Bool
    public var notBefore: Date?
    public init(mealTypes: [String] = MealPlanEditingRules.mealTypes,
                days: [MealPlanningDayBrief] = (0..<7).map { .init(offset: $0) },
                repeatMeals: Bool = true, usePreparedStock: Bool = true, notBefore: Date? = nil) {
        self.mealTypes = mealTypes; self.days = days; self.repeatMeals = repeatMeals
        self.usePreparedStock = usePreparedStock; self.notBefore = notBefore
    }
    public func validate() throws {
        let allowed = Set(MealPlanEditingRules.mealTypes)
        guard !mealTypes.isEmpty, Set(mealTypes).count == mealTypes.count, Set(mealTypes).isSubset(of: allowed),
              days.count == 7, Set(days.map(\.offset)) == Set(0..<7),
              days.allSatisfy({ (0...480).contains($0.cookingMinutes) && Set($0.openMealTypes).isSubset(of: allowed) }),
              notBefore?.timeIntervalSinceReferenceDate.isFinite != false else { throw MealPlanConstraintError.invalid }
    }
    public func slots(offset: Int, date: Date) -> [String] {
        guard notBefore.map({ date >= $0 }) ?? true else { return [] }
        let open = Set(days.first { $0.offset == offset }?.openMealTypes ?? [])
        return MealPlanEditingRules.mealTypes.filter { mealTypes.contains($0) && !open.contains($0) }
    }
    public static func targetShare(_ slot: String) -> Double {
        switch MealPlanEditingRules.canonicalSlot(slot) {
        case "Breakfast": 0.25
        case "Lunch": 0.30
        case "Dinner": 0.35
        case "Snack": 0.10
        default: 0
        }
    }
}

/// Planning a verified cooked portion does not consume it or change its original cooking graph.
public struct PreparedMealStockReference: Codable, Equatable, Sendable {
    public let stockID: UUID
    public let batchID: String
    public let foodFingerprint: String
    public let reviewedAt: Date
    public init(item: PantryItem, reviewedAt: Date) throws {
        guard let batch = item.cookedBatch, let food = item.portionFood,
              item.creationUndone != true, InventoryQuantityRules.usable(item, now: reviewedAt),
              item.unit == "portion" else { throw InventoryError.invalid }
        stockID = item.id; batchID = batch.id; self.reviewedAt = reviewedAt
        foodFingerprint = try Self.fingerprint(food)
    }
    public static func fingerprint(_ food: FoodItem) throws -> String {
        var content = RecipePortionRules.revisionIngredient(food)
        content.id = "prepared-portion" // Plan adoption changes presentation IDs, never the frozen portion's contents.
        return try PlanFingerprint.make(content)
    }
    public func matches(_ item: PantryItem, meal: PlannedMeal) -> Bool {
        guard item.id == stockID, item.cookedBatch?.id == batchID, item.creationUndone != true,
              let food = item.portionFood, let planned = meal.foodItem else { return false }
        return foodFingerprint == (try? Self.fingerprint(food)) && foodFingerprint == (try? Self.fingerprint(planned))
    }
}

public enum PreparedMealStockRules {
    public static func consumptionKey(meal: PlannedMeal, date: Date, batchID: String) -> String {
        "consume-\(batchID)-\(PlannedMealLoggingRules.entryID(for: meal, date: date))"
    }
    /// Existing pending portions, including other saved weeks, retain first claim on the known stock.
    public static func reserved(item: PantryItem, plans: [MealPlanDay], from date: Date) -> Double {
        guard let batchID = item.cookedBatch?.id else { return 0 }
        let recorded = Set(item.recordedPlannedPortions ?? [])
        var seen = Set<String>()
        return plans.filter { $0.date >= Calendar.current.startOfDay(for: date) }.reduce(0) { total, day in
            total + day.meals.reduce(0) { subtotal, meal in
                guard meal.preparedStock?.stockID == item.id || meal.cookingBatch?.id == batchID else { return subtotal }
                let key = consumptionKey(meal: meal, date: day.date, batchID: batchID)
                guard seen.insert(key).inserted, !recorded.contains(key) else { return subtotal }
                return subtotal + meal.portions
            }
        }
    }
    public static func validate(plans: [MealPlanDay], stock: [PantryItem], now: Date = Date()) throws {
        let references = plans.flatMap { day in day.meals.compactMap { meal -> (Date, PlannedMeal)? in
            meal.preparedStock == nil ? nil : (day.date, meal)
        } }
        for (date, meal) in references where date >= Calendar.current.startOfDay(for: now) {
            guard let reference = meal.preparedStock,
                  let item = stock.first(where: { $0.id == reference.stockID }), reference.matches(item, meal: meal),
                  InventoryQuantityRules.usable(item, now: max(now, date)),
                  reserved(item: item, plans: plans, from: now) <= item.availableQuantity + 0.000001 else {
                throw MealPlanConstraintError.infeasible(["Prepared portions changed or are reserved elsewhere. Rebuild the review from current stock."])
            }
        }
    }
}

/// Uses frozen saved recipes and measured stock. A proposed batch is not physical food.
public enum PracticalMealWeekPlanner {
    private struct Candidate {
        var meal: PlannedMeal
        var recipeKey: String
        var minutes: Int
        var stock: PantryItem?
        var batchID: String?
    }
    private struct Batch {
        var definition: MealCookingBatch
        var recipeKey: String
        var minutes: Int
    }
    public static func make(recipes: [Recipe], constraints c: MealPlanConstraints, starting date: Date,
                            locked: [MealPlanDay], stock: [PantryItem], savedPlans: [MealPlanDay],
                            now: Date = Date(), calendar: Calendar = .current, allowPartialReview: Bool = false) throws -> [MealPlanDay] {
        try c.validate()
        guard let brief = c.practicalWeek else { throw MealPlanConstraintError.invalid }
        var days: [MealPlanDay] = [], batches: [Batch] = [], usedStock: [UUID: Double] = [:]
        var reservationPlans = savedPlans
        for day in locked {
            if let index = reservationPlans.firstIndex(where: { $0.id == day.id }) {
                let ids = Set(reservationPlans[index].meals.map(\.id))
                reservationPlans[index].meals += day.meals.filter { !ids.contains($0.id) }
            } else { reservationPlans.append(day) }
        }
        let recipeCandidates = try SavedRecipeWeekPlanner.eligibleRecipes(recipes, constraints: c).map { recipe -> Candidate in
            let food = try RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings))
            var meal = PlannedMeal(mealType: "Lunch", recipeID: recipe.id, foodItem: food,
                ingredients: try RecipePortionRules.ingredients(for: recipe, selection: .init(unit: .servings)),
                instructions: recipe.instructions.joined(separator: "\n"))
            let profile = recipe.planningProfile?.isCurrent(for: recipe) == true ? recipe.planningProfile! : .init()
            meal.planningEvidence = try PlannedMealEvidence(profile: profile, meal: meal)
            return Candidate(meal: meal, recipeKey: recipe.id ?? recipe.name,
                minutes: profile.prepMinutes ?? (profile.equipment.map(MealPlanConstraintRules.normalized).contains("no cooking") ? 0 : -1))
        }
        for offset in 0..<7 {
            try Task.checkCancellation()
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let dayBrief = brief.days.first(where: { $0.offset == offset }) else { throw MealPlanConstraintError.invalid }
            var day = MealPlanEditingRules.emptyDay(dayDate, calendar: calendar)
            day.meals = locked.first { calendar.isDate($0.date, inSameDayAs: dayDate) }?.meals ?? []
            let latestCookingOffset = brief.days.filter { $0.offset <= offset && $0.cookingMinutes > 0 }.map(\.offset).max() ?? offset
            let latestCookingDate = calendar.date(byAdding: .day, value: latestCookingOffset, to: calendar.startOfDay(for: date)) ?? dayDate
            var countedExistingBatches = Set<String>()
            let cookingMinutesUsed = day.meals.reduce(0) { total, meal in
                guard meal.preparedStock == nil, let evidence = meal.planningEvidence, evidence.isCurrent(for: meal) else { return total }
                if let batch = meal.cookingBatch {
                    guard calendar.isDate(batch.cookingDate, inSameDayAs: dayDate), countedExistingBatches.insert(batch.id).inserted else { return total }
                }
                return total + max(0, evidence.profile.prepMinutes ?? 0)
            }
            var cookingMinutes = cookingMinutesUsed
            let occupied = Set(day.meals.map { MealPlanEditingRules.canonicalSlot($0.mealType) })
            for slot in brief.slots(offset: offset, date: dayDate) where !occupied.contains(slot) {
                let target = c.calories * MealPlanningWeekBrief.targetShare(slot)
                var candidates = recipeCandidates.filter { $0.minutes >= 0 && $0.minutes + cookingMinutes <= dayBrief.cookingMinutes }
                if brief.repeatMeals {
                    for batch in batches where batch.definition.cookingDate >= latestCookingDate && calendar.dateComponents([.day], from: batch.definition.cookingDate, to: dayDate).day.map({ (0...3).contains($0) }) == true {
                        guard let recipe = recipeCandidates.first(where: { $0.recipeKey == batch.recipeKey }) else { continue }
                        var repeated = recipe; repeated.batchID = batch.definition.id; repeated.minutes = 0
                        candidates.append(repeated)
                    }
                }
                if brief.usePreparedStock && recipeCandidates.isEmpty {
                    candidates += try stockCandidates(stock, plans: reservationPlans, constraints: c, date: dayDate, now: now)
                }
                let options = candidates.flatMap { candidate in
                    let exact = (target / max(candidate.meal.foodItem?.calories ?? 0, 1) * 100).rounded() / 100
                    let amounts = Array(Set([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, exact])).sorted().filter { (0.25...8).contains($0) }
                    return amounts.compactMap { amount -> (Candidate, Double, Double)? in
                        guard let food = candidate.meal.foodItem, food.calories.isFinite, food.calories > 0 else { return nil }
                        if let stock = candidate.stock {
                            let capacity = stock.availableQuantity - PreparedMealStockRules.reserved(item: stock, plans: reservationPlans, from: now)
                                - (usedStock[stock.id] ?? 0)
                            guard amount <= capacity + 0.000001 else { return nil }
                        }
                        if let id = candidate.batchID, let batch = batches.first(where: { $0.definition.id == id }),
                           batch.definition.allocatedPortions + amount > 100 { return nil }
                        let energyDifference = abs(food.calories * amount - target) / max(target, 1)
                        guard energyDifference <= c.calorieTolerance + 0.000001 else { return nil }
                        let requiredProtein = c.protein * MealPlanningWeekBrief.targetShare(slot) * 0.85
                        guard !c.enforceProtein || food.protein * amount + 0.000001 >= requiredProtein else { return nil }
                        let convenience = candidate.stock != nil ? -0.25 : candidate.batchID != nil ? -0.20 : 0
                        return (candidate, amount, energyDifference + convenience)
                    }
                }
                guard let best = options.enumerated().min(by: { left, right in
                    left.element.2 == right.element.2 ? left.offset < right.offset : left.element.2 < right.element.2
                })?.element else {
                    if allowPartialReview { continue }
                    throw MealPlanConstraintError.infeasible(["\(dayDate.formatted(date: .abbreviated, time: .omitted)) \(slot.lowercased()): add a compatible recipe, allow more cooking time, or leave this meal open. Prepared stock is never assumed."])
                }
                var meal = best.0.meal
                meal.id = UUID().uuidString; meal.foodItem?.id = "plan-food-\(meal.id)"
                meal.mealType = slot; meal.portionMultiplier = best.1
                if let evidence = best.0.meal.planningEvidence { meal.planningEvidence = try PlannedMealEvidence(profile: evidence.profile, meal: meal) }
                if let item = best.0.stock {
                    meal.preparedStock = try PreparedMealStockReference(item: item, reviewedAt: now)
                    usedStock[item.id, default: 0] += meal.portions
                } else if let id = best.0.batchID, let index = batches.firstIndex(where: { $0.definition.id == id }) {
                    batches[index].definition.allocations.append(.init(mealID: meal.id, date: dayDate, portions: meal.portions))
                    batches[index].definition.totalPortions = max(c.householdPortions, batches[index].definition.allocatedPortions)
                    meal.cookingBatch = batches[index].definition
                } else {
                    meal = try MealPlanCookingRules.configuring(meal, date: dayDate, cookingPortions: max(meal.portions, c.householdPortions))
                    guard let batch = meal.cookingBatch else { throw MealCookingError.invalid }
                    batches.append(.init(definition: batch, recipeKey: best.0.recipeKey, minutes: best.0.minutes))
                    cookingMinutes += best.0.minutes
                }
                day.meals.append(meal)
            }
            day.meals = MealPlanEditingRules.sorted(day.meals); days.append(day)
        }
        let byID = Dictionary(uniqueKeysWithValues: batches.map { ($0.definition.id, $0.definition) })
        days = days.map { day in
            var value = day
            value.meals = day.meals.map { original in
                var meal = original
                if let id = meal.cookingBatch?.id, let batch = byID[id] { meal.cookingBatch = batch }
                return meal
            }
            return value
        }
        if brief.usePreparedStock && !recipeCandidates.isEmpty {
            days = try usingPreparedStock(days, stock: stock, savedPlans: reservationPlans, constraints: c, now: now,
                protectedIDs: Set(locked.flatMap(\.meals).map(\.id)))
        }
        let report = MealPlanConstraintRules.report(days: days, constraints: c)
        guard allowPartialReview || report.canSave else { throw MealPlanConstraintError.infeasible(report.issues.filter(\.blocking).map(\.message)) }
        return days
    }

    private static func usingPreparedStock(_ original: [MealPlanDay], stock: [PantryItem], savedPlans: [MealPlanDay],
                                           constraints c: MealPlanConstraints, now: Date, protectedIDs: Set<String>) throws -> [MealPlanDay] {
        var days = original, used: [UUID: Double] = [:]
        let positions = days.indices.flatMap { day in days[day].meals.indices.map { (day, $0) } }
        // Keep a cooking-day anchor while any planned allocation still needs that batch.
        let ordered = positions.sorted { left, right in
            let a = days[left.0].meals[left.1], b = days[right.0].meals[right.1]
            let sourceA = a.cookingBatch?.sourceMealID == a.id, sourceB = b.cookingBatch?.sourceMealID == b.id
            return sourceA == sourceB ? left.0 < right.0 : !sourceA
        }
        for (dayIndex, mealIndex) in ordered {
            let originalMeal = days[dayIndex].meals[mealIndex], date = days[dayIndex].date
            guard !protectedIDs.contains(originalMeal.id), let originalFood = originalMeal.plannedFood else { continue }
            if let batch = originalMeal.cookingBatch, batch.sourceMealID == originalMeal.id,
               days.flatMap(\.meals).contains(where: { $0.id != originalMeal.id && $0.cookingBatch?.id == batch.id }) { continue }
            let candidates = try stockCandidates(stock, plans: savedPlans, constraints: c, date: date, now: now)
            for candidate in candidates {
                guard let item = candidate.stock, let food = candidate.meal.foodItem, food.calories > 0 else { continue }
                let amount = (originalFood.calories / food.calories * 100).rounded() / 100
                guard (0.25...8).contains(amount), abs(food.calories * amount - originalFood.calories) <= max(1, originalFood.calories * 0.01),
                      !c.enforceProtein || food.protein * amount >= c.protein * MealPlanningWeekBrief.targetShare(originalMeal.mealType) * 0.85,
                      amount <= item.availableQuantity - PreparedMealStockRules.reserved(item: item, plans: savedPlans, from: now) - (used[item.id] ?? 0) + 0.000001 else { continue }
                var meal = candidate.meal; meal.id = originalMeal.id; meal.mealType = originalMeal.mealType
                meal.foodItem?.id = "plan-food-\(meal.id)"; meal.portionMultiplier = amount
                meal.preparedStock = try PreparedMealStockReference(item: item, reviewedAt: now)
                if let evidence = candidate.meal.planningEvidence { meal.planningEvidence = try PlannedMealEvidence(profile: evidence.profile, meal: meal) }
                days[dayIndex].meals[mealIndex] = meal; used[item.id, default: 0] += amount
                if let batch = originalMeal.cookingBatch {
                    var revised = batch; revised.allocations.removeAll { $0.mealID == originalMeal.id }
                    revised.totalPortions = max(c.householdPortions, revised.allocatedPortions)
                    for index in days.indices {
                        for member in days[index].meals.indices where days[index].meals[member].cookingBatch?.id == batch.id {
                            days[index].meals[member].cookingBatch = revised
                        }
                    }
                }
                break
            }
        }
        return days
    }

    private static func stockCandidates(_ stock: [PantryItem], plans: [MealPlanDay], constraints: MealPlanConstraints,
                                        date: Date, now: Date) throws -> [Candidate] {
        try stock.sorted { ($0.bestBefore ?? .distantFuture) < ($1.bestBefore ?? .distantFuture) }.compactMap { item in
            guard item.creationUndone != true, item.cookedAt.map({ $0 <= now }) == true,
                  InventoryQuantityRules.usable(item, now: max(date, now)), let food = item.portionFood,
                  let batch = item.cookedBatch, item.unit == "portion" else { return nil }
            var meal = PlannedMeal(mealType: "Lunch", foodItem: food,
                ingredients: batch.ingredientsPerPortion.map(\.originalText), instructions: batch.instructions)
            if let source = plans.flatMap(\.meals).first(where: { $0.cookingBatch?.id == batch.id }),
               let evidence = source.planningEvidence, evidence.isCurrent(for: source),
               let sourceFood = source.foodItem,
               (try? PreparedMealStockReference.fingerprint(sourceFood)) == (try? PreparedMealStockReference.fingerprint(food)) {
                meal.planningEvidence = try PlannedMealEvidence(profile: evidence.profile, meal: meal)
            }
            let profile = meal.planningEvidence?.profile
            guard constraints.diet == .unrestricted || profile.map({ constraints.diet.permits($0.diet) }) == true else { return nil }
            let text = ([food.name] + (meal.ingredients ?? [])).joined(separator: " ")
            guard constraints.exclusions.allSatisfy({ exclusion in
                !MealPlanConstraintRules.contains(text, phrase: exclusion)
                    && profile?.reviewedExclusions.contains(where: { MealPlanConstraintRules.normalized($0) == MealPlanConstraintRules.normalized(exclusion) }) == true
            }) else { return nil }
            return Candidate(meal: meal, recipeKey: batch.id, minutes: 0, stock: item)
        }
    }
}
