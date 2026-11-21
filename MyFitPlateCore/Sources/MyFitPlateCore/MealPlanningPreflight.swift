import Foundation

public struct MealRecipeReadiness: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let issues: [String]
    public var usable: Bool { issues.isEmpty }
}
public struct MealPlanningMissingSlot: Identifiable, Equatable {
    public let dayOffset: Int
    public let date: Date
    public let mealType: String
    public var id: String { "\(MealPlanEditingRules.dayID(date))-\(mealType)" }
}
public enum MealPlanningPreflight {
    public static func recipes(_ recipes: [Recipe], constraints c: MealPlanConstraints) -> [MealRecipeReadiness] {
        recipes.filter { RecipeLibraryRules.isVisible($0) }.map { recipe in
            let profile = recipe.planningProfile?.isCurrent(for: recipe) == true ? recipe.planningProfile : nil
            let food = try? RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings))
            var issues = MealConstraintRules.report(candidate: .init(name: recipe.name, ingredients: recipe.ingredients,
                instructions: recipe.instructions.joined(separator: "\n"), food: food),
                profile: c.effectiveIngredientProfile, recipeReview: profile).issues.map(\.message)
            if recipe.nutritionBasis == nil || food == nil { issues.append("Confirm nutrition basis and recipe yield.") }
            if let food, !food.calories.isFinite || food.calories <= 0 || !food.protein.isFinite || food.protein < 0 {
                issues.append("Confirm finite calories and protein per portion.")
            }
            let noCooking = profile?.equipment.map(MealPlanConstraintRules.normalized).contains("no cooking") == true
            if c.practicalWeek != nil, !noCooking, profile?.prepMinutes.map({ (1...480).contains($0) }) != true {
                issues.append("Add a current prep-time estimate, or review this recipe as no cooking.")
            }
            if let limit = c.maxPrepMinutes {
                if let minutes = profile?.prepMinutes, minutes > 0 || (minutes == 0 && noCooking) {
                    if minutes > limit { issues.append("Prep takes \(minutes) min; the recipe limit is \(limit) min.") }
                } else { issues.append("Add a prep-time estimate for the \(limit)-minute limit.") }
            }
            if c.weeklyBudget != nil {
                if profile?.costPerServing.map({ $0.isFinite && $0 >= 0 }) != true || profile?.currency != c.currency {
                    issues.append("Add a current \(c.currency) price per original serving.")
                }
            }
            if !c.availableEquipment.isEmpty {
                let tools = profile?.equipment ?? []
                if tools.isEmpty { issues.append("Review the required equipment.") } else {
                    let unavailable = Set(tools.map(MealPlanConstraintRules.normalized)).subtracting(["no cooking"])
                        .subtracting(c.availableEquipment.map(MealPlanConstraintRules.normalized))
                    if !unavailable.isEmpty { issues.append("Needs unavailable equipment: " + unavailable.sorted().joined(separator: ", ") + ".") }
                }
            }
            return .init(id: recipe.id ?? recipe.name, name: recipe.name, issues: Array(NSOrderedSet(array: issues)) as? [String] ?? issues)
        }
    }
    public static func missingSlots(days: [MealPlanDay], constraints c: MealPlanConstraints) -> [MealPlanningMissingSlot] {
        guard let brief = c.practicalWeek, days.count == 7,
              Set(days.map { MealPlanEditingRules.dayID($0.date) }).count == 7 else { return [] }
        return days.sorted { $0.date < $1.date }.enumerated().flatMap { offset, day in
            let occupied = Set(day.meals.map { MealPlanEditingRules.canonicalSlot($0.mealType) })
            return brief.slots(offset: offset, date: day.date).filter { !occupied.contains($0) }
                .map { MealPlanningMissingSlot(dayOffset: offset, date: day.date, mealType: $0) }
        }
    }
    /// The caller explicitly reviews each open slot. No dietary, nutrition, stock
    /// or cooking constraint is relaxed; only the selected scope changes.
    public static func leavingOpen(_ slot: MealPlanningMissingSlot, in constraints: MealPlanConstraints) throws -> MealPlanConstraints {
        var c = constraints
        guard var brief = c.practicalWeek, let index = brief.days.firstIndex(where: { $0.offset == slot.dayOffset }),
              brief.slots(offset: slot.dayOffset, date: slot.date).contains(slot.mealType) else { throw MealPlanConstraintError.invalid }
        if !brief.days[index].openMealTypes.contains(slot.mealType) { brief.days[index].openMealTypes.append(slot.mealType) }
        c.practicalWeek = brief; try c.validate(); return c
    }
}
