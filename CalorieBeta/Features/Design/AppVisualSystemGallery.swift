#if DEBUG
import SwiftUI

struct AppVisualSystemGallery: View {
    @State private var sampleToggle = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Foundation",
                    title: "Visual system",
                    subtitle: "One quiet hierarchy for evidence, action, and configuration."
                ) {
                    Button {} label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .accessibilityLabel("Gallery settings")
                }

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text(verbatim: "Current plan")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)

                    Text(verbatim: "Fuel the work ahead")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)

                    Text(verbatim: "Your next meal and training window agree on one useful action.")
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {} label: {
                        HStack(spacing: AppSpacing.compact) {
                            Text(verbatim: "Review plan")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                }
                .appSurface(.emphasized, radius: AppRadius.hero)
                .accessibilityIdentifier("visualSystemHero")

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(
                        title: "Actions",
                        subtitle: "One filled action, then quieter alternatives."
                    )

                    Button {} label: {
                        Text(verbatim: "Primary action")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))

                    Button {} label: {
                        Text(verbatim: "Secondary action")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                }

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(title: "Rows", subtitle: "Aligned information without nested cards.")

                    VStack(spacing: 0) {
                        AppListRow(
                            icon: "checkmark.seal.fill",
                            iconColor: AppPalette.brand,
                            title: "Source verified",
                            subtitle: "Two independent databases agree"
                        ) {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }

                        Divider().padding(.leading, 68)

                        AppListRow(
                            icon: "bell",
                            title: "Recovery reminder",
                            subtitle: "After completed training"
                        ) {
                            Toggle("Recovery reminder", isOn: $sampleToggle)
                                .labelsHidden()
                        }
                    }
                    .appSurface(.quiet, padding: 0)
                }

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(title: "Type roles")

                    ForEach(AppTextRole.allCases, id: \.self) { role in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: roleName(role))
                                .appTextRole(role)
                                .foregroundStyle(AppPalette.text)

                            Spacer()

                            Text(verbatim: "\(Int(role.pointSize)) pt")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, 120)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("visualSystemGallery")
    }

    private func roleName(_ role: AppTextRole) -> String {
        switch role {
        case .display: "Display"
        case .screenTitle: "Screen title"
        case .sectionTitle: "Section title"
        case .control: "Control"
        case .body: "Body"
        case .secondary: "Secondary"
        case .caption: "Caption"
        case .metric: "Metric"
        }
    }
}
#endif
