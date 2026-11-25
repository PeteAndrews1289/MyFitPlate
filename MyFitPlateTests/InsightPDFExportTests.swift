import XCTest
import PDFKit
import MyFitPlateCore
@testable import MyFitPlate

@MainActor
final class InsightPDFExportTests: XCTestCase {
    func testGoalDisplayHidesFloatingPointNoiseWithoutChangingCapturedEvidence() throws {
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        let evidence = try InsightEvidenceSnapshot(ownerID: "precision-fixture", logs: [], sleepHoursByNight: [:],
            calorieGoal: 2100, proteinGoal: 160.00005,
            start: Calendar.current.startOfDay(for: now), end: now, origin: .localRules, now: now)
        let originalFingerprint = try PlanFingerprint.make(evidence)
        let insight = UserInsight(title: "Captured targets", message: "Review the captured daily goals.",
            category: .nutritionGeneral, evidence: evidence)
        let url = try InsightPDFExport.render(insights: [insight], includeEvidence: true, includeSourceText: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)
        XCTAssertTrue(text.contains("160 g protein/day"), text)
        XCTAssertFalse(text.contains("160.00005"), text)
        let retained = try XCTUnwrap(insight.evidence)
        XCTAssertEqual(retained.proteinGoal, 160.00005)
        XCTAssertEqual(retained.calorieGoal, 2100)
        XCTAssertEqual(try PlanFingerprint.make(retained), originalFingerprint)
    }

    func testLongInsightPaginatesEveryParagraphAndExcludesUnselectedPrivateExplanation() throws {
        let now = Date()
        let owner = "qa-owner-not-for-export"
        let meal = Meal(name: "Lunch", foodItems: [FoodItem(id: "private-food-id", name: "Rice bowl", calories: 500, protein: 30)])
        let log = DailyLog(id: "private-diary-id", date: now, meals: [meal], nutritionDayStatus: .complete)
        let evidence = try InsightEvidenceSnapshot(ownerID: owner, logs: [log], sleepHoursByNight: [:],
            calorieGoal: 2000, proteinGoal: 150, start: Calendar.current.startOfDay(for: now), end: now,
            origin: .localRules, now: now)
        let paragraphs = (0..<45).map { index in
            "Paragraph \(index): Review the recorded food and workout evidence in its original date window. A partial food log is excluded from intake averages; missing intake is not a zero-calorie day. END-\(index)."
        }
        let insight = UserInsight(title: "Nutrition evidence - café and rice", message: paragraphs.joined(separator: "\n\n"),
            category: .nutritionGeneral, sourceData: "PRIVATE SOURCE EXPLANATION", evidence: evidence)
        let url = try InsightPDFExport.render(insights: [insight], includeEvidence: true, includeSourceText: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 1)
        let text = try XCTUnwrap(document.string)
        for index in 0..<45 { XCTAssertTrue(text.contains("END-\(index)."), "Missing paragraph \(index)") }
        XCTAssertTrue(text.contains("500"))
        XCTAssertTrue(text.contains("Fully logged"))
        XCTAssertFalse(text.contains(owner))
        XCTAssertFalse(text.contains("private-food-id"))
        XCTAssertFalse(text.contains("private-diary-id"))
        XCTAssertFalse(text.contains("PRIVATE SOURCE EXPLANATION"))
        let pdf = XCTAttachment(contentsOfFile: url)
        pdf.name = "Insight report - paginated evidence export"; pdf.lifetime = .keepAlways; add(pdf)
        for index in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: index))
            XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
            let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Insight report page \(index + 1) of \(document.pageCount)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
