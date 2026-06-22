import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var signUpError = ""
    @State private var isLoading = false

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword &&
        !isLoading
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        AuthHeaderCard(
                            icon: "sparkles",
                            title: "Create Your Account",
                            subtitle: "Set up your personal nutrition and training workspace."
                        )
                        .padding(.top, 18)

                        VStack(spacing: 14) {
                            TextField("Username", text: $username)
                                .textFieldStyle(AppTextFieldStyle(iconName: "person.fill"))
                                .textInputAutocapitalization(.words)

                            TextField("Email", text: $email)
                                .textFieldStyle(AppTextFieldStyle(iconName: "envelope.fill"))
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            SecureField("Password", text: $password)
                                .textFieldStyle(AppTextFieldStyle(iconName: "lock.fill"))

                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(AppTextFieldStyle(iconName: "lock.fill"))
                        }
                        .asCard()

                        VStack(alignment: .leading, spacing: 8) {
                            RequirementRow(text: "Password is at least 6 characters", isMet: password.count >= 6)
                            RequirementRow(text: "Passwords match", isMet: !password.isEmpty && password == confirmPassword)
                        }
                        .asCard()

                        if !signUpError.isEmpty {
                            AuthErrorBanner(message: signUpError)
                        }

                        Button {
                            signUpUser()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Join Now")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSubmit)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func signUpUser() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty else {
            signUpError = "Username is required"
            return
        }
        guard password.count >= 6 else {
            signUpError = "Password must be at least 6 characters"
            return
        }
        guard password == confirmPassword else {
            signUpError = "Passwords do not match"
            return
        }

        isLoading = true
        signUpError = ""

        Auth.auth().createUser(withEmail: trimmedEmail, password: password) { authResult, error in
            if let error = error {
                isLoading = false
                signUpError = error.localizedDescription
                return
            }
            if let user = authResult?.user {
                saveUserData(user: user, username: trimmedUsername)
            } else {
                isLoading = false
                signUpError = "Account creation failed. Please try again."
            }
        }
    }

    private func saveUserData(user: FirebaseAuth.User, username: String) {
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
                isLoading = false
                signUpError = "Failed to save user data: \(error.localizedDescription)"
            } else {
                db.collection("users").document(user.uid).collection("calorieHistory").addDocument(data: [
                    "date": Timestamp(date: Date()),
                    "calories": 0.0
                ]) { historyError in
                    isLoading = false
                    if let historyError = historyError {
                        signUpError = "Failed to save initial history: \(historyError.localizedDescription)"
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct RequirementRow: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .accentPositive : Color(UIColor.secondaryLabel))
            Text(text)
                .appFont(size: 13, weight: .medium)
                .foregroundColor(isMet ? .textPrimary : Color(UIColor.secondaryLabel))
        }
    }
}
