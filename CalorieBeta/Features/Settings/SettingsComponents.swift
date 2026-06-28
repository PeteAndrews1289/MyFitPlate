import SwiftUI

struct SettingsSectionCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title.uppercased())
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.horizontal, 8)
            }
            
            VStack(spacing: 0) {
                content
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}

struct SettingsLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SettingsHeaderCard: View {
    let calorieGoal: Double?
    let waterGoal: Double
    let heightText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 46, height: 46)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal Settings")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Tune the goals and integrations that power the rest of MyFitPlate.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                SettingsMetric(title: "Calories", value: calorieGoal.map { "\(Int($0.rounded()))" } ?? "--", color: .orange)
                SettingsMetric(title: "Water", value: "\(Int(waterGoal.rounded())) oz", color: .cyan)
                SettingsMetric(title: "Height", value: heightText, color: .blue)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct DeleteAccountAlerts: ViewModifier {
    @Binding var showingReauthForDelete: Bool
    @Binding var reauthPassword: String
    @Binding var deleteErrorMessage: String?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Confirm Your Password", isPresented: $showingReauthForDelete) {
                SecureField("Password", text: $reauthPassword)
                Button("Cancel", role: .cancel) { reauthPassword = "" }
                Button("Delete Account", role: .destructive) { onConfirm() }
            } message: {
                Text("For your security, re-enter your password to permanently delete your account.")
            }
            .alert("Couldn't Delete Account", isPresented: errorBinding) {
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
        case .privacy: return "Privacy & Data"
        case .terms: return "Terms & Safety"
        }
    }

    var icon: String {
        switch self {
        case .privacy: return "lock.shield.fill"
        case .terms: return "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .privacy: return .blue
        case .terms: return .purple
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
                SettingsLegalSection(title: "Personal Data", body: "MyFitPlate stores account, goal, nutrition, weight, workout, recipe, meal plan, pantry, and progress data so the app can personalize your experience."),
                SettingsLegalSection(title: "Apple Health", body: "Health data is requested only when you connect Apple Health. You can manage or revoke those permissions in the Health app or iOS Settings."),
                SettingsLegalSection(title: "AI Features", body: "Maia, food photo analysis, recipe generation, meal planning, and insights may send your prompts and relevant nutrition context to the configured AI service to generate a response."),
                SettingsLegalSection(title: "Analytics", body: "Analytics should be used only to understand app stability and feature health. Keep your App Store privacy labels aligned with the analytics and SDKs actually enabled in the release build."),
                SettingsLegalSection(title: "Deleting Your Account", body: "The Delete Account action removes the app's stored user data and then attempts to delete the Firebase Authentication account.")
            ]
        case .terms:
            return [
                SettingsLegalSection(title: "Not Medical Advice", body: "Nutrition targets, calorie estimates, fasting suggestions, cycle insights, workouts, and AI responses are informational and may not fit every health situation."),
                SettingsLegalSection(title: "Estimate Accuracy", body: "Food databases, barcode matches, manual entries, and AI-generated estimates can be incomplete or wrong. Review entries before relying on them."),
                SettingsLegalSection(title: "User Responsibility", body: "Use your judgment and consult a qualified professional before making major diet, exercise, medication, fasting, or weight-change decisions."),
                SettingsLegalSection(title: "Emergency Care", body: "Do not use MyFitPlate for urgent medical concerns. Contact emergency services or a licensed clinician when immediate care is needed.")
            ]
        }
    }
}

struct SettingsLegalInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: SettingsLegalInfoKind

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: kind.icon)
                            .appFont(size: 22, weight: .bold)
                            .foregroundColor(kind.color)
                            .frame(width: 46, height: 46)
                            .background(kind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(kind.intro)
                            .appFont(size: 14)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))

                    ForEach(kind.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .appFont(size: 17, weight: .bold)
                                .foregroundColor(.textPrimary)
                            Text(section.body)
                                .appFont(size: 14)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
