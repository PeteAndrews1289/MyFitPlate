import XCTest
@testable import MyFitPlateCore

final class FeatureFlagServiceTests: XCTestCase {

    /// In-memory stand-in for the Firebase Remote Config provider.
    private final class StubProvider: FeatureFlagRemoteProviding {
        var values: [FeatureFlag: Bool]
        private(set) var refreshCount = 0
        init(_ values: [FeatureFlag: Bool] = [:]) { self.values = values }
        func remoteValue(for flag: FeatureFlag) -> Bool? { values[flag] }
        func refresh() async { refreshCount += 1 }
    }

    func testFallsBackToCompiledDefaultWithNoOverrideOrRemote() {
        let service = FeatureFlagService()
        XCTAssertEqual(service.boolValue(for: .newMealPlanner), FeatureFlag.newMealPlanner.defaultValue)
        XCTAssertEqual(service.isFeatureEnabled(.premiumFeatures), FeatureFlag.premiumFeatures.defaultValue)
    }

    func testRemoteValueOverridesDefault() {
        let service = FeatureFlagService(remoteProvider: StubProvider([.newMealPlanner: true]))
        XCTAssertTrue(service.boolValue(for: .newMealPlanner))
        // A flag with no remote value still falls back to its default.
        XCTAssertEqual(service.boolValue(for: .premiumFeatures), FeatureFlag.premiumFeatures.defaultValue)
    }

    func testLocalOverrideBeatsRemoteValue() {
        let service = FeatureFlagService(
            remoteProvider: StubProvider([.newMealPlanner: false]),
            localOverrides: [.newMealPlanner: true]
        )
        XCTAssertTrue(service.boolValue(for: .newMealPlanner))
    }

    func testSetOverrideThenClearFallsBackToRemote() {
        let service = FeatureFlagService(remoteProvider: StubProvider([.newWorkoutRoutine: false]))
        service.setOverride(true, for: .newWorkoutRoutine)
        XCTAssertTrue(service.isFeatureEnabled(.newWorkoutRoutine))

        service.setOverride(nil, for: .newWorkoutRoutine)
        XCTAssertFalse(service.isFeatureEnabled(.newWorkoutRoutine)) // back to remote = false
    }

    func testRefreshDelegatesToProvider() async {
        let provider = StubProvider()
        let service = FeatureFlagService(remoteProvider: provider)
        await service.refresh()
        XCTAssertEqual(provider.refreshCount, 1)
    }

    func testRemoteConfigKeysAreUniqueAndStable() {
        let keys = FeatureFlag.allCases.map(\.remoteConfigKey)
        XCTAssertEqual(Set(keys).count, FeatureFlag.allCases.count, "Remote config keys must be unique.")
        XCTAssertEqual(FeatureFlag.newMealPlanner.remoteConfigKey, "feature_newMealPlanner")
    }
}
