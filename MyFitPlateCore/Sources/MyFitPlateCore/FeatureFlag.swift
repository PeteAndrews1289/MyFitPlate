import Foundation

public enum FeatureFlag: String, CaseIterable {
    case newMealPlanner
    case newWorkoutRoutine
    case premiumFeatures
    case menuScanner
    case receiptScanner
    case communityBarcodeCorrections

    /// Value used when neither a local override nor a remote value is present.
    /// New/gated features stay dark until deliberately enabled. Already-shipped, higher-risk
    /// surfaces default on so Remote Config can act as a kill switch without hiding them locally.
    public var defaultValue: Bool {
        switch self {
        case .newMealPlanner: return false
        case .newWorkoutRoutine: return false
        case .premiumFeatures: return false
        case .menuScanner: return true
        case .receiptScanner: return true
        // Dark until the extended barcodes rules are deployed and the pool has soaked.
        case .communityBarcodeCorrections: return false
        }
    }

    /// Stable key used to look the flag up in the remote config backend.
    public var remoteConfigKey: String { "feature_\(rawValue)" }
}
