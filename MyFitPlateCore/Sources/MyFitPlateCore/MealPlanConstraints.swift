import Foundation

public enum PlanningDiet: String, Codable, CaseIterable, Identifiable, Sendable {
    case unrestricted, vegetarian, vegan, pescatarian
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public func permits(_ other: PlanningDiet) -> Bool {
        switch self {
        case .unrestricted: true
        case .vegan: other == .vegan
        case .vegetarian: other == .vegan || other == .vegetarian
        case .pescatarian: other != .unrestricted
        }
    }
}

/// Personal ingredient review is retained as personal evidence, never an allergy-safe certification.
public struct RecipePlanningProfile: Codable, Equatable, Sendable {
    public var prepMinutes: Int?
    public var equipment: [String]
    public var diet: PlanningDiet
    public var reviewedExclusions: [String]
    public var costPerServing: Double?
    public var currency: String
    public var reviewedAt: Date?
    public var contentFingerprint: String?
    public init(prepMinutes: Int? = nil, equipment: [String] = [], diet: PlanningDiet = .unrestricted,
                reviewedExclusions: [String] = [], costPerServing: Double? = nil, currency: String = "USD",
                reviewedAt: Date? = nil, contentFingerprint: String? = nil) {
        self.prepMinutes = prepMinutes; self.equipment = equipment; self.diet = diet
        self.reviewedExclusions = reviewedExclusions; self.costPerServing = costPerServing
        self.currency = currency; self.reviewedAt = reviewedAt; self.contentFingerprint = contentFingerprint
    }
    public static func fingerprint(_ recipe: Recipe) throws -> String {
        var content = recipe; content.planningProfile = nil; content.id = nil; content.revisionID = nil
        return try RecipePortionRules.revisionID(for: content)
    }
    public func isCurrent(for recipe: Recipe) -> Bool {
        reviewedAt != nil && contentFingerprint == (try? Self.fingerprint(recipe))
    }
}

public struct PlannedMealEvidence: Codable, Equatable, Sendable {
    public var profile: RecipePlanningProfile
    public var mealFingerprint: String
    public static func fingerprint(_ meal: PlannedMeal) throws -> String {
        struct Basis: Encodable { let food: FoodItem?; let ingredients: [String]?; let instructions: String? }
        return try PlanFingerprint.make(Basis(food: meal.foodItem.map(RecipePortionRules.revisionIngredient), ingredients: meal.ingredients, instructions: meal.instructions))
    }
    public var userReviewed: Bool { profile.reviewedAt != nil }
    public func isCurrent(for meal: PlannedMeal) -> Bool { mealFingerprint == (try? Self.fingerprint(meal)) }
    public init(profile: RecipePlanningProfile, meal: PlannedMeal) throws {
        self.profile = profile; mealFingerprint = try Self.fingerprint(meal)
    }
}

public struct MealPlanConstraints: Codable, Equatable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fats: Double
    public var calorieTolerance: Double = 0.20
    public var enforceProtein = true
    public var diet: PlanningDiet = .unrestricted
    public var exclusions: [String] = []
    public var maxPrepMinutes: Int?
    public var weeklyBudget: Double?
    public var currency = "USD"
    public var availableEquipment: [String] = []
    public var householdPortions: Double = 1
    public var practicalWeek: MealPlanningWeekBrief?
    public var ingredientProfile: MealConstraintProfile?
    public var effectiveIngredientProfile: MealConstraintProfile? {
        if let ingredientProfile { return ingredientProfile.adding(diet: diet, exclusions: exclusions) }
        guard diet != .unrestricted || !exclusions.isEmpty else { return nil }
        return MealConstraintProfile(revisionID: "weekly-brief", diet: diet, hardExclusions: exclusions)
    }
    public init(calories: Double, protein: Double, carbs: Double, fats: Double) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fats = fats
    }
    public func validate() throws {
        try effectiveIngredientProfile?.validate()
        try practicalWeek?.validate()
        guard calories.isFinite, (500...10_000).contains(calories),
              [protein, carbs, fats].allSatisfy({ $0.isFinite && (0...2_000).contains($0) }),
              calorieTolerance.isFinite, (0.05...0.5).contains(calorieTolerance),
              householdPortions.isFinite, (1...12).contains(householdPortions),
              maxPrepMinutes.map({ (1...480).contains($0) }) ?? true,
              weeklyBudget.map({ $0.isFinite && $0 > 0 && $0 <= 100_000 }) ?? true,
              exclusions.count <= 30, exclusions.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 100 }),
              !currency.isEmpty else { throw MealPlanConstraintError.invalid }
    }
}

