import Foundation

public struct LibraryMutationReceipt: Codable, Sendable {
    public let schemaVersion: Int
    public let userID: String
    public let operationID: UUID
    public let kind: String
    public let fingerprint: String
    public let status: String
    public let operationData: Data?
    public let recordedAt: Date

    public init(userID: String, operation: LibraryOperation, accepted: Bool) throws {
        guard !userID.isEmpty else { throw LibraryMutationError.accountChanged }
        try operation.validate()
        schemaVersion = 1; self.userID = userID; operationID = operation.id
        kind = Self.kind(of: operation); fingerprint = try Self.fingerprint(of: operation)
        status = accepted ? "accepted" : "cancelled"
        operationData = accepted ? try JSONEncoder().encode(operation) : nil
        recordedAt = Date()
    }

    public var operation: LibraryOperation? { operationData.flatMap { try? JSONDecoder().decode(LibraryOperation.self, from: $0) } }

    public func validate(userID: String, operation: LibraryOperation) throws {
        guard schemaVersion == 1, self.userID == userID, operationID == operation.id,
              kind == Self.kind(of: operation), fingerprint == (try Self.fingerprint(of: operation)),
              ["accepted", "cancelled"].contains(status), (status == "accepted") == (operationData != nil) else {
            throw LibraryMutationError.changed
        }
        if status == "accepted" {
            guard let saved = self.operation, saved.id == operationID,
                  try Self.fingerprint(of: saved) == fingerprint else { throw LibraryMutationError.invalid }
        }
    }

    public static func kind(of operation: LibraryOperation) -> String {
        switch operation {
        case .recipes: "recipes"
        case .foods: "foods"
        }
    }
    public static func fingerprint(of operation: LibraryOperation) throws -> String {
        switch operation {
        case .recipes(let value): try value.fingerprint
        case .foods(let value): try value.fingerprint
        }
    }

    public static func validateInverse(_ operation: LibraryOperation, original: LibraryOperation) throws {
        guard operation.undoingID == original.id, operation.id != original.id else { throw LibraryMutationError.invalid }
        switch (operation, original.inverse()) {
        case let (.recipes(proposed), .recipes(expected)):
            func snapshots(_ recipes: [Recipe]) throws -> [String] {
                try recipes.sorted { ($0.id ?? "") < ($1.id ?? "") }.map(RecipeLibraryMutation.snapshotFingerprint)
            }
            guard try snapshots(proposed.before) == snapshots(expected.before),
                  try snapshots(proposed.after) == snapshots(expected.after) else { throw LibraryMutationError.changed }
        case let (.foods(proposed), .foods(expected)):
            func snapshots(_ foods: [FoodItem]) throws -> [String] {
                try foods.sorted { $0.id < $1.id }.map { try SavedFoodLibraryMutation.snapshotFingerprint($0) }
            }
            guard proposed.removedIDs == expected.removedIDs,
                  try snapshots(proposed.before) == snapshots(expected.before),
                  try snapshots(proposed.upserts) == snapshots(expected.upserts) else { throw LibraryMutationError.changed }
        default: throw LibraryMutationError.changed
        }
    }
}
