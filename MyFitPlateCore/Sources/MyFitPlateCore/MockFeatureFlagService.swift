import Foundation

public class MockFeatureFlagService: FeatureFlagServiceProtocol {
    public init() {}
    public func isFeatureEnabled(_ feature: FeatureFlag) -> Bool { return true }
    public func boolValue(for flag: FeatureFlag) -> Bool { return true }
    public func refresh() async {}
}
