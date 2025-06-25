import SwiftUI
import FirebaseAuth
import Firebase

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
        let db = Firestore.firestore()

        db.collection("users").document(userID).getDocument { document, error in
            if let error = error {
                print("Error fetching username: \(error.localizedDescription)")
                return
            }

            if let document = document, let data = document.data(), let username = data["username"] as? String {
                let newPost = CommunityPost(
                    id: UUID().uuidString,
                    author: username,
                    content: content,
                    likes: 0,
                    isLikedByCurrentUser: false,
                    reactions: [:],
                    comments: [],
                    timestamp: Date(),
                    groupID: groupID
                )
                onPostCreated(newPost)
                dismiss()
            } else {
                print("Username not found for user \(userID).")
            }
        }
    }
}
