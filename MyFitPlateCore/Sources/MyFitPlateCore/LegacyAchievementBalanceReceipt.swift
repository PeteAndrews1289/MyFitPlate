import Foundation

/// A migration opening balance, not an award. It freezes the aggregate that existed
/// before this migration and never adds it to the profile again. Some of these points
/// may already have individual receipts; no missing event-level history is invented.
public struct LegacyAchievementBalanceReceipt: Codable, Equatable, Identifiable {
    public static let migrationID = "aggregate-opening-balance-v1"
    public let id: String
    public let ownerID: String
    public let openingPoints: Int
    public let capturedAt: Date
    public let schemaVersion: Int
    public init(ownerID: String, openingPoints: Int, capturedAt: Date = Date()) {
        id = Self.migrationID; self.ownerID = ownerID; self.openingPoints = openingPoints
        self.capturedAt = capturedAt; schemaVersion = 1
    }
    public func validate(ownerID: String) throws {
        guard self.ownerID == ownerID, !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              id == Self.migrationID, schemaVersion == 1, openingPoints >= 0,
              capturedAt.timeIntervalSince1970.isFinite else { throw AchievementAwardError.invalid }
    }
    public static func preserving(_ existing: Self?, ownerID: String, profilePoints: Int,
                                  now: Date = Date()) throws -> Self {
        guard profilePoints >= 0 else { throw AchievementAwardError.invalid }
        if let existing { try existing.validate(ownerID: ownerID); return existing }
        let receipt = Self(ownerID: ownerID, openingPoints: profilePoints, capturedAt: now)
        try receipt.validate(ownerID: ownerID)
        return receipt
    }
    public var explanation: String {
        "\(openingPoints.formatted()) points carried forward on \(capturedAt.formatted(date: .abbreviated, time: .omitted)). This immutable opening-balance receipt adds no points. Earlier points may include individually recorded awards; missing source history is not reconstructed."
    }
}
