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
    }

    func testRevokingAIConsentBlocksAllAIDataSharing() {
        let store = AIDataConsentStore(defaults: defaults)
        store.grant(for: "user-a", includesHealthData: false)

        store.revoke(for: "user-a")

        XCTAssertFalse(store.hasCurrentConsent(for: "user-a"))
        XCTAssertFalse(store.allowsHealthData(for: "user-a"))
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
}
