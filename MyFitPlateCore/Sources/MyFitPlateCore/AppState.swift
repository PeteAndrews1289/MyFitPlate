import SwiftUI
import OSLog

@MainActor
public class AppState: ObservableObject {

    @Published public var isUserLoggedIn: Bool = false
    @Published public var isDarkModeEnabled: Bool = false {
        didSet {
            saveDarkModePreference()
        }
    }
    @Published public var selectedTab: Int = 0
    @Published public var pendingChatPrompt: String? = nil
    
    private var authStateHandle: Any?

    public init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            self.isUserLoggedIn = true
            return
        }
        
        authStateHandle = DIContainer.shared.authService.observeAuthState { [weak self] userID in
            Task { @MainActor in
                guard let self = self else { return }
                if let userID = userID {
                    self.isUserLoggedIn = true
                    self.loadDarkModePreference(userID: userID)
                    self.recordLastLogin(userID: userID)
                } else {
                    self.isUserLoggedIn = false
                }
            }
        }
    }

    public func setUserLoggedIn(_ loggedIn: Bool) {
        isUserLoggedIn = loggedIn
    }
    
    private func loadDarkModePreference(userID: String) {
        Task {
            do {
                let darkMode = try await DIContainer.shared.databaseService.loadDarkModePreference(userID: userID)
                await MainActor.run {
                    if self.isDarkModeEnabled != darkMode {
                        self.isDarkModeEnabled = darkMode
                    }
                }
            } catch {
                AppLog.app.error("Failed to load dark mode preference: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    if self.isDarkModeEnabled != false {
                         self.isDarkModeEnabled = false
                    }
                }
            }
        }
    }

    private func saveDarkModePreference() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let isEnabled = self.isDarkModeEnabled
        Task {
            do {
                try await DIContainer.shared.databaseService.saveDarkModePreference(userID: userID, isEnabled: isEnabled)
            } catch {
                AppLog.app.error("Failed to save dark mode preference: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Stamps the user's last-login / last-active time on their profile doc.
    private func recordLastLogin(userID: String) {
        Task {
            do {
                try await DIContainer.shared.databaseService.recordLastLogin(userID: userID)
            } catch {
                AppLog.app.error("Failed to record last login: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func signOut() {
        do {
            try DIContainer.shared.authService.signOut()
        } catch {
            AppLog.app.error("Failed to sign out: \(error.localizedDescription, privacy: .public)")
        }
    }
}


public enum AppLog {
    public static let app = Logger(subsystem: subsystem, category: "App")
    public static let ai = Logger(subsystem: subsystem, category: "AI")
    public static let data = Logger(subsystem: subsystem, category: "Data")
    public static let health = Logger(subsystem: subsystem, category: "Health")
    public static let liveActivity = Logger(subsystem: subsystem, category: "LiveActivity")
    public static let mealPlanner = Logger(subsystem: subsystem, category: "MealPlanner")
    public static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    public static let recipes = Logger(subsystem: subsystem, category: "Recipes")
    public static let social = Logger(subsystem: subsystem, category: "Social")
    public static let watch = Logger(subsystem: subsystem, category: "WatchConnectivity")
    public static let workouts = Logger(subsystem: subsystem, category: "Workouts")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "MyFitPlate"
}
