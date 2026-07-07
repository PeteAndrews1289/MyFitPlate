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

    // MARK: - Time in zones

    func testTimeInZonesChargesEachSampleUntilTheNext() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples: [(date: Date, bpm: Double)] = [
            (t0, 133),                          // Z3
            (t0.addingTimeInterval(10), 152),   // Z4
            (t0.addingTimeInterval(20), 152),   // Z4
            (t0.addingTimeInterval(30), 100)    // last sample — not charged (no next)
        ]
        let z = HeartRateZones.timeInZones(samples: samples, maxHR: 190)
        XCTAssertEqual(z[2], 10, accuracy: 0.001, "Z3")
        XCTAssertEqual(z[3], 20, accuracy: 0.001, "Z4")
        XCTAssertEqual(z[0] + z[1] + z[4], 0, accuracy: 0.001)
    }

    func testTimeInZonesSkipsLongGaps() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples: [(date: Date, bpm: Double)] = [
            (t0, 152),                            // 1000s gap follows → not charged
            (t0.addingTimeInterval(1000), 152),   // charged 10s to Z4
            (t0.addingTimeInterval(1010), 152)
        ]
        let z = HeartRateZones.timeInZones(samples: samples, maxHR: 190)
        XCTAssertEqual(z[3], 10, accuracy: 0.001, "Only the 10s interval counts; the 1000s pause is skipped")
    }

    func testTimeInZonesEmptyOrSingleSampleIsAllZero() {
        XCTAssertEqual(HeartRateZones.timeInZones(samples: [], maxHR: 190), [0, 0, 0, 0, 0])
        let one: [(date: Date, bpm: Double)] = [(Date(), 150)]
        XCTAssertEqual(HeartRateZones.timeInZones(samples: one, maxHR: 190), [0, 0, 0, 0, 0])
    }
}
