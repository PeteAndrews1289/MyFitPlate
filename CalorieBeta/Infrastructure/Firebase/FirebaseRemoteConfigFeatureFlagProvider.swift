/*
import Foundation
import MyFitPlateCore
import FirebaseCore
import FirebaseRemoteConfig

final class FirebaseRemoteConfigFeatureFlagProvider: FeatureFlagServiceProtocol {
    private let remoteConfig: RemoteConfig

    static func makeIfConfigured() -> FirebaseRemoteConfigFeatureFlagProvider? {
        guard FirebaseApp.app() != nil else { return nil }
        return FirebaseRemoteConfigFeatureFlagProvider()
    }

    init(
        remoteConfig: RemoteConfig = .remoteConfig(),
        minimumFetchInterval: TimeInterval = 3_600
    ) {
        self.remoteConfig = remoteConfig

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = minimumFetchInterval
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults(defaultValues)
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        let value = remoteConfig.configValue(forKey: flag.remoteConfigKey)
        guard value.source == .remote else { return flag.defaultValue }
        return value.boolValue
    }

    func refresh() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            remoteConfig.fetchAndActivate { _, _ in
                continuation.resume()
            }
        }
    }

    private var defaultValues: [String: NSObject] {
        Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { flag in
            (flag.remoteConfigKey, NSNumber(value: flag.defaultValue))
        })
    }
}
*/
