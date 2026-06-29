import XCTest
@testable import MyFitPlateCore

final class RoutineEditorModelsTests: XCTestCase {

    func testExerciseTypeProperties() {
        XCTAssertEqual(ExerciseType.strength.shortTitle, "Strength")
        XCTAssertEqual(ExerciseType.strength.icon, "dumbbell.fill")
        XCTAssertEqual(ExerciseType.strength.targetLabel, "Target Reps")
        XCTAssertEqual(ExerciseType.strength.targetPlaceholder, "8-12")
        XCTAssertEqual(ExerciseType.strength.restPresets, [60, 90, 120, 180])
        
        XCTAssertEqual(ExerciseType.cardio.shortTitle, "Cardio")
        XCTAssertEqual(ExerciseType.cardio.icon, "heart.fill")
        XCTAssertEqual(ExerciseType.cardio.targetLabel, "Target Duration or Distance")
        XCTAssertEqual(ExerciseType.cardio.targetPlaceholder, "20 min or 2 miles")
        XCTAssertEqual(ExerciseType.cardio.restPresets, [0, 30, 60, 90])
        
        XCTAssertEqual(ExerciseType.flexibility.shortTitle, "Mobility")
        XCTAssertEqual(ExerciseType.flexibility.icon, "figure.flexibility")
        XCTAssertEqual(ExerciseType.flexibility.targetLabel, "Target Hold")
        XCTAssertEqual(ExerciseType.flexibility.targetPlaceholder, "45 sec")
        XCTAssertEqual(ExerciseType.flexibility.restPresets, [0, 15, 30, 45])
    }
    
    func testRoutineEditorDefaultsSetTarget() {
        // Fallback to defaults when empty
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "   "), "8-12")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .cardio, target: ""), "20 min")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .flexibility, target: " "), "45 sec")
        
        // Appends reps if missing for strength
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "10"), "10 reps")
        
        // Leaves alone if has units
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "10 reps"), "10 reps")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "amrap"), "amrap")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "60 sec"), "60 sec")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "1 min"), "1 min")
        
        // Cardio and flexbility pass through
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .cardio, target: "5 miles"), "5 miles")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .flexibility, target: "1 hour"), "1 hour")
    }

    func testRoutineEditorDefaultsInferredType() {
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Treadmill", category: "Cardio"), .cardio)
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Morning Run", category: "Legs"), .cardio)
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Cycling", category: "Legs"), .cardio)
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Yoga Session", category: "Full Body"), .flexibility)
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Plank", category: "Abs"), .flexibility)
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Bench Press", category: "Chest"), .strength)
    }
    
    func testRoutineEditorDefaultsRestLabel() {
        XCTAssertEqual(RoutineEditorDefaults.restLabel(0), "No rest")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(-10), "No rest")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(45), "45s")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(60), "1m")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(90), "1m 30s")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(120), "2m")
    }

    func testExercisePickerEntrySorting() {
        let entry1 = ExercisePickerEntry(name: "Squat", category: "Legs")
        let entry2 = ExercisePickerEntry(name: "Deadlift", category: "Legs")
        let entry3 = ExercisePickerEntry(name: "Bench Press", category: "Chest")
        
        XCTAssertTrue(entry3 < entry1) // Chest < Legs
        XCTAssertTrue(entry2 < entry1) // Deadlift < Squat (same category)
    }
    
    func testStringExtensions() {
        XCTAssertEqual("  hello  ".trimmed, "hello")
        XCTAssertEqual("\n test \t".trimmed, "test")
        
        let emptyArray: [String] = []
        XCTAssertNil(emptyArray.nilIfEmpty)
        
        let filledArray: [String] = ["a"]
        XCTAssertEqual(filledArray.nilIfEmpty, ["a"])
    }
}
