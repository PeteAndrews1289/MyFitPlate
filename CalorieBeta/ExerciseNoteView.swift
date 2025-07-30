
import SwiftUI

struct ExerciseNoteView: View {
    @Binding var note: String
    @Binding var isPinned: Bool
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Exercise Note")
                .appFont(size: 20, weight: .bold)

            TextEditor(text: $note)
                .frame(height: 150)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )

            Toggle(isOn: $isPinned) {
                Label("Pin this note for future workouts", systemImage: "pin.fill")
            }
            .tint(.brandPrimary)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())

                Button("OK", action: onSave)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(40)
    }
}
