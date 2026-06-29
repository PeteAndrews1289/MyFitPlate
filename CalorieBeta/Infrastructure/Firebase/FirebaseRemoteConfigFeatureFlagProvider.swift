import Foundation
import MyFitPlateCore
import FirebaseCore
import FirebaseRemoteConfig

/// App-layer adapter that backs MyFitPlateCore's feature flags with Firebase Remote Config.
/// Kept in the app target so Core stays SDK-free; injected into `FeatureFlagService`.
final class FirebaseRemoteConfigFeatureFlagProvider: FeatureFlagRemoteProviding {
    private let remoteConfig: RemoteConfig

    /// Returns a provider only when Firebase is configured (nil in previews/tests so the
    /// service falls back to compiled defaults).
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

    func remoteValue(for flag: FeatureFlag) -> Bool? {
        let value = remoteConfig.configValue(forKey: flag.remoteConfigKey)
        // Only treat genuinely-remote values as overrides; otherwise let Core use its default.
        guard value.source == .remote else { return nil }
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
