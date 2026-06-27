import SwiftUI
import Firebase

struct PostRowView: View {
    @State private var post: CommunityPost
    @State private var showingComments = false

    init(post: CommunityPost) {
        _post = State(initialValue: post)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.author) // Displays the username
                .font(.headline)
            Text(post.content)
                .font(.body)

            HStack {
                Button(action: { toggleLike() }) {
                    HStack {
                        Image(systemName: post.isLikedByCurrentUser ? "hand.thumbsup.fill" : "hand.thumbsup")
                        Text("\(post.likes)")
                    }
                }
                
                Button(action: { showingComments = true }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("\(post.comments.count) Comments")
                    }
                }
            }
            .sheet(isPresented: $showingComments) {
                CommentsView(post: $post)
            }
        }
        .padding()
    }

    private func toggleLike() {
        post.isLikedByCurrentUser.toggle()
        post.likes += post.isLikedByCurrentUser ? 1 : -1
        saveLikeStatusToFirebase()
    }

    private func saveLikeStatusToFirebase() {
        guard let postId = post.id else {
            AppLog.social.warning("Cannot save like status because post ID is missing.")
            return
        }

        let db = Firestore.firestore()
        db.collection(FirestoreCollection.posts).document(postId).updateData([
            "likes": post.likes,
            "isLikedByCurrentUser": post.isLikedByCurrentUser
        ]) { error in
            if let error = error {
                AppLog.social.error("Failed to update like status: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
