
import SwiftUI

struct CycleSettingsView: View {
    @Binding var cycleSettings: CycleSettings

    var body: some View {
        Form {
            Section(header: Text("Cycle Preferences")) {
                Picker("Typical Period Length", selection: $cycleSettings.typicalPeriodLength) {
                    ForEach(3...10, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                Picker("Typical Cycle Length", selection: $cycleSettings.typicalCycleLength) {
                    ForEach(21...40, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
            }
        }
        .navigationTitle("Cycle Settings")
    }
}
