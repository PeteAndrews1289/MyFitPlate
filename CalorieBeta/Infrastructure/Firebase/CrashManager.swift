import Foundation
import MyFitPlateCore
import FirebaseCrashlytics

public final class FirebaseCrashManager: CrashManagerProtocol {
    public init() {}

    public func logError(_ error: Error) {
        Crashlytics.crashlytics().record(error: error)
    }
    
    public func record(error: Error, additionalUserInfo: [String: Any]) {
        let nsError = error as NSError
        var userInfo = nsError.userInfo
        for (key, value) in additionalUserInfo {
            userInfo[key] = value
        }
        let customError = NSError(domain: nsError.domain, code: nsError.code, userInfo: userInfo)
        Crashlytics.crashlytics().record(error: customError)
    }
    
    public func setCustomValue(_ value: Any, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }
    
    public func setUserID(_ id: String) {
        Crashlytics.crashlytics().setUserID(id)
    }
    
    public func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }
}
