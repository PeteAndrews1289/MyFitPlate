import XCTest
@testable import MyFitPlateCore

final class OnboardingStateRulesTests: XCTestCase {
    func testMissingProfileRequiresSetup() {
        XCTAssertTrue(OnboardingStateRules.requiresSetup(profile: nil))
    }

    func testPartiallyProvisionedProfileRequiresSetup() {
        XCTAssertTrue(OnboardingStateRules.requiresSetup(profile: ["email": "person@example.com"]))
    }

    func testFirstLoginProfileRequiresSetup() {
        XCTAssertTrue(OnboardingStateRules.requiresSetup(profile: ["isFirstLogin": true]))
    }

    func testCompletedProfileDoesNotRequireSetup() {
        XCTAssertFalse(OnboardingStateRules.requiresSetup(profile: ["isFirstLogin": false]))
    }
}
