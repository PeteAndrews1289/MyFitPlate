import XCTest
import MyFitPlateShared
@testable import MyFitPlateCore

@MainActor
final class AppCoordinatorTests: XCTestCase {
    private var auth: MockAuthService!
    private var database: MockDatabaseService!

    override func setUp() {
        super.setUp()
        auth = MockAuthService()
        database = MockDatabaseService()
        DIContainer.shared.authService = auth
        DIContainer.shared.databaseService = database
        DIContainer.shared.analyticsManager = MockAnalyticsManager()
        DIContainer.shared.crashManager = MockCrashManager()
    }

    override func tearDown() {
        database = nil
        auth = nil
        super.tearDown()
    }

    func testHomeDeepLinkSelectsHomeTab() throws {
        let coordinator = AppCoordinator()
        let appState = AppState()
        appState.selectedTab = 3

        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://home")), appState: appState)

        XCTAssertEqual(coordinator.currentRoute, .home)
        XCTAssertEqual(coordinator.pendingRoute, .home)
        XCTAssertEqual(appState.selectedTab, 0)
    }

    func testCompanionLinksCarryOnlyTheirSessionAndStayReadOnly() throws {
        let coordinator = AppCoordinator()
        let destinations: [(MyFitPlateLinks.ActivityDestination, Route)] = [(.workout, .activeWorkout), (.run, .activeRun), (.fast, .activeFast)]
        for (destination, route) in destinations {
            let url = try XCTUnwrap(destination.url(sessionID: "session-a"))
            XCTAssertEqual(coordinator.handle(url: url), route)
            XCTAssertEqual(coordinator.takePendingRequest()?.objectID, "session-a")
            let legacy: Route = route == .activeWorkout ? .workouts : route == .activeRun ? .runs : .home
            XCTAssertEqual(coordinator.handle(url: try XCTUnwrap(destination.url(sessionID: nil))), legacy)
            XCTAssertNil(coordinator.takePendingRequest()?.objectID)
            let modified = try XCTUnwrap(URL(string: url.absoluteString + "&action=complete"))
            XCTAssertEqual(coordinator.handle(url: modified), .unavailable)
            let otherOwner = try XCTUnwrap(URL(string: url.absoluteString + "&owner=b"))
            coordinator.handle(url: otherOwner)
            XCTAssertEqual(coordinator.takePendingRequest()?.resolvedRoute(currentUserID: "a"), .unavailable)
        }
    }

