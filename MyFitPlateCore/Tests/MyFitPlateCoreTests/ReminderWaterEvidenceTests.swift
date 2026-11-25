import XCTest
@testable import MyFitPlateCore

@MainActor final class ReminderWaterEvidenceTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9, minute: 59))! }
    private var source: ReminderEvidence {
        .init(logs: ["2026-11-04": .init(id: "2026-11-04", date: now, meals: [], waterTracker: .init(totalOunces: 8, date: now))],
            goals: .init(calories: 2_000, protein: 120, carbs: 200, fats: 65), waterGoal: 64)
    }
    private func record() -> ReminderAccountRecord { var value = ReminderAccountRecord(); value.preferences[.hydration].enabled = true; return value }

    func testRecentAcceptedWaterSuppressesOnlyNearRequestAndOldTapWhileLaterScheduleRemains() throws {
        var evidence = source; evidence.recentWaterAcceptedAt["2026-11-04"] = now
        let decisions = ReminderPolicy.decisions(ownerID: "owner", record: record(), evidence: evidence, now: now, calendar: calendar)
        let first = try XCTUnwrap(decisions.first { $0.candidate.target.dayKey == "2026-11-04" })
        XCTAssertEqual(first.state, .suppressed)
        XCTAssertTrue(first.reason.contains("45 minutes"))
        XCTAssertTrue(decisions.contains { $0.candidate.target.dayKey == "2026-11-04" && $0.state == .ready })
        let afterWindow = now.addingTimeInterval(46 * 60)
        XCTAssertTrue(ReminderPolicy.actionIsCurrent(first.candidate, ownerID: "owner", preferences: record().preferences,
            evidence: evidence, now: afterWindow, calendar: calendar))
        evidence.recentWaterAcceptedAt["2026-11-04"] = afterWindow
        XCTAssertFalse(ReminderPolicy.actionIsCurrent(first.candidate, ownerID: "owner", preferences: record().preferences,
            evidence: evidence, now: afterWindow, calendar: calendar))
    }

    func testPendingWaterBelowGoalAndUnreadableReceiptSuppressWithoutFabricatedIntake() {
        var evidence = source; evidence.pendingWaterDayKeys = ["2026-11-04"]
        let today = ReminderPolicy.decisions(ownerID: "owner", record: record(), evidence: evidence, now: now, calendar: calendar)
            .filter { $0.candidate.target.dayKey == "2026-11-04" }
        XCTAssertTrue(today.allSatisfy { $0.state == .suppressed && $0.reason.contains("waiting") })
        XCTAssertEqual(evidence.logs["2026-11-04"]?.waterTracker?.totalOunces, 8)
        evidence.pendingWaterDayKeys = []; evidence.waterEvidenceUnavailable = true
        XCTAssertTrue(ReminderPolicy.decisions(ownerID: "owner", record: record(), evidence: evidence, now: now, calendar: calendar)
            .allSatisfy { $0.state == .suppressed && $0.reason.contains("unavailable") })
    }

    func testWaterReceiptIsOwnerScopedDurableIdempotentAndCannotOutliveUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReminderWaterEvidenceStore(drafts: .init(directory: directory))
        try store.recordAccepted(ownerID: "owner", currentUserID: "owner", entryID: "water", dayKey: "2026-11-04", totalAfterOunces: 8, acceptedAt: now)
        try store.recordAccepted(ownerID: "owner", currentUserID: "owner", entryID: "water", dayKey: "2026-11-04", totalAfterOunces: 8, acceptedAt: now.addingTimeInterval(30))
        let restored = ReminderWaterEvidenceStore(drafts: .init(directory: directory))
        XCTAssertEqual(try restored.recentAcceptedTimes(ownerID: "owner", logs: source.logs, now: now.addingTimeInterval(40))["2026-11-04"], now)
        XCTAssertTrue(try restored.recentAcceptedTimes(ownerID: "other", logs: source.logs, now: now).isEmpty)
        XCTAssertThrowsError(try restored.recordAccepted(ownerID: "owner", currentUserID: "other", entryID: "changed", dayKey: "2026-11-04", totalAfterOunces: 8))
        var undone = source.logs; undone["2026-11-04"]?.waterTracker?.totalOunces = 0
        XCTAssertTrue(try restored.recentAcceptedTimes(ownerID: "owner", logs: undone, now: now).isEmpty)
        XCTAssertTrue(try restored.recentAcceptedTimes(ownerID: "owner", logs: source.logs, now: now.addingTimeInterval(45 * 60)).isEmpty)
    }
}
