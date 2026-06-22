import SwiftUI
import FirebaseAuth
import Firebase

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var loginError = ""
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        AuthHeaderCard(
                            icon: "person.crop.circle.fill.badge.checkmark",
                            title: "Welcome Back",
                            subtitle: "Pick up your dashboard, goals, and Maia history."
                        )
                        .padding(.top, 18)

                        VStack(spacing: 14) {
                            TextField("Email", text: $email)
                                .textFieldStyle(AppTextFieldStyle(iconName: "envelope.fill"))
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            SecureField("Password", text: $password)
                                .textFieldStyle(AppTextFieldStyle(iconName: "lock.fill"))
                        }
                        .asCard()

                        if !loginError.isEmpty {
                            AuthErrorBanner(message: loginError)
                        }

                        Button {
                            loginUser()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Log In")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSubmit)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Log In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func loginUser() {
        guard canSubmit else { return }
        isLoading = true
        loginError = ""

        Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) { authResult, error in
            isLoading = false
            if let error = error {
                loginError = error.localizedDescription
                return
            }

            if let user = authResult?.user {
                fetchUserData(user: user)
            }
        }
    }

    private func fetchUserData(user: FirebaseAuth.User) {
        let db = Firestore.firestore()
        db.collection("users").document(user.uid).getDocument { document, error in
            if let document = document, document.exists {
                dismiss()
            } else {
                loginError = "User data not found."
            }
        }
    }
}

struct AuthHeaderCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.brandPrimary)
                .frame(width: 50, height: 50)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .appFont(size: 30, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .asCard()
    }
}

struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .appFont(size: 13)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
