import XCTest
@testable import MyFitPlateCore

final class PrivacyGuardrailTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PrivacyGuardrailTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAIConsentIsVersionedAndScopedPerAccount() {
        let store = AIDataConsentStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_750_000_000)

        store.grant(for: "user-a", includesHealthData: true, date: date)

        XCTAssertEqual(
            store.consent(for: "user-a"),
            AIDataConsent(grantedAt: date, includesHealthData: true)
        )
        XCTAssertTrue(store.allowsHealthData(for: "user-a"))
        XCTAssertNil(store.consent(for: "user-b"))
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.joined().contains("user-a"))
    }

    func testRevokingAIConsentBlocksAllAIDataSharing() {
        let store = AIDataConsentStore(defaults: defaults)
        store.grant(for: "user-a", includesHealthData: false)

        store.revoke(for: "user-a")

        XCTAssertFalse(store.hasCurrentConsent(for: "user-a"))
        XCTAssertFalse(store.allowsHealthData(for: "user-a"))
    }

    func testLegacyAIConsentMigratesAwayFromRawAccountKey() throws {
        let userID = "legacy-consent-user"
        let legacyKey = "ai_data_consent_v1_\(userID)"
        let consent = AIDataConsent(
            grantedAt: Date(timeIntervalSince1970: 1_750_000_000),
            includesHealthData: true
        )
        defaults.set(try JSONEncoder().encode(consent), forKey: legacyKey)
        let store = AIDataConsentStore(defaults: defaults)

        XCTAssertEqual(store.consent(for: userID), consent)
        XCTAssertNil(defaults.data(forKey: legacyKey))
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.joined().contains(userID))
    }

    func testMaiaContractDropsHealthKitScopeWithoutOptionalConsent() {
        let contract = MaiaContextContract.dailyRead(includeHealthKit: true)

        let filtered = contract.respectingHealthDataConsent(false)

        XCTAssertFalse(filtered.allows(.healthKit))
        XCTAssertTrue(filtered.allows(.todayLog))
    }

    func testAnalyticsSanitizerDropsHealthAndFitnessValues() {
        let result = AnalyticsPrivacy.sanitizedParameters([
            "action": "meal_logged",
            "remaining_calories": 500,
            "protein": 40,
            "sleep_score": 82,
            "source": "search"
        ])

        XCTAssertEqual(result?["action"] as? String, "meal_logged")
        XCTAssertEqual(result?["source"] as? String, "search")
        XCTAssertNil(result?["remaining_calories"])
        XCTAssertNil(result?["protein"])
        XCTAssertNil(result?["sleep_score"])
    }

    func testAnalyticsSanitizerDropsIdentityAndFreeformContentKeys() {
        let result = AnalyticsPrivacy.sanitizedParameters([
            "action": "correction_saved",
            "source": "usda",
            "barcode": "0123456789012",
            "food_id": "private-food-id",
            "food_name": "Protein Bar",
            "uid": "private-user",
            "email": "private@example.com",
            "prompt": "private prompt",
            "query": "private search",
            "message": "private message"
        ])

        XCTAssertEqual(result?["action"] as? String, "correction_saved")
        XCTAssertEqual(result?["source"] as? String, "usda")
        for key in [
            "barcode", "food_id", "food_name", "uid", "email", "prompt", "query", "message"
        ] {
            XCTAssertNil(result?[key], key)
        }
    }

    func testAnalyticsSanitizerKeepsLivingDayAggregateDimensions() {
        let result = AnalyticsPrivacy.sanitizedParameters([
            "path_event_count": 4,
            "has_training": true,
            "freshness": "current",
            "next_action_kind": "recovery_meal",
            "density": "compact",
            "includes_budget": true,
            "includes_path": true,
            "includes_trust": false,
            "includes_action": true,
            "food_name": "Private meal",
            "route": "Private GPS route"
        ])

        XCTAssertEqual(result?["path_event_count"] as? Int, 4)
        XCTAssertEqual(result?["has_training"] as? Bool, true)
        XCTAssertEqual(result?["freshness"] as? String, "current")
        XCTAssertEqual(result?["next_action_kind"] as? String, "recovery_meal")
        XCTAssertEqual(result?["density"] as? String, "compact")
        XCTAssertEqual(result?["includes_budget"] as? Bool, true)
        XCTAssertEqual(result?["includes_path"] as? Bool, true)
        XCTAssertEqual(result?["includes_trust"] as? Bool, false)
        XCTAssertEqual(result?["includes_action"] as? Bool, true)
        XCTAssertNil(result?["food_name"])
        XCTAssertNil(result?["route"])
    }

    func testAnalyticsSanitizerRejectsUnknownIdentityAndNameSuffixes() {
        let result = AnalyticsPrivacy.sanitizedParameters([
            "screen_name": "food_search",
            "correlation_id": "private-id",
            "item_name": "Private meal",
            "recipe_description": "Private recipe text",
            "provider": "health_canada"
        ])

        XCTAssertEqual(result?["screen_name"] as? String, "food_search")
        XCTAssertEqual(result?["provider"] as? String, "health_canada")
        XCTAssertNil(result?["correlation_id"])
        XCTAssertNil(result?["item_name"])
        XCTAssertNil(result?["recipe_description"])
    }
}
