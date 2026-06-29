import Foundation
import MyFitPlateCore
import FirebaseFirestore
import OSLog

final class FirestoreGroupRepository: GroupRepositoryProtocol, @unchecked Sendable {
    private let db = Firestore.firestore()
    
    func createGroup(group: CommunityGroup) async throws {
        let groupData: [String: Any] = [
            "id": group.id ?? "",
            "name": group.name,
            "description": group.description,
            "creatorID": group.creatorID,
            "isPreset": group.isPreset
        ]
        
        let groupID = group.id ?? UUID().uuidString
        try await db.collection(FirestoreCollection.groups).document(groupID).setData(groupData)
    }
    
    func fetchGroups() async throws -> [CommunityGroup] {
        let snapshot = try await db.collection(FirestoreCollection.groups).getDocuments()
        return snapshot.documents.compactMap { document in
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
        }
    }
    
    func joinGroup(userID: String, groupID: String) async throws {
        let membershipID = "\(userID)_\(groupID)"
        let membershipData: [String: Any] = [
            "userID": userID,
            "groupID": groupID,
            "joinedAt": Timestamp(date: Date())
        ]
        try await db.collection(FirestoreCollection.groupMemberships).document(membershipID).setData(membershipData)
    }
    
    func leaveGroup(userID: String, groupID: String) async throws {
        let membershipID = "\(userID)_\(groupID)"
        try await db.collection(FirestoreCollection.groupMemberships).document(membershipID).delete()
    }
    
    func checkGroupMembership(userID: String, groupID: String) async throws -> Bool {
        let membershipID = "\(userID)_\(groupID)"
        let doc = try await db.collection(FirestoreCollection.groupMemberships).document(membershipID).getDocument()
        return doc.exists
    }
}
