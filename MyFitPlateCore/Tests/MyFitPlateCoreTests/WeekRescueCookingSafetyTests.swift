import XCTest
@testable import MyFitPlateCore

final class WeekRescueCookingSafetyTests: XCTestCase {
    private var saturday: Date {
        Calendar.current.startOfDay(for: Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7))!)
    }
    private var sunday: Date { Calendar.current.date(byAdding: .day, value: 1, to: saturday)! }
    private func meal(id: String = "rice", type: String = "Dinner") -> PlannedMeal {
        PlannedMeal(id: id, mealType: type, foodItem: FoodItem(id: "food-\(id)", name: id,
            calories: 400, protein: 25, carbs: 50, fats: 10, servingSize: "1 bowl", servingWeight: 300),
            ingredients: ["100 g rice"], instructions: "Cook rice.")
    }
    private func program() -> WorkoutProgram {
        let exercise = RoutineExercise(name: "Row", sets: [ExerciseSet(target: "8")], targetSets: 1)
        let routine = WorkoutRoutine(id: "routine", userID: "u", name: "Upper", dateCreated: saturday, exercises: [exercise])
        return WorkoutProgram(id: "phul", userID: "u", name: "PHUL", routines: [routine], startDate: saturday,
            daysOfWeek: [7], currentProgressIndex: 0)
    }
    private func linkedPlans() throws -> [MealPlanDay] {
        var source = MealPlanEditingRules.emptyDay(saturday)
        source.meals = [try MealPlanCookingRules.configuring(meal(), date: saturday, cookingPortions: 4)]
        let destination = MealPlanEditingRules.emptyDay(sunday)
        return try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: destination, mealType: "Lunch", portions: 1).after
    }
    private func replacingDinner(in source: MealPlanDay) -> MealPlanDay {
        var replacement = source
        replacement.meals[0] = meal(id: "easy-recipe")
        return replacement
    }

    func testPreviewCreationRejectsReplacingSaturdayBatchWithSundayLeftover() throws {
        let plans = try linkedPlans()
        XCTAssertThrowsError(try WeekRescueRules.preview(program: program(), reason: .busyDay,
            workoutDate: sunday, mealChanges: [RescueMealChange(original: plans[0], replacement: replacingDinner(in: plans[0]))], now: saturday)) { error in
            switch error {
            case WeekRescueError.linkedMealBatch: break
            default: XCTFail("Expected an actionable cooking-batch error, got \(error)")
            }
        }
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: [plans[0]], starting: saturday, unitSystem: .metric).first?.quantity, 400)
        XCTAssertEqual(plans[1].meals[0].plannedFood?.calories, 400)
    }

    func testLegacyIncompatibleOverlayDecodesButResolvesToBaseAndPreservesProgramUndo() throws {
        let plans = try linkedPlans()
        struct SavedLegacyChange: Encodable {
            let originalFingerprint: String
            let original: MealPlanDay?
            let replacement: MealPlanDay
        }
        let legacy = SavedLegacyChange(originalFingerprint: try PlanFingerprint.make(Optional(plans[0])),
            original: plans[0], replacement: replacingDinner(in: plans[0]))
        // Deliberately simulate bytes written before the creation guard existed.
        let decoded = try JSONDecoder().decode(RescueMealChange.self, from: JSONEncoder().encode(legacy))
        let rescue = WeekRescueAdjustment(id: "legacy-rescue", createdAt: saturday, reason: .busyDay,
            sourceProgramFingerprint: "legacy-program", slots: [], meals: [decoded], explanation: [])
        var active = program()
        active.currentProgressIndex = 1; active.skippedIndices = [0]; active.weekRescue = rescue
        let restored = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(active))
        XCTAssertEqual(restored.id, "phul")
        XCTAssertEqual(restored.currentProgressIndex, 1)
        XCTAssertEqual(restored.skippedIndices, [0])
        XCTAssertEqual(restored.weekRescue?.id, rescue.id)
        let effective = restored.weekRescue?.resolving(plans[0], on: saturday)
        XCTAssertEqual(try PlanFingerprint.make(effective), try PlanFingerprint.make(Optional(plans[0])))
        XCTAssertEqual(effective?.meals[0].cookingBatch, plans[0].meals[0].cookingBatch)
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: [try XCTUnwrap(effective)], starting: saturday, unitSystem: .metric).first?.quantity, 400)
        let undone = try WeekRescueRules.undoing(id: rescue.id, in: restored)
        XCTAssertNil(undone.weekRescue)
        XCTAssertEqual(undone.id, restored.id)
        XCTAssertEqual(undone.currentProgressIndex, restored.currentProgressIndex)
        XCTAssertEqual(undone.skippedIndices, restored.skippedIndices)
        XCTAssertEqual(try PlanFingerprint.make(undone.routines), try PlanFingerprint.make(restored.routines))
    }

    func testPlainMealReplacementAndWorkoutOnlyRescueRemainAvailable() throws {
        var source = MealPlanEditingRules.emptyDay(saturday); source.meals = [meal()]
        let replacement = replacingDinner(in: source)
        let change = try RescueMealChange(original: source, replacement: replacement)
        let mealRescue = try WeekRescueRules.preview(program: program(), reason: .busyDay, workoutDate: sunday,
            mealChanges: [change], now: saturday)
        XCTAssertEqual(mealRescue.resolving(source, on: saturday)?.meals[0].id, "easy-recipe")
        let workoutOnly = try WeekRescueRules.preview(program: program(), reason: .busyDay, workoutDate: sunday, now: saturday)
        XCTAssertTrue(workoutOnly.meals.isEmpty)
        XCTAssertEqual(try PlanFingerprint.make(workoutOnly.resolving(source, on: saturday)), try PlanFingerprint.make(Optional(source)))
    }

    func testUnrelatedMealChangeDoesNotDisableExistingSharedBatch() throws {
        var source = try linkedPlans()[0]
        source.meals.append(meal(id: "snack", type: "Snack"))
        var replacement = source
        replacement.meals[1] = meal(id: "easy-snack", type: "Snack")
        let change = try RescueMealChange(original: source, replacement: replacement)
        let rescue = try WeekRescueRules.preview(program: program(), reason: .busyDay, workoutDate: sunday,
            mealChanges: [change], now: saturday)
        let effective = try XCTUnwrap(rescue.resolving(source, on: saturday))
        XCTAssertEqual(effective.meals[0].cookingBatch, source.meals[0].cookingBatch)
        XCTAssertEqual(effective.meals[1].id, "easy-snack")
    }
}
