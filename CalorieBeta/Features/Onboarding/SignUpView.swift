import SwiftUI

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

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
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AuthIntro(
                        icon: "person.badge.plus",
                        eyebrow: "One account",
                        title: "Build your MyFitPlate",
                        subtitle: "Your food history, body trends, training, and preferences will stay together."
                    )

                    VStack(spacing: 0) {
                        AuthTextFieldRow(
                            label: "Name",
                            icon: "person",
                            placeholder: "How should we address you?",
                            text: $username,
                            contentType: .name,
                            keyboardType: .default,
                            capitalization: .words,
                            submitLabel: .next
                        )

                        Divider().padding(.leading, 68)

                        AuthTextFieldRow(
                            label: "Email",
                            icon: "envelope",
                            placeholder: "you@example.com",
                            text: $email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress,
                            capitalization: .never,
                            submitLabel: .next
                        )

                        Divider().padding(.leading, 68)

                        AuthSecureFieldRow(
                            label: "Password",
                            text: $password,
                            contentType: .newPassword,
                            submitLabel: .next,
                            onSubmit: { }
                        )

                        Divider().padding(.leading, 68)

                        AuthSecureFieldRow(
                            label: "Confirm password",
                            text: $confirmPassword,
                            contentType: .newPassword,
                            submitLabel: .done,
                            onSubmit: signUpUser
                        )
                    }
                    .appSurface(.emphasized, padding: 0)

                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        RequirementRow(
                            text: "At least 6 characters",
                            isMet: password.count >= 6
                        )
                        RequirementRow(
                            text: "Both passwords match",
                            isMet: !password.isEmpty && password == confirmPassword
                        )
                    }

                    if !signUpError.isEmpty {
                        AuthErrorBanner(message: signUpError)
                    }

                    Button(action: signUpUser) {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Label("Create account", systemImage: "arrow.right")
                            }
                        }
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("signup_submit")

                    Text("By creating an account, you agree to our [Terms of service](https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/terms_of_service.md) and [Privacy policy](https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md).")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Create account")
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
            signUpError = "Enter the name you want MyFitPlate to use."
            return
        }
        guard password.count >= 6 else {
            signUpError = "Choose a password with at least 6 characters."
            return
        }
        guard password == confirmPassword else {
            signUpError = "The passwords do not match."
            return
        }
        guard !isLoading else { return }

        isLoading = true
        signUpError = ""

        Task { @MainActor in
            do {
                let session = try await DIContainer.shared.authService.createUser(
                    email: trimmedEmail,
                    password: password
                )
                try await DIContainer.shared.settingsRepository.createInitialUserData(
                    userID: session.userID,
                    email: session.email ?? trimmedEmail,
                    username: trimmedUsername
                )
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                signUpError = error.localizedDescription
            }
        }
    }
}

private struct RequirementRow: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isMet ? .accentPositive : .secondary)
                .accessibilityHidden(true)
            Text(text)
                .appTextRole(.secondary)
                .foregroundStyle(isMet ? AppPalette.text : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), \(isMet ? "met" : "not yet met")")
    }
}
