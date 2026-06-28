import Foundation
import Combine

protocol PostRepositoryProtocol: Sendable {
    func fetchPostsForGroup(groupID: String) -> AnyPublisher<[CommunityPost], Error>
    func savePost(post: CommunityPost) async throws
    func updatePostComments(postId: String, comments: [CommunityPost.Comment]) async throws
    func updatePostLikes(postId: String, likes: Int, isLikedByCurrentUser: Bool) async throws
    func fetchUserName(userID: String) async throws -> String?
}
