import XCTest
@testable import MyFitPlateCore

final class WorkoutSupersetTests: XCTestCase {

    private func ex(_ name: String, group: String? = nil) -> RoutineExercise {
        RoutineExercise(name: name, sets: [], supersetGroupID: group)
    }

    func testNoGroupsAreAllStandalone() {
        let positions = SupersetRules.positions(for: [ex("Squat"), ex("Bench"), ex("Row")])
        XCTAssertEqual(positions, [.standalone, .standalone, .standalone])
    }

    func testAdjacentPairFormsASuperset() {
        let positions = SupersetRules.positions(for: [ex("Bench", group: "g1"), ex("Row", group: "g1")])
        XCTAssertTrue(positions[0].isInSuperset)
        XCTAssertTrue(positions[0].isFirstInGroup)
        XCTAssertFalse(positions[0].isLastInGroup)
        XCTAssertTrue(positions[1].isInSuperset)
        XCTAssertFalse(positions[1].isFirstInGroup)
        XCTAssertTrue(positions[1].isLastInGroup)
        XCTAssertEqual(positions[0].groupLabel, "A")
        XCTAssertEqual(positions[1].groupLabel, "A")
    }

    func testLoneTaggedExerciseIsNotASuperset() {
        // A group id with no adjacent same-id neighbor should not read as a superset.
        let positions = SupersetRules.positions(for: [ex("Squat", group: "g1"), ex("Bench")])
        XCTAssertEqual(positions[0], .standalone)
        XCTAssertEqual(positions[1], .standalone)
    }

    func testDistinctGroupsGetSequentialLabels() {
        let positions = SupersetRules.positions(for: [
            ex("Bench", group: "g1"), ex("Row", group: "g1"),
            ex("Curl", group: "g2"), ex("Pushdown", group: "g2")
        ])
        XCTAssertEqual(positions[0].groupLabel, "A")
        XCTAssertEqual(positions[1].groupLabel, "A")
        XCTAssertEqual(positions[2].groupLabel, "B")
        XCTAssertEqual(positions[3].groupLabel, "B")
    }

    func testTripleGroupMiddleIsNeitherFirstNorLast() {
        let positions = SupersetRules.positions(for: [
            ex("A", group: "g"), ex("B", group: "g"), ex("C", group: "g")
        ])
        XCTAssertTrue(positions[0].isFirstInGroup && !positions[0].isLastInGroup)
        XCTAssertFalse(positions[1].isFirstInGroup || positions[1].isLastInGroup)
        XCTAssertTrue(positions[2].isLastInGroup && !positions[2].isFirstInGroup)
    }
}
