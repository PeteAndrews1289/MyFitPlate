import MyFitPlateCore
import SwiftUI

struct CycleSettingsView: View {
    @Binding var cycleSettings: CycleSettings

    var body: some View {
        Form {
            Section {
                Picker("Period length", selection: $cycleSettings.typicalPeriodLength) {
                    ForEach(3...10, id: \.self) { days in Text("\(days) days").tag(days) }
                }
                Picker("Cycle length", selection: $cycleSettings.typicalCycleLength) {
                    ForEach(21...40, id: \.self) { days in Text("\(days) days").tag(days) }
                }
            } header: {
                Text("Typical timing")
            } footer: {
                Text("These averages improve calendar estimates. They do not measure ovulation or hormone levels.")
            }
            Section {
                Label("Changes save automatically", systemImage: "checkmark.circle")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .appFormStyle()
        .navigationTitle("Cycle settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("cycle_settings_screen")
    }
}
