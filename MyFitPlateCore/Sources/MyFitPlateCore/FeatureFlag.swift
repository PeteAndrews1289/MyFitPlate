import Foundation

public enum FeatureFlag: String, CaseIterable {
    case newMealPlanner
    case newWorkoutRoutine
    case premiumFeatures

    /// Value used when neither a local override nor a remote value is present.
    /// Conservative defaults (off) so new/gated features stay dark until deliberately enabled.
    public var defaultValue: Bool {
        switch self {
        case .newMealPlanner: return false
        case .newWorkoutRoutine: return false
        case .premiumFeatures: return false
        }
    }

    /// Stable key used to look the flag up in the remote config backend.
    public var remoteConfigKey: String { "feature_\(rawValue)" }
}
