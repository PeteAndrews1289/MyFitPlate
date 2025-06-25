import SwiftUI

struct JoinGroupConfirmationView: View {
    var group: CommunityGroup
    var onJoin: (CommunityGroup) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Join \(group.name)?")
                .font(.title)
                .padding()

            Text(group.description)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                
                Button("Join") {
                    onJoin(group)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
