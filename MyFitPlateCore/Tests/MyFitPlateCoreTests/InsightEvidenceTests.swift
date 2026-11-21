import XCTest
@testable import MyFitPlateCore

@MainActor
final class InsightEvidenceTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }
    func log(_ offset: Int, status: NutritionDayStatus, calories: Double = 500) -> DailyLog {
        .init(id: "source-\(offset)", date: day(offset), meals: [.init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 100 + offset))!, name: "Lunch", foodItems: [
            FoodItem(id: "food-\(offset)", name: "Lunch", calories: calories, protein: 30, timestamp: now)
        ])], nutritionDayStatus: status)
    }
    func snapshot(_ logs: [DailyLog], origin: InsightEvidenceSnapshot.Origin = .localRules,
                  sleep: [Date: Double] = [:]) throws -> InsightEvidenceSnapshot {
        try .init(ownerID: "owner", logs: logs, sleepHoursByNight: sleep, calorieGoal: 2000,
            proteinGoal: 150, start: day(-6), end: day(0), origin: origin, now: now, calendar: calendar)
    }

    func testCoverageIncludesMissingDaysAndExcludesPartialIntakeWithoutInventingZero() throws {
        let value = try snapshot([log(-1, status: .complete), log(-2, status: .partial), log(-9, status: .complete)])
        XCTAssertEqual(value.calendarDayCount, 7)
        XCTAssertEqual(value.days.count, 2)
        XCTAssertEqual(value.completeFoodDays, 1)
        XCTAssertNil(value.days.first?.calories)
        XCTAssertFalse(value.days.first!.includedInIntake)
        XCTAssertEqual(value.days.last?.calories, 500)
        XCTAssertEqual(value.days.last?.foodIDs, ["food--1"])
        XCTAssertEqual(value.coverageDescription, "1/7 fully logged food days · 2 days with records · 0 sleep nights included")
    }

    func testExactInputsChangeFingerprintAndSourceIDsAreStableAcrossRecalculation() throws {
        let original = try snapshot([log(-1, status: .complete)], sleep: [day(-2): 7, day(-8): 8])
        let same = try snapshot([log(-1, status: .complete)], sleep: [day(-2): 7, day(-8): 8])
        XCTAssertEqual(original.inputFingerprint, same.inputFingerprint)
        XCTAssertNotEqual(original.id, same.id)
        XCTAssertEqual(original.sleepNights.count, 1)
        XCTAssertEqual(original.stableInsightID(title: "Protein", category: "macroBalance", message: "Example"),
                       same.stableInsightID(title: "Protein", category: "macroBalance", message: "Example"))
        let edited = try snapshot([log(-1, status: .complete, calories: 600)], sleep: [day(-2): 7])
        XCTAssertNotEqual(original.inputFingerprint, edited.inputFingerprint)
        XCTAssertNotEqual(original.stableInsightID(title: "Protein", category: "macroBalance", message: "Example"),
                          edited.stableInsightID(title: "Protein", category: "macroBalance", message: "Example"))
    }

    func testLegacyInsightDecodesWithoutFabricatingEvidenceAndNewEvidenceRoundTrips() throws {
        let legacy = try JSONDecoder().decode(UserInsight.self, from: Data(#"{"title":"Old","message":"Old message","category":"nutritionGeneral"}"#.utf8))
        XCTAssertNil(legacy.evidence)
        let evidence = try snapshot([log(-1, status: .complete)])
        let insight = legacy.attaching(evidence)
        let restored = try JSONDecoder().decode(UserInsight.self, from: JSONEncoder().encode(insight))
        XCTAssertEqual(restored, insight)
        XCTAssertEqual(restored.id, insight.id)
        XCTAssertEqual(restored.evidence?.inputFingerprint, evidence.inputFingerprint)
    }

    func testReportArchiveKeepsOriginalInputsAndRejectsOtherOwnerAndChangedReceipt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InsightReportStore(store: EditorDraftStore(directory: directory))
        let evidence = try snapshot([log(-1, status: .complete)])
        let insight = UserInsight(title: "Protein", message: "Read your records", category: .macroBalance).attaching(evidence)
        let report = SavedInsightReport(evidence: evidence, insights: [insight])
        try store.record(report, currentUserID: "owner")
        try store.record(report, currentUserID: "owner")
        XCTAssertEqual(try store.reports(userID: "owner"), [report])
        XCTAssertTrue(try store.reports(userID: "other").isEmpty)
        XCTAssertThrowsError(try store.record(report, currentUserID: "other"))
        XCTAssertThrowsError(try store.record(SavedInsightReport(evidence: evidence, insights: []), currentUserID: "owner"))
        XCTAssertEqual(try store.reports(userID: "owner"), [report])
    }
}