    func testTodayShortcutResolvesTheOwnersCurrentDayWhenItOpens() throws {
        let coordinator = AppCoordinator()
        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://today")))
        let request = try XCTUnwrap(coordinator.takePendingRequest())
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let utc = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-25T04:55:00Z"))
        XCTAssertEqual(request.diaryDayContext(for: "a", timeZone: zone, now: utc)?.dayKey, "2026-11-24")
        XCTAssertEqual(request.diaryDayContext(for: "a", timeZone: zone, now: utc.addingTimeInterval(600))?.dayKey, "2026-11-25")
        XCTAssertEqual(coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://today?day=2026-11-20"))), .unavailable)
    }

    func testWidgetNextActionExpiresAtMidnightAndWhenSnapshotIsOld() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 23, minute: 50)))
        var snapshot = WidgetData.previewData
        snapshot.lastUpdated = day
        snapshot.pathDate = day
        XCTAssertEqual(snapshot.currentNextAction(at: day, calendar: calendar)?.deepLink, snapshot.nextAction?.deepLink)
        XCTAssertNil(snapshot.currentNextAction(at: day.addingTimeInterval(900), calendar: calendar))
        XCTAssertEqual(snapshot.nextDayRefreshBoundary(after: day, calendar: calendar), day.addingTimeInterval(600))
        snapshot.pathDate = day.addingTimeInterval(-86400)
        XCTAssertNil(snapshot.currentNextAction(at: day, calendar: calendar))
        snapshot.pathDate = nil
        snapshot.lastUpdated = day.addingTimeInterval(-10800)
        XCTAssertNil(snapshot.currentNextAction(at: day, calendar: calendar))
        snapshot.lastUpdated = nil
        XCTAssertTrue(snapshot.needsDayRefresh(at: day, calendar: calendar))
    }

    func testDeepLinksRouteKnownTabs() throws {
        let coordinator = AppCoordinator()
        let appState = AppState()

        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://nutrition")), appState: appState)
        XCTAssertEqual(coordinator.currentRoute, .nutrition)
        XCTAssertEqual(appState.selectedTab, 3)

        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://workouts")), appState: appState)
        XCTAssertEqual(coordinator.currentRoute, .workouts)
        XCTAssertEqual(appState.selectedTab, 2)

        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://maia")), appState: appState)
        XCTAssertEqual(coordinator.currentRoute, .maia)
        XCTAssertEqual(appState.selectedTab, 1)

        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://reports")), appState: appState)
        XCTAssertEqual(coordinator.currentRoute, .reports)
        XCTAssertEqual(appState.selectedTab, 4)
    }

    func testCustomProductPageLinksQueueExactDestinations() throws {
        let coordinator = AppCoordinator()
        let appState = AppState()
        appState.isUserLoggedIn = false

        let cases: [(String, Route, Int)] = [
            ("myfitplate://food-search?source=app_store", .foodSearch, 0),
            ("myfitplate://trust-score", .trust, 0),
            ("myfitplate://fast-food-builder", .builder, 0),
            ("myfitplate://running", .runs, 2),
            ("myfitplate://meal-plan", .nutrition, 3),
            ("myfitplate://training-fuel", .trainingFuel, 0)
        ]

        for (urlString, expectedRoute, expectedTab) in cases {
            coordinator.handle(url: try XCTUnwrap(URL(string: urlString)), appState: appState)

            XCTAssertEqual(coordinator.currentRoute, expectedRoute)
            XCTAssertEqual(coordinator.pendingRoute, expectedRoute)
            XCTAssertEqual(appState.selectedTab, expectedTab)
        }
    }

    func testRouteCanQueueWithoutAnAppStateForNotificationDelegate() throws {
        let coordinator = AppCoordinator()

        let route = coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://recovery-fuel")))

        XCTAssertEqual(route, .trainingFuel)
        XCTAssertEqual(coordinator.currentRoute, .trainingFuel)
        XCTAssertEqual(coordinator.pendingRoute, .trainingFuel)
    }

    func testPathStyleLinkAndPendingRouteSurviveUntilTaken() throws {
        let coordinator = AppCoordinator()
        let appState = AppState()

        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate:///food-trust")), appState: appState)

        XCTAssertEqual(coordinator.pendingRoute, .trust)
        XCTAssertEqual(coordinator.takePendingRoute(), .trust)
        XCTAssertNil(coordinator.pendingRoute)
        XCTAssertNil(coordinator.takePendingRoute())
    }

    func testNonMyFitPlateLinksAreIgnored() throws {
        let coordinator = AppCoordinator()
        let appState = AppState()
        appState.selectedTab = 2
        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://workouts")), appState: appState)

        coordinator.handle(url: try XCTUnwrap(URL(string: "https://example.com/home")), appState: appState)

        XCTAssertEqual(coordinator.currentRoute, .workouts)
        XCTAssertEqual(coordinator.pendingRoute, .workouts)
        XCTAssertEqual(appState.selectedTab, 2)
    }

    func testUnsupportedAndUndeliveredCommunityLinksQueueAnExplicitUnavailableDestination() throws {
        let coordinator = AppCoordinator()
        for url in ["myfitplate://not-a-feature", "myfitplate://community"] {
            XCTAssertEqual(coordinator.handle(url: try XCTUnwrap(URL(string: url))), .unavailable)
            XCTAssertEqual(coordinator.takePendingRoute(), .unavailable)
        }
    }

    func testProfileAndSettingsRemainExactDeferredDestinations() throws {
        let coordinator = AppCoordinator()
        XCTAssertEqual(coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://profile"))), .profile)
        XCTAssertEqual(coordinator.takePendingRoute(), .profile)
        XCTAssertEqual(coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://settings"))), .settings)
        XCTAssertEqual(coordinator.takePendingRoute(), .settings)
    }
}
