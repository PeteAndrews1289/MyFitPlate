import SwiftUI

struct SettingsAppearanceSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var useMetricBodyUnits: Bool

    var body: some View {
        VStack(spacing: 24) {
            SettingsSectionCard(title: "Appearance") {
                Toggle(isOn: $appState.isDarkModeEnabled.animation()) {
                    SettingsLabel(icon: "moon.fill", title: "Dark Mode", subtitle: "Use the darker app appearance.", color: .purple)
                }
                .padding(16)
            }

            SettingsSectionCard(title: "Units") {
                Toggle(isOn: $useMetricBodyUnits) {
                    SettingsLabel(icon: "ruler.fill", title: "Metric Units", subtitle: "Show weight in kg and height in cm.", color: .teal)
                }
                .padding(16)
            }
        }
    }
}
