import XCTest
@testable import MyFitPlateCore

final class WorkoutSubstitutionRankingTests: XCTestCase {
    func testCuratedRolesReferenceExactUniqueCatalogEntries() {
        let names = WorkoutSubstitutionRanking.patterns.values.flatMap { $0 }
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertTrue(Set(names).isSubset(of: Set(ExerciseList.entries.map(\.name))))
        XCTAssertNil(WorkoutSubstitutionRanking.pattern(for: "My custom bench machine"))
    }

    func testRoleAndExplicitAuthorAlternativeRankBeforeUnrelatedMuscleMovements() throws {
        var source = RoutineExercise(name: "Barbell Bent-over Row", type: .strength)
        let suggestions = WorkoutSubstitutionRanking.suggestions(for: source, limit: 30)
        let row = try XCTUnwrap(suggestions.firstIndex { $0.name == "Dumbbell Row" })
        let pullup = try XCTUnwrap(suggestions.firstIndex { $0.name == "Pull-up" })
        XCTAssertLessThan(row, pullup)
        source.alternatives = ["Pull-up"]
        XCTAssertEqual(WorkoutSubstitutionRanking.suggestions(for: source).first?.name, "Pull-up")
        XCTAssertTrue(suggestions.allSatisfy { $0.patternVersion == 1 })
    }

    func testMappedImplementIsEvidenceAndOccupiedImplementIsPenalized() throws {
        let gym = StrengthGymProfile(name: "Actual gym", implements: [.init(id: "bar", name: "My bar", equipment: .init(kind: .barbell, loadingMeaning: .total, barWeight: 45, plates: [25]))])
        let setup = try XCTUnwrap(gym.equipment(for: "bar"))
        var source = RoutineExercise(name: "Barbell Bench Press", type: .strength); source.loadEquipment = setup
        let mappings = ["Incline Barbell Bench Press": setup]
        let available = try XCTUnwrap(WorkoutSubstitutionRanking.suggestions(for: source, gym: gym, confirmedMovements: mappings, limit: 30).first { $0.name == "Incline Barbell Bench Press" })
        let occupied = try XCTUnwrap(WorkoutSubstitutionRanking.suggestions(for: source, gym: gym, confirmedMovements: mappings, reason: .occupied, limit: 30).first { $0.name == available.name })
        XCTAssertGreaterThan(available.score, occupied.score)
        XCTAssertTrue(occupied.reasons.contains { $0.contains("implement you are replacing") })
        var stale = gym; stale.revisionID = "newer"
        let unconfirmed = try XCTUnwrap(WorkoutSubstitutionRanking.suggestions(for: source, gym: stale, confirmedMovements: mappings, limit: 30).first { $0.name == available.name })
        XCTAssertFalse(unconfirmed.reasons.contains { $0.contains("already mapped") })
    }

    func testSavedFavoriteAndExplicitPriorityAffectRankingWithoutChangingWorkout() throws {
        let source = RoutineExercise(name: "Barbell Curl", type: .strength)
        let before = try PlanFingerprint.make(source)
        let key = WorkoutMovementSelectionStore.key(name: "Dumbbell Curl", identity: WorkoutMovementCatalog.identity(for: "Dumbbell Curl"))
        let suggestions = WorkoutSubstitutionRanking.suggestions(for: source, favorites: [key], intent: .preferredMovement)
        XCTAssertEqual(suggestions.first?.name, "Dumbbell Curl")
        XCTAssertTrue(suggestions.first?.reasons.contains("Your saved favorite") == true)
        XCTAssertEqual(try PlanFingerprint.make(source), before)
        XCTAssertTrue(WorkoutSubstitutionRanking.suggestions(for: .init(name: "My custom row", type: .strength)).isEmpty)
    }
}
