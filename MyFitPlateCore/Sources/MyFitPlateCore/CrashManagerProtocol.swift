import Foundation

public protocol CrashManagerProtocol {
    func logError(_ error: Error)
    func record(error: Error, additionalUserInfo: [String: Any])
    func setCustomValue(_ value: Any, forKey key: String)
    func setUserID(_ id: String)
    func log(_ message: String)
}

public extension CrashManagerProtocol {
    func record(error: Error, additionalUserInfo: [String: Any]) {
        logError(error)
    }

    func log(_ message: String) {}
}
