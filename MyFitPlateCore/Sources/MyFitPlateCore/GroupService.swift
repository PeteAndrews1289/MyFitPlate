import Foundation

public class GroupService: ObservableObject {
    public init() {}

    // MARK: - Create Group
    public func createGroup(name: String, description: String, creatorID: String, completion: @escaping (Result<CommunityGroup, Error>) -> Void) {
        let groupID = UUID().uuidString
        let newGroup = CommunityGroup(
            id: groupID,
            name: name,
            description: description,
            creatorID: creatorID,
            isPreset: false
        )

        Task {
            do {
                try await DIContainer.shared.groupRepository.createGroup(group: newGroup)
                DispatchQueue.main.async {
                    completion(.success(newGroup))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Fetch All Groups
    public func fetchGroups(completion: @escaping (Result<[CommunityGroup], Error>) -> Void) {
        Task {
            do {
                let groups = try await DIContainer.shared.groupRepository.fetchGroups()
                DispatchQueue.main.async {
                    completion(.success(groups))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Join Group
    public func joinGroup(userID: String, groupID: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await DIContainer.shared.groupRepository.joinGroup(userID: userID, groupID: groupID)
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }

    // MARK: - Leave Group
    public func leaveGroup(userID: String, groupID: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await DIContainer.shared.groupRepository.leaveGroup(userID: userID, groupID: groupID)
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
}
