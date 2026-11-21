import XCTest
@testable import MyFitPlateCore

final class WeightGoalHistoryTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))! }
    private func date(_ day: Int) -> Date { calendar.date(byAdding: .day, value: day, to: start)! }
    private func selection(intent: String = "Lose", target: Double = 170, metric: Bool = false, calories: Double = 2200) -> WeightGoalPeriod.Selection {
        .init(intent: intent, targetPounds: target, weeklyChangePounds: 0.7, metricAtAcceptance: metric, acceptedCalories: calories)
    }
    private func samples(_ days: ClosedRange<Int>, rate: Double = -0.1) -> [AdaptiveWeightEvidence] {
        days.map { .init(id: "d\($0)", date: date($0), pounds: 180 + Double($0) * rate) }
    }
    @MainActor func testGoalHistoryIsImmutableAccountScopedAndDoesNotInventALegacyStart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WeightGoalHistoryStore(drafts: EditorDraftStore(directory: folder))
        let first = try store.record(userID: "a", currentUserID: "a", selection: selection(), source: .observed, now: start)
        XCTAssertEqual(first.count, 1); XCTAssertEqual(first[0].recordedAt, start); XCTAssertEqual(first[0].source, .observed)
        let repeatSave = try store.record(userID: "a", currentUserID: "a", selection: selection(calories: 2100), source: .accepted, now: date(1))
        XCTAssertEqual(first, repeatSave, "A recalculated calorie value must not reset a weight-goal period")
        let second = try store.record(userID: "a", currentUserID: "a", selection: selection(intent: "Maintain", target: 175, metric: true), source: .accepted, now: date(7))
        XCTAssertEqual(second.count, 2); XCTAssertEqual(second[0], first[0]); XCTAssertTrue(second[1].selection.metricAtAcceptance)
        XCTAssertEqual(try store.load(userID: "b", currentUserID: "b"), [])
        XCTAssertThrowsError(try store.load(userID: "a", currentUserID: "b"))
        XCTAssertThrowsError(try store.record(userID: "a", currentUserID: "a", selection: selection(), source: .accepted, now: date(-1)))
        XCTAssertEqual(try store.load(userID: "a", currentUserID: "a"), second)
    }
    @MainActor func testCorruptHistoryIsKeptAndCannotBeReplacedByAutomaticObservation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let drafts = EditorDraftStore(directory: folder)
        let invalid = WeightGoalPeriod(ownerID: "other", recordedAt: start, selection: selection(), source: .observed)
        try drafts.save([invalid], userID: "a", scope: "weight-goal-periods-v1")
        let store = WeightGoalHistoryStore(drafts: drafts)
        XCTAssertThrowsError(try store.record(userID: "a", currentUserID: "a", selection: selection(), source: .observed))
        XCTAssertEqual(try drafts.load([WeightGoalPeriod].self, userID: "a", scope: "weight-goal-periods-v1")?.value, [invalid])
    }
    func testDenseStableEvidenceOffersQualifiedFourteenDayScenariosWithoutChangingTargets() throws {
        let period = WeightGoalPeriod(ownerID: "a", recordedAt: start, selection: selection(), source: .accepted)
        let result = WeightGoalComparisonRules.evaluate(period: period, samples: samples(0...28), asOf: date(28), calendar: calendar)
        XCTAssertEqual(result.desiredWeeklyChange, -0.7, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(result.observedWeeklyChange), -0.7, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(result.projectedPounds).lowerBound, 175.8, accuracy: 0.00001)
        XCTAssertEqual(result.projectionDate, date(42))
        XCTAssertTrue(result.explanation.contains("not a confidence interval"))
        XCTAssertEqual(period.selection.acceptedCalories, 2200)
    }
    func testProjectionRefusesSparseStaleChangingOrPreviousGoalEvidence() {
        let period = WeightGoalPeriod(ownerID: "a", recordedAt: start, selection: selection(), source: .accepted)
        let sparse = samples(0...28).filter { Int($0.id.dropFirst())! % 4 == 0 }
        XCTAssertNil(WeightGoalComparisonRules.evaluate(period: period, samples: sparse, asOf: date(28), calendar: calendar).projectedPounds)
        XCTAssertNil(WeightGoalComparisonRules.evaluate(period: period, samples: samples(0...20), asOf: date(28), calendar: calendar).projectedPounds)
        XCTAssertNil(WeightGoalComparisonRules.evaluate(period: period, samples: samples(0...28, rate: 1), asOf: date(28), calendar: calendar).projectedPounds)
        let newGoal = WeightGoalPeriod(ownerID: "a", recordedAt: date(27), selection: selection(intent: "Gain"), source: .accepted)
        let recent = WeightGoalComparisonRules.evaluate(period: newGoal, samples: samples(0...28), asOf: date(28), calendar: calendar)
        XCTAssertEqual(recent.measuredDays, 2); XCTAssertNil(recent.observedWeeklyChange); XCTAssertNil(recent.projectedPounds)
    }
    func testLongGapsAreNotConvertedIntoConfidentScenarios() {
        let period = WeightGoalPeriod(ownerID: "a", recordedAt: start, selection: selection(), source: .accepted)
        let result = WeightGoalComparisonRules.evaluate(period: period, samples: samples(0...6) + samples(20...28), asOf: date(28), calendar: calendar)
        XCTAssertNil(result.projectedPounds); XCTAssertTrue(result.explanation.contains("gaps"))
    }
}
