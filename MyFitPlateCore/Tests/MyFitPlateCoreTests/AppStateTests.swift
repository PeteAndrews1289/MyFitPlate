import XCTest
@testable import MyFitPlateCore

@MainActor
final class AppStateTests: XCTestCase {
    private var auth: MockAuthService!
    private var database: MockDatabaseService!
    private var analytics: MockAnalyticsManager!
    private var crash: MockCrashManager!

    override func setUp() {
        super.setUp()
        auth = MockAuthService()
        database = MockDatabaseService()
        analytics = MockAnalyticsManager()
        crash = MockCrashManager()
        DIContainer.shared.authService = auth
        DIContainer.shared.databaseService = database
        DIContainer.shared.analyticsManager = analytics
        DIContainer.shared.crashManager = crash
    }

    override func tearDown() {
        crash = nil
        analytics = nil
        database = nil
        auth = nil
        super.tearDown()
    }

    private func waitForAppStateTasks() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testInitWithAuthenticatedUserLoadsPreferenceAndRecordsLogin() async {
        auth.currentUserID = "user-1"
        database.darkModePreference = true

        let state = AppState()
        await waitForAppStateTasks()

        XCTAssertTrue(state.isUserLoggedIn)
        XCTAssertTrue(state.isDarkModeEnabled)
        XCTAssertEqual(database.loadedDarkModeUserIDs, ["user-1"])
        XCTAssertEqual(database.recordedLastLoginUserIDs, ["user-1"])
        XCTAssertEqual(crash.userIDs.last, "user-1")
        XCTAssertEqual(analytics.userIDs.last!, "user-1")
        XCTAssertEqual(crash.customValues["is_logged_in"] as? String, "true")
    }

    func testInitWithNoAuthenticatedUserMarksLoggedOut() async {
        auth.currentUserID = nil

        let state = AppState()
        await waitForAppStateTasks()

        XCTAssertFalse(state.isUserLoggedIn)
        XCTAssertTrue(database.loadedDarkModeUserIDs.isEmpty)
        XCTAssertTrue(database.recordedLastLoginUserIDs.isEmpty)
        XCTAssertEqual(crash.userIDs.last, "")
        XCTAssertNil(analytics.userIDs.last!)
        XCTAssertEqual(crash.customValues["is_logged_in"] as? String, "false")
    }

    func testSetUserLoggedInUpdatesPublishedFlag() {
        auth.currentUserID = nil
        let state = AppState()

        state.setUserLoggedIn(true)

        XCTAssertTrue(state.isUserLoggedIn)
    }

    func testChangingDarkModeSavesPreferenceForCurrentUser() async {
        auth.currentUserID = "user-1"
        let state = AppState()
        await waitForAppStateTasks()
        database.savedDarkModePreferences.removeAll()

        state.isDarkModeEnabled = true
        await waitForAppStateTasks()

        XCTAssertEqual(database.savedDarkModePreferences.count, 1)
        XCTAssertEqual(database.savedDarkModePreferences.first?.userID, "user-1")
        XCTAssertEqual(database.savedDarkModePreferences.first?.isEnabled, true)
    }

    func testChangingDarkModeWithoutCurrentUserSkipsSave() async {
        auth.currentUserID = nil
        let state = AppState()
        await waitForAppStateTasks()

        state.isDarkModeEnabled = true
        await waitForAppStateTasks()

        XCTAssertTrue(database.savedDarkModePreferences.isEmpty)
    }

    func testDarkModeLoadFailureFallsBackToFalse() async {
        auth.currentUserID = "user-1"
        database.darkModePreference = true
        database.loadDarkModePreferenceError = URLError(.cannotLoadFromNetwork)
        let state = AppState()
        state.isDarkModeEnabled = true

        await waitForAppStateTasks()

        XCTAssertFalse(state.isDarkModeEnabled)
        XCTAssertEqual(crash.recordedErrors.count, 1)
        XCTAssertEqual(crash.recordedErrors.first?.userInfo["release_health_area"] as? String, "database")
        XCTAssertEqual(
            crash.recordedErrors.first?.userInfo["release_health_operation"] as? String,
            "load_dark_mode_preference"
        )
    }

    func testSignOutDelegatesToAuthService() {
        let state = AppState()

        state.signOut()

        XCTAssertTrue(auth.signOutCalled)
        XCTAssertEqual(crash.userIDs.last, "")
        XCTAssertNil(analytics.userIDs.last!)
    }

    func testSignOutFailureDoesNotThrowToCaller() {
        auth.signOutError = URLError(.cannotConnectToHost)
        let state = AppState()

        state.signOut()

        XCTAssertFalse(auth.signOutCalled)
        XCTAssertEqual(crash.recordedErrors.count, 1)
        XCTAssertEqual(
            crash.recordedErrors.first?.userInfo["release_health_operation"] as? String,
            "sign_out"
        )
    }
}
