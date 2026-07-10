import SwiftUI

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
                            title: "Create account",
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

                            SecureField("Confirm password", text: $confirmPassword)
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
                                Text("Join now")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSubmit)

                        Text("By joining, you agree to our [Terms of service](https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/terms_of_service.md) and [Privacy policy](https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Sign up")
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

        Task { @MainActor in
            do {
                let session = try await DIContainer.shared.authService.createUser(email: trimmedEmail, password: password)
                saveUserData(userID: session.userID, email: session.email ?? trimmedEmail, username: trimmedUsername)
            } catch {
                isLoading = false
                signUpError = error.localizedDescription
            }
        }
    }

    private func saveUserData(userID: String, email: String, username: String) {
        Task {
            do {
                try await DIContainer.shared.settingsRepository.createInitialUserData(userID: userID, email: email, username: username)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    signUpError = "Failed to save user data: \(error.localizedDescription)"
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
