import SwiftUI
import MyFitPlateCore

struct SettingsSectionCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let title {
                Text(title)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.compact)
            }

            VStack(spacing: 0) {
                content
            }
            .appSurface(.quiet, padding: 0, radius: AppRadius.control)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    let showsDisclosure: Bool

    init(
        icon: String,
        title: String,
        subtitle: String,
        showsDisclosure: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showsDisclosure = showsDisclosure
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 17, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(
                    AppPalette.surface,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.compact)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .appTextRole(.secondary)
                    .foregroundStyle(.tertiary)
                    .padding(.top, AppSpacing.compact)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsHeaderCard: View {
    let calorieGoal: Double?
    let waterGoal: Double
    let heightText: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Your Targets",
                subtitle: "The current goals used across food, hydration, and training."
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Calories",
                    value: calorieGoal.map { "\(Int($0.rounded()).formatted()) cal" } ?? "--",
                    accent: AppPalette.energy
                ),
                AppMetricItem(
                    label: "Water",
                    value: "\(Int(waterGoal.rounded()).formatted()) oz",
                    accent: AppPalette.hydration
                ),
                AppMetricItem(label: "Height", value: heightText, accent: AppPalette.brand)
            ])
        }
        .appSurface(.emphasized)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings_goals_summary")
    }
}

struct DeleteAccountAlerts: ViewModifier {
    @Binding var showingReauthForDelete: Bool
    @Binding var reauthPassword: String
    @Binding var deleteErrorMessage: String?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Confirm your password", isPresented: $showingReauthForDelete) {
                SecureField("Password", text: $reauthPassword)
                Button("Cancel", role: .cancel) { reauthPassword = "" }
                Button("Delete account", role: .destructive) { onConfirm() }
            } message: {
                Text("For your security, re-enter your password to permanently delete your account.")
            }
            .alert("Couldn't delete account", isPresented: errorBinding) {
                Button("OK", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { deleteErrorMessage != nil }, set: { if !$0 { deleteErrorMessage = nil } })
    }
}

struct SettingsLegalSection: Identifiable {
    let title: String
    let body: String
    var id: String { title }
}

enum SettingsLegalInfoKind {
    case privacy
    case terms

    var title: String {
        switch self {
        case .privacy: return "Privacy & data"
        case .terms: return "Terms & safety"
        }
    }

    var intro: String {
        switch self {
        case .privacy:
            return "This in-app summary is here for transparency. Your App Store privacy policy should remain the full legal source of truth."
        case .terms:
            return "MyFitPlate is designed to support everyday nutrition and fitness tracking. It should not replace professional medical, nutrition, or emergency care."
        }
    }

    var sections: [SettingsLegalSection] {
        switch self {
        case .privacy:
            return [
                SettingsLegalSection(title: "Personal data", body: "MyFitPlate stores account, goal, nutrition, weight, workout, recipe, meal plan, pantry, and progress data so the app can personalize your experience."),
                SettingsLegalSection(title: "Apple Health", body: "Health data is requested only when you connect Apple Health. You can manage or revoke those permissions in the Health app or iOS Settings."),
                SettingsLegalSection(title: "AI features", body: "Maia, food photo analysis, recipe generation, meal planning, and insights may send your prompts and relevant nutrition context to the configured AI service to generate a response."),
                SettingsLegalSection(title: "Analytics", body: "Analytics should be used only to understand app stability and feature health. Keep your App Store privacy labels aligned with the analytics and SDKs actually enabled in the release build."),
                SettingsLegalSection(title: "Deleting your account", body: "The Delete account action removes the app's stored user data and then attempts to delete the Firebase Authentication account.")
            ]
        case .terms:
            return [
                SettingsLegalSection(title: "Not medical advice", body: "Nutrition targets, calorie estimates, fasting suggestions, cycle insights, workouts, and AI responses are informational and may not fit every health situation."),
                SettingsLegalSection(title: "Estimate accuracy", body: "Food databases, barcode matches, manual entries, and AI-generated estimates can be incomplete or wrong. Review entries before relying on them."),
                SettingsLegalSection(title: "User responsibility", body: "Use your judgment and consult a qualified professional before making major diet, exercise, medication, fasting, or weight-change decisions."),
                SettingsLegalSection(title: "Emergency care", body: "Do not use MyFitPlate for urgent medical concerns. Contact emergency services or a licensed clinician when immediate care is needed.")
            ]
        }
    }
}

struct SettingsLegalInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: SettingsLegalInfoKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "MyFitPlate",
                    title: kind.title,
                    subtitle: kind.intro
                )

                VStack(spacing: 0) {
                    ForEach(Array(kind.sections.enumerated()), id: \.element.id) { index, section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.text)
                            Text(section.body)
                                .appTextRole(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(AppSpacing.group)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < kind.sections.count - 1 {
                            Divider()
                                .padding(.leading, AppSpacing.group)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0, radius: AppRadius.control)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppPalette.brand)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
