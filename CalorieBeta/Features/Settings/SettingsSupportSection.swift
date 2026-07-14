import SwiftUI
import MyFitPlateCore

struct SettingsSupportSection: View {
    @Environment(\.openURL) private var openURL
    @Binding var showingHealthDisclaimer: Bool
    @Binding var showingResetTourConfirmation: Bool
    @Binding var showingAIDataConsent: Bool
    @Binding var showingSignOutAlert: Bool
    @Binding var showingDeleteAccountAlert: Bool
    let isDeletingAccount: Bool

    var body: some View {
        VStack(spacing: AppSpacing.section) {
            SettingsSectionCard(title: "Help & Support") {
                Button {
                    showingHealthDisclaimer = true
                } label: {
                    SettingsLabel(
                        icon: "cross.case.fill",
                        title: "Health disclaimers",
                        subtitle: "Review medical, nutrition, and AI estimate guidance.",
                        showsDisclosure: true
                    )
                }
                .padding(AppSpacing.group)

                Divider().padding(.leading, 50)

                Link(destination: URL(string: "https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md")!) {
                    SettingsLabel(
                        icon: "lock.shield.fill",
                        title: "Privacy & data",
                        subtitle: "See how health, nutrition, and AI data are handled."
                    )
                }
                .padding(AppSpacing.group)

                Divider().padding(.leading, 50)

                Button {
                    showingAIDataConsent = true
                } label: {
                    SettingsLabel(
                        icon: "brain.head.profile",
                        title: "AI data sharing",
                        subtitle: "Review or change what Maia may send for processing.",
                        showsDisclosure: true
                    )
                }
                .padding(AppSpacing.group)

                Divider().padding(.leading, 50)

                Link(destination: URL(string: "https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/terms_of_service.md")!) {
                    SettingsLabel(
                        icon: "doc.text.fill",
                        title: "Terms of service",
                        subtitle: "Read our terms, conditions, and usage policies."
                    )
                }
                .padding(AppSpacing.group)

                Divider().padding(.leading, 50)

                Button {
                    openFeedbackEmail()
                } label: {
                    SettingsLabel(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Feedback & support",
                        subtitle: "Tell us what worked or where you got stuck."
                    )
                }
                .padding(AppSpacing.group)

                Divider().padding(.leading, 50)

                ShareLink(
                    item: MyFitPlateLinks.appStoreURL,
                    subject: Text("MyFitPlate"),
                    message: Text("Nutrition built for people who train.")
                ) {
                    SettingsLabel(
                        icon: "square.and.arrow.up",
                        title: "Share MyFitPlate",
                        subtitle: "Send the App Store link to someone who trains."
                    )
                }
                .simultaneousGesture(TapGesture().onEnded {
                    DIContainer.shared.analyticsManager?.logEvent("app_store_share_opened", parameters: [
                        "source": "settings"
                    ])
                })
                .padding(AppSpacing.group)

                Divider().padding(.leading, 50)

                Button {
                    showingResetTourConfirmation = true
                } label: {
                    SettingsLabel(
                        icon: "questionmark.circle.fill",
                        title: "Reset feature tooltips",
                        subtitle: "Replay the guided app tips."
                    )
                }
                .padding(AppSpacing.group)
            }
            .accessibilityIdentifier("settings_help_support")
            
            SettingsSectionCard(title: "Account Access") {
                Button(role: .destructive) {
                    showingSignOutAlert = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .appTextRole(.control)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppSpacing.group)
                
                Divider()
                
                if isDeletingAccount {
                    HStack {
                        Text("Deleting account")
                            .appTextRole(.control)
                        Spacer()
                        ProgressView()
                    }
                    .padding(AppSpacing.group)
                } else {
                    Button(role: .destructive) {
                        showingDeleteAccountAlert = true
                    } label: {
                        Label("Delete account", systemImage: "trash")
                            .appTextRole(.control)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(AppSpacing.group)
                }
            }
            .accessibilityIdentifier("settings_account_access")
        }
    }

    private func openFeedbackEmail() {
        guard let url = feedbackEmailURL else { return }
        DIContainer.shared.analyticsManager?.logEvent("feedback_email_opened", parameters: [
            "source": "settings"
        ])
        openURL(url)
    }

    private var feedbackEmailURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
        What were you trying to do?


        What worked well or where did you get stuck?


        App version: \(version) (\(build))
        System: \(systemVersion)
        """

        var components = URLComponents(string: "mailto:peteandrews1289@gmail.com")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "MyFitPlate feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }
}

struct AIDataConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var includeHealthData = false
    @State private var hasExistingConsent = false

    private var userID: String {
        DIContainer.shared.authService.currentUserID ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("MyFitPlate uses OpenAI through a secured Firebase service to power Maia, photo and menu analysis, meal planning, and workout insights.")
                    Text("When you use an AI feature, MyFitPlate may send the text or image you submit plus the nutrition goals, food logs, journal entries, cycle information, pantry items, or workout details needed for that request. Your email and username are not included in AI prompts.")
                } header: {
                    Text("AI processing")
                }

                Section {
                    Toggle("Include Apple Health data", isOn: $includeHealthData)
                        .accessibilityIdentifier("settings_ai_health_toggle")
                    Text("When enabled, Maia may also receive relevant steps, active energy, sleep summaries, and recovery signals. Apple Health data is never used for advertising.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Optional Health context")
                }

                Section {
                    Link("Read the privacy policy", destination: URL(string: "https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md")!)
                    Text("You can change this choice here at any time. Turning AI data sharing off blocks future AI requests until you allow it again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(hasExistingConsent ? "Save AI preferences" : "Allow AI features") {
                        AIDataConsentStore.shared.grant(for: userID, includesHealthData: includeHealthData)
                        dismiss()
                    }
                    .disabled(userID.isEmpty)
                    .accessibilityIdentifier("settings_ai_allow")

                    if hasExistingConsent {
                        Button("Turn off AI data sharing", role: .destructive) {
                            AIDataConsentStore.shared.revoke(for: userID)
                            dismiss()
                        }
                        .accessibilityIdentifier("settings_ai_revoke")
                    } else {
                        Button("Not now", role: .cancel) { dismiss() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("AI Data Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppPalette.brand)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if let consent = AIDataConsentStore.shared.consent(for: userID) {
                    includeHealthData = consent.includesHealthData
                    hasExistingConsent = true
                }
            }
        }
        .accessibilityIdentifier("settings_ai_data_screen")
    }
}
