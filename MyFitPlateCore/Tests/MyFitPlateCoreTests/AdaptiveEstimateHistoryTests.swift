import XCTest
@testable import MyFitPlateCore

@MainActor
final class AdaptiveEstimateHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    private var now: Date { DateComponents(calendar: calendar, year: 2026, month: 11, day: 4).date! }
    private func inputs(slope: Double = 0, spike: Int? = nil, completeCount: Int = 42) -> AdaptiveEstimateInputs {
        let weights = (0..<42).map { day in
            AdaptiveWeightEvidence(id: "w-\(day)", date: calendar.date(byAdding: .day, value: day - 41, to: now)!,
                pounds: 180 + Double(day) * slope + (day == spike ? 10 : 0))
        }
        let intake = (0..<42).map { day in
            AdaptiveIntakeEvidence(date: calendar.date(byAdding: .day, value: day - 41, to: now)!,
                calories: 2_300, complete: day < completeCount)
        }
        return AdaptiveEstimateInputs(weights: weights, intake: intake, now: now, calendar: calendar)
    }
    private var baseline: AdaptiveGoalService.ExpenditureSnapshot {
        .init(recentWeighInCount: 21, recentLogCount: 21, last21DaysCalorieAverage: 2_300,
              weightChangeRatePerDay: 0, calculatedTDEE: 2_300, dataConfidence: .high,
              validLogCount: 21, isActionable: true)
    }

    func testKnownBalanceCorpusUsesRealDatesWithoutTargetMutationOrFalseIntervalClaims() throws {
        for slope in [-0.12, -0.05, 0, 0.05, 0.12] {
            let result = AdaptiveShadowEstimate.calculate(inputs: inputs(slope: slope), review: .init(), calendar: calendar)
            XCTAssertEqual(try XCTUnwrap(result.estimatedBurn), 2_300 - 3_500 * slope, accuracy: 0.01)
            XCTAssertEqual(try XCTUnwrap(result.slopeSpreadCalories), 0, accuracy: 0.01)
            XCTAssertEqual(result.evidenceDays, 42)
            XCTAssertTrue(result.message.contains("not measure"))
        }
    }

    func testOneLargeTransientSpikeDoesNotInventSustainedEnergyImbalance() throws {
        let result = AdaptiveShadowEstimate.calculate(inputs: inputs(spike: 40), review: .init(), calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(result.estimatedBurn), 2_300, accuracy: 1)
        let resultWithLoss = AdaptiveShadowEstimate.calculate(inputs: inputs(slope: -0.1, spike: 40), review: .init(), calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(resultWithLoss.estimatedBurn), 2_650, accuracy: 1)
    }

    func testShadowComparisonMatchesBaselineOnKnownBalancesAndReducesSingleSpikeTailError() throws {
        for spike in [nil, 40] as [Int?] {
            let input = inputs(spike: spike)
            let logs = input.intake.map { day in
                var log = DailyLog(date: day.date, meals: [Meal(name: "Complete day", foodItems: [
                    FoodItem(name: "Known synthetic intake", calories: day.calories ?? 0, protein: 150, carbs: 250, fats: 70)
                ])])
                log.nutritionDayStatus = .complete
                return log
            }
            let baseline = try XCTUnwrap(AdaptiveGoalService.expenditureSnapshot(
                weightHistory: input.weights.map { ($0.id, $0.date, $0.pounds) }, dailyLogs: logs, today: now, calendar: calendar))
            let originalError = abs(try XCTUnwrap(baseline.calculatedTDEE) - 2_300)
            let comparison = AdaptiveShadowEstimate.calculate(inputs: input, review: .init(), calendar: calendar)
            let shadowError = abs(try XCTUnwrap(comparison.estimatedBurn) - 2_300)
            XCTAssertLessThan(shadowError, 1)
            if spike == nil { XCTAssertLessThan(originalError, 1) }
            else { XCTAssertGreaterThan(originalError, 300) }
        }
    }

    func testMissingPartialAndLongGapEvidenceWithholdsComparison() {
        let partial = AdaptiveShadowEstimate.calculate(inputs: inputs(completeCount: 20), review: .init(), calendar: calendar)
        XCTAssertNil(partial.estimatedBurn); XCTAssertTrue(partial.message.contains("Missing intake"))
        let full = inputs()
        let gap = AdaptiveEstimateInputs(weights: full.weights.filter { !["w-19", "w-20", "w-21", "w-22", "w-23", "w-24", "w-25", "w-26"].contains($0.id) },
            intake: full.intake, now: now, calendar: calendar)
        XCTAssertNil(AdaptiveShadowEstimate.calculate(inputs: gap, review: .init(), calendar: calendar).estimatedBurn)
        let endGap = AdaptiveEstimateInputs(weights: Array(full.weights.prefix(30)), intake: full.intake, now: now, calendar: calendar)
        XCTAssertNil(AdaptiveShadowEstimate.calculate(inputs: endGap, review: .init(), calendar: calendar).estimatedBurn)
    }

    func testGoalTransitionDoesNotBlendEarlierEvidenceIntoNewIntent() {
        let result = AdaptiveShadowEstimate.calculate(inputs: inputs(), review: .init(),
            goalChangedAt: now.addingTimeInterval(-7 * 86_400), calendar: calendar)
        XCTAssertNil(result.estimatedBurn)
        XCTAssertTrue(result.message.contains("goal intent"))
    }

    func testExcludedSourceIsExactAccountScopedAndReversibleWithoutEditingOriginalInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AdaptiveEstimateHistoryStore(store: EditorDraftStore(directory: directory))
        let original = inputs(spike: 40)
        let record = try AdaptiveEstimateRecord(userID: "owner", inputs: original, review: .init(), baseline: baseline,
            goalIntent: "Maintain:0", previous: nil, now: now)
        try store.record(record, currentUserID: "owner")
        try store.record(record, currentUserID: "owner")
        XCTAssertEqual(try store.records(userID: "owner").count, 1)
        let weight = original.weights[40]
        XCTAssertThrowsError(try store.setExclusion(weight, excluded: true, reason: "Unusual weigh-in", userID: "owner", currentUserID: "other", expectedRevision: 0))
        try store.setExclusion(weight, excluded: true, reason: "Different scale", userID: "owner", currentUserID: "owner", expectedRevision: 0)
        let review = try store.review(userID: "owner")
        XCTAssertTrue(review.excludes(weight))
        XCTAssertFalse(review.excludes(AdaptiveWeightEvidence(id: weight.id, date: weight.date, pounds: weight.pounds - 1)), "A correction invalidates the old exclusion")
        XCTAssertThrowsError(try store.setExclusion(weight, excluded: false, reason: "", userID: "owner", currentUserID: "owner", expectedRevision: 0))
        try store.setExclusion(weight, excluded: false, reason: "", userID: "owner", currentUserID: "owner", expectedRevision: 1)
        XCTAssertFalse(try store.review(userID: "owner").excludes(weight))
        XCTAssertEqual(try store.records(userID: "owner").first?.inputs, original)
        XCTAssertTrue(try store.records(userID: "other").isEmpty)
        let reopened = AdaptiveEstimateHistoryStore(store: EditorDraftStore(directory: directory))
        XCTAssertEqual(try reopened.review(userID: "owner").revision, 2)
    }

    func testHistoryPreservesDifferentEvidenceAndGoalTransitionSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AdaptiveEstimateHistoryStore(store: EditorDraftStore(directory: directory))
        let first = try AdaptiveEstimateRecord(userID: "owner", inputs: inputs(), review: .init(), baseline: baseline,
            goalIntent: "Maintain:0", previous: nil, now: now)
        let next = try AdaptiveEstimateRecord(userID: "owner", inputs: inputs(spike: 40), review: .init(), baseline: baseline,
            goalIntent: "Lose:0.5", previous: first, now: now.addingTimeInterval(60))
        try store.record(first, currentUserID: "owner"); try store.record(next, currentUserID: "owner")
        XCTAssertEqual(try store.records(userID: "owner"), [next, first])
        XCTAssertEqual(next.goalChangedAt, next.calculatedAt)
        XCTAssertNil(next.shadow.estimatedBurn)
    }
}
