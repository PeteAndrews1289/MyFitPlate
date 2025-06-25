import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var signUpError = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Spacer()

                Text("Create Your Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)
                
                VStack(spacing: 16) {
                    RoundedTextField(placeholder: "Username", text: $username, iconName: "person.fill")
                    RoundedTextField(placeholder: "Email", text: $email, iconName: "envelope.fill", isEmail: true)
                    RoundedSecureField(placeholder: "Password", text: $password, iconName: "lock.fill")
                    RoundedSecureField(placeholder: "Confirm Password", text: $confirmPassword, iconName: "lock.fill")
                }

                if !signUpError.isEmpty {
                    Text(signUpError)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.top, 10)
                }
                Spacer()

                Button(action: signUpUser) {
                    Text("Join Now")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 30)
            .navigationBarHidden(true)
        }
    }

    private func signUpUser() {
        guard !username.isEmpty else {
            signUpError = "Username is required"
            return
        }
        guard password == confirmPassword else {
            signUpError = "Passwords do not match"
            return
        }
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                signUpError = error.localizedDescription
                return
            }
            if let user = authResult?.user {
                saveUserData(user: user)
            }
        }
    }

    private func saveUserData(user: FirebaseAuth.User) {
        let db = Firestore.firestore()
        let userData: [String: Any] = [
            "email": user.email ?? "",
            "userID": user.uid,
            "username": username,
            "goals": [
                "calories": 2000,
                "protein": 150,
                "fats": 70,
                "carbs": 250
            ],
            "weight": 150.0,
            "isFirstLogin": true,
            "totalAchievementPoints": 0,
            "userLevel": 1
        ]

        db.collection("users").document(user.uid).setData(userData) { error in
            if let error = error {
                signUpError = "Failed to save user data: \(error.localizedDescription)"
            } else {
                db.collection("users").document(user.uid).collection("calorieHistory").addDocument(data: [
                    "date": Timestamp(date: Date()),
                    "calories": 0.0
                ]) { historyError in
                    if let historyError = historyError {
                        signUpError = "Failed to save initial history: \(historyError.localizedDescription)"
                    }
                }
            }
        }
    }
}
