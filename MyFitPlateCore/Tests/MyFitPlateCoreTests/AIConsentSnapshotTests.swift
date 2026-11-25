import XCTest
@testable import MyFitPlateCore

final class AIConsentSnapshotTests: XCTestCase {
    func testHealthScopeChangeInvalidatesAlreadyCapturedRequestReceipt() throws {
        let name = "consent-snapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AIDataConsentStore(defaults: defaults)
        store.grant(for: "owner", includesHealthData: true, date: Date(timeIntervalSince1970: 100))
        let receipt = try XCTUnwrap(store.consent(for: "owner"))
        XCTAssertTrue(store.matches(receipt, for: "owner"))
        store.grant(for: "owner", includesHealthData: false, date: Date(timeIntervalSince1970: 101))
        XCTAssertTrue(store.hasCurrentConsent(for: "owner"))
        XCTAssertFalse(store.matches(receipt, for: "owner"), "A retry must not resend the original Health-containing prompt")
        XCTAssertFalse(store.matches(receipt, for: "other"))
    }

    func testRevokeThenRegrantDoesNotAuthorizeOldRequestEvenWithSameScope() throws {
        let name = "consent-revoke-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AIDataConsentStore(defaults: defaults)
        store.grant(for: "owner", includesHealthData: false, date: Date(timeIntervalSince1970: 100))
        let receipt = try XCTUnwrap(store.consent(for: "owner"))
        store.revoke(for: "owner")
        XCTAssertFalse(store.matches(receipt, for: "owner"))
        store.grant(for: "owner", includesHealthData: false, date: Date(timeIntervalSince1970: 102))
        XCTAssertFalse(store.matches(receipt, for: "owner"))
        XCTAssertTrue(store.matches(try XCTUnwrap(store.consent(for: "owner")), for: "owner"))
    }
}
