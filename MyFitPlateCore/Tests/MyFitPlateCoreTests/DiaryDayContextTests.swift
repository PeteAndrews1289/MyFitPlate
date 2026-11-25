import XCTest
@testable import MyFitPlateCore

final class DiaryDayContextTests: XCTestCase {
    func testNewDayUsesGregorianCivilDateRatherThanTheUsersOtherCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        let date = try XCTUnwrap(buddhist.date(from: DateComponents(year: 2567, month: 2, day: 29, hour: 12)))
        let context = try XCTUnwrap(DiaryDayContext(userID: "owner", date: date, timeZone: buddhist.timeZone))
        XCTAssertEqual(context.dayKey, "2024-02-29")
        XCTAssertEqual(context.calendar.identifier, .gregorian)
        XCTAssertEqual(context.originalDate, date)
    }

    func testAuthoritativeKeyAndAnchorSurviveTravelAndEncoding() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let anchor = try instant("2024-12-31T23:30:00Z")
        let captured = try XCTUnwrap(DiaryDayContext(userID: "owner", date: anchor, timeZone: newYork, dayKey: "2024-12-30"))
        let restored = try JSONDecoder().decode(DiaryDayContext.self, from: JSONEncoder().encode(captured))
        XCTAssertEqual(restored, captured)
        XCTAssertEqual(restored.dayKey, "2024-12-30", "An existing document ID wins over a newly interpreted timestamp")
        XCTAssertEqual(restored.originalDate, anchor)
        XCTAssertEqual(restored.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(restored.calendar.component(.day, from: restored.displayDate), 30)
        XCTAssertEqual(DiaryDayContext.dayKey(for: anchor, timeZone: tokyo), "2025-01-01")
    }

    func testNewEmptyDayAnchorUsesAuthoritativeCivilKeyWithoutChangingCapturedTimestamp() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let original = try instant("2024-03-12T18:37:00Z")
        let captured = try XCTUnwrap(DiaryDayContext(userID: "owner", date: original, timeZone: zone, dayKey: "2024-03-10"))
        XCTAssertEqual(captured.startOfDay, try instant("2024-03-10T05:00:00Z"))
        XCTAssertEqual(captured.originalDate, original)
        XCTAssertEqual(captured.dayKey, "2024-03-10")
    }

    func testCivilNavigationCrossesLeapDayAndYearBoundary() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let leap = try XCTUnwrap(DiaryDayContext(userID: "owner", date: instant("2024-02-28T00:00:00Z"), timeZone: utc))
        XCTAssertEqual(leap.adding(days: 1)?.dayKey, "2024-02-29")
        XCTAssertEqual(leap.adding(days: 2)?.dayKey, "2024-03-01")
        let yearEnd = try XCTUnwrap(DiaryDayContext(userID: "owner", date: instant("2024-12-31T00:00:00Z"), timeZone: utc))
        XCTAssertEqual(yearEnd.adding(days: 1)?.dayKey, "2025-01-01")
        XCTAssertEqual(yearEnd.adding(days: -1)?.dayKey, "2024-12-30")
    }

    func testNavigationUsesCalendarDaysAcrossBothDSTChanges() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let spring = try XCTUnwrap(DiaryDayContext(userID: "owner", date: instant("2024-03-10T05:00:00Z"), timeZone: zone))
        let springNext = try XCTUnwrap(spring.adding(days: 1))
        XCTAssertEqual(springNext.dayKey, "2024-03-11")
        XCTAssertEqual(springNext.originalDate.timeIntervalSince(spring.originalDate), 23 * 3_600)
        let autumn = try XCTUnwrap(DiaryDayContext(userID: "owner", date: instant("2024-11-03T04:00:00Z"), timeZone: zone))
        let autumnNext = try XCTUnwrap(autumn.adding(days: 1))
        XCTAssertEqual(autumnNext.dayKey, "2024-11-04")
        XCTAssertEqual(autumnNext.originalDate.timeIntervalSince(autumn.originalDate), 25 * 3_600)
        XCTAssertEqual(autumnNext.userID, "owner")
        XCTAssertEqual(autumnNext.timeZoneIdentifier, zone.identifier)
    }

    func testFutureAndAccountChecksUseTheCapturedDayAndOwner() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try instant("2024-03-01T02:00:00Z")
        let day = try XCTUnwrap(DiaryDayContext(userID: "original-owner", date: now, timeZone: zone))
        XCTAssertEqual(day.dayKey, "2024-02-29")
        XCTAssertTrue(day.isToday(now: now))
        XCTAssertFalse(day.isFuture(now: now))
        XCTAssertTrue(try XCTUnwrap(day.adding(days: 1)).isFuture(now: now))
        XCTAssertTrue(day.isOwned(by: "original-owner"))
        XCTAssertFalse(day.isOwned(by: "other-owner"))
        XCTAssertFalse(day.isOwned(by: nil))
    }

    func testInvalidKeysOwnersAndCorruptCapturedZonesFailClosed() throws {
        let anchor = try instant("2024-02-29T12:00:00Z")
        for key in ["2023-02-29", "2024-02-30", "2024-13-01", "0000-01-01", "2024-2-29", "../2024-02", "٢٠٢٤-٠٢-٢٩"] {
            XCTAssertNil(DiaryDayContext(userID: "owner", date: anchor, dayKey: key), key)
        }
        XCTAssertNil(DiaryDayContext(userID: "  ", date: anchor))
        let valid = try XCTUnwrap(DiaryDayContext(userID: "owner", date: anchor))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object["timeZoneIdentifier"] = "Not/A_Time_Zone"
        XCTAssertThrowsError(try JSONDecoder().decode(DiaryDayContext.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testSubmittedLegacyDraftAndQueuedOperationKeepTheirExactIdentitiesAndPayload() throws {
        let anchor = try instant("2024-02-29T23:17:00Z")
        let entry = FoodLoggingDraft.Entry(food: FoodItem(id: "source", name: "Oats", calories: 200, protein: 8), now: anchor)
        let legacy = LegacyDraft(id: UUID(), date: anchor, mealName: "Lunch", entries: [entry], isSubmitted: true)
        let legacyData = try JSONEncoder().encode(legacy)
        let restored = try JSONDecoder().decode(FoodLoggingDraft.self, from: legacyData)
        XCTAssertNil(restored.dayContext, "Opening a submitted legacy payload must not invent a new destination")
        XCTAssertEqual(restored.id, legacy.id)
        XCTAssertEqual(restored.date, anchor, "Decode must not normalize the saved anchor to a different midnight")
        XCTAssertEqual(restored.entries.first?.id, entry.id)
        XCTAssertTrue(restored.isSubmitted)
        XCTAssertEqual(try jsonObject(JSONEncoder().encode(restored)), try jsonObject(legacyData))

        let pending = PendingQuickFoodLog(id: UUID(), sourceFoodID: "source", draft: restored, source: "legacy", isAccepted: true)
        let retried = try JSONDecoder().decode(PendingQuickFoodLog.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(retried.id, pending.id)
        XCTAssertEqual(retried.draft.id, legacy.id)
        XCTAssertEqual(retried.draft.date, anchor)
        XCTAssertEqual(retried.draft.foods.first?.id, pending.draft.foods.first?.id)
        XCTAssertEqual(retried.isAccepted, true)
    }

    func testOlderDraftReaderCanIgnoreNewContextWithoutChangingFrozenFood() throws {
        let anchor = try instant("2024-02-29T12:00:00Z")
        let context = try XCTUnwrap(DiaryDayContext(userID: "owner", date: anchor, timeZone: TimeZone(secondsFromGMT: 0)!))
        var draft = FoodLoggingDraft(date: anchor, mealName: "Dinner", dayContext: context)
        draft.entries = [FoodLoggingDraft.Entry(food: FoodItem(id: "source", name: "Rice", calories: 150), now: anchor)]
        draft.isSubmitted = true
        let older = try JSONDecoder().decode(LegacyDraft.self, from: JSONEncoder().encode(draft))
        let upgradedAgain = try JSONDecoder().decode(FoodLoggingDraft.self, from: JSONEncoder().encode(older))
        XCTAssertEqual(older.id, draft.id)
        XCTAssertEqual(upgradedAgain.id, draft.id)
        XCTAssertEqual(upgradedAgain.date, anchor)
        XCTAssertEqual(upgradedAgain.foods.first?.id, draft.foods.first?.id)
        XCTAssertEqual(upgradedAgain.foods.first?.calories, 150)
        XCTAssertTrue(upgradedAgain.isSubmitted)
        XCTAssertNil(upgradedAgain.dayContext)
    }

    private func instant(_ string: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: string)) }
    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private struct LegacyDraft: Codable {
        let id: UUID
        let date: Date
        let mealName: String
        let entries: [FoodLoggingDraft.Entry]
        let isSubmitted: Bool
    }
}
