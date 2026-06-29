import SwiftUI
struct CurrentWeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var weight = ""
    @State private var entryDate = Date()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("Weight")) {
                TextField("Enter your weight (\(BodyUnits.weightUnit(metric: useMetric)))", text: $weight)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(AppTextFieldStyle(iconName: nil))

                DatePicker("Date", selection: $entryDate, in: ...Date(), displayedComponents: .date)
            }

            Button("Save Weight") {
                saveWeight()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Log Weight")
        .onAppear {
            weight = String(format: "%.1f", BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: useMetric))
        }
    }

    private func saveWeight() {
        guard let value = Double(weight), value > 0 else { return }
        goalSettings.updateUserWeight(BodyUnits.weightToLbs(value, metric: useMetric), date: entryDate)
    }
}
