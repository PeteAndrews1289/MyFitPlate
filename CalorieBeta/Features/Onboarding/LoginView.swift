import SwiftUI
import UIKit

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var loginError = ""
    @State private var isLoading = false
    @State private var loadingMessage = "Signing in…"
    @State private var showingResetAlert = false
    @State private var resetAlertMessage = ""
    @FocusState private var focusedField: AuthField?
    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty &&
            !isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    OnboardingBrandHeader()
                    OnboardingHeadline(
                        title: "Welcome back",
                        subtitle: "Pick up your meals, training and progress."
                    )

                    AppleSignInButton(
                        label: .signIn,
                        accessibilityIdentifier: "login_apple",
                        onResult: handleAppleResult
                    )
                    .disabled(isLoading)

                    AuthMethodDivider()

                    VStack(spacing: 0) {
                        AuthTextFieldRow(
                            label: "Email",
                            icon: "envelope",
                            placeholder: "you@example.com",
                            text: $email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress,
                            capitalization: .never,
                            submitLabel: .next,
                            focus: $focusedField,
                            field: .email,
                            identifier: "login_email",
                            onSubmit: { focusedField = .password }
                        )

                        Divider().padding(.leading, 68)

                        AuthSecureFieldRow(
                            label: "Password",
                            text: $password,
                            contentType: .password,
                            focus: $focusedField,
                            identifier: "login_password",
                            onSubmit: loginUser
                        )
                    }
                    .appSurface(.quiet, padding: 0)
                    .disabled(isLoading)

                    if !loginError.isEmpty {
                        AuthErrorBanner(message: loginError)
                    }

                    VStack(spacing: AppSpacing.row) {
                        Button(action: loginUser) {
                            Group {
                                if isLoading {
                                    HStack(spacing: AppSpacing.compact) {
                                        ProgressView().tint(AppPalette.onBrand)
                                        Text(loadingMessage)
                                    }
                                } else {
                                    Label("Sign in", systemImage: "arrow.right")
                                }
                            }
                        }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("login_submit")

                        Button("Forgot password?", action: sendPasswordReset)
                            .buttonStyle(OnboardingTextButtonStyle())
                            .disabled(isLoading)
                            .accessibilityIdentifier("login_reset_password")
                    }

                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .disabled(isLoading)
                }
            }
            .interactiveDismissDisabled(isLoading)
            .alert("Check your inbox", isPresented: $showingResetAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetAlertMessage)
            }
        }
    }

    private func loginUser() {
        guard canSubmit else { return }
        focusedField = nil
        loadingMessage = "Signing in…"
        isLoading = true
        loginError = ""

        Task { @MainActor in
            do {
                _ = try await DIContainer.shared.authService.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                DIContainer.shared.analyticsManager?.logEvent(
                    ProductAnalytics.Event.signInCompleted.rawValue,
                    parameters: ["method": AccountSignInMethod.email.rawValue]
                )
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                loginError = error.localizedDescription
            }
        }
    }

    /// Apple sign-in can also create an account, so the root view waits until this records
    /// whether it did before it decides how to set the account up.
    private func handleAppleResult(_ result: Result<AppleIDCredential, Error>) {
        guard case .success(let credential) = result else {
            if case .failure(let error) = result {
                loginError = error.localizedDescription
            }
            return
        }

        focusedField = nil
        loadingMessage = "Signing in…"
        isLoading = true
        loginError = ""
        let accountSetup = AccountSetupCoordinator.shared
        accountSetup.beginAuthentication()

        Task { @MainActor in
            do {
                let session = try await DIContainer.shared.authService.signInWithApple(credential)
                accountSetup.finishAuthentication(
                    session: session,
                    method: .apple,
                    displayName: credential.displayName
                )
                let event: ProductAnalytics.Event = session.isNewUser ? .accountCreated : .signInCompleted
                DIContainer.shared.analyticsManager?.logEvent(
                    event.rawValue,
                    parameters: ["method": AccountSignInMethod.apple.rawValue]
                )
                isLoading = false
                dismiss()
            } catch {
                accountSetup.cancelAuthentication()
                isLoading = false
                loginError = error.localizedDescription
            }
        }
    }

    private func sendPasswordReset() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loginError = "Enter your email above, then request a reset link."
            focusedField = .email
            return
        }
        loginError = ""
        focusedField = nil
        loadingMessage = "Sending link…"
        isLoading = true

        Task { @MainActor in
            do {
                try await DIContainer.shared.authService.sendPasswordReset(email: trimmed)
                isLoading = false
                resetAlertMessage = "If an account matches that address, a reset link is on the way. Check your inbox and spam folder."
                showingResetAlert = true
            } catch {
                isLoading = false
                loginError = error.localizedDescription
            }
        }
    }
}

