import XCTest
@testable import MyFitPlateCore

final class DataExporterTests: XCTestCase {

    func testFoodLogCSVRowsAndHeader() {
        let item = FoodItem(name: "Greek Yogurt", calories: 160, protein: 15.5, carbs: 8, fats: 6, servingSize: "1 cup", servingWeight: 245)
        let log = DailyLog(date: Date(timeIntervalSince1970: 1_700_000_000), meals: [Meal(name: "Breakfast", foodItems: [item])])

        let csv = DataExporter.foodLogCSV(from: [log])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines[0], "date,meal,food,calories,protein_g,carbs_g,fats_g,serving,serving_weight_g")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasSuffix("Breakfast,Greek Yogurt,160,15.5,8,6,1 cup,245"))
    }

    func testFieldsWithCommasAndQuotesAreEscaped() {
        let item = FoodItem(name: "Chicken, Rice \"Bowl\"", calories: 500, servingSize: "1 bowl, large", servingWeight: 400)
        let log = DailyLog(date: Date(), meals: [Meal(name: "Lunch", foodItems: [item])])

        let csv = DataExporter.foodLogCSV(from: [log])

        XCTAssertTrue(csv.contains("\"Chicken, Rice \"\"Bowl\"\"\""))
        XCTAssertTrue(csv.contains("\"1 bowl, large\""))
    }

    func testSpreadsheetFormulaPrefixesAreNeutralized() {
        XCTAssertEqual(DataExporter.escape("=1+1"), "'=1+1")
        XCTAssertEqual(DataExporter.escape(" +SUM(A1:A2)"), "' +SUM(A1:A2)")
        XCTAssertEqual(DataExporter.escape("-2+3"), "'-2+3")
        XCTAssertEqual(DataExporter.escape("@SUM(A1:A2)"), "'@SUM(A1:A2)")
        XCTAssertEqual(DataExporter.escape("\t=1+1"), "'\t=1+1")
        XCTAssertEqual(DataExporter.escape("Ordinary food"), "Ordinary food")
    }

    func testWorkoutCSVNumbersSetsPerExercise() {
        let exercise = RoutineExercise(name: "Bench Press", type: .strength, sets: [])
        let completed = CompletedExercise(exerciseName: "Bench Press", exercise: exercise, sets: [
            CompletedSet(reps: 5, weight: 185, distance: 0, durationInSeconds: 0),
            CompletedSet(reps: 5, weight: 190, distance: 0, durationInSeconds: 0)
        ])
        let session = WorkoutSessionLog(date: Date(), routineID: "r1", completedExercises: [completed])

        let csv = DataExporter.workoutCSV(from: [session])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines[0], "date,exercise,set,weight_lbs,reps,distance_miles,duration_seconds")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].contains("Bench Press,1,185,5,0,0"))
        XCTAssertTrue(lines[2].contains("Bench Press,2,190,5,0,0"))
    }

    func testNonFiniteValuesExportAsMissingInsteadOfCrashing() {
        let item = FoodItem(
            name: "Legacy item",
            calories: .infinity,
            protein: .nan,
            carbs: 10,
            fats: 5,
            servingSize: "1 serving",
            servingWeight: .infinity
        )
        let log = DailyLog(date: Date(), meals: [Meal(name: "Meal", foodItems: [item])])

        let csv = DataExporter.foodLogCSV(from: [log])

        XCTAssertTrue(csv.contains("Meal,Legacy item,,,10,5,1 serving,"))
        XCTAssertFalse(csv.lowercased().contains("inf"))
        XCTAssertFalse(csv.lowercased().contains("nan"))
    }

    func testEmptyInputsProduceHeaderOnly() {
        XCTAssertEqual(DataExporter.foodLogCSV(from: []).split(separator: "\n").count, 1)
        XCTAssertEqual(DataExporter.workoutCSV(from: []).split(separator: "\n").count, 1)
    }
}
