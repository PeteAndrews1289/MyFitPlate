import SwiftUI
import FirebaseAuth
import FirebaseFirestore
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
    
    private let db = Firestore.firestore()
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self = self else { return }
                if let user = user {
                    self.isUserLoggedIn = true
                    self.loadDarkModePreference(userID: user.uid)
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
        db.collection("users").document(userID).getDocument { [weak self] document, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error {
                    AppLog.app.error("Failed to load dark mode preference: \(error.localizedDescription, privacy: .public)")
                    self.isDarkModeEnabled = false
                } else if let document = document, document.exists,
                          let data = document.data(),
                          let darkMode = data["darkMode"] as? Bool {
                    if self.isDarkModeEnabled != darkMode {
                         self.isDarkModeEnabled = darkMode
                    }
                } else {
                    if self.isDarkModeEnabled != false {
                         self.isDarkModeEnabled = false
                    }
                }
            }
        }
    }

    private func saveDarkModePreference() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(userID).setData(["darkMode": self.isDarkModeEnabled], merge: true) { error in
            if let error {
                AppLog.app.error("Failed to save dark mode preference: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
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
