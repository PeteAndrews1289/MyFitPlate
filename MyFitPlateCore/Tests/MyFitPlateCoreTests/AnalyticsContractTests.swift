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
            "notification_type": "recovery",
            "item_count": 3,
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
        XCTAssertEqual(parameters["notification_type"] as? String, "recovery")
        XCTAssertEqual(parameters["item_count"] as? Int, 3)
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

    func testLibraryAndWeekAggregateDimensionsSurvivePrivacySanitizer() {
        let parameters = ProductAnalytics.firebaseParameters([
            "saved_count": 12,
            "personal_match_count": 3,
            "needs_review_count": 2,
            "duplicate_group_count": 1,
            "days_logged": 6,
            "training_days": 4,
            "recovery_eligible": 2,
            "trust_eligible": 3,
            "observation_kind": "recovery",
            "observation_tone": "attention",
            "barcode": "0044000087579",
            "food_name": "Private food"
        ])

        XCTAssertEqual(parameters["saved_count"] as? Int, 12)
        XCTAssertEqual(parameters["personal_match_count"] as? Int, 3)
        XCTAssertEqual(parameters["needs_review_count"] as? Int, 2)
        XCTAssertEqual(parameters["duplicate_group_count"] as? Int, 1)
        XCTAssertEqual(parameters["days_logged"] as? Int, 6)
        XCTAssertEqual(parameters["training_days"] as? Int, 4)
        XCTAssertEqual(parameters["recovery_eligible"] as? Int, 2)
        XCTAssertEqual(parameters["trust_eligible"] as? Int, 3)
        XCTAssertEqual(parameters["observation_kind"] as? String, "recovery")
        XCTAssertEqual(parameters["observation_tone"] as? String, "attention")
        XCTAssertNil(parameters["barcode"])
        XCTAssertNil(parameters["food_name"])
    }

    func testDurationBucketsAreStable() {
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: -1), "under_500ms")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 700), "500ms_to_1s")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 1_500), "1s_to_2s")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 3_000), "2s_to_4s")
        XCTAssertEqual(ProductAnalytics.durationBucket(milliseconds: 6_000), "over_4s")
    }

    func testMockAnalyticsRecordsConcurrentEventsSafely() async {
        let analytics = MockAnalyticsManager()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    analytics.logEvent("concurrent_event_\(index)", parameters: nil)
                }
            }
        }

        XCTAssertEqual(Set(analytics.loggedEvents.map(\.name)).count, 40)
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
