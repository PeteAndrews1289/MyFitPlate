import Foundation

public class MockAnalyticsManager: AnalyticsManagerProtocol {
    public init() {}
    public func logEvent(_ name: String, parameters: [String: Any]?) {}
    public func setUserProperty(_ value: String, forName name: String) {}
    public func setUserID(_ id: String) {}
    public func log(_ event: AppEvent, _ parameters: [String: Any]) {}
}
