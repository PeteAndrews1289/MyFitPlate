import XCTest
@testable import MyFitPlateCore

final class ReportsModelsTests: XCTestCase {

    func testMicroAverageDataPoint() {
        let point = MicroAverageDataPoint(name: "Calcium", unit: "mg", averageValue: 500, goalValue: 1000)
        
        XCTAssertEqual(point.percentageMet, 50.0)
        XCTAssertEqual(point.progressViewValue, 0.5)
        
        let pointOver = MicroAverageDataPoint(name: "Vitamin C", unit: "mg", averageValue: 150, goalValue: 100)
        
        XCTAssertEqual(pointOver.percentageMet, 150.0)
        XCTAssertEqual(pointOver.progressViewValue, 1.0)
        
        let pointZeroGoal = MicroAverageDataPoint(name: "Iron", unit: "mg", averageValue: 10, goalValue: 0)
        
        XCTAssertEqual(pointZeroGoal.percentageMet, 0.0)
        XCTAssertEqual(pointZeroGoal.progressViewValue, 0.0)
    }

    func testEnhancedSleepReportDailySleepStageDataWeekday() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 29 // A Monday
        let date = calendar.date(from: components)!
        
        let data = EnhancedSleepReport.DailySleepStageData(date: date, timeInBed: 0, timeAsleep: 0, timeCore: 0, timeDeep: 0, timeREM: 0, timeAwake: 0)
        
        XCTAssertEqual(data.weekday, "Mon")
    }
}
