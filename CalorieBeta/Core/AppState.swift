import SwiftUI
import OSLog

@MainActor
class AppState: ObservableObject {

    @Published var isUserLoggedIn: Bool = false
    @Published var isDarkModeEnabled: Bool = false {
        didSet {
            saveDarkModePreference()
        }
    }
    @Published var selectedTab: Int = 0
    @Published var pendingChatPrompt: String? = nil
    
    private var authStateHandle: Any?

    init() {
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

    func setUserLoggedIn(_ loggedIn: Bool) {
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

    func signOut() {
        do {
            try DIContainer.shared.authService.signOut()
        } catch {
            AppLog.app.error("Failed to sign out: \(error.localizedDescription, privacy: .public)")
        }
    }
}


enum AppLog {
    static let app = Logger(subsystem: subsystem, category: "App")
    static let ai = Logger(subsystem: subsystem, category: "AI")
    static let data = Logger(subsystem: subsystem, category: "Data")
    static let health = Logger(subsystem: subsystem, category: "Health")
    static let liveActivity = Logger(subsystem: subsystem, category: "LiveActivity")
    static let mealPlanner = Logger(subsystem: subsystem, category: "MealPlanner")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let recipes = Logger(subsystem: subsystem, category: "Recipes")
    static let social = Logger(subsystem: subsystem, category: "Social")
    static let watch = Logger(subsystem: subsystem, category: "WatchConnectivity")
    static let workouts = Logger(subsystem: subsystem, category: "Workouts")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "MyFitPlate"
}
