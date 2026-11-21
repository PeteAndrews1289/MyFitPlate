import Foundation
import MyFitPlateCore
import FirebaseAuth
import FirebaseFirestore

/// Each immutable item revision is its own document. Only the small per-item head
/// list is transactional; no ever-growing library/history blob is rewritten.
final class FirestoreRunCloudRepository: RunCloudRepository {
    private let db: Firestore
    private let currentOwner: () -> String?
    init(db: Firestore = .firestore(), currentOwner: @escaping () -> String? = { Auth.auth().currentUser?.uid }) {
        self.db = db; self.currentOwner = currentOwner
    }
    private func check(_ userID: String) throws {
        guard !userID.isEmpty, currentOwner() == userID else { throw RunCloudError.accountChanged }
    }
    func fetch(userID: String, scope: RunCloudScope) async throws -> [RunCloudRevision] {
        try check(userID)
        let base = db.collection("users").document(userID).collection("runLibraryRevisions")
            .whereField("scope", isEqualTo: scope.rawValue).order(by: FieldPath.documentID()).limit(to: 300)
        var query: Query = base, values: [RunCloudRevision] = []
        while true {
            let page = try await query.getDocuments(source: .server)
            try check(userID)
            for document in page.documents {
                let value = try document.data(as: RunCloudRevision.self)
                guard value.id == document.documentID else { throw RunCloudError.invalid }
                try value.validate(ownerID: userID, scope: scope); values.append(value)
            }
            guard page.documents.count == 300, let last = page.documents.last else { break }
            query = base.start(afterDocument: last)
        }
        _ = try RunCloudGraph.validated(values, ownerID: userID, scope: scope)
        return values
    }
    func publish(_ revision: RunCloudRevision) async throws {
        try check(revision.ownerID); try revision.validate(ownerID: revision.ownerID, scope: revision.scope)
        let owner = db.collection("users").document(revision.ownerID)
        let collection = owner.collection("runLibraryRevisions")
        let reference = collection.document(revision.id)
        let headID = try PlanFingerprint.make([revision.scope.rawValue, revision.key])
        let head = owner.collection("runLibraryHeads").document(headID)
        _ = try await db.runTransaction { [self] transaction, pointer -> Any? in
            do {
                try check(revision.ownerID)
                let existing = try transaction.getDocument(reference)
                let current = try transaction.getDocument(head)
                for id in revision.parents {
                    let snapshot = try transaction.getDocument(collection.document(id))
                    guard snapshot.exists else { throw RunCloudError.invalid }
                    let parent = try snapshot.data(as: RunCloudRevision.self)
                    try parent.validate(ownerID: revision.ownerID, scope: revision.scope)
                    guard parent.id == id, parent.key == revision.key else { throw RunCloudError.invalid }
                    if revision.key.hasPrefix("receipt/") || revision.key.hasPrefix("revision/") || revision.key.hasPrefix("abandoned/") {
                        guard parent.payload == revision.payload else { throw RunCloudError.protectedEvidence }
                    }
                }
                var heads: [String] = []
                if current.exists {
                    guard let data = current.data(), data["ownerID"] as? String == revision.ownerID,
                          data["scope"] as? String == revision.scope.rawValue, data["key"] as? String == revision.key,
                          let saved = data["heads"] as? [String], Set(saved).count == saved.count,
                          !saved.isEmpty else { throw RunCloudError.invalid }
                    heads = saved
                }
                if existing.exists {
                    guard try existing.data(as: RunCloudRevision.self) == revision, current.exists else { throw RunCloudError.invalid }
                    return true // Already committed; do not resurrect an ancestor head.
                }
                heads = Array(Set(heads).subtracting(revision.parents).union([revision.id])).sorted()
                guard heads.count <= 32 else { throw RunCloudError.invalid }
                let data = try Firestore.Encoder().encode(revision)
                try check(revision.ownerID)
                transaction.setData(data, forDocument: reference)
                transaction.setData(["ownerID": revision.ownerID, "scope": revision.scope.rawValue,
                    "key": revision.key, "heads": heads, "version": 1], forDocument: head)
                return true
            } catch { pointer?.pointee = error as NSError; return nil }
        }
        try check(revision.ownerID)
    }
}
