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
        SharedDataManager.shared.clearWidgetData()
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
        XCTAssertEqual(crash.userIDs.last, "")
        XCTAssertNil(analytics.userIDs.last!)
        XCTAssertEqual(crash.customValues["is_logged_in"] as? String, "true")
    }

    func testLoadedDarkModePreferenceIsNotWrittenBackAsAUserChange() async {
        auth.currentUserID = "user-1"
        database.darkModePreference = true

        let state = AppState()
        await waitForAppStateTasks()

        XCTAssertTrue(state.isDarkModeEnabled)
        XCTAssertTrue(database.savedDarkModePreferences.isEmpty)
    }

    func testLateDarkModeLoadCannotCrossAnAccountSwitch() async {
        auth.currentUserID = "user-1"
        database.loadDarkModePreferenceHandler = { userID in
            if userID == "user-1" {
                try await Task.sleep(nanoseconds: 200_000_000)
                return true
            }
            return false
        }

        let state = AppState()
        try? await Task.sleep(nanoseconds: 20_000_000)
        auth.sendAuthState("user-2")
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(state.isUserLoggedIn)
        XCTAssertFalse(state.isDarkModeEnabled)
        XCTAssertEqual(database.loadedDarkModeUserIDs, ["user-1", "user-2"])
        XCTAssertTrue(database.savedDarkModePreferences.isEmpty)
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
        XCTAssertTrue(SharedDataManager.shared.saveData(.previewData))
        let state = AppState()

        state.signOut()

        XCTAssertTrue(auth.signOutCalled)
        XCTAssertNil(SharedDataManager.shared.loadData())
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
