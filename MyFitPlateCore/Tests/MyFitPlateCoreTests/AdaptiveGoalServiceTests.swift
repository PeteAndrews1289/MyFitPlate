import XCTest
@testable import MyFitPlateCore

final class AdaptiveGoalServiceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: Date {
        DateComponents(calendar: calendar, year: 2026, month: 6, day: 29).date!
    }

    func testExpenditureSnapshotProducesHighConfidenceStableTDEE() throws {
        let snapshot = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
            weightHistory: weightHistory(count: 21, startingWeight: 200),
            dailyLogs: dailyLogs(count: 21, calories: 2_200),
            today: today,
            calendar: calendar
        ))

        XCTAssertEqual(snapshot.recentWeighInCount, 21)
        XCTAssertEqual(snapshot.recentLogCount, 21)
        assertOptionalEqual(snapshot.last21DaysCalorieAverage, 2_200)
        assertOptionalEqual(snapshot.weightChangeRatePerDay, 0)
        assertOptionalEqual(snapshot.calculatedTDEE, 2_200)
        XCTAssertEqual(snapshot.dataConfidence, .high)
    }

    func testExpenditureSnapshotConfidenceThresholds() throws {
        let medium = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
            weightHistory: weightHistory(count: 10, startingWeight: 180),
            dailyLogs: dailyLogs(count: 13, calories: 2_100),
            today: today,
            calendar: calendar
        ))
        XCTAssertEqual(medium.dataConfidence, .medium)
        assertOptionalEqual(medium.calculatedTDEE, 2_100)

        let low = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
            weightHistory: weightHistory(count: 7, startingWeight: 180),
            dailyLogs: dailyLogs(count: 10, calories: 1_900),
            today: today,
            calendar: calendar
        ))
        XCTAssertEqual(low.dataConfidence, .low)
        assertOptionalEqual(low.calculatedTDEE, 1_900)
    }

    func testExpenditureSnapshotReportsProgressWhenDataIsInsufficient() throws {
        let snapshot = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
            weightHistory: weightHistory(count: 6, startingWeight: 200),
            dailyLogs: dailyLogs(count: 10, calories: 2_000),
            today: today,
            calendar: calendar
        ))

        XCTAssertEqual(snapshot.recentWeighInCount, 6)
        XCTAssertEqual(snapshot.recentLogCount, 10)
        XCTAssertNil(snapshot.last21DaysCalorieAverage)
        XCTAssertNil(snapshot.weightChangeRatePerDay)
        XCTAssertNil(snapshot.calculatedTDEE)
        XCTAssertEqual(snapshot.dataConfidence, .insufficient)
    }

    func testExpenditureSnapshotIgnoresLowCalorieLogsAndClampsMinimumTDEE() throws {
        let snapshot = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
            weightHistory: weightHistory(count: 7, startingWeight: 200),
            dailyLogs: dailyLogs(count: 10, calories: 400),
            today: today,
            calendar: calendar
        ))

        assertOptionalEqual(snapshot.last21DaysCalorieAverage, 0)
        assertOptionalEqual(snapshot.calculatedTDEE, 1_000)
        XCTAssertEqual(snapshot.dataConfidence, .low)
    }

    func testExpenditureSnapshotRaisesTDEEWhenWeightIsFalling() throws {
        let snapshot = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
            weightHistory: weightHistory(count: 21, startingWeight: 200, dailyChange: -0.2),
            dailyLogs: dailyLogs(count: 21, calories: 2_000),
            today: today,
            calendar: calendar
        ))

        XCTAssertEqual(snapshot.dataConfidence, .high)
        assertOptionalEqual(snapshot.last21DaysCalorieAverage, 2_000)
        XCTAssertLessThan(try XCTUnwrap(snapshot.weightChangeRatePerDay), 0)
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.calculatedTDEE), 2_000)
    }

    func testExpenditureSnapshotClampsMaximumTDEE() throws {
        let snapshot = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
            weightHistory: weightHistory(count: 21, startingWeight: 200),
            dailyLogs: dailyLogs(count: 21, calories: 8_000),
            today: today,
            calendar: calendar
        ))

        assertOptionalEqual(snapshot.calculatedTDEE, 5_000)
    }

    func testDataConfidenceColorNamesAreStableForUI() {
        XCTAssertEqual(AdaptiveGoalService.DataConfidence.high.colorName, "accentPositive")
        XCTAssertEqual(AdaptiveGoalService.DataConfidence.medium.colorName, "orange")
        XCTAssertEqual(AdaptiveGoalService.DataConfidence.low.colorName, "red")
        XCTAssertEqual(AdaptiveGoalService.DataConfidence.insufficient.colorName, "gray")
    }

    private func weightHistory(
        count: Int,
        startingWeight: Double,
        dailyChange: Double = 0
    ) -> [(id: String, date: Date, weight: Double)] {
        (0..<count).map { index in
            let daysAgo = count - 1 - index
            return (
                id: "weight-\(index)",
                date: day(daysAgo),
                weight: startingWeight + dailyChange * Double(index)
            )
        }
    }

    private func dailyLogs(count: Int, calories: Double) -> [DailyLog] {
        (0..<count).map { index in
            let daysAgo = count - 1 - index
            let food = FoodItem(
                id: "food-\(index)",
                name: "Logged Day \(index)",
                calories: calories,
                protein: calories * 0.3 / 4,
                carbs: calories * 0.4 / 4,
                fats: calories * 0.3 / 9
            )
            return DailyLog(
                id: "log-\(index)",
                date: day(daysAgo),
                meals: [Meal(name: "Meals", foodItems: [food])]
            )
        }
    }

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    private func assertOptionalEqual(
        _ actual: Double?,
        _ expected: Double,
        accuracy: Double = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected \(expected), got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }
}
