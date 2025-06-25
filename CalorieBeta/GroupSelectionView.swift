import SwiftUI

struct GroupSelectionView: View {
    @Binding var groups: [CommunityGroup]
    @Binding var selectedGroup: CommunityGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(groups) { group in
                    Button(action: {
                        selectedGroup = group
                    }) {
                        Text(group.name)
                            .padding(10)
                            .background(selectedGroup?.id == group.id ? Color.blue : Color.gray.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
    }
}
