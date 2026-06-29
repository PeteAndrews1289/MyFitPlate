import Foundation

public class MockCrashManager: CrashManagerProtocol {
    public init() {}
    public func logError(_ error: Error) {}
    public func setCustomValue(_ value: Any, forKey key: String) {}
    public func setUserID(_ id: String) {}
}
