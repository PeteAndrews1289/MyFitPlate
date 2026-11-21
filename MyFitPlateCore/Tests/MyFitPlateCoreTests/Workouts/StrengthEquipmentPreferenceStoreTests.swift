import XCTest
@testable import MyFitPlateCore

@MainActor
final class StrengthEquipmentPreferenceStoreTests: XCTestCase {
    func testEquipmentSurvivesStoreRecreationWithoutCrossingAccounts() throws {
        try withDefaults { defaults in
            let store = StrengthEquipmentPreferenceStore(userDefaults: defaults)
            let equipment = StrengthEquipment(kind: .fixedWeights, unit: .kg, loadingMeaning: .perHand,
                                              name: "Upstairs rack", availableWeights: [22.046226, 33.069339, 44.092452])
            try store.save(equipment, userID: "owner", routineID: "upper", exerciseID: "press", exerciseName: "Dumbbell Press")
            let recreated = StrengthEquipmentPreferenceStore(userDefaults: defaults)
            XCTAssertEqual(recreated.load(userID: "owner", routineID: "upper", exerciseID: "press", exerciseName: "  dumbbell  PRESS \n"), equipment)
            XCTAssertNil(recreated.load(userID: "other", routineID: "upper", exerciseID: "press", exerciseName: "Dumbbell Press"))
        }
    }

    func testExactRoutineExerciseAndNameKeepSeparateEquipment() throws {
        try withDefaults { defaults in
            let store = StrengthEquipmentPreferenceStore(userDefaults: defaults)
            let machine = StrengthEquipment(kind: .fixedWeights, name: "Cable A", availableWeights: [20, 30, 40])
            try store.save(machine, userID: "owner", routineID: "heavy", exerciseID: "row", exerciseName: "Cable Row")
            XCTAssertNil(store.load(userID: "owner", routineID: "volume", exerciseID: "row", exerciseName: "Cable Row"))
            XCTAssertNil(store.load(userID: "owner", routineID: "heavy", exerciseID: "other", exerciseName: "Cable Row"))
            XCTAssertNil(store.load(userID: "owner", routineID: "heavy", exerciseID: "row", exerciseName: "Dumbbell Row"))
            // Delimiter-like identifiers cannot create an accidental context collision.
            try store.save(machine, userID: "owner", routineID: "a|b", exerciseID: "c", exerciseName: "Row")
            XCTAssertNil(store.load(userID: "owner", routineID: "a", exerciseID: "b|c", exerciseName: "Row"))
        }
    }

    func testRejectedEquipmentPreservesTheLastAcceptedSetup() throws {
        try withDefaults { defaults in
            let store = StrengthEquipmentPreferenceStore(userDefaults: defaults)
            let bar = StrengthEquipment(kind: .barbell, loadingMeaning: .total, barWeight: 45, plates: [45, 25, 10, 5, 2.5])
            try store.save(bar, userID: "owner", routineID: "lower", exerciseID: "squat", exerciseName: "Squat")
            var invalid = bar
            invalid.plates = [.nan]
            XCTAssertThrowsError(try store.save(invalid, userID: "owner", routineID: "lower", exerciseID: "squat", exerciseName: "Squat"))
            XCTAssertEqual(store.load(userID: "owner", routineID: "lower", exerciseID: "squat", exerciseName: "Squat"), bar)
            let empty = StrengthEquipment(kind: .fixedWeights)
            XCTAssertThrowsError(try store.save(empty, userID: "owner", routineID: "lower", exerciseID: "squat", exerciseName: "Squat"))
            XCTAssertEqual(store.load(userID: "owner", routineID: "lower", exerciseID: "squat", exerciseName: "Squat"), bar)
        }
    }

    func testRemovingASetupLeavesOtherRoutinesAndAccountsIntact() throws {
        try withDefaults { defaults in
            let store = StrengthEquipmentPreferenceStore(userDefaults: defaults)
            let weights = StrengthEquipment(availableWeights: [10, 15, 20])
            for (owner, routine) in [("owner", "upper"), ("owner", "lower"), ("other", "upper")] {
                try store.save(weights, userID: owner, routineID: routine, exerciseID: "curl", exerciseName: "Curl")
            }
            try store.save(nil, userID: "owner", routineID: "upper", exerciseID: "curl", exerciseName: "Curl")
            XCTAssertNil(store.load(userID: "owner", routineID: "upper", exerciseID: "curl", exerciseName: "Curl"))
            XCTAssertEqual(store.load(userID: "owner", routineID: "lower", exerciseID: "curl", exerciseName: "Curl"), weights)
            XCTAssertEqual(store.load(userID: "other", routineID: "upper", exerciseID: "curl", exerciseName: "Curl"), weights)
        }
    }

    func testMalformedIdentityAndCorruptStoredDataFailClosed() throws {
        try withDefaults { defaults in
            let store = StrengthEquipmentPreferenceStore(userDefaults: defaults)
            let weights = StrengthEquipment(availableWeights: [10, 20])
            for (owner, routine, exercise, name) in [("", "routine", "exercise", "Row"),
                                                    ("owner", " ", "exercise", "Row"),
                                                    ("owner", "routine", "", "Row"),
                                                    ("owner", "routine", "exercise", " \n")] {
                XCTAssertThrowsError(try store.save(weights, userID: owner, routineID: routine, exerciseID: exercise, exerciseName: name))
                XCTAssertNil(store.load(userID: owner, routineID: routine, exerciseID: exercise, exerciseName: name))
            }
            try store.save(weights, userID: "owner", routineID: "routine", exerciseID: "exercise", exerciseName: "Row")
            let key = try XCTUnwrap(defaults.dictionaryRepresentation().keys.first { $0.hasPrefix("strengthEquipment.") })
            defaults.set(Data("invalid json".utf8), forKey: key)
            XCTAssertNil(store.load(userID: "owner", routineID: "routine", exerciseID: "exercise", exerciseName: "Row"))
            let invalid = StrengthEquipment(availableWeights: [-5])
            defaults.set(try JSONEncoder().encode(invalid), forKey: key)
            XCTAssertNil(store.load(userID: "owner", routineID: "routine", exerciseID: "exercise", exerciseName: "Row"))
        }
    }

    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suite = "strength-equipment-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }
}
