import Foundation
import MyFitPlateCore
import SwiftUI
import FirebaseAnalytics

/// Central, typed wrapper around Firebase Analytics.
///
/// Event and parameter names are intentionally verbose and self-describing so the Firebase
/// dashboard reads like plain English ("screen_viewed", "ai_feature_used") instead of cryptic
/// codes. Add new cases to `AppScreen` / `AppEvent` rather than scattering string literals.
public final class FirebaseAnalyticsManager: AnalyticsManagerProtocol {

    public init() {}

    // MARK: - Screen views (what users actually open)

    public func screenViewed(_ screen: AppScreen) {
        Analytics.logEvent("screen_viewed", parameters: ["screen_name": screen.rawValue])
    }

    // MARK: - Feature / action events

    public func log(_ event: AppEvent, _ parameters: [String: Any] = [:]) {
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
    }

    public func logEvent(_ name: String, parameters: [String: Any]?) {
        Analytics.logEvent(name, parameters: parameters)
    }

    /// Convenience for the most common pattern: "which AI feature was used."
    public func aiFeatureUsed(_ feature: AIFeature) {
        Analytics.logEvent(AppEvent.aiFeatureUsed.rawValue, parameters: ["ai_feature": feature.rawValue])
    }

    // MARK: - User properties (for segmenting the dashboards)

    public func setUserProperty(_ value: String, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    public func setUserID(_ id: String?) {
        Analytics.setUserID(id)
    }
}

public extension View {
    func trackScreen(_ screen: AppScreen) -> some View {
        self.onAppear {
            DIContainer.shared.analyticsManager.logEvent("screen_viewed", parameters: ["screen_name": screen.rawValue])
        }
    }
}
