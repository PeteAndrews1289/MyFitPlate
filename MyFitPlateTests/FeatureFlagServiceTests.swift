import XCTest
@testable import MyFitPlate

final class FeatureFlagServiceTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "FeatureFlagServiceTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    func testDefaultStateUsesFlagDefault() {
        let service = DefaultFeatureFlagService(userDefaults: userDefaults, launchArguments: [])

        let state = service.state(for: .mealPlanning)

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.source, .defaultValue)
    }

    func testLocalOverrideCanDisableAndClearFlag() {
        let service = DefaultFeatureFlagService(userDefaults: userDefaults, launchArguments: [])

        service.setOverride(false, for: .aiFoodLogging)
        XCTAssertFalse(service.isEnabled(.aiFoodLogging))
        XCTAssertEqual(service.state(for: .aiFoodLogging).source, .localOverride)

        service.setOverride(nil, for: .aiFoodLogging)
        XCTAssertTrue(service.isEnabled(.aiFoodLogging))
        XCTAssertEqual(service.state(for: .aiFoodLogging).source, .defaultValue)
    }

    func testLaunchArgumentOverridesLocalOverride() {
        let service = DefaultFeatureFlagService(
            userDefaults: userDefaults,
            launchArguments: ["-feature-flag-grocery_list=false"]
        )

        service.setOverride(true, for: .groceryList)

        XCTAssertFalse(service.isEnabled(.groceryList))
        XCTAssertEqual(service.state(for: .groceryList).source, .launchArgument)
    }

    func testRemoteValueIsUsedWhenNoHigherPriorityOverrideExists() {
        let remoteProvider = StubRemoteFeatureFlagProvider(values: [.mealPlanning: false])
        let service = DefaultFeatureFlagService(
            userDefaults: userDefaults,
            launchArguments: [],
            remoteProvider: remoteProvider
        )

        let state = service.state(for: .mealPlanning)

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.source, .remoteConfig)
    }

    func testLocalOverrideWinsOverRemoteValue() {
        let remoteProvider = StubRemoteFeatureFlagProvider(values: [.groceryList: false])
        let service = DefaultFeatureFlagService(
            userDefaults: userDefaults,
            launchArguments: [],
            remoteProvider: remoteProvider
        )

        service.setOverride(true, for: .groceryList)

        XCTAssertTrue(service.isEnabled(.groceryList))
        XCTAssertEqual(service.state(for: .groceryList).source, .localOverride)
    }

    func testLaunchArgumentWinsOverRemoteValue() {
        let remoteProvider = StubRemoteFeatureFlagProvider(values: [.premiumReports: false])
        let service = DefaultFeatureFlagService(
            userDefaults: userDefaults,
            launchArguments: ["-enable-feature-premium_reports"],
            remoteProvider: remoteProvider
        )

        XCTAssertTrue(service.isEnabled(.premiumReports))
        XCTAssertEqual(service.state(for: .premiumReports).source, .launchArgument)
    }

    func testEnableAndDisableLaunchArgumentsAreSupported() {
        let service = DefaultFeatureFlagService(
            userDefaults: userDefaults,
            launchArguments: [
                "-disable-feature-premium_reports",
                "-enable-feature-premium_reports"
            ]
        )

        XCTAssertTrue(service.isEnabled(.premiumReports))
        XCTAssertEqual(service.state(for: .premiumReports).source, .launchArgument)
    }

    func testAllStatesIncludesEveryFlag() {
        let service = DefaultFeatureFlagService(userDefaults: userDefaults, launchArguments: [])

        XCTAssertEqual(service.allStates().count, FeatureFlag.allCases.count)
    }

    func testRefreshDelegatesToRemoteProvider() async {
        let remoteProvider = StubRemoteFeatureFlagProvider(values: [:])
        let service = DefaultFeatureFlagService(
            userDefaults: userDefaults,
            launchArguments: [],
            remoteProvider: remoteProvider
        )

        await service.refresh()

        XCTAssertEqual(remoteProvider.refreshCallCount, 1)
    }

    func testMockServiceCanOverrideFlags() {
        let service = MockFeatureFlagService(overrides: [.maiaAssistant: false])

        XCTAssertFalse(service.isEnabled(.maiaAssistant))
        XCTAssertTrue(service.isEnabled(.mealPlanning))
    }
}

private final class StubRemoteFeatureFlagProvider: FeatureFlagRemoteProviding {
    var values: [FeatureFlag: Bool]
    var refreshCallCount = 0

    init(values: [FeatureFlag: Bool]) {
        self.values = values
    }

    func value(for flag: FeatureFlag) -> Bool? {
        values[flag]
    }

    func refresh() async {
        refreshCallCount += 1
    }
}
