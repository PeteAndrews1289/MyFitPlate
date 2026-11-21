import Foundation

public enum MealPlanChangeReceiptError: Int, Error, LocalizedError, CustomNSError {
    case invalid = 400
    case accountChanged = 401
    case changed = 409
    case cancelled = 410
    case unavailable = 503

    public static var errorDomain: String { "MyFitPlate.MealPlanChangeReceipt" }
    public var errorCode: Int { rawValue }
    public var errorDescription: String? {
        switch self {
        case .invalid: "This saved meal proposal could not be read. Its draft has been kept."
        case .accountChanged: "Return to the account that opened this meal plan before continuing."
        case .changed: "This save identity belongs to a different meal proposal. Its draft has been kept."
        case .cancelled: "This pending meal change was cancelled. It cannot change your plans."
        case .unavailable: "This meal change could not be confirmed. Keep its draft and try again."
        }
    }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "The meal change could not be confirmed."] }
}

public enum MealPlanChangeResolution: Equatable, Sendable {
    case pending
    case accepted
    case cancelled
}

/// Permanent remote acceptance/cancellation evidence. A replay never reapplies an
/// old proposal over later edits; the fingerprint covers the exact frozen payload.
public struct MealPlanChangeReceipt: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case accepted, cancelled }
    public let schemaVersion: Int
    public let userID: String
    public let operationID: UUID
    public let fingerprint: String
    public let status: Status
    /// Older receipts remain valid; only new accepted operations have a browsable snapshot.
    public let changeData: Data?
    public let recordedAt: Date?
    public var change: MealPlanChange? { changeData.flatMap { try? JSONDecoder().decode(MealPlanChange.self, from: $0) } }

    public init(userID: String, change: MealPlanChange, status: Status) throws {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MealPlanChangeReceiptError.accountChanged }
        schemaVersion = 1
        self.userID = userID; operationID = change.id
        fingerprint = try Self.commandFingerprint(userID: userID, change: change)
        self.status = status
        changeData = status == .accepted ? try JSONEncoder().encode(change) : nil
        recordedAt = Date()
    }

    /// Recovery identifies the frozen command without reinterpreting its calendar dates.
    public static func validateEnvelope(userID: String, change: MealPlanChange) throws {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MealPlanChangeReceiptError.accountChanged
        }
        guard !change.before.isEmpty, change.before.count <= 14, change.after.count == change.before.count,
              Set(change.before.map(\.id)).count == change.before.count,
              Set(change.before.map(\.id)) == Set(change.after.map(\.id)),
              (change.before + change.after).allSatisfy({ !$0.id.isEmpty && !$0.id.contains("/") && $0.date.timeIntervalSince1970.isFinite }),
              try JSONEncoder().encode(change).count <= 750_000 else { throw MealPlanChangeReceiptError.invalid }
    }

    public static func commandFingerprint(userID: String, change: MealPlanChange) throws -> String {
        struct Intent: Encodable {
            let schemaVersion = 1
            let userID: String
            let change: MealPlanChange
        }
        return try PlanFingerprint.make(Intent(userID: userID, change: change))
    }

    public func validate(userID: String, change: MealPlanChange) throws {
        guard schemaVersion == 1, self.userID == userID, operationID == change.id,
              try fingerprint == Self.commandFingerprint(userID: userID, change: change) else {
            throw MealPlanChangeReceiptError.changed
        }
    }

    public var resolution: MealPlanChangeResolution { status == .accepted ? .accepted : .cancelled }
}

/// Shared transaction preconditions. The live repository applies these to the
/// documents it actually reads inside the deletion transaction, not cached plans.
public enum MealPlanDiscardRules {
    public static func validate(plans: [MealPlanDay], deleting dateStrings: Set<String>) throws {
        guard !dateStrings.isEmpty, dateStrings.count <= 400,
              dateStrings.allSatisfy({ $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }) else {
            throw MealPlanEditError.invalid
        }
        for batch in plans.flatMap(\.meals).compactMap(\.cookingBatch) {
            guard Set(batch.allocations.map { MealPlanEditingRules.dayID($0.date) }).isSubset(of: dateStrings) else {
                throw MealCookingError.linkedBatch
            }
        }
    }

    public static func removes(_ item: GroceryListItem, deleting dateStrings: Set<String>) -> Bool {
        guard item.source == "mealPlan" else { return false }
        // Legacy generated rows without a window have no narrower provenance.
        guard let start = item.sourcePlanStart else { return true }
        return dateStrings.contains(MealPlanEditingRules.dayID(start))
    }
}
