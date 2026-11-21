import SwiftUI
import MyFitPlateCore
import UIKit

struct SettingsSupportSection: View {
    @Environment(\.openURL) private var openURL
    @State private var showingSupportFallback = false
    @State private var copiedSupportAddress = false
    @State private var showingDataSources = false
    @State private var didPresentScreenshotDestination = false
    @Binding var showingHealthDisclaimer: Bool
    @Binding var showingResetTourConfirmation: Bool
    @Binding var showingAIDataConsent: Bool
    @Binding var showingSignOutAlert: Bool
    @Binding var showingDeleteAccountAlert: Bool
    let isDeletingAccount: Bool

    var body: some View {
        VStack(spacing: AppSpacing.section) {
            SettingsSectionCard(title: "Help") {
                Button { openFeedbackEmail() } label: {
                    SettingsLabel(icon: "bubble.left.and.bubble.right", title: "Feedback & support",
                                  subtitle: "Get help or suggest an improvement", showsDisclosure: true)
                }.padding(AppSpacing.group)
                Divider().padding(.leading, 64)
                Button { showingResetTourConfirmation = true } label: {
                    SettingsLabel(icon: "questionmark.circle", title: "Replay the app tour",
                                  subtitle: "See the guided tips again")
                }.padding(AppSpacing.group)
                Divider().padding(.leading, 64)
                ShareLink(item: MyFitPlateLinks.appStoreURL, subject: Text("MyFitPlate"),
                          message: Text("Nutrition built for people who train.")) {
                    SettingsLabel(icon: "square.and.arrow.up", title: "Share MyFitPlate",
                                  subtitle: "Send the App Store link")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    DIContainer.shared.analyticsManager?.logEvent("app_store_share_opened", parameters: ["source": "settings"])
                })
                .padding(AppSpacing.group)
            }
            .accessibilityIdentifier("settings_help_support")

            SettingsSectionCard(title: "Privacy & information") {
                Button { showingAIDataConsent = true } label: {
                    SettingsLabel(icon: "brain.head.profile", title: "AI data sharing",
                                  subtitle: "Choose what Maia can use", showsDisclosure: true)
                }.padding(AppSpacing.group)
                Divider().padding(.leading, 64)
                Link(destination: MyFitPlateLinks.privacyPolicyURL) {
                    SettingsLabel(icon: "lock.shield", title: "Privacy & data",
                                  subtitle: "How your information is handled")
                }.padding(AppSpacing.group)
                Divider().padding(.leading, 64)
                Button { showingDataSources = true } label: {
                    SettingsLabel(icon: "books.vertical", title: "Nutrition data sources",
                                  subtitle: "Food and supplement attribution", showsDisclosure: true)
                }.padding(AppSpacing.group)
                Divider().padding(.leading, 64)
                Button { showingHealthDisclaimer = true } label: {
                    SettingsLabel(icon: "cross.case", title: "Health guidance",
                                  subtitle: "Medical, nutrition and AI estimates", showsDisclosure: true)
                }.padding(AppSpacing.group)
                Divider().padding(.leading, 64)
                Link(destination: MyFitPlateLinks.termsOfServiceURL) {
                    SettingsLabel(icon: "doc.text", title: "Terms of service", subtitle: "Terms and usage policies")
                }.padding(AppSpacing.group)
            }

            SettingsSectionCard(title: "Account access") {
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
        .sheet(isPresented: $showingSupportFallback) {
            supportFallbackSheet
        }
        .navigationDestination(isPresented: $showingDataSources) { NutritionDataSourcesView() }
        .onAppear {
            #if DEBUG
            guard ScreenshotDemoMode.isEnabled, !didPresentScreenshotDestination else { return }
            didPresentScreenshotDestination = true
            if ScreenshotDemoData.requestedScreen == "settings-sources" { showingDataSources = true }
            if ScreenshotDemoData.requestedScreen == "settings-support-fallback" { showingSupportFallback = true }
            #endif
        }
    }

    private func openFeedbackEmail() {
        guard let url = feedbackEmailURL else {
            showingSupportFallback = true
            return
        }
        DIContainer.shared.analyticsManager?.logEvent("feedback_email_opened", parameters: [
            "source": "settings"
        ])
        openURL(url) { accepted in
            if !accepted {
                showingSupportFallback = true
                DIContainer.shared.analyticsManager?.logEvent("feedback_email_fallback_shown", parameters: [
                    "source": "settings"
                ])
            }
        }
    }

    private var feedbackEmailURL: URL? {
        var components = URLComponents(string: "mailto:\(MyFitPlateLinks.supportEmailAddress)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "MyFitPlate feedback"),
            URLQueryItem(name: "body", value: feedbackBody)
        ]
        return components?.url
    }

    private var feedbackBody: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        What were you trying to do?


        What worked well or where did you get stuck?


        App version: \(version) (\(build))
        System: \(systemVersion)
        """
    }

    private var supportFallbackSheet: some View {
        AppSheetScaffold(
            title: "Contact support",
            subtitle: "Your mail app did not open. The address and diagnostic details are still available below.",
            dismiss: { showingSupportFallback = false }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Label("Email support", systemImage: "envelope")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        Text(MyFitPlateLinks.supportEmailAddress)
                            .appTextRole(.control)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .textSelection(.enabled)
                        Text("Include what you were trying to do and what happened.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.quiet)

                    Button {
                        UIPasteboard.general.string = MyFitPlateLinks.supportEmailAddress
                        copiedSupportAddress = true
                        HapticsService.shared.playSuccess()
                    } label: {
                        Label(
                            copiedSupportAddress ? "Address copied" : "Copy email address",
                            systemImage: copiedSupportAddress ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))

                    ShareLink(
                        item: "Email \(MyFitPlateLinks.supportEmailAddress)\n\n\(feedbackBody)",
                        subject: Text("MyFitPlate support details")
                    ) {
                        Label("Share support details", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(AppActionButtonStyle(.ghost))

                    Text("The shared details contain app and operating-system versions, not your food, health, or account data.")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { copiedSupportAddress = false }
    }
}

struct NutritionDataSourcesView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                Text("Every matched food keeps its source and evidence type.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)

                sourceGroup(
                    title: "Health Canada CNF",
                    icon: "checkmark.seal.fill",
                    detail: "Generic food composition from the Canadian Nutrient File 2026. Values may combine analysis, calculations, manufacturer data, and other government composition records; they are not treated as exact branded-product labels.",
                    links: [
                        ("Canadian Nutrient File", "https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-about-us.html"),
                        ("Open dataset", "https://open.canada.ca/data/en/dataset/1b6139bd-ed7e-4043-bc28-ff00e10f3109"),
                        ("Open Government Licence - Canada", "https://open.canada.ca/en/open-government-licence-canada")
                    ],
                    attribution: "Contains information licensed under the Open Government Licence - Canada."
                )

                sourceGroup(
                    title: "NIH DSLD",
                    icon: "pills.fill",
                    detail: "Supplement facts from current manufacturer label records in the NIH Dietary Supplement Label Database. Label amounts are not laboratory verification of product contents.",
                    links: [
                        ("Dietary Supplement Label Database", "https://ods.od.nih.gov/Research/Dietary_Supplement_Label_Database.aspx")
                    ],
                    attribution: "NIH DSLD data is made available under CC0."
                )

                sourceGroup(
                    title: "Other food sources",
                    icon: "fork.knife",
                    detail: "MyFitPlate also uses USDA FoodData Central, FatSecret, and Open Food Facts. Trust distinguishes analytical references, licensed records, public label data, and manufacturer labels instead of treating every database match as independent proof.",
                    links: [
                        ("USDA FoodData Central", "https://fdc.nal.usda.gov/"),
                        ("Open Food Facts", "https://world.openfoodfacts.org/terms-of-use")
                    ],
                    attribution: nil
                )
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Data sources")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppPalette.brand)
        .accessibilityIdentifier("nutrition_data_sources_screen")
    }

    private func sourceGroup(
        title: String,
        icon: String,
        detail: String,
        links: [(String, String)],
        attribution: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label(title, systemImage: icon)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text(detail)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let attribution {
                Text(attribution)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ForEach(links, id: \.0) { label, destination in
                    if let url = URL(string: destination) {
                        Link(destination: url) {
                            HStack {
                                Text(label)
                                    .appTextRole(.control)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .appTextRole(.caption)
                            }
                        }
                    }
                }
            }
        }
        .appSurface(.quiet)
    }
}

struct AIDataConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var includeHealthData = false
    @State private var hasExistingConsent = false
    @State private var showsProcessingDetails = false

    private var userID: String {
        DIContainer.shared.authService.currentUserID ?? ""
    }

    var body: some View {
        AppEditorScaffold(
            title: "AI data sharing",
            subtitle: "Choose what MyFitPlate may use only when you ask for an AI-powered result.",
            dismiss: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("What you share")
                                .appTextRole(.sectionTitle)
                                .foregroundStyle(AppPalette.text)
                            Text("Text or images you submit, plus only the app context needed to answer.")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.shield.fill")
                            .appFont(size: 22, weight: .semibold)
                            .foregroundStyle(AppPalette.brandText)
                    }

                    VStack(spacing: 0) {
                        consentRow(
                            icon: "person.crop.circle.badge.xmark",
                            title: "Identity excluded",
                            detail: "Your email and username are not placed in AI prompts."
                        )
                        Divider().padding(.leading, 52)
                        consentRow(
                            icon: "lock.fill",
                            title: "Secured route",
                            detail: "Requests pass through MyFitPlate's protected service."
                        )
                        Divider().padding(.leading, 52)
                        consentRow(
                            icon: "arrow.uturn.backward.circle",
                            title: "Reversible",
                            detail: "Turn sharing off here at any time to block future AI requests."
                        )
                    }

                    DisclosureGroup(isExpanded: $showsProcessingDetails) {
                        Text("Depending on the feature, a request may include nutrition goals, food logs, pantry items, journal or cycle context, workout details, or the image and text you submit. MyFitPlate sends only the context needed for that request.")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, AppSpacing.compact)
                    } label: {
                        Label("What can be included", systemImage: "doc.text.magnifyingglass")
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.brandText)
                    }
                }
                .appSurface(.quiet)

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "Optional health context",
                        subtitle: "This is separate from the core AI permission."
                    )

                    Toggle("Include Apple Health data", isOn: $includeHealthData)
                        .appTextRole(.control)
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                        .accessibilityIdentifier("settings_ai_health_toggle")

                    Text("When enabled, Maia may also receive relevant steps, active energy, sleep summaries, and recovery signals. Apple Health data is never used for advertising.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Link(destination: MyFitPlateLinks.privacyPolicyURL) {
                    AppListRow(
                        icon: "doc.text",
                        iconColor: AppPalette.brandText,
                        title: "Privacy policy",
                        subtitle: "Review the complete data-use terms."
                    ) {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .appSurface(.quiet, padding: 0)
            }
        } actions: {
            Button(hasExistingConsent ? "Save preferences" : "Allow AI features") {
                AIDataConsentStore.shared.grant(
                    for: userID,
                    includesHealthData: includeHealthData
                )
                dismiss()
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(userID.isEmpty)
            .accessibilityIdentifier("settings_ai_allow")

            if hasExistingConsent {
                Button("Turn Off AI data sharing") {
                    AIDataConsentStore.shared.revoke(for: userID)
                    dismiss()
                }
                .buttonStyle(AppActionButtonStyle(.destructive))
                .accessibilityIdentifier("settings_ai_revoke")
            } else {
                Button("Not now") { dismiss() }
                    .buttonStyle(AppActionButtonStyle(.ghost))
            }
        }
        .tint(AppPalette.brand)
        .onAppear {
            if let consent = AIDataConsentStore.shared.consent(for: userID) {
                includeHealthData = consent.includesHealthData
                hasExistingConsent = true
            }
        }
        .accessibilityIdentifier("settings_ai_data_screen")
    }

    private func consentRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appTextRole(.secondary)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).appTextRole(.control).foregroundStyle(AppPalette.text)
                Text(detail).appTextRole(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.compact)
    }
}
