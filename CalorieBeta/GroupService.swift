import Foundation
import FirebaseFirestore
import FirebaseAuth



class GroupService: ObservableObject {
    private let db = Firestore.firestore()

    // MARK: - Create Group
    func createGroup(name: String, description: String, creatorID: String, completion: @escaping (Result<CommunityGroup, Error>) -> Void) {
        let groupID = UUID().uuidString
        let newGroup = CommunityGroup(
            id: groupID,
            name: name,
            description: description,
            creatorID: creatorID,
            isPreset: false
        )

        // Prepare Firestore document data
        let groupData: [String: Any] = [
            "id": newGroup.id,
            "name": newGroup.name,
            "description": newGroup.description,
            "creatorID": newGroup.creatorID,
            "isPreset": newGroup.isPreset
        ]

        // Save the new group document to Firestore
        db.collection("groups").document(groupID).setData(groupData) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(newGroup))
            }
        }
    }

    // MARK: - Fetch All Groups
    func fetchGroups(completion: @escaping (Result<[CommunityGroup], Error>) -> Void) {
        db.collection("groups").getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let groups: [CommunityGroup] = snapshot?.documents.compactMap { document in
                let data = document.data()
                guard let id = data["id"] as? String,
                      let name = data["name"] as? String,
                      let description = data["description"] as? String,
                      let creatorID = data["creatorID"] as? String,
                      let isPreset = data["isPreset"] as? Bool else {
                    return nil
                }
                return CommunityGroup(
                    id: id,
                    name: name,
                    description: description,
                    creatorID: creatorID,
                    isPreset: isPreset
                )
            } ?? []

            completion(.success(groups))
        }
    }

    // MARK: - Join Group
    func joinGroup(userID: String, groupID: String, completion: @escaping (Error?) -> Void) {
        let membershipID = "\(userID)_\(groupID)"
        let membershipData: [String: Any] = [
            "userID": userID,
            "groupID": groupID,
            "joinedAt": Timestamp(date: Date())
        ]

        db.collection("groupMemberships").document(membershipID).setData(membershipData) { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Leave Group
    func leaveGroup(userID: String, groupID: String, completion: @escaping (Error?) -> Void) {
        let membershipID = "\(userID)_\(groupID)"
        db.collection("groupMemberships").document(membershipID).delete { error in
            completion(error)
        }
    }
}
