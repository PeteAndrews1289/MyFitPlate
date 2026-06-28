import SwiftUI

struct HomeQuickActionsView: View {
    @Binding var showingWorkoutRoutines: Bool
    @Binding var showingCoachingDashboard: Bool
    @Binding var showingMenuScanner: Bool
    @Binding var showingWeightEntrySheet: Bool
    @Binding var showingFastingSheet: Bool
    @Binding var showSettings: Bool

    var isMenuScannerSpotlightActive: Bool
    var onRepeatYesterdayMeals: () -> Void

    var body: some View {
VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Command Center")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Jump into the tools you use most.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button(action: {
                        HapticManager.instance.feedback(.light)
                        showingWorkoutRoutines = true
                    }) {
                        QuickActionButton(
                            icon: "dumbbell.fill",
                            label: "Workouts",
                            subtitle: "Train or resume a plan",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticManager.instance.feedback(.light)
                        showingCoachingDashboard = true
                    }) {
                        QuickActionButton(
                            icon: "brain.head.profile",
                            label: "Coaching",
                            subtitle: "Maia's Strategy",
                            color: .brandPrimary
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticManager.instance.feedback(.light)
                        onRepeatYesterdayMeals()
                    }) {
                        QuickActionButton(
                            icon: "clock.arrow.circlepath",
                            label: "Yesterday",
                            subtitle: "Repeat meals",
                            color: .accentPositive
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticManager.instance.feedback(.light)
                        showingMenuScanner = true
                    }) {
                        QuickActionButton(
                            icon: "menucard.fill",
                            label: "Menu Scan",
                            subtitle: "Find best macros",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                    .featureSpotlight(isActive: isMenuScannerSpotlightActive)

                    Button(action: {
                        HapticManager.instance.feedback(.light)
                        showingWeightEntrySheet = true
                    }) {
                        QuickActionButton(
                            icon: "scalemass.fill",
                            label: "Log Weight",
                            subtitle: "Track body metrics",
                            color: .teal
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticManager.instance.feedback(.light)
                        showingFastingSheet = true
                    }) {
                        QuickActionButton(
                            icon: "timer",
                            label: "Fasting",
                            subtitle: "Start or track a fast",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { showSettings = true }) {
                        QuickActionButton(
                            icon: "gearshape.fill",
                            label: "Settings",
                            subtitle: "Manage your goals",
                            color: .gray
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: 520)

}
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let subtitle: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .appFont(size: 17, weight: .semibold)
                    .foregroundColor(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }

            Text(label)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Text(subtitle)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 136, height: 136, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            colorScheme == .dark ? Color.backgroundPrimary.opacity(0.76) : color.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
