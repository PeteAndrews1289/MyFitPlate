import Foundation

/// Supplies remote flag values (e.g. Firebase Remote Config), provided by the app layer so
/// MyFitPlateCore stays free of any SDK dependency. Returns `nil` when a flag has no remote
/// value set, so the service falls back to the compiled default.
public protocol FeatureFlagRemoteProviding {
    func remoteValue(for flag: FeatureFlag) -> Bool?
    func refresh() async
}

public protocol FeatureFlagServiceProtocol {
    func isFeatureEnabled(_ feature: FeatureFlag) -> Bool
    func boolValue(for flag: FeatureFlag) -> Bool
    func refresh() async
}

/// Resolves a flag with precedence: local override > remote value > compiled default.
///
/// Previously this was a stub that always returned `false`, so every gated feature was
/// silently dark and feature-flagging was unavailable. It now consults an optional remote
/// provider and supports local overrides (e.g. a debug toggle / launch argument).
public final class FeatureFlagService: FeatureFlagServiceProtocol {
    private let remoteProvider: FeatureFlagRemoteProviding?
    private var localOverrides: [FeatureFlag: Bool]

    public init(remoteProvider: FeatureFlagRemoteProviding? = nil,
                localOverrides: [FeatureFlag: Bool] = [:]) {
        self.remoteProvider = remoteProvider
        self.localOverrides = localOverrides
    }

    public func isFeatureEnabled(_ feature: FeatureFlag) -> Bool {
        boolValue(for: feature)
    }

    public func boolValue(for flag: FeatureFlag) -> Bool {
        if let override = localOverrides[flag] { return override }
        if let remote = remoteProvider?.remoteValue(for: flag) { return remote }
        return flag.defaultValue
    }

    /// Sets or clears a local override (pass `nil` to clear and fall back to remote/default).
    public func setOverride(_ value: Bool?, for flag: FeatureFlag) {
        localOverrides[flag] = value
    }

    public func refresh() async {
        await remoteProvider?.refresh()
    }
}
