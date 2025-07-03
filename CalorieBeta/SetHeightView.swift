import SwiftUI

struct SetHeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var feetInput: String
    @Binding var inchesInput: String
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter Your Height")
                .appFont(size: 28, weight: .bold)
                .padding(.bottom)

            HStack {
                VStack {
                    TextField("Feet", text: $feetInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(AppTextFieldStyle(iconName: nil))
                        .frame(width: 100)
                }
                Text("'")
                    .appFont(size: 28, weight: .semibold)
                VStack {
                    TextField("Inches", text: $inchesInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(AppTextFieldStyle(iconName: nil))
                        .frame(width: 100)
                }
                Text("\"")
                    .appFont(size: 28, weight: .semibold)
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
