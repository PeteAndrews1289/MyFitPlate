import XCTest
@testable import MyFitPlateCore

final class HeartRateZonesTests: XCTestCase {

    func testEstimatedMaxHRUsesFoxFormulaWithFloor() {
        XCTAssertEqual(HeartRateZones.estimatedMaxHR(age: 30), 190, accuracy: 0.001)
        XCTAssertEqual(HeartRateZones.estimatedMaxHR(age: 25), 195, accuracy: 0.001)
        // Absurd age can't drop below the safety floor.
        XCTAssertEqual(HeartRateZones.estimatedMaxHR(age: 120), 140, accuracy: 0.001)
    }

    func testZoneClassification() {
        let maxHR = 190.0
        // 152 bpm == 80% of 190 → Tempo (Z4).
        XCTAssertEqual(HeartRateZones.zone(forHeartRate: 152, maxHR: maxHR)?.number, 4)
        // 133 bpm == 70% → Aerobic (Z3).
        XCTAssertEqual(HeartRateZones.zone(forHeartRate: 133, maxHR: maxHR)?.number, 3)
        // 180 bpm == ~95% → Threshold (Z5).
        XCTAssertEqual(HeartRateZones.zone(forHeartRate: 180, maxHR: maxHR)?.number, 5)
    }

    func testVeryLowHeartRateFallsIntoZoneOne() {
        XCTAssertEqual(HeartRateZones.zone(forHeartRate: 80, maxHR: 190)?.number, 1)
    }

    func testNonPositiveInputsReturnNil() {
        XCTAssertNil(HeartRateZones.zone(forHeartRate: 0, maxHR: 190))
        XCTAssertNil(HeartRateZones.zone(forHeartRate: 150, maxHR: 0))
    }

    func testZoneBounds() {
        let z4 = HeartRateZones.zones[3] // Tempo, 80–90%
        let bounds = z4.bounds(maxHR: 190)
        XCTAssertEqual(bounds.lower, 152)
        XCTAssertEqual(bounds.upper, 171)
    }
}
