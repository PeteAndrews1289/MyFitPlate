import XCTest
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
            ("myfitplate://meal-plan", .nutrition, 3)
        ]

        for (urlString, expectedRoute, expectedTab) in cases {
            coordinator.handle(url: try XCTUnwrap(URL(string: urlString)), appState: appState)

            XCTAssertEqual(coordinator.currentRoute, expectedRoute)
            XCTAssertEqual(coordinator.pendingRoute, expectedRoute)
            XCTAssertEqual(appState.selectedTab, expectedTab)
        }
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
}
