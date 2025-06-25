import SwiftUI
import FirebaseAuth

struct CreateGroupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var groupService: GroupService
    @State private var groupName = ""
    @State private var groupDescription = ""
    var onGroupCreated: (CommunityGroup) -> Void

    var body: some View {
        VStack {
            TextField("Group Name", text: $groupName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            TextField("Group Description", text: $groupDescription)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            Button("Create Group") {
                createGroup()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .navigationTitle("New Group")
    }

    private func createGroup() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        groupService.createGroup(name: groupName, description: groupDescription, creatorID: userID) { result in
            switch result {
            case .success(let newGroup):
                onGroupCreated(newGroup)
                dismiss()
            case .failure(let error):
                print("Error creating group: \(error.localizedDescription)")
            }
        }
    }
}
