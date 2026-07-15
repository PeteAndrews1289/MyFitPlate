import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var loginError = ""
    @State private var isLoading = false
    @State private var showingResetAlert = false
    @State private var resetAlertMessage = ""
    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty &&
            !isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AuthIntro(
                        icon: "person.crop.circle.badge.checkmark",
                        eyebrow: "Your account",
                        title: "Welcome back",
                        subtitle: "Continue with the same food history, goals, training, and Maia context."
                    )

                    VStack(spacing: 0) {
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
                            contentType: .password,
                            submitLabel: .go,
                            onSubmit: loginUser
                        )
                    }
                    .appSurface(.emphasized, padding: 0)

                    if !loginError.isEmpty {
                        AuthErrorBanner(message: loginError)
                    }

                    VStack(spacing: AppSpacing.row) {
                        Button(action: loginUser) {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Sign in", systemImage: "arrow.right")
                                }
                            }
                        }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("login_submit")

                        Button("Send a password reset link", action: sendPasswordReset)
                            .buttonStyle(AppActionButtonStyle(.ghost))
                            .disabled(isLoading)
                    }

                    Text("Password resets are sent only to the email entered above.")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Reset link sent", isPresented: $showingResetAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetAlertMessage)
            }
        }
    }

    private func loginUser() {
        guard canSubmit else { return }
        isLoading = true
        loginError = ""

        Task { @MainActor in
            do {
                _ = try await DIContainer.shared.authService.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                loginError = error.localizedDescription
            }
        }
    }

    private func sendPasswordReset() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loginError = "Enter your email above, then request a reset link."
            return
        }
        loginError = ""
        isLoading = true

        Task { @MainActor in
            do {
                try await DIContainer.shared.authService.sendPasswordReset(email: trimmed)
                isLoading = false
                resetAlertMessage = "We sent a password reset link to \(trimmed). Check your inbox and spam folder."
                showingResetAlert = true
            } catch {
                isLoading = false
                loginError = error.localizedDescription
            }
        }
    }
}

struct AuthIntro: View {
    let icon: String
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Image(systemName: icon)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 48, height: 48)
                .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            AppScreenHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
        }
    }
}

struct AuthTextFieldRow: View {
    let label: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType?
    let keyboardType: UIKeyboardType
    let capitalization: TextInputAutocapitalization
    let submitLabel: SubmitLabel

    var body: some View {
        AuthFieldShell(label: label, icon: icon) {
            TextField(placeholder, text: $text)
                .appTextRole(.control)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
        }
    }
}

struct AuthSecureFieldRow: View {
    let label: String
    @Binding var text: String
    let contentType: UITextContentType?
    let submitLabel: SubmitLabel
    let onSubmit: () -> Void

    @State private var revealsText = false

    var body: some View {
        AuthFieldShell(label: label, icon: "lock") {
            HStack(spacing: AppSpacing.compact) {
                Group {
                    if revealsText {
                        TextField(label, text: $text)
                    } else {
                        SecureField(label, text: $text)
                    }
                }
                .appTextRole(.control)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)

                Button {
                    revealsText.toggle()
                } label: {
                    Image(systemName: revealsText ? "eye.slash" : "eye")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel(revealsText ? "Hide \(label.lowercased())" : "Show \(label.lowercased())")
                .help(revealsText ? "Hide \(label.lowercased())" : "Show \(label.lowercased())")
            }
        }
    }
}

private struct AuthFieldShell<Content: View>: View {
    let label: String
    let icon: String
    private let content: Content

    init(label: String, icon: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                content
                    .frame(minHeight: 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.group)
    }
}

struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppPalette.caution)
                .accessibilityHidden(true)
            Text(message)
                .appTextRole(.secondary)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.caution.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.caution.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
