import Foundation

public enum MyFitPlateLinks {
    public static let appStoreURLString = "https://apps.apple.com/app/myfitplate/id6740922831"
    public static let privacyPolicyURLString = "https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md"
    public static let termsOfServiceURLString = "https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/terms_of_service.md"
    public static let supportEmailAddress = "peteandrews1289@gmail.com"

    public static var appStoreURL: URL {
        guard let url = URL(string: appStoreURLString) else {
            preconditionFailure("MyFitPlate App Store URL must remain valid.")
        }
        return url
    }

    public static var privacyPolicyURL: URL {
        guard let url = URL(string: privacyPolicyURLString) else {
            preconditionFailure("MyFitPlate privacy URL must remain valid.")
        }
        return url
    }

    public static var termsOfServiceURL: URL {
        guard let url = URL(string: termsOfServiceURLString) else {
            preconditionFailure("MyFitPlate terms URL must remain valid.")
        }
        return url
    }

    public static func shareMessage(_ message: String) -> String {
        let lead = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let invitation = "Try MyFitPlate: \(appStoreURLString)"
        return lead.isEmpty ? invitation : "\(lead)\n\n\(invitation)"
    }
}
