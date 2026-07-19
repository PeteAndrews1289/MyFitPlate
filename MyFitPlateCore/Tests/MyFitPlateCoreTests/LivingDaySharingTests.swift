import XCTest
@testable import MyFitPlateCore

final class LivingDaySharingTests: XCTestCase {
    func testWidgetProjectionKeepsOnlyNearestPrivacySafeEvents() throws {
        let snapshot = makeSnapshot(eventCount: 7)

        let events = WidgetPathProjection.make(from: snapshot, limit: 3)

        XCTAssertEqual(events.map(\.sequence), [3, 4, 5])
        XCTAssertEqual(events.map(\.kind), [.strength, .run, .recovery])
        let encoded = try JSONEncoder().encode(events)
        let payload = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(payload.contains("Private meal"))
        XCTAssertFalse(payload.contains("Private workout"))
        XCTAssertFalse(payload.contains("private-account"))
    }

    func testWidgetProjectionDropsSkippedEventsAndPreservesTrustMarker() {
        let base = date(hour: 8)
        let snapshot = makeSnapshot(events: [
            event(
                id: "private-skipped",
                kind: .strength,
                state: .skipped,
                start: base,
                evidence: .notApplicable
            ),
            event(
                id: "private-review",
                kind: .meal,
                state: .completed,
                start: base.addingTimeInterval(3_600),
                evidence: .correction
            )
        ])

        let events = WidgetPathProjection.make(from: snapshot)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .meal)
        XCTAssertEqual(events.first?.needsTrustReview, true)
    }

    func testShareSelectionIncludesOnlyExplicitVisibleSections() {
        let snapshot = makeSnapshot(eventCount: 4)

        let pathOnly = LivingDayShareBuilder.make(from: snapshot, selection: .path)
        XCTAssertNil(pathOnly.budget)
        XCTAssertEqual(pathOnly.events.count, 4)
        XCTAssertNil(pathOnly.trustReviewCount)
        XCTAssertNil(pathOnly.nextActionKind)
        XCTAssertTrue(pathOnly.events.allSatisfy { !$0.needsTrustReview })

        let trustOnly = LivingDayShareBuilder.make(from: snapshot, selection: .trust)
        XCTAssertNil(trustOnly.budget)
        XCTAssertTrue(trustOnly.events.isEmpty)
        XCTAssertEqual(trustOnly.trustReviewCount, 1)
        XCTAssertNil(trustOnly.nextActionKind)

        let budgetOnly = LivingDayShareBuilder.make(from: snapshot, selection: .budget)
        XCTAssertNotNil(budgetOnly.budget)
        XCTAssertTrue(budgetOnly.events.isEmpty)
        XCTAssertNil(budgetOnly.trustReviewCount)
        XCTAssertNil(budgetOnly.nextActionKind)

        let actionOnly = LivingDayShareBuilder.make(from: snapshot, selection: .action)
        XCTAssertNil(actionOnly.budget)
        XCTAssertTrue(actionOnly.events.isEmpty)
        XCTAssertNil(actionOnly.trustReviewCount)
        XCTAssertEqual(actionOnly.nextActionKind, .proteinCatchUp)
    }

    func testEmptyShareSelectionFailsClosedToStandardAggregateContent() {
        let snapshot = makeSnapshot(eventCount: 2)

        let share = LivingDayShareBuilder.make(from: snapshot, selection: [])

        XCTAssertEqual(share.selection, .standard)
        XCTAssertNotNil(share.budget)
        XCTAssertEqual(share.events.count, 2)
        XCTAssertNil(share.trustReviewCount)
        XCTAssertEqual(share.nextActionKind, .proteinCatchUp)
    }

    func testShareProjectionCannotRetainPrivateSourceStrings() {
        let snapshot = makeSnapshot(eventCount: 3)
        let share = LivingDayShareBuilder.make(
            from: snapshot,
            selection: [.budget, .path, .trust, .action]
        )

        let reflected = String(reflecting: share)
        XCTAssertFalse(reflected.contains("Private meal"))
        XCTAssertFalse(reflected.contains("Private workout"))
        XCTAssertFalse(reflected.contains("private-account"))
        XCTAssertFalse(reflected.contains("coordinates"))
    }

    private func makeSnapshot(eventCount: Int) -> LivingDaySnapshot {
        let kinds: [LivingDaySnapshot.EventKind] = [
            .meal, .run, .meal, .strength, .run, .recovery, .plannedMeal
        ]
        var events: [LivingDaySnapshot.Event] = []
        for index in 0..<eventCount {
            let kind = kinds[index % kinds.count]
            let state: LivingDaySnapshot.EventState = index < 3 ? .completed : .planned
            let start = date(hour: 7).addingTimeInterval(Double(index) * 3_600)
            let evidence: LivingDaySnapshot.Evidence = index == 2 ? .review : .supported
            events.append(event(
                id: "private-account:event:\(index)",
                kind: kind,
                state: state,
                start: start,
                evidence: evidence
            ))
        }
        return makeSnapshot(events: events)
    }

    private func makeSnapshot(events: [LivingDaySnapshot.Event]) -> LivingDaySnapshot {
        let day = date(hour: 0)
        return LivingDaySnapshot(
            date: day,
            generatedAt: date(hour: 10, minute: 30),
            pathWindow: .init(start: date(hour: 6), end: date(hour: 22)),
            budget: budget,
            events: events,
            trainingWindow: nil,
            nextAction: DailyNextAction(
                kind: .proteinCatchUp,
                title: "Private next action",
                detail: "Private detail",
                deepLink: "myfitplate://food-search"
            ),
            freshness: .current(updatedAt: date(hour: 10)),
            currentTime: date(hour: 10, minute: 30)
        )
    }

    private func event(
        id: String,
        kind: LivingDaySnapshot.EventKind,
        state: LivingDaySnapshot.EventState,
        start: Date,
        evidence: LivingDaySnapshot.Evidence
    ) -> LivingDaySnapshot.Event {
        LivingDaySnapshot.Event(
            id: id,
            kind: kind,
            state: state,
            title: kind == .meal ? "Private meal" : "Private workout",
            detail: "Private coordinates and notes",
            startDate: start,
            timing: .exact,
            evidence: evidence,
            destination: .none
        )
    }

    private var budget: LivingDaySnapshot.Budget {
        LivingDaySnapshot.Budget(
            calories: .init(kind: .calories, consumed: 900, planned: 400, target: 2_000),
            protein: .init(kind: .protein, consumed: 70, planned: 30, target: 140),
            carbs: .init(kind: .carbs, consumed: 100, planned: 60, target: 240),
            fats: .init(kind: .fats, consumed: 35, planned: 12, target: 70)
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: hour,
            minute: minute
        ))!
    }
}
