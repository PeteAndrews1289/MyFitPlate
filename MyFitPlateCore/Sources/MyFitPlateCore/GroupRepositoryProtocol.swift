import Foundation

public protocol GroupRepositoryProtocol: Sendable {
    func createGroup(group: CommunityGroup) async throws
    func fetchGroups() async throws -> [CommunityGroup]
    func joinGroup(userID: String, groupID: String) async throws
    func leaveGroup(userID: String, groupID: String) async throws
    func checkGroupMembership(userID: String, groupID: String) async throws -> Bool
}
