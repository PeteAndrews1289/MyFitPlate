import XCTest
@testable import MyFitPlateCore

final class InsightReportExportTests: XCTestCase {
    func testTextAndCSVKeepScopeUnknownIntakeAndExcludePrivateIdentifiers() throws {
        let now = Date(), date = Calendar.current.startOfDay(for: now)
        let partial = DailyLog(id: "private-day", date: date, meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "private-food", name: "Rice", calories: 250)])], nutritionDayStatus: .partial)
        let evidence = try InsightEvidenceSnapshot(ownerID: "private-owner", logs: [partial], sleepHoursByNight: [date: 7], calorieGoal: 2000, proteinGoal: 150, start: date, end: now, origin: .aiInterpretation, now: now)
        let insight = UserInsight(title: "=Potential formula", message: "Line one, with commas\nLine two", category: .nutritionGeneral, sourceData: "OPTIONAL_SOURCE", evidence: evidence)
        for format in InsightReportExport.Format.allCases {
            let content = try InsightReportExport.content(insights: [insight], format: format, includeEvidence: true, includeSourceText: false)
            for secret in ["private-day", "private-food", "private-owner", "OPTIONAL_SOURCE"] { XCTAssertFalse(content.contains(secret)) }
            XCTAssertTrue(content.contains("Partly logged")); XCTAssertTrue(content.contains("0/1 fully logged"))
            XCTAssertTrue(content.contains("AI interpretation")); XCTAssertFalse(content.contains("250"))
        }
        let csv = try InsightReportExport.content(insights: [insight], format: .csv, includeEvidence: true, includeSourceText: false)
        XCTAssertTrue(csv.contains("'=Potential formula")); XCTAssertTrue(csv.contains("recorded_sleep")); XCTAssertTrue(csv.contains("false,,,,,"))
        XCTAssertTrue(csv.contains("\"Line one, with commas\nLine two\""))
    }
    func testUnselectedEvidenceIsAbsentAndOptionalExplanationNeedsExplicitInclusion() throws {
        let insight = UserInsight(title: "Report", message: "Selected message", category: .nutritionGeneral, sourceData: "SOURCE_EXPLANATION")
        let text = try InsightReportExport.content(insights: [insight], format: .text, includeEvidence: false, includeSourceText: false)
        XCTAssertFalse(text.contains("SOURCE_EXPLANATION")); XCTAssertFalse(text.contains("No captured"))
        let included = try InsightReportExport.content(insights: [insight], format: .text, includeEvidence: true, includeSourceText: true)
        XCTAssertTrue(included.contains("may be AI-written")); XCTAssertTrue(included.contains("SOURCE_EXPLANATION")); XCTAssertTrue(included.contains("No captured"))
        XCTAssertThrowsError(try InsightReportExport.content(insights: [], format: .csv, includeEvidence: true, includeSourceText: true))
    }
}
