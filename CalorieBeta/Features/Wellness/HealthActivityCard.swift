import HealthKit
import MyFitPlateCore
import SwiftUI

struct HealthActivityCard: View {
    @EnvironmentObject var healthViewModel: HealthKitViewModel
    @AppStorage("hasRequestedAppleHealthAccess") private var hasRequestedAppleHealthAccess = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let stepGoal: Double = 10_000

    var body: some View {
        Group {
            if healthViewModel.hasSyncedHealthData {
                connectedContent
            } else {
                connectContent
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("apple_health_summary")
        .onAppear {
            if healthViewModel.isAuthorized {
                healthViewModel.fetchTodayPassiveData()
            }
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Apple Health", subtitle: "Today") {
                Image(systemName: "heart.text.square.fill")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Steps",
                    value: Int(healthViewModel.todaySteps.rounded()).formatted(),
                    accent: .blue
                ),
                AppMetricItem(
                    label: "Active Calories",
                    value: "\(Int(healthViewModel.todayActiveEnergy.rounded()).formatted()) cal",
                    accent: .orange
                )
            ])

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ProgressView(value: min(max(healthViewModel.todaySteps / stepGoal, 0), 1))
                    .tint(.blue)

                Text("\(Int(healthViewModel.todaySteps.rounded()).formatted()) of \(Int(stepGoal).formatted()) daily steps")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Apple Health",
                subtitle: "Optional context for activity, sleep, and recovery"
            )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                        connectionDescription
                        connectionButton
                            .buttonStyle(AppActionButtonStyle(.secondary))
                    }
                } else {
                    HStack(spacing: AppSpacing.group) {
                        connectionDescription
                        Spacer(minLength: AppSpacing.compact)
                        connectionButton
                            .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: false))
                    }
                }
            }
        }
        .onChange(of: healthViewModel.isAuthorized) { _, isAuthorized in
            if isAuthorized {
                healthViewModel.fetchTodayPassiveData()
            }
        }
    }

    private var connectionDescription: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: "heart.text.square.fill")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(.red)
                .frame(width: 40, height: 40)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            Text("Bring your device activity into the same daily view as nutrition and training.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionButton: some View {
        Button(hasRequestedAppleHealthAccess ? "Review Access" : "Connect") {
            if hasRequestedAppleHealthAccess,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            } else {
                hasRequestedAppleHealthAccess = true
                healthViewModel.authError = nil
                healthViewModel.requestAuthorization()
            }
        }
        .accessibilityHint(
            hasRequestedAppleHealthAccess
                ? "Opens Settings so you can review Apple Health access"
                : "Shows Apple's Health access request"
        )
        .accessibilityIdentifier("apple_health_connect_button")
    }
}

#Preview {
    let viewModel = HealthKitViewModel()

    HealthActivityCard()
        .environmentObject(viewModel)
        .padding()
        .background(AppPalette.canvas)
}
