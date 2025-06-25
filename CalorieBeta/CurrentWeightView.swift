import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CurrentWeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @State private var weight = ""
    @Environment(\.dismiss) var dismiss

    // Define the accent color using the values from your assets
    private let accentGreen = Color(red: 0.263, green: 0.679, blue: 0.436)

    var body: some View {
        Form {
            Section(header: Text("Current Weight")) {
                TextField("Enter your weight (lbs)", text: $weight)
                    .keyboardType(.decimalPad)
            }

            Button(action: {
                saveWeight()
                dismiss()
            }) {
                Text("Save Weight")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(accentGreen) // Use the defined accentGreen
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top)
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
