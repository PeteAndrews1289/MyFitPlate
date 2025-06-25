import SwiftUI
import FirebaseAuth
import UserNotifications
import FirebaseFirestore

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

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
            } else if let error = error {
            }
        }

        Auth.auth().addStateDidChangeListener { auth, user in
            DispatchQueue.main.async {
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
        DispatchQueue.main.async {
            self.isUserLoggedIn = loggedIn
        }
    }
    
    private func loadDarkModePreference(userID: String) {
        db.collection("users").document(userID).getDocument { document, error in
            DispatchQueue.main.async {
                if let error = error {
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
             if let error = error {
             } else {
             }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch let signOutError as NSError {
        }
    }
}

// Global helper function to read the API key from the project's configuration.
func getAPIKey() -> String {
    guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String else {
        fatalError("OpenAI API Key not set in Info.plist")
    }
    return key
}
