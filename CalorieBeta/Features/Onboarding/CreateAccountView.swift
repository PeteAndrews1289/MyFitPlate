import SwiftUI

/// The last onboarding step: save the quiz plan to a new account. Sign in with Apple is the
/// one-tap path; email stays available for people who prefer it.
struct CreateAccountView: View {
    let draft: OnboardingProfileDraft

    @ObservedObject private var accountSetup = AccountSetupCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showsEmailForm = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isWorking = false
    @State private var showingSignIn = false

    private var plan: OnboardingPlan {
        OnboardingPlanRules.plan(for: draft)
    }

    private var canSubmitEmail: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            password.count >= 6 &&
            !isWorking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Last step",
                    title: "Save your plan",
                    subtitle: "Create a free account to keep your plan, food log, and progress in sync on your iPhone and Apple Watch."
                )

                planSummary

                VStack(spacing: AppSpacing.group) {
                    AppleSignInButton(
                        label: .continue,
                        accessibilityIdentifier: "create_account_apple",
                        onResult: handleAppleResult
                    )
                    .disabled(isWorking)

                    AuthMethodDivider()

                    if showsEmailForm {
                        emailForm
                    } else {
                        Button {
                            withAnimation(AppMotion.standard) { showsEmailForm = true }
                        } label: {
                            Label("Continue with email", systemImage: "envelope")
                        }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .disabled(isWorking)
                        .accessibilityIdentifier("create_account_email")
                    }
                }

                if isWorking {
                    HStack(spacing: AppSpacing.compact) {
                        ProgressView()
                        Text("Saving your plan…")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }

                if !errorMessage.isEmpty {
                    AuthErrorBanner(message: errorMessage)
                }

                Text("By continuing, you agree to our [Terms of service](https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/terms_of_service.md) and [Privacy policy](https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md).")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Button("Already have an account? Sign in") {
                    showingSignIn = true
                }
                .buttonStyle(AppActionButtonStyle(.ghost))
                .disabled(isWorking)
                .accessibilityIdentifier("create_account_sign_in")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppPalette.canvas.ignoresSafeArea())
        .sheet(isPresented: $showingSignIn) {
            LoginView()
        }
    }

    private var planSummary: some View {
        AppListRow(
            icon: "checkmark.seal.fill",
            iconColor: AppPalette.brandText,
            title: "Your plan",
            subtitle: "\(Int(plan.dailyCalories.rounded()).formatted()) calories and \(Int(plan.proteinGrams.rounded()).formatted()) g protein a day"
        )
        .appSurface(.interpreted, padding: 0)
    }

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            VStack(spacing: 0) {
                AuthTextFieldRow(
                    label: "First name (optional)",
                    icon: "person",
                    placeholder: "How should we address you?",
                    text: $name,
                    contentType: .givenName,
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
                    submitLabel: .done,
                    onSubmit: createEmailAccount
                )
            }
            .appSurface(.emphasized, padding: 0)

            RequirementRow(text: "At least 6 characters", isMet: password.count >= 6)

            Button(action: createEmailAccount) {
                Label("Create account", systemImage: "arrow.right")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(!canSubmitEmail)
            .accessibilityIdentifier("create_account_submit")
        }
    }

    private func handleAppleResult(_ result: Result<AppleIDCredential, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let credential):
            authenticate(method: .apple, displayName: credential.displayName) {
                try await DIContainer.shared.authService.signInWithApple(credential)
            }
        }
    }

    private func createEmailAccount() {
        guard canSubmitEmail else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenPassword = password
        authenticate(method: .email, displayName: trimmedName.isEmpty ? nil : trimmedName) {
            try await DIContainer.shared.authService.createUser(email: trimmedEmail, password: chosenPassword)
        }
    }

    /// Saves the draft, then authenticates. The root view waits until `finishAuthentication`
    /// records whether this created the account before it sets the account up.
    private func authenticate(
        method: AccountSignInMethod,
        displayName: String?,
        _ operation: @escaping () async throws -> AuthUserSession
    ) {
        guard !isWorking else { return }
        errorMessage = ""
        isWorking = true
        accountSetup.store.saveDraft(draft)
        accountSetup.beginAuthentication()

        Task { @MainActor in
            do {
                let session = try await operation()
                accountSetup.finishAuthentication(session: session, method: method, displayName: displayName)
                let event: ProductAnalytics.Event = session.isNewUser ? .accountCreated : .signInCompleted
                DIContainer.shared.analyticsManager?.logEvent(event.rawValue, parameters: ["method": method.rawValue])
                // The root view takes over setup; close the onboarding cover like sign-up always has.
                dismiss()
            } catch {
                accountSetup.cancelAuthentication()
                isWorking = false
                errorMessage = error.localizedDescription
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
