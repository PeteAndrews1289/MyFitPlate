import XCTest
@testable import MyFitPlateCore

final class ReleaseHealthTests: XCTestCase {
    func testConfigureStampsCrashAndAnalyticsContext() {
        let crash = MockCrashManager()
        let analytics = MockAnalyticsManager()
        let context = ReleaseHealthBuildContext(
            appVersion: "2.1",
            buildNumber: "210",
            bundleIdentifier: "com.myfitplate.app",
            buildEnvironment: "release",
            osVersion: "iOS 18.5",
            isUITesting: false
        )

        ReleaseHealth.configure(
            crashManager: crash,
            analyticsManager: analytics,
            context: context
        )

        XCTAssertEqual(crash.customValues["release_health_schema"] as? String, "1")
        XCTAssertEqual(crash.customValues["app_version"] as? String, "2.1")
        XCTAssertEqual(crash.customValues["build_number"] as? String, "210")
        XCTAssertEqual(crash.customValues["build_environment"] as? String, "release")
        XCTAssertEqual(analytics.userProperties["app_version"], "2.1")
        XCTAssertEqual(analytics.userProperties["build_number"], "210")
        XCTAssertEqual(analytics.loggedEvents.first?.name, "app_session_started")
        XCTAssertEqual(analytics.loggedEvents.first?.parameters?["app_version"] as? String, "2.1")
        XCTAssertTrue(crash.logs.first?.contains("release_health.session_started") == true)
    }

    func testIdentifyUserUpdatesCrashAndAnalyticsState() {
        let crash = MockCrashManager()
        let analytics = MockAnalyticsManager()

        ReleaseHealth.identifyUser(
            userID: "user-123",
            crashManager: crash,
            analyticsManager: analytics
        )
        ReleaseHealth.identifyUser(
            userID: nil,
            crashManager: crash,
            analyticsManager: analytics
        )

        XCTAssertEqual(crash.userIDs, ["user-123", ""])
        XCTAssertEqual(analytics.userIDs.count, 2)
        XCTAssertEqual(analytics.userIDs[0], "user-123")
        XCTAssertNil(analytics.userIDs[1])
        XCTAssertEqual(crash.customValues["is_logged_in"] as? String, "false")
    }

    func testRecordStartupCompletedLogsDurationAndBucket() {
        let crash = MockCrashManager()
        let analytics = MockAnalyticsManager()

        ReleaseHealth.recordStartupCompleted(
            duration: 1.234,
            crashManager: crash,
            analyticsManager: analytics
        )

        XCTAssertEqual(crash.customValues["startup_duration_ms"] as? Int, 1_234)
        XCTAssertEqual(crash.customValues["startup_duration_bucket"] as? String, "1s_to_2s")
        XCTAssertEqual(analytics.loggedEvents.first?.name, "app_startup_completed")
        XCTAssertEqual(analytics.loggedEvents.first?.parameters?["duration_ms"] as? Int, 1_234)
        XCTAssertEqual(analytics.loggedEvents.first?.parameters?["duration_bucket"] as? String, "1s_to_2s")
        XCTAssertTrue(crash.logs.first?.contains("release_health.startup_completed") == true)
    }

    func testStartupDurationBucketsAreStable() {
        XCTAssertEqual(ReleaseHealth.startupDurationBucket(milliseconds: 100), "under_500ms")
        XCTAssertEqual(ReleaseHealth.startupDurationBucket(milliseconds: 700), "500ms_to_1s")
        XCTAssertEqual(ReleaseHealth.startupDurationBucket(milliseconds: 1_500), "1s_to_2s")
        XCTAssertEqual(ReleaseHealth.startupDurationBucket(milliseconds: 3_000), "2s_to_4s")
        XCTAssertEqual(ReleaseHealth.startupDurationBucket(milliseconds: 4_500), "over_4s")
    }

    func testRecordNonFatalAddsSafeContextAndAnalyticsBreadcrumb() {
        let crash = MockCrashManager()
        let analytics = MockAnalyticsManager()
        let error = URLError(.cannotConnectToHost)

        ReleaseHealth.recordNonFatal(
            error,
            area: .database,
            operation: "save_dark_mode_preference",
            metadata: ["retry_count": 2, "will_retry": false],
            crashManager: crash,
            analyticsManager: analytics
        )

        XCTAssertEqual(crash.recordedErrors.count, 1)
        XCTAssertEqual(
            crash.recordedErrors.first?.userInfo["release_health_area"] as? String,
            "database"
        )
        XCTAssertEqual(
            crash.recordedErrors.first?.userInfo["release_health_operation"] as? String,
            "save_dark_mode_preference"
        )
        XCTAssertEqual(crash.recordedErrors.first?.userInfo["retry_count"] as? Int, 2)
        XCTAssertEqual(crash.recordedErrors.first?.userInfo["will_retry"] as? String, "false")
        XCTAssertEqual(analytics.loggedEvents.first?.name, "nonfatal_error_recorded")
        XCTAssertEqual(analytics.loggedEvents.first?.parameters?["area"] as? String, "database")
    }
}