public struct MealPlanConstraintIssue: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var message: String
    public var blocking: Bool
    public var dayID: String?
    public var mealID: String?
}

public struct MealPlanConstraintReport: Codable, Equatable, Sendable {
    public var issues: [MealPlanConstraintIssue]
    public var knownWeeklyCost: Double
    public var unpricedMeals: Int
    public var unknownPrepMeals: Int
    public var largestCalorieDeviation: Double
    public var canSave: Bool { !issues.contains(where: \.blocking) }
}

public enum MealPlanConstraintError: Error, LocalizedError {
    case invalid, noCandidates([String]), infeasible([String])
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review your targets, cooking quantities and constraints."
        case .noCandidates(let reasons): "No saved recipes meet these constraints. " + reasons.prefix(3).joined(separator: " ")
        case .infeasible(let reasons): "A complete week could not meet these limits. " + reasons.prefix(3).joined(separator: " ")
        }
    }
}

public enum MealPlanConstraintRules {
    public static func report(days: [MealPlanDay], constraints c: MealPlanConstraints) -> MealPlanConstraintReport {
        var issues: [MealPlanConstraintIssue] = [], cost = 0.0, unpriced = 0, unknownPrep = 0, largest = 0.0
        func add(_ key: String, _ message: String, _ blocking: Bool, day: String? = nil, meal: String? = nil) {
            issues.append(.init(id: key, message: message, blocking: blocking, dayID: day, mealID: meal))
        }
        do { try c.validate() } catch {
            add("request", error.localizedDescription, true)
            return MealPlanConstraintReport(issues: issues, knownWeeklyCost: 0, unpricedMeals: 0, unknownPrepMeals: 0, largestCalorieDeviation: 0)
        }
        if days.count != 7 || Set(days.map { MealPlanEditingRules.dayID($0.date) }).count != 7 {
            add("week", "The proposal must contain seven distinct days.", true)
        }
        var countedBatches = Set<String>()
        let orderedDays = days.sorted { $0.date < $1.date }
        var cookingMinutesByDay: [String: Int] = [:]
        for (offset, day) in orderedDays.enumerated() {
            let key = MealPlanEditingRules.dayID(day.date)
            let foods = day.meals.compactMap(\.plannedFood)
            let expectedSlots = c.practicalWeek?.slots(offset: offset, date: day.date)
            let plannedSlots = Set(day.meals.map { MealPlanEditingRules.canonicalSlot($0.mealType) })
            let share = expectedSlots.map { Set($0).union(plannedSlots).reduce(0) { $0 + MealPlanningWeekBrief.targetShare($1) } } ?? 1
            let energyTarget = c.calories * share, proteinTarget = c.protein * share
            if let expectedSlots, !Set(expectedSlots).isSubset(of: plannedSlots) {
                add("missing-slots-\(key)", "\(key): a selected meal is missing. Rebuild or leave that slot open in your brief.", true, day: key)
            }
            let total = foods.reduce(0) { $0 + $1.calories }
            let protein = foods.reduce(0) { $0 + $1.protein }
            if !foods.allSatisfy({ food in [food.calories, food.protein, food.carbs, food.fats].allSatisfy { $0.isFinite && (0..<100_000).contains($0) } }) {
                add("invalid-nutrition-\(key)", "Review non-finite or negative nutrition on \(key).", true, day: key)
                continue
            }
            for (label, actual, target) in [("carbohydrate", foods.reduce(0) { $0 + $1.carbs }, c.carbs * share), ("fat", foods.reduce(0) { $0 + $1.fats }, c.fats * share)] where target > 0 && abs(actual-target)/target > 0.30 {
                add("macro-\(label)-\(key)", "\(key): \(label) is more than 30% from your target; review your daily balance.", false, day: key)
            }
            let deviation = abs(total - energyTarget) / max(energyTarget, 1)
            largest = max(largest, deviation)
            if deviation > c.calorieTolerance + 0.000001 {
                add("energy-\(key)", "\(key): \(Int(total.rounded())) cal is outside your chosen target range.", true, day: key)
            }
            if c.enforceProtein && protein + 0.000001 < proteinTarget * 0.85 {
                add("protein-\(key)", "\(key): protein is below 85% of your target.", true, day: key)
            }
            if foods.count != day.meals.count || (day.meals.isEmpty && share > 0) {
                add("nutrition-\(key)", "Each planned meal needs a reviewed nutrition amount.", true, day: key)
            }
            for meal in day.meals {
                if c.householdPortions > 1 && meal.preparedStock == nil && (meal.cookingBatch?.totalPortions ?? 0) < c.householdPortions {
                    add("household-\(meal.id)", "\(meal.foodItem?.name ?? meal.mealType) needs the requested household cooking quantity.", true, day: key, meal: meal.id)
                }
                let evidence = meal.planningEvidence
                let profile = evidence?.isCurrent(for: meal) == true ? evidence?.profile : nil
                let ingredientReport = MealConstraintRules.report(candidate: meal.constraintCandidate,
                    profile: c.effectiveIngredientProfile, recipeReview: profile)
                for issue in ingredientReport.issues {
                    add("ingredient-\(meal.id)-\(issue.id)", issue.message, true, day: key, meal: meal.id)
                }
                let isPrepared = meal.preparedStock != nil
                let isLaterAllocation = meal.cookingBatch.map { $0.sourceMealID != meal.id } ?? false
                let noCooking = profile?.equipment.map(normalized).contains("no cooking") == true
                if isPrepared || isLaterAllocation {
                    // The source cooking event owns its time and cost. Stored portions are already prepared.
                } else if let minutes = profile?.prepMinutes, minutes > 0 || (minutes == 0 && noCooking), minutes <= 480 {
                    if let limit = c.maxPrepMinutes, minutes > limit {
                        add("prep-\(meal.id)", "\(meal.foodItem?.name ?? meal.mealType) takes an estimated \(minutes) minutes; your limit is \(limit).", true, day: key, meal: meal.id)
                    }
                } else {
                    unknownPrep += 1
                    if c.maxPrepMinutes != nil { add("prep-\(meal.id)", "Add a prep-time estimate for \(meal.foodItem?.name ?? meal.mealType).", true, day: key, meal: meal.id) }
                }
                if !c.availableEquipment.isEmpty && !isPrepared && !isLaterAllocation {
                    let allowed = Set(c.availableEquipment.map(normalized))
                    let needed = profile?.equipment ?? []
                    if needed.isEmpty {
                        add("equipment-\(meal.id)", "Review the cooking equipment for \(meal.foodItem?.name ?? meal.mealType).", true, day: key, meal: meal.id)
                    } else if !Set(needed.map(normalized)).subtracting(["no cooking"]).isSubset(of: allowed) {
                        add("equipment-\(meal.id)", "\(meal.foodItem?.name ?? meal.mealType) needs cooking equipment outside your selection.", true, day: key, meal: meal.id)
                    }
                }
                if isPrepared { continue }
                if c.practicalWeek != nil, let batch = meal.cookingBatch,
                   let start = orderedDays.first?.date, let end = Calendar.current.date(byAdding: .day, value: 7, to: start),
                   batch.cookingDate < start || batch.cookingDate >= end { continue }
                if let batch = meal.cookingBatch, !countedBatches.insert(batch.id).inserted { continue }
                if c.practicalWeek != nil {
                    let cookingDay = meal.cookingBatch.map { MealPlanEditingRules.dayID($0.cookingDate) } ?? key
                    let noCooking = profile?.equipment.map(normalized).contains("no cooking") == true
                    if let minutes = profile?.prepMinutes, minutes > 0 {
                        cookingMinutesByDay[cookingDay, default: 0] += minutes
                    } else if !noCooking {
                        add("day-prep-\(meal.id)", "Add a current cooking-time estimate before scheduling \(meal.foodItem?.name ?? meal.mealType).", true, day: key)
                    }
                }
                let quantity = meal.cookingBatch?.totalPortions ?? meal.portions
                if let price = profile?.costPerServing, price.isFinite, price >= 0, profile?.currency == c.currency {
                    cost += price * quantity
                } else { unpriced += 1 }
            }
        }
        if let brief = c.practicalWeek {
            for (offset, day) in orderedDays.enumerated() {
                let key = MealPlanEditingRules.dayID(day.date)
                if let limit = brief.days.first(where: { $0.offset == offset })?.cookingMinutes,
                   (cookingMinutesByDay[key] ?? 0) > limit {
                    add("day-time-\(key)", "\(key): planned cooking exceeds your \(limit)-minute availability.", true, day: key)
                }
            }
            add("partial-week", "Targets cover selected meal slots only. Open meals are not assumed eaten or included in these totals.", false)
        }
        if let budget = c.weeklyBudget {
            if unpriced > 0 { add("price-coverage", "\(unpriced) cooking quantities need your own \(c.currency) price estimates before the budget can be checked.", true) }
            if cost > budget + 0.000001 { add("budget", "Known cooking costs exceed your weekly budget by \((cost-budget).formatted(.number.precision(.fractionLength(2)))) \(c.currency).", true) }
        }
        if unpriced > 0 && c.weeklyBudget == nil { add("price-unknown", "Costs are unknown for \(unpriced) cooking quantities.", false) }
        if unknownPrep > 0 && c.maxPrepMinutes == nil { add("prep-unknown", "Prep time is unknown for \(unknownPrep) meals.", false) }
        return MealPlanConstraintReport(issues: issues, knownWeeklyCost: cost, unpricedMeals: unpriced,
            unknownPrepMeals: unknownPrep, largestCalorieDeviation: largest)
    }

