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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(subtitle)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

struct SettingsHeaderCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let calorieGoal: Double?
    let waterGoal: Double
    let heightText: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: dynamicTypeSize.isAccessibilitySize ? "Targets" : "Your Targets",
                subtitle: dynamicTypeSize.isAccessibilitySize
                    ? nil
                    : "The current goals used across food, hydration, and training."
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
