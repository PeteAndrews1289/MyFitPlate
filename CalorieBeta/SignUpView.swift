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
        VStack(spacing: 20) {
            
            Spacer()

            Text("Create Your Account")
                .appFont(size: 34, weight: .bold)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 30)
            
            VStack(spacing: 16) {
                TextField("Username", text: $username)
                    .textFieldStyle(AppTextFieldStyle(iconName: "person.fill"))
                
                TextField("Email", text: $email)
                    .textFieldStyle(AppTextFieldStyle(iconName: "envelope.fill"))
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                SecureField("Password", text: $password)
                    .textFieldStyle(AppTextFieldStyle(iconName: "lock.fill"))

                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(AppTextFieldStyle(iconName: "lock.fill"))
            }

            if !signUpError.isEmpty {
                Text(signUpError)
                    .foregroundColor(.red)
                    .appFont(size: 12)
                    .padding(.top, 10)
            }
            Spacer()

            Button("Join Now") {
                signUpUser()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 30)
        .background(Color.backgroundPrimary.edgesIgnoringSafeArea(.all))
        .navigationBarHidden(true)
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
                "carbs": 250,
                "proteinPercentage": 30.0,
                "carbsPercentage": 50.0,
                "fatsPercentage": 20.0,
                "activityLevel": 1.2,
                "goal": "Maintain",
                "targetWeight": NSNull(),
                "waterGoal": 64.0
            ],
            "weight": 150.0,
            "height": 170.0,
            "age": 25,
            "gender": "Male",
            "isFirstLogin": true,
            "calorieGoalMethod": "mifflinWithActivity",
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
