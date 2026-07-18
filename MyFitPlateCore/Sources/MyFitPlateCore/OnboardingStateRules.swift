import Foundation

public enum OnboardingStateRules {
    /// A missing profile or missing first-login marker is treated as unfinished setup. Firebase
    /// authentication can complete before a new profile write, so defaulting the other way can
    /// let a newly created account bypass onboarding.
    public static func requiresSetup(profile: [String: Any]?) -> Bool {
        guard let profile else { return true }
        return profile["isFirstLogin"] as? Bool ?? true
    }
}
