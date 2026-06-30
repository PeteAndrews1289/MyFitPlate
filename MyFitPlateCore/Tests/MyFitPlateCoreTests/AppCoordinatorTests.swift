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
    }

    func testNonMyFitPlateLinksAreIgnored() throws {
        let coordinator = AppCoordinator()
        let appState = AppState()
        appState.selectedTab = 2
        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://workouts")), appState: appState)

        coordinator.handle(url: try XCTUnwrap(URL(string: "https://example.com/home")), appState: appState)

        XCTAssertEqual(coordinator.currentRoute, .workouts)
        XCTAssertEqual(appState.selectedTab, 2)
    }
}
