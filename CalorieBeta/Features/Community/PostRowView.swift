import SwiftUI

struct PostRowView: View {
    @State private var post: CommunityPost
    @State private var showingComments = false

    init(post: CommunityPost) {
        _post = State(initialValue: post)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CachedAsyncImage(url: URL(string: "https://i.pravatar.cc/150?u=\(post.author)")) { image in
                    image.resizable()
                         .aspectRatio(contentMode: .fill)
                         .frame(width: 40, height: 40)
                         .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
                }

                Text(post.author) // Displays the username
                    .font(.headline)
            }
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
        HapticsService.shared.playImpact(style: .medium)
        post.isLikedByCurrentUser.toggle()
        post.likes += post.isLikedByCurrentUser ? 1 : -1
        saveLikeStatusToFirebase()
    }

    private func saveLikeStatusToFirebase() {
        guard let postId = post.id else {
            AppLog.social.warning("Cannot save like status because post ID is missing.")
            return
        }

        Task {
            do {
                try await DIContainer.shared.postRepository.updatePostLikes(postId: postId, likes: post.likes, isLikedByCurrentUser: post.isLikedByCurrentUser)
            } catch {
                AppLog.social.error("Failed to update like status: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
