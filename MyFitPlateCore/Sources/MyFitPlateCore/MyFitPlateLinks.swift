import Foundation

public enum MyFitPlateLinks {
    public static let appStoreURLString = "https://apps.apple.com/app/myfitplate/id6740922831"

    public static var appStoreURL: URL {
        guard let url = URL(string: appStoreURLString) else {
            preconditionFailure("MyFitPlate App Store URL must remain valid.")
        }
        return url
    }

    public static func shareMessage(_ message: String) -> String {
        let lead = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let invitation = "Try MyFitPlate: \(appStoreURLString)"
        return lead.isEmpty ? invitation : "\(lead)\n\n\(invitation)"
    }
}
