import Foundation

public protocol FeatureFlagServiceProtocol {
    func isFeatureEnabled(_ feature: FeatureFlag) -> Bool
    func boolValue(for flag: FeatureFlag) -> Bool
    func refresh() async
}

public class FeatureFlagService: FeatureFlagServiceProtocol {
    public init() {}
    public func isFeatureEnabled(_ feature: FeatureFlag) -> Bool {
        return false
    }
    public func boolValue(for flag: FeatureFlag) -> Bool {
        return false
    }
    public func refresh() async {
        
    }
}
