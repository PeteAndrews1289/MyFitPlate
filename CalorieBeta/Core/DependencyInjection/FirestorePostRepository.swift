import Foundation
import FirebaseFirestore
import Combine

final class FirestorePostRepository: PostRepositoryProtocol, @unchecked Sendable {
    private let db = Firestore.firestore()

    func fetchPostsForGroup(groupID: String) -> AnyPublisher<[CommunityPost], Error> {
        let subject = PassthroughSubject<[CommunityPost], Error>()
        
        let listener = db.collection(FirestoreCollection.posts)
            .whereField("groupID", isEqualTo: groupID)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    subject.send(completion: .failure(error))
                    return
                }
                
                guard let docs = snapshot?.documents else {
                    subject.send([])
                    return
                }
                
                let posts = docs.compactMap { try? $0.data(as: CommunityPost.self) }
                subject.send(posts)
            }
            
        return subject.handleEvents(receiveCancel: {
            listener.remove()
        }).eraseToAnyPublisher()
    }

    func savePost(post: CommunityPost) async throws {
        guard let postId = post.id else { return }
        try db.collection(FirestoreCollection.posts).document(postId).setData(from: post)
    }

    func updatePostComments(postId: String, comments: [CommunityPost.Comment]) async throws {
        let encoder = Firestore.Encoder()
        let encodedComments = comments.compactMap { try? encoder.encode($0) }
        try await db.collection(FirestoreCollection.posts).document(postId).updateData([
            "comments": encodedComments
        ])
    }

    func updatePostLikes(postId: String, likes: Int, isLikedByCurrentUser: Bool) async throws {
        try await db.collection(FirestoreCollection.posts).document(postId).updateData([
            "likes": likes,
            "isLikedByCurrentUser": isLikedByCurrentUser
        ])
    }

    func fetchUserName(userID: String) async throws -> String? {
        let doc = try await db.collection(FirestoreCollection.users).document(userID).getDocument()
        return doc.data()?["username"] as? String
    }
}