enum AuthField: Hashable { case name, email, password }

struct AuthTextFieldRow: View {
    let label: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType?
    let keyboardType: UIKeyboardType
    let capitalization: TextInputAutocapitalization
    let submitLabel: SubmitLabel
    @FocusState.Binding var focus: AuthField?
    let field: AuthField
    let identifier: String
    var onSubmit: () -> Void = {}

    var body: some View {
        AuthFieldShell(label: label, icon: icon) {
            TextField(placeholder, text: $text)
                .appTextRole(.control)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
                .onSubmit(onSubmit)
        }
    }
}

struct AuthSecureFieldRow: View {
    let label: String
    @Binding var text: String
    let contentType: UITextContentType?
    @FocusState.Binding var focus: AuthField?
    let identifier: String
    let onSubmit: () -> Void

    @State private var revealsText = false

    var body: some View {
        AuthFieldShell(label: label, icon: "lock") {
            HStack(spacing: AppSpacing.compact) {
                AuthPasswordInput(
                    text: $text, label: label, contentType: contentType,
                    isSecure: !revealsText, identifier: identifier, onSubmit: onSubmit
                )
                // One focus owner: the UIKit bridge must not reclaim AutoFill's focus.
                .focused($focus, equals: .password)
                .privacySensitive()

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

/// Keep the same native password field when revealing its text. Replacing a SecureField with
/// a TextField can end the autofill session and prompt to save a password before sign-in.
private struct AuthPasswordInput: UIViewRepresentable {
    @Binding var text: String
    let label: String
    let contentType: UITextContentType?
    let isSecure: Bool
    let identifier: String
    let onSubmit: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.placeholder = label
        field.accessibilityLabel = label
        field.accessibilityIdentifier = identifier
        field.textContentType = contentType
        field.isSecureTextEntry = isSecure
        field.clearsOnBeginEditing = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isApplyingState = true
        defer { context.coordinator.isApplyingState = false }
        if field.isEnabled != isEnabled { field.isEnabled = isEnabled }
        field.textColor = UIColor(AppPalette.text)
        let base = UIFont.preferredFont(forTextStyle: dynamicTypeSize.isAccessibilitySize ? .headline : .body)
        let descriptor = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold).fontDescriptor
            .withDesign(.default)
        let font = UIFont(descriptor: descriptor ?? base.fontDescriptor, size: base.pointSize)
        if field.font != font { field.font = font }
        if field.text != text { field.text = text }
        // UIKit can temporarily change its secure-entry state during new-password input.
        // Reapply only when the user's Show/Hide choice changes, never on every keystroke.
        if context.coordinator.appliedSecureState != isSecure {
            let value = text
            let selection = field.selectedTextRange
            context.coordinator.appliedSecureState = isSecure
            field.isSecureTextEntry = isSecure
            // Reinsert without ending editing; UIKit otherwise may clear the secure value on
            // the next keystroke. Preserve the caret if the user revealed mid-password.
            field.text = nil
            field.insertText(value)
            if let selection { field.selectedTextRange = selection }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: max(44, uiView.intrinsicContentSize.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AuthPasswordInput
        var appliedSecureState: Bool
        var isApplyingState = false
        init(_ parent: AuthPasswordInput) {
            self.parent = parent
            appliedSecureState = parent.isSecure
        }

        @objc func textChanged(_ field: UITextField) {
            guard !isApplyingState else { return }
            let value = field.text ?? ""
            if parent.text != value { parent.text = value }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            guard textField.isSecureTextEntry, let value = textField.text, !value.isEmpty else { return }
            // Secure fields can replace their entire value on the first key after
            // refocusing. Reinsert it so returning from Email continues editing.
            isApplyingState = true
            defer { isApplyingState = false }
            textField.text = nil
            textField.insertText(value)
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
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
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                content
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.group)
    }
}

struct AuthErrorBanner: View {
    let message: String
    @AccessibilityFocusState private var isErrorFocused: Bool

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
        .accessibilityIdentifier("auth_error")
        .accessibilityFocused($isErrorFocused)
        .task(id: message) { isErrorFocused = true }
    }
}
