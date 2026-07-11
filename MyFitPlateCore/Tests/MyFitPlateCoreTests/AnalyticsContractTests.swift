import XCTest
@testable import MyFitPlateCore

@MainActor
final class AnalyticsContractTests: XCTestCase {
    func testFirebaseParametersAddSchemaAndPreserveSafeDestination() {
        let parameters = ProductAnalytics.firebaseParameters([
            "destination": "foodSearch",
            "route": "gps-polyline",
            "remaining_calories": 420,
            "source": "app_store"
        ])

        XCTAssertEqual(parameters["analytics_schema"] as? String, ProductAnalytics.schemaVersion)
        XCTAssertEqual(parameters["destination"] as? String, "foodSearch")
        XCTAssertEqual(parameters["source"] as? String, "app_store")
        XCTAssertNil(parameters["route"])
        XCTAssertNil(parameters["remaining_calories"])
    }

    func testDashboardEventNamesFitFirebaseContract() {
        for event in ProductAnalytics.Event.allCases {
            XCTAssertLessThanOrEqual(event.rawValue.count, 40, event.rawValue)
            XCTAssertEqual(event.rawValue, event.rawValue.lowercased())
            XCTAssertFalse(event.rawValue.contains(" "))
        }
    }

    func testTrainingFuelDimensionsSurviveWithoutNutritionDetails() {
        let parameters = ProductAnalytics.firebaseParameters([
            "training_mode": "strength",
            "phase_count": 2,
            "confirmation_path": "handoff",
            "outcome": "completed",
            "source": "recorded_run",
            "phase": "before_training",
            "destination": "food_search",
            "target_protein": 25,
            "target_carbs": 40
        ])

        XCTAssertEqual(parameters["training_mode"] as? String, "strength")
        XCTAssertEqual(parameters["phase_count"] as? Int, 2)
        XCTAssertEqual(parameters["confirmation_path"] as? String, "handoff")
        XCTAssertEqual(parameters["outcome"] as? String, "completed")
        XCTAssertEqual(parameters["source"] as? String, "recorded_run")
        XCTAssertEqual(parameters["phase"] as? String, "before_training")
        XCTAssertEqual(parameters["destination"] as? String, "food_search")
        XCTAssertNil(parameters["target_protein"])
        XCTAssertNil(parameters["target_carbs"])
    }

    func testGenericSensitiveAliasesCannotBypassPrivacySanitizer() {
        let parameters = ProductAnalytics.firebaseParameters([
            "action": "opened",
            "amount": 16,
            "category": "Private journal category",
            "delta": -250,
            "duration": 45,
            "goal": "Personal training goal",
            "routine_name": "User-created routine",
            "set_count": 12,
            "title": "Personalized coaching title",
            "weigh_ins": 8
        ])

        XCTAssertEqual(parameters["action"] as? String, "opened")
        XCTAssertEqual(parameters["analytics_schema"] as? String, ProductAnalytics.schemaVersion)
        for key in [
            "amount", "category", "delta", "duration", "goal",
            "routine_name", "set_count", "title", "weigh_ins"
        ] {
            XCTAssertNil(parameters[key], key)
        }
    }

    func testDurationBucketsAreStable() {
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: -1), "under_500ms")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 700), "500ms_to_1s")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 1_500), "1s_to_2s")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 3_000), "2s_to_4s")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 6_000), "over_4s")
    }

    func testActiveLoggerEventFiresOncePerLocalDay() throws {
        let suiteName = "analytics-contract-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = MockAnalyticsManager()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let firstDay = Date(timeIntervalSince1970: 1_700_000_000)

        ProductEngagementTelemetry.recordFoodLoggingDay(
            source: "quick_log",
            now: firstDay,
            calendar: calendar,
            userDefaults: defaults,
            analyticsManager: analytics
        )
        ProductEngagementTelemetry.recordFoodLoggingDay(
            source: "manual_add",
            now: firstDay.addingTimeInterval(60),
            calendar: calendar,
            userDefaults: defaults,
            analyticsManager: analytics
        )
        ProductEngagementTelemetry.recordFoodLoggingDay(
            source: "repeat_yesterday",
            now: firstDay.addingTimeInterval(86_400),
            calendar: calendar,
            userDefaults: defaults,
            analyticsManager: analytics
        )

        let events = analytics.loggedEvents.filter {
            $0.name == ProductAnalytics.Event.loggingDayActive.rawValue
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.parameters?["entry_source"] as? String, "quick_log")
        XCTAssertEqual(events.last?.parameters?["entry_source"] as? String, "repeat_yesterday")
    }
}
