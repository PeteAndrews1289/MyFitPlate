import SwiftUI

struct SettingsAppearanceSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var useMetricBodyUnits: Bool

    var body: some View {
        SettingsSectionCard(title: "Display & Units") {
            Toggle(isOn: $appState.isDarkModeEnabled.animation()) {
                SettingsLabel(
                    icon: "moon.fill",
                    title: "Dark mode",
                    subtitle: "Use the darker app appearance."
                )
            }
            .padding(AppSpacing.group)

            Divider()
                .padding(.leading, 64)

            Toggle(isOn: $useMetricBodyUnits) {
                SettingsLabel(
                    icon: "ruler.fill",
                    title: "Metric units",
                    subtitle: "Show weight in kg and height in cm."
                )
            }
            .padding(AppSpacing.group)
        }
        .accessibilityIdentifier("settings_display_units")
    }
}
