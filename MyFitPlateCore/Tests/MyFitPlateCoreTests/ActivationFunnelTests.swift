import XCTest
@testable import MyFitPlateCore

@MainActor
final class ActivationFunnelTests: XCTestCase {
    private let suiteName = "activation-funnel-tests"
    private var defaults: UserDefaults!
    private var mockAnalytics: MockAnalyticsManager!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        mockAnalytics = MockAnalyticsManager()
        DIContainer.shared.analyticsManager = mockAnalytics
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLogOnceFiresExactlyOncePerInstall() {
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)

        let fired = mockAnalytics.loggedEvents.filter { $0.name == ActivationFunnel.firstFoodLogged }
        XCTAssertEqual(fired.count, 1)
    }

    func testDistinctEventsFireIndependently() {
        ActivationFunnel.logOnce(ActivationFunnel.onboardingCompleted, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstWorkoutCompleted, userDefaults: defaults)

        XCTAssertEqual(mockAnalytics.loggedEvents.count, 2)
        XCTAssertEqual(
            Set(mockAnalytics.loggedEvents.map(\.name)),
            [ActivationFunnel.onboardingCompleted, ActivationFunnel.firstWorkoutCompleted]
        )
    }
}
