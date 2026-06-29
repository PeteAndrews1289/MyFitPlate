import XCTest
@testable import MyFitPlateCore

final class BodyUnitsTests: XCTestCase {
    func testWeightConversionAndFormatting() {
        XCTAssertEqual(BodyUnits.weightDisplayValue(lbs: 220.46226218, metric: true), 100, accuracy: 0.001)
        XCTAssertEqual(BodyUnits.weightDisplayValue(lbs: 185, metric: false), 185, accuracy: 0.001)
        XCTAssertEqual(BodyUnits.weightToLbs(100, metric: true), 220.46226218, accuracy: 0.001)
        XCTAssertEqual(BodyUnits.weightToLbs(185, metric: false), 185, accuracy: 0.001)

        XCTAssertEqual(BodyUnits.weightUnit(metric: true), "kg")
        XCTAssertEqual(BodyUnits.weightUnit(metric: false), "lbs")
        XCTAssertEqual(BodyUnits.weightString(lbs: 220.46226218, metric: true), "100.0 kg")
        XCTAssertEqual(BodyUnits.weightString(lbs: 185.25, metric: false, decimals: 0), "185 lbs")
    }

    func testHeightConversionFromFeetAndInchesToCentimeters() {
        XCTAssertEqual(BodyUnits.cm(feet: 5, inches: 10), 177.8, accuracy: 0.001)
    }
}
