import SwiftUI

struct SetWaterGoalView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var waterGoalInput: String
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Daily Water Goal")
                .appFont(size: 28, weight: .bold)
                .padding(.bottom)

            HStack {
                TextField("Goal (oz)", text: $waterGoalInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(AppTextFieldStyle(iconName: nil))
                    .frame(width: 150)
                Text("oz")
                    .appFont(size: 17)
            }

            Button("Save") {
                self.onSave()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding()

            Spacer()
        }
        .padding()
    }
}
