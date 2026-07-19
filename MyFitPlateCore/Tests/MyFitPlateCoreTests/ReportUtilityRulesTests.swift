import XCTest
@testable import MyFitPlateCore

final class ReportUtilityRulesTests: XCTestCase {
    func testPlateLoadoutBuildsExactTwoHundredTwentyFivePoundBar() {
        let loadout = PlateLoadingRules.loadout(targetWeight: 225)

        XCTAssertEqual(loadout?.loadedWeight, 225)
        XCTAssertEqual(loadout?.difference, 0)
        XCTAssertEqual(loadout?.platesPerSide, [PlateLoad(weight: 45, countPerSide: 2)])
        XCTAssertEqual(loadout?.totalPlateCount, 4)
        XCTAssertEqual(loadout?.isExact, true)
    }

    func testPlateLoadoutDisclosesClosestSupportedLoad() {
        let loadout = PlateLoadingRules.loadout(targetWeight: 103)

        XCTAssertEqual(loadout?.loadedWeight, 100)
        XCTAssertEqual(loadout?.difference, 3)
        XCTAssertEqual(loadout?.platesPerSide, [
            PlateLoad(weight: 25, countPerSide: 1),
            PlateLoad(weight: 2.5, countPerSide: 1)
        ])
        XCTAssertEqual(loadout?.isExact, false)
    }

    func testPlateLoadoutSupportsBarOnlyAndSanitizesDuplicatePlateSizes() {
        let barOnly = PlateLoadingRules.loadout(targetWeight: 45)
        let duplicateSizes = PlateLoadingRules.loadout(
            targetWeight: 135,
            availablePlates: [45, 45, .nan, -10]
        )

        XCTAssertEqual(barOnly?.platesPerSide, [])
        XCTAssertEqual(barOnly?.loadedWeight, 45)
        XCTAssertEqual(duplicateSizes?.platesPerSide, [PlateLoad(weight: 45, countPerSide: 1)])
        XCTAssertEqual(duplicateSizes?.loadedWeight, 135)
    }

    func testPlateLoadoutRejectsUnsafeTargets() {
        XCTAssertNil(PlateLoadingRules.loadout(targetWeight: 44))
        XCTAssertNil(PlateLoadingRules.loadout(targetWeight: .nan))
        XCTAssertNil(PlateLoadingRules.loadout(targetWeight: .infinity))
        XCTAssertNil(PlateLoadingRules.loadout(targetWeight: 10_001))
        XCTAssertNil(PlateLoadingRules.loadout(targetWeight: 225, barWeight: 0))
    }

    func testNutritionTrendPointsExcludeUnsafeValuesAndSortByDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
        let points = [
            DateValuePoint(date: second, value: 2_100),
            DateValuePoint(date: first, value: 2_000),
            DateValuePoint(date: second, value: -.infinity),
            DateValuePoint(date: first, value: -1)
        ]

        let valid = NutritionTrendRules.validPoints(points)

        XCTAssertEqual(valid.map(\.date), [first, second])
        XCTAssertEqual(valid.map(\.value), [2_000, 2_100])
    }

    func testNutritionTrendSummaryUsesValidDataAndDistinctObservedDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let second = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))

        let summary = NutritionTrendRules.summary(
            calories: [
                DateValuePoint(date: first, value: 2_000),
                DateValuePoint(date: second, value: 2_200),
                DateValuePoint(date: second, value: .nan)
            ],
            protein: [DateValuePoint(date: first, value: 150)],
            carbs: [DateValuePoint(date: first, value: 230)],
            fat: [DateValuePoint(date: first, value: 65)],
            calendar: calendar
        )

        XCTAssertEqual(summary.observedDays, 2)
        XCTAssertEqual(summary.averageCalories, 2_100)
        XCTAssertEqual(summary.averageProtein, 150)
        XCTAssertEqual(summary.averageCarbs, 230)
        XCTAssertEqual(summary.averageFat, 65)
    }

    func testNutritionTrendValueGuardsRejectInvalidNumbers() {
        XCTAssertEqual(NutritionTrendRules.validGoal(2_100), 2_100)
        XCTAssertNil(NutritionTrendRules.validGoal(0))
        XCTAssertNil(NutritionTrendRules.validGoal(.nan))
        XCTAssertEqual(NutritionTrendRules.finiteNonnegative(0), 0)
        XCTAssertNil(NutritionTrendRules.finiteNonnegative(-1))
        XCTAssertNil(NutritionTrendRules.finiteNonnegative(.infinity))
    }
}
