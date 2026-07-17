import SwiftUI
import OSLog

@MainActor
public class AppState: ObservableObject {

    @Published public var isUserLoggedIn: Bool = false
    @Published public var isDarkModeEnabled: Bool = false {
        didSet {
            if !isApplyingRemoteDarkModePreference {
                saveDarkModePreference()
            }
        }
    }
    @Published public var selectedTab: Int = 0
    @Published public var pendingChatPrompt: String? = nil
    @Published public var pendingTrainingFuelTarget: TrainingFuelTarget? = nil
    
    private var authStateHandle: Any?
    private var activeUserID: String?
    private var isApplyingRemoteDarkModePreference = false

    public init() {
        if AppRuntime.isUITesting() {
            self.isUserLoggedIn = true
            return
        }
        
        authStateHandle = DIContainer.shared.authService.observeAuthState { [weak self] userID in
            Task { @MainActor in
                guard let self = self else { return }
                self.activeUserID = userID
                if let userID = userID {
                    self.isUserLoggedIn = true
                    self.identifyReleaseHealthUser(userID)
                    self.loadDarkModePreference(userID: userID)
                    self.recordLastLogin(userID: userID)
                } else {
                    self.isUserLoggedIn = false
                    self.pendingTrainingFuelTarget = nil
                    self.identifyReleaseHealthUser(nil)
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
                guard activeUserID == userID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
                if isDarkModeEnabled != darkMode {
                    isApplyingRemoteDarkModePreference = true
                    isDarkModeEnabled = darkMode
                    isApplyingRemoteDarkModePreference = false
                }
            } catch {
                guard activeUserID == userID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
                AppLog.app.error("Failed to load dark mode preference: \(error.localizedDescription, privacy: .public)")
                self.recordNonFatal(error, area: .database, operation: "load_dark_mode_preference")
                if isDarkModeEnabled {
                    isApplyingRemoteDarkModePreference = true
                    isDarkModeEnabled = false
                    isApplyingRemoteDarkModePreference = false
                }
            }
        }
    }

    private func saveDarkModePreference() {
        guard let userID = activeUserID,
              DIContainer.shared.authService.currentUserID == userID else { return }
        let isEnabled = self.isDarkModeEnabled
        Task {
            do {
                try await DIContainer.shared.databaseService.saveDarkModePreference(userID: userID, isEnabled: isEnabled)
            } catch {
                AppLog.app.error("Failed to save dark mode preference: \(error.localizedDescription, privacy: .public)")
                self.recordNonFatal(error, area: .database, operation: "save_dark_mode_preference")
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
                self.recordNonFatal(error, area: .database, operation: "record_last_login")
            }
        }
    }

    public func signOut() {
        let userID = DIContainer.shared.authService.currentUserID
        do {
            try DIContainer.shared.authService.signOut()
            if let userID {
                TTSManager.shared.clearCachedSpeech(for: userID)
            }
            EcosystemSyncManager.shared.clearAccountWidgetData()
            identifyReleaseHealthUser(nil)
        } catch {
            AppLog.app.error("Failed to sign out: \(error.localizedDescription, privacy: .public)")
            recordNonFatal(error, area: .authentication, operation: "sign_out")
        }
    }

    private func identifyReleaseHealthUser(_ userID: String?) {
        guard let crashManager = DIContainer.shared.crashManager,
              let analyticsManager = DIContainer.shared.analyticsManager else { return }
        ReleaseHealth.identifyUser(
            userID: userID,
            crashManager: crashManager,
            analyticsManager: analyticsManager
        )
    }

    private func recordNonFatal(_ error: Error, area: ReleaseHealthArea, operation: String) {
        guard let crashManager = DIContainer.shared.crashManager else { return }
        ReleaseHealth.recordNonFatal(
            error,
            area: area,
            operation: operation,
            crashManager: crashManager,
            analyticsManager: DIContainer.shared.analyticsManager
        )
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
