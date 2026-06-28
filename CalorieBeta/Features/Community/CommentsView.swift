import SwiftUI


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
            AppLog.social.warning("Cannot save comment because post ID is missing.")
            return
        }

        Task {
            do {
                try await DIContainer.shared.postRepository.updatePostComments(postId: postId, comments: post.comments)
            } catch {
                AppLog.social.error("Failed to save comment: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
