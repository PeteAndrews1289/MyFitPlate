import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CurrentWeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @State private var weight = ""
    @State private var entryDate = Date()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("Weight")) {
                TextField("Enter your weight (lbs)", text: $weight)
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
            weight = String(format: "%.1f", goalSettings.weight)
        }
    }

    private func saveWeight() {
        guard let weightValue = Double(weight), weightValue > 0 else { return }
        goalSettings.updateUserWeight(weightValue, date: entryDate)
    }
}
