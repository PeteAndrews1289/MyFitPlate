import XCTest
@testable import MyFitPlateCore

final class WaveTwoFlowRulesTests: XCTestCase {
    func testAuthoredSessionAndBlockEndAgreeAcrossUpcomingAgendaAndFuel() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let routine = WorkoutRoutine(id: "routine", userID: "wave2", name: "Normal session", dateCreated: date,
            exercises: [RoutineExercise(id: "exercise", name: "Squat", sets: [ExerciseSet(id: "set", target: "8 reps")])])
        var program = WorkoutProgram(id: "program", userID: "wave2", name: "Four-week block", dateCreated: date,
            routines: [routine], startDate: date, daysOfWeek: [2], currentProgressIndex: 3)
        var block = try WorkoutBlockRules.createRepeatingBlock(for: program, weekCount: 4)
        let variation = try XCTUnwrap(routine.deepCopy()); variation.name = "Lighter final session"
        variation.exercises[0].sets[0].prescription = WorkoutPrescription(kind: .repetitions, lowerBound: 5)
        variation.exercises[0].sets[0].target = "5 reps"
        block.overrides = [WorkoutBlockSlotOverride(slotIndex: 3, routine: variation)]
        program.trainingBlock = block
        XCTAssertEqual(TrainingScheduleOverview.upcoming(program).map(\.routine.name), ["Lighter final session"])
        let candidate = try XCTUnwrap(TrainingFuelSessionAdapter.activeStrengthCandidate(from: program))
        XCTAssertEqual(candidate.title, "Lighter final session")
        XCTAssertTrue(candidate.detail.contains("Week 4, Day 1"))
        program.currentProgressIndex = 4
        XCTAssertTrue(TrainingScheduleOverview.upcoming(program).isEmpty)
        XCTAssertNil(TrainingFuelSessionAdapter.activeStrengthCandidate(from: program))
    }

    func testCopiedRecipePortionKeepsFrozenBatchEvidenceAndScalesSelectedAmountOnce() throws {
        let recipe = Recipe(id: "recipe", name: "Rice batch", ingredients: ["400 g rice"], instructions: ["Cook."],
            nutrition: Nutrition(calories: 1_600, protein: 40, carbs: 300, fats: 16, fiber: 8), servings: 4,
            nutritionBasis: .wholeRecipe, cookedWeightGrams: 800)
        let food = try RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings, amount: 1.5), entryID: "original")
        let context = try XCTUnwrap(DiaryDayContext(userID: "wave2", date: Date(timeIntervalSince1970: 1_700_000_000)))
        let destination = try XCTUnwrap(context.adding(days: 1))
        let log = DailyLog(id: context.dayKey, date: context.startOfDay, meals: [Meal(name: "Dinner", foodItems: [food])])
        var proposal = try DiaryTransferDraft(source: context, destination: destination, sourceLog: log, mode: .copy, foodIDs: [food.id])
        proposal.entries[0].multiplier = 2
        let command = try proposal.freeze()
        let copied = try XCTUnwrap(command.entries.first?.destinationFood)
        XCTAssertNotEqual(copied.id, food.id)
        XCTAssertEqual(copied.calories, 1_200)
        XCTAssertEqual(copied.recipePortionSnapshot?.selectedNutrition.calories, 1_200)
        XCTAssertEqual(copied.recipePortionSnapshot?.selection.amount, 3)
        XCTAssertEqual(copied.recipePortionSnapshot?.cookedGrams, 600)
        XCTAssertEqual(copied.recipePortionSnapshot?.sourceNutrition.calories, 1_600)
        XCTAssertEqual(copied.recipePortionSnapshot?.recipeRevisionID, food.recipePortionSnapshot?.recipeRevisionID)
        XCTAssertEqual(food.calories, 600)
        XCTAssertEqual(food.recipePortionSnapshot?.yieldServings, 4)
    }
}
