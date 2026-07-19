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
            } else if hasRequestedAppleHealthAccess || healthViewModel.isAuthorized {
                awaitingDataContent
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
            AppSectionHeader(title: "Apple Health", subtitle: "Today's device activity") {
                Image(systemName: "heart.text.square.fill")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(AppPalette.recovery)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                AppFreshnessLabel(healthFreshness)
                Spacer(minLength: 0)
                if healthFreshness.state == .aging || healthFreshness.state == .stale {
                    Button("Refresh") {
                        healthViewModel.fetchTodayPassiveData()
                    }
                    .appTextRole(.caption)
                    .accessibilityHint("Reads today's Apple Health activity again")
                }
            }

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Steps",
                    value: Int(healthViewModel.todaySteps.rounded()).formatted(),
                    accent: AppPalette.effort
                ),
                AppMetricItem(
                    label: "Active Calories",
                    value: "\(Int(healthViewModel.todayActiveEnergy.rounded()).formatted()) cal",
                    accent: AppPalette.energy
                )
            ])

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ProgressView(value: min(max(healthViewModel.todaySteps / stepGoal, 0), 1))
                    .tint(AppPalette.effort)

                Text("\(Int(healthViewModel.todaySteps.rounded()).formatted()) of \(Int(stepGoal).formatted()) daily steps")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var awaitingDataContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Apple Health",
                subtitle: "Access was requested, but MyFitPlate has not received readable activity yet."
            ) {
                Image(systemName: "heart.text.square")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(AppPalette.recovery)
                    .accessibilityHidden(true)
            }

            AppListRow(
                icon: AppDataAvailabilityReason.notSynced.icon,
                iconColor: AppPalette.caution,
                title: AppDataAvailabilityReason.notSynced.title,
                subtitle: "There may be no activity yet, a permission may be off, or Health is still syncing."
            )
            .appSurface(.quiet, padding: 0)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.row) {
                    refreshButton
                    reviewAccessButton
                }
                VStack(spacing: AppSpacing.row) {
                    refreshButton
                    reviewAccessButton
                }
            }

            if let authError = healthViewModel.authError, !authError.isEmpty {
                Text(authError)
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.critical)
                    .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(AppPalette.recovery)
                .frame(width: 40, height: 40)
                .background(AppPalette.recovery.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
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

    private var refreshButton: some View {
        Button {
            healthViewModel.syncAllHealthData()
        } label: {
            Label("Try Sync Again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .accessibilityIdentifier("apple_health_retry_sync")
    }

    private var reviewAccessButton: some View {
        Button {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settingsURL)
        } label: {
            Label("Review Access", systemImage: "gear")
        }
        .buttonStyle(AppActionButtonStyle(.ghost))
        .accessibilityIdentifier("apple_health_review_access")
    }

    private var healthFreshness: AppDataFreshness {
        AppDataFreshness(
            updatedAt: healthViewModel.lastSyncedAt,
            currentFor: 15 * 60,
            staleAfter: 2 * 60 * 60
        )
    }
}

#Preview {
    let viewModel = HealthKitViewModel()

    HealthActivityCard()
        .environmentObject(viewModel)
        .padding()
        .background(AppPalette.canvas)
}
