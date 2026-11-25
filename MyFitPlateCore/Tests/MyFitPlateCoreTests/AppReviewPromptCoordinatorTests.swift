import XCTest
@testable import MyFitPlateCore

final class AppReviewPromptCoordinatorTests: XCTestCase {
    private let suiteName = "app-review-prompt-tests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRequiresThreeDistinctSessionsAcrossThreeDays() {
        let start = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(register("one", at: start))
        XCTAssertFalse(register("two", at: start.addingTimeInterval(60)))
        XCTAssertTrue(register("three", at: start.addingTimeInterval(3 * 24 * 60 * 60)))
    }

    func testDuplicateSessionDoesNotAdvanceEligibility() {
        let start = Date(timeIntervalSince1970: 20_000)

        XCTAssertFalse(register("one", at: start))
        XCTAssertFalse(register("one", at: start.addingTimeInterval(4 * 24 * 60 * 60)))
        XCTAssertFalse(register("two", at: start.addingTimeInterval(5 * 24 * 60 * 60)))
    }

    func testRequestsOnlyOncePerVersionAndHonorsCooldown() {
        let start = Date(timeIntervalSince1970: 30_000)
        XCTAssertFalse(register("one", at: start))
        XCTAssertFalse(register("two", at: start.addingTimeInterval(60)))
        XCTAssertTrue(register("three", at: start.addingTimeInterval(3 * 24 * 60 * 60)))

        XCTAssertFalse(register("four", version: "2.2", at: start.addingTimeInterval(130 * 24 * 60 * 60)))
        XCTAssertFalse(register("five", version: "2.3", at: start.addingTimeInterval(100 * 24 * 60 * 60)))
        XCTAssertTrue(register("six", version: "2.3", at: start.addingTimeInterval(130 * 24 * 60 * 60)))
    }

    func testRejectsMissingSessionOrVersion() {
        XCTAssertFalse(register("", at: Date()))
        XCTAssertFalse(register("session", version: "", at: Date()))
    }

    func testLoggingDayMomentIsStableWithinALocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let morning = Date(timeIntervalSince1970: 1_790_000_000)

        XCTAssertEqual(
            AppReviewPromptCoordinator.loggingDayMomentID(for: morning, calendar: calendar),
            AppReviewPromptCoordinator.loggingDayMomentID(for: morning.addingTimeInterval(3 * 60 * 60), calendar: calendar)
        )
        XCTAssertEqual(AppReviewPromptCoordinator.loggingDayMomentID(for: morning, calendar: calendar), "logging-day:2026-09-21")
        XCTAssertNotEqual(
            AppReviewPromptCoordinator.loggingDayMomentID(for: morning, calendar: calendar),
            AppReviewPromptCoordinator.weeklyCheckInMomentID(for: morning, calendar: calendar)
        )
    }

    private func register(
        _ sessionID: String,
        version: String = "2.2",
        at date: Date
    ) -> Bool {
        AppReviewPromptCoordinator.registerCompletedSession(
            id: sessionID,
            appVersion: version,
            now: date,
            userDefaults: defaults
        )
    }
}

@MainActor
final class AppReviewPromptQueueTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    override func setUp() {
        super.setUp()
        suiteName = "app-review-queue-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeQueue(version: String = "3.0", enabled: Bool = true) -> AppReviewPromptQueue {
        AppReviewPromptQueue(userDefaults: defaults, appVersion: { version }, isEnabled: { enabled })
    }

    func testLoggingOnThreeDaysAcrossThreeDaysQueuesARequest() {
        let queue = makeQueue()

        queue.recordLoggingDay(now: start, calendar: calendar)
        queue.recordLoggingDay(now: start.addingTimeInterval(day), calendar: calendar)
        XCTAssertNil(queue.pendingMoment, "two logging days are not enough")

        queue.recordLoggingDay(now: start.addingTimeInterval(3 * day), calendar: calendar)
        XCTAssertEqual(queue.pendingMoment, .loggingDay)
    }

    func testRepeatedLoggingOnOneDayDoesNotAdvance() {
        let queue = makeQueue()

        for hour in 0..<6 {
            queue.recordLoggingDay(now: start.addingTimeInterval(TimeInterval(hour) * 60 * 60), calendar: calendar)
        }
        queue.recordLoggingDay(now: start.addingTimeInterval(4 * day), calendar: calendar)

        XCTAssertNil(queue.pendingMoment)
    }

    func testTakingTheRequestAsksOncePerVersion() {
        let queue = makeQueue()
        queue.recordLoggingDay(now: start, calendar: calendar)
        queue.recordLoggingDay(now: start.addingTimeInterval(day), calendar: calendar)
        queue.recordLoggingDay(now: start.addingTimeInterval(3 * day), calendar: calendar)

        XCTAssertEqual(queue.takePendingRequest(now: start.addingTimeInterval(3 * day)), .loggingDay)
        XCTAssertNil(queue.pendingMoment)

        queue.recordLoggingDay(now: start.addingTimeInterval(5 * day), calendar: calendar)
        XCTAssertNil(queue.pendingMoment, "already asked in this version")
    }

    func testAWorkoutRequestSuppressesTheQueuedOne() {
        let queue = makeQueue()
        queue.recordLoggingDay(now: start, calendar: calendar)
        queue.recordLoggingDay(now: start.addingTimeInterval(day), calendar: calendar)
        queue.recordLoggingDay(now: start.addingTimeInterval(3 * day), calendar: calendar)
        XCTAssertEqual(queue.pendingMoment, .loggingDay)

        XCTAssertTrue(AppReviewPromptCoordinator.registerCompletedSession(
            id: "workout-1",
            appVersion: "3.0",
            now: start.addingTimeInterval(3 * day),
            userDefaults: defaults
        ))

        XCTAssertNil(queue.takePendingRequest(now: start.addingTimeInterval(3 * day)), "never ask twice in one version")
    }

    func testWeeklyCheckInsAndWorkoutsShareOneHistory() {
        let queue = makeQueue()
        XCTAssertFalse(AppReviewPromptCoordinator.registerCompletedSession(
            id: "workout-1",
            appVersion: "3.0",
            now: start,
            userDefaults: defaults
        ))
        queue.recordLoggingDay(now: start.addingTimeInterval(day), calendar: calendar)
        queue.recordWeeklyCheckIn(now: start.addingTimeInterval(7 * day), calendar: calendar)

        XCTAssertEqual(queue.pendingMoment, .weeklyCheckIn)
    }

    func testDisabledQueueRecordsNothing() {
        let queue = makeQueue(enabled: false)
        for offset in 0..<5 {
            queue.recordLoggingDay(now: start.addingTimeInterval(TimeInterval(offset) * day), calendar: calendar)
        }

        XCTAssertNil(queue.pendingMoment)
        XCTAssertFalse(AppReviewPromptCoordinator.isEligibleForRequest(
            appVersion: "3.0",
            now: start.addingTimeInterval(5 * day),
            userDefaults: defaults
        ))
    }

    func testClearingDropsThePendingRequest() {
        let queue = makeQueue()
        queue.recordLoggingDay(now: start, calendar: calendar)
        queue.recordLoggingDay(now: start.addingTimeInterval(day), calendar: calendar)
        queue.recordLoggingDay(now: start.addingTimeInterval(3 * day), calendar: calendar)

        queue.clearPending()

        XCTAssertNil(queue.takePendingRequest(now: start.addingTimeInterval(3 * day)))
    }
}
