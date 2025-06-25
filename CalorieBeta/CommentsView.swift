import SwiftUI
import Firebase

struct CommentsView: View {
    @Binding var post: CommunityPost
    @State private var newCommentText = ""

    var body: some View {
        VStack {
            List(post.comments) { comment in
                VStack(alignment: .leading) {
                    Text(comment.author)
                        .font(.headline)
                    Text(comment.content)
                        .font(.subheadline)
                }
            }

            HStack {
                TextField("Add a comment...", text: $newCommentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Post") {
                    addComment()
                }
            }
            .padding()
        }
        .navigationTitle("Comments")
    }

    private func addComment() {
        let newComment = CommunityPost.Comment(author: "User", content: newCommentText)
        post.comments.append(newComment)
        newCommentText = ""
        saveCommentToFirebase(comment: newComment)
    }

    private func saveCommentToFirebase(comment: CommunityPost.Comment) {
        guard let postId = post.id else {
            print("Post ID is nil; cannot save comment.")
            return
        }

        let db = Firestore.firestore()
        db.collection("posts").document(postId).updateData([
            "comments": post.comments.map { try? Firestore.Encoder().encode($0) }
        ]) { error in
            if let error = error {
                print("Error saving comment: \(error)")
            }
        }
    }
}

