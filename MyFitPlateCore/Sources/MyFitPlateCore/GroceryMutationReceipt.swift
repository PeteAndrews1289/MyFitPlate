import Foundation

public enum GroceryMutationResolution: String, Codable, Sendable { case pending, accepted, cancelled }

public struct GroceryMutationReceipt: Codable {
    public let schemaVersion: Int
    public let userID: String
    public let operationID: UUID
    public let fingerprint: String
    public let status: GroceryMutationResolution
    public let mutationData: Data?
    public let acceptedAt: Date

    public init(userID: String, mutation: GroceryListMutation, status: GroceryMutationResolution) throws {
        guard !userID.isEmpty, status != .pending else { throw GroceryChecklistError.invalid }
        _ = try mutation.applying(to: mutation.before, checkingConflicts: false)
        schemaVersion = 2; self.userID = userID; operationID = mutation.id
        fingerprint = try mutation.fingerprint; self.status = status
        mutationData = status == .accepted ? try JSONEncoder().encode(mutation) : nil
        acceptedAt = Date()
    }
    public func mutation() throws -> GroceryListMutation {
        guard status == .accepted, let mutationData else { throw GroceryChecklistError.invalid }
        return try JSONDecoder().decode(GroceryListMutation.self, from: mutationData)
    }
    public func validate(userID: String, mutation: GroceryListMutation) throws {
        guard schemaVersion == 2, self.userID == userID, operationID == mutation.id,
              fingerprint == (try mutation.fingerprint), status != .pending else { throw GroceryChecklistError.changed }
        if status == .accepted {
            let saved = try self.mutation()
            guard saved.id == operationID, try saved.fingerprint == fingerprint else { throw GroceryChecklistError.invalid }
        }
    }
}
