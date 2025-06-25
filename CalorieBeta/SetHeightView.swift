import SwiftUI

struct SetHeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var feetInput: String
    @Binding var inchesInput: String
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter Your Height")
                .font(.title)
                .padding(.bottom)

            HStack {
                VStack {
                    TextField("Feet", text: $feetInput)
                        .keyboardType(.numberPad)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .frame(width: 100)
                }
                Text("'")
                VStack {
                    TextField("Inches", text: $inchesInput)
                        .keyboardType(.numberPad)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .frame(width: 100)
                }
                Text("\"")
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
