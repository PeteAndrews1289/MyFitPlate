import SwiftUI

struct SetWaterGoalView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var waterGoalInput: String
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Daily Water Goal")
                .font(.title)
                .padding(.bottom)

            HStack {
                TextField("Goal (oz)", text: $waterGoalInput)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .frame(width: 150)
                Text("oz")
            }

            Button(action: {
                self.onSave()
            }) {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.top, 16)

            Spacer()
        }
        .padding()
    }
}
