import Foundation

public protocol CrashManagerProtocol {
    func logError(_ error: Error)
    func setCustomValue(_ value: Any, forKey key: String)
    func setUserID(_ id: String)
}
