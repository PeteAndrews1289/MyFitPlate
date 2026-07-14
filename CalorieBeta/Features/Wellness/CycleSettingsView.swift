import MyFitPlateCore
import SwiftUI

struct CycleSettingsView: View {
    @Binding var cycleSettings: CycleSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Cycle Profile",
                    title: "Cycle Settings",
                    subtitle: "These averages improve calendar estimates. They do not measure ovulation or hormone levels."
                )

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(title: "Typical Timing")

                    VStack(spacing: 0) {
                        Picker("Typical Period Length", selection: $cycleSettings.typicalPeriodLength) {
                            ForEach(3...10, id: \.self) { days in
                                Text("\(days) days").tag(days)
                            }
                        }
                        .appTextRole(.control)
                        .padding(.horizontal, AppSpacing.group)
                        .frame(minHeight: 56)

                        Divider()
                            .padding(.leading, AppSpacing.group)

                        Picker("Typical Cycle Length", selection: $cycleSettings.typicalCycleLength) {
                            ForEach(21...40, id: \.self) { days in
                                Text("\(days) days").tag(days)
                            }
                        }
                        .appTextRole(.control)
                        .padding(.horizontal, AppSpacing.group)
                        .frame(minHeight: 56)
                    }
                    .appSurface(.quiet, padding: 0)
                }

                AppListRow(
                    icon: "checkmark.circle",
                    iconColor: AppPalette.brand,
                    title: "Saved Automatically",
                    subtitle: "Changes update your estimated phase as soon as you make them."
                )
                .appSurface(.quiet, padding: 0)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("cycle_settings_screen")
    }
}
