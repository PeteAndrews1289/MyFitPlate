import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CurrentWeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @State private var weight = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("Current Weight")) {
                TextField("Enter your weight (lbs)", text: $weight)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(AppTextFieldStyle(iconName: nil))
            }

            Button("Save Weight") {
                saveWeight()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Current Weight")
        .onAppear {
            weight = String(format: "%.1f", goalSettings.weight)
        }
    }

    private func saveWeight() {
        guard let weightValue = Double(weight), weightValue > 0 else { return }
        goalSettings.updateUserWeight(weightValue)
    }
}