    public static func normalized(_ value: String) -> String {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func contains(_ text: String, phrase: String) -> Bool {
        let source = " " + normalized(text) + " ", query = normalized(phrase)
        return !query.isEmpty && source.contains(" " + query + " ")
    }
}

/// Bounded beam search over frozen, user-saved recipe quantities. It never invents foods or nutrients.
public enum SavedRecipeWeekPlanner {
    public static func makeAsync(recipes: [Recipe], constraints: MealPlanConstraints, starting date: Date,
                                 locked: [MealPlanDay] = [], stock: [PantryItem] = [], savedPlans: [MealPlanDay] = [],
                                 now: Date = Date(), calendar: Calendar = .current, allowPartialReview: Bool = false) async throws -> [MealPlanDay] {
        let worker = Task.detached(priority: .userInitiated) {
            if allowPartialReview, constraints.practicalWeek != nil {
                return try PracticalMealWeekPlanner.make(recipes: recipes, constraints: constraints, starting: date,
                    locked: locked, stock: stock, savedPlans: savedPlans, now: now, calendar: calendar, allowPartialReview: true)
            }
            return try make(recipes: recipes, constraints: constraints, starting: date, locked: locked, stock: stock, savedPlans: savedPlans, now: now, calendar: calendar)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    static func eligibleRecipes(_ recipes: [Recipe], constraints c: MealPlanConstraints) -> ArraySlice<Recipe> {
        return recipes.filter { RecipeLibraryRules.isVisible($0) }.filter { recipe in
            let p = recipe.planningProfile?.isCurrent(for: recipe) == true ? recipe.planningProfile : nil
            let candidate = MealConstraintCandidate(name: recipe.name, ingredients: recipe.ingredients,
                instructions: recipe.instructions.joined(separator: "\n"),
                food: try? RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings, amount: 1)))
            guard MealConstraintRules.report(candidate: candidate, profile: c.effectiveIngredientProfile, recipeReview: p).canAccept else { return false }
            let noCooking = p?.equipment.map(MealPlanConstraintRules.normalized).contains("no cooking") == true
            if let limit = c.maxPrepMinutes, p?.prepMinutes.map({ $0 <= limit && ($0 > 0 || ($0 == 0 && noCooking)) }) != true { return false }
            if c.practicalWeek != nil, !noCooking, p?.prepMinutes.map({ (1...480).contains($0) }) != true { return false }
            if c.weeklyBudget != nil && (p?.costPerServing.map { !$0.isFinite || $0 < 0 } != false || p?.currency != c.currency) { return false }
            if !c.availableEquipment.isEmpty {
                guard let tools = p?.equipment, !tools.isEmpty,
                      Set(tools.map(MealPlanConstraintRules.normalized)).subtracting(["no cooking"]).isSubset(of: Set(c.availableEquipment.map(MealPlanConstraintRules.normalized))) else { return false }
            }
            return recipe.nutritionBasis != nil
        }.prefix(80)
    }
    private struct Choice { let recipe: Recipe; let amount: Double; let food: FoodItem }
    private static func pricePenalty(_ choices: [Choice], constraints c: MealPlanConstraints, fraction: Double) -> Double {
        guard let budget = c.weeklyBudget else { return 0 }
        let cost = choices.reduce(0.0) { $0 + ($1.recipe.planningProfile?.costPerServing ?? 0) * $1.amount * c.householdPortions }
        return max(0, cost / max(budget / 7 * fraction, 0.01) - 0.8) * 3
    }
    private struct Partial { var choices: [Choice]; var energy: Double; var protein: Double; var score: Double }
    public static func make(recipes: [Recipe], constraints c: MealPlanConstraints, starting date: Date,
                            locked: [MealPlanDay] = [], stock: [PantryItem] = [], savedPlans: [MealPlanDay] = [],
                            now: Date = Date(), calendar: Calendar = .current) throws -> [MealPlanDay] {
        try c.validate()
        if c.practicalWeek != nil {
            return try PracticalMealWeekPlanner.make(recipes: recipes, constraints: c, starting: date,
                locked: locked, stock: stock, savedPlans: savedPlans, now: now, calendar: calendar)
        }
        let candidates = eligibleRecipes(recipes, constraints: c)
        guard !candidates.isEmpty else { throw MealPlanConstraintError.noCandidates(["Confirm recipe yields and review the requested diet, exclusions, prep time and prices in your recipe library."]) }
        let choices = candidates.flatMap { recipe in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].compactMap { amount -> Choice? in
            guard let food = try? RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings, amount: amount)),
                  food.calories.isFinite, food.calories > 0, food.protein.isFinite, food.protein >= 0 else { return nil }
            return Choice(recipe: recipe, amount: amount, food: food)
        } }
        guard !choices.isEmpty else { throw MealPlanConstraintError.noCandidates(["Add recipes with confirmed nutrition and yield."]) }
        var days: [MealPlanDay] = [], used: [String: Int] = [:]
        for offset in 0..<7 {
            try Task.checkCancellation()
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { throw MealPlanConstraintError.invalid }
            let lockedMeals = locked.first { calendar.isDate($0.date, inSameDayAs: dayDate) }?.meals ?? []
            let slots = MealPlanEditingRules.mealTypes.filter { type in !lockedMeals.contains { MealPlanEditingRules.canonicalSlot($0.mealType) == type } }
            let baseFoods = lockedMeals.compactMap(\.plannedFood)
            var beam = [Partial(choices: [], energy: baseFoods.reduce(0) { $0+$1.calories }, protein: baseFoods.reduce(0) { $0+$1.protein }, score: 0)]
            for index in slots.indices {
                try Task.checkCancellation()
                let fraction = Double(index+1) / Double(max(slots.count, 1))
                let baseEnergy = baseFoods.reduce(0) { $0+$1.calories }, baseProtein = baseFoods.reduce(0) { $0+$1.protein }
                let targetEnergy = baseEnergy + (c.calories-baseEnergy)*fraction
                let targetProtein = baseProtein + max(0, c.protein-baseProtein)*fraction
                beam = beam.flatMap { state in choices.map { choice -> Partial in
                    let energy = state.energy + choice.food.calories, protein = state.protein + choice.food.protein
                    let key = choice.recipe.id ?? choice.recipe.name
                    let repeatPenalty = Double((used[key] ?? 0) + state.choices.filter { ($0.recipe.id ?? $0.recipe.name) == key }.count) * 0.025
                    return Partial(choices: state.choices + [choice], energy: energy, protein: protein,
                        score: abs(energy-targetEnergy)/c.calories + max(0, targetProtein-protein)/max(c.protein, 1)*0.7 + repeatPenalty + pricePenalty(state.choices + [choice], constraints: c, fraction: fraction))
                } }.sorted { $0.score < $1.score }.prefix(48).map { $0 }
            }
            guard let best = beam.filter({ abs($0.energy-c.calories)/c.calories <= c.calorieTolerance + 0.000001 && (!c.enforceProtein || $0.protein >= c.protein*0.85) }).min(by: { $0.score < $1.score }) else {
                throw MealPlanConstraintError.infeasible(["Add more varied recipes, widen the calorie range, or lower the protein minimum. Locked meals have been kept."])
            }
            var day = MealPlanEditingRules.emptyDay(dayDate, calendar: calendar); day.meals = lockedMeals
            for (index, choice) in best.choices.enumerated() {
                var meal = PlannedMeal(mealType: slots[index], recipeID: choice.recipe.id, foodItem: choice.food,
                    ingredients: try RecipePortionRules.ingredients(for: choice.recipe, selection: .init(unit: .servings, amount: choice.amount)),
                    instructions: choice.recipe.instructions.joined(separator: "\n"))
                var profile = choice.recipe.planningProfile?.isCurrent(for: choice.recipe) == true ? choice.recipe.planningProfile! : RecipePlanningProfile()
                profile.costPerServing = profile.costPerServing.map { $0 * choice.amount }
                meal.planningEvidence = try PlannedMealEvidence(profile: profile, meal: meal)
                if c.householdPortions > 1 { meal = try MealPlanCookingRules.configuring(meal, date: dayDate, cookingPortions: c.householdPortions) }
                day.meals.append(meal); used[choice.recipe.id ?? choice.recipe.name, default: 0] += 1
            }
            day.meals = MealPlanEditingRules.sorted(day.meals); days.append(day)
        }
        let report = MealPlanConstraintRules.report(days: days, constraints: c)
        guard report.canSave else { throw MealPlanConstraintError.infeasible(report.issues.filter(\.blocking).map(\.message)) }
        return days
    }
}
