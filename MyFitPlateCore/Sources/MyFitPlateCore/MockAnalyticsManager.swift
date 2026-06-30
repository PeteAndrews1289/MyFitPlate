import Foundation

public class MockAnalyticsManager: AnalyticsManagerProtocol {
    public init() {}
    public private(set) var loggedEvents: [(name: String, parameters: [String: Any]?)] = []
    public private(set) var userProperties: [String: String] = [:]
    public private(set) var userIDs: [String?] = []
    public private(set) var typedEvents: [(event: AppEvent, parameters: [String: Any])] = []

    public func logEvent(_ name: String, parameters: [String: Any]?) {
        loggedEvents.append((name, parameters))
    }

    public func setUserProperty(_ value: String, forName name: String) {
        userProperties[name] = value
    }

    public func setUserID(_ id: String?) {
        userIDs.append(id)
    }

    public func log(_ event: AppEvent, _ parameters: [String: Any]) {
        typedEvents.append((event, parameters))
    }
}
