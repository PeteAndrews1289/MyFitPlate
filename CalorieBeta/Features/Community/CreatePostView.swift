import SwiftUI
import FirebaseAuth


struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @State private var content = ""
    let groupID: String
    var onPostCreated: (CommunityPost) -> Void

    var body: some View {
        NavigationView {
            VStack {
                Text("Creating post in group")
                    .font(.headline)
                    .padding()
                
                TextEditor(text: $content)
                    .padding()
                    .border(Color.gray, width: 1)
                    .cornerRadius(8)

                Button("Post") {
                    createPost()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .navigationTitle("New Post")
        }
    }

    private func createPost() {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        Task {
            do {
                if let username = try await DIContainer.shared.postRepository.fetchUserName(userID: userID) {
                    let newPost = CommunityPost(
                        id: UUID().uuidString,
                        authorID: userID,
                        author: username,
                        content: content,
                        likes: 0,
                        isLikedByCurrentUser: false,
                        reactions: [:],
                        comments: [],
                        timestamp: Date(),
                        groupID: groupID
                    )
                    await MainActor.run {
                        onPostCreated(newPost)
                        dismiss()
                    }
                } else {
                    AppLog.social.warning("Username missing for user \(userID, privacy: .private).")
                }
            } catch {
                AppLog.social.error("Failed to fetch username for post creation: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
