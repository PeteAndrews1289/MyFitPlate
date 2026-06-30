import Foundation

public class MockCrashManager: CrashManagerProtocol {
    public init() {}
    public private(set) var loggedErrors: [Error] = []
    public private(set) var recordedErrors: [(error: Error, userInfo: [String: Any])] = []
    public private(set) var customValues: [String: Any] = [:]
    public private(set) var userIDs: [String] = []
    public private(set) var logs: [String] = []

    public func logError(_ error: Error) {
        loggedErrors.append(error)
    }

    public func record(error: Error, additionalUserInfo: [String: Any]) {
        recordedErrors.append((error, additionalUserInfo))
    }

    public func setCustomValue(_ value: Any, forKey key: String) {
        customValues[key] = value
    }

    public func setUserID(_ id: String) {
        userIDs.append(id)
    }

    public func log(_ message: String) {
        logs.append(message)
    }
}
