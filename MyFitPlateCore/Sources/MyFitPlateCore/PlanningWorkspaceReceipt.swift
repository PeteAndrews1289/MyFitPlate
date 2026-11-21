import Foundation

/// Permanent accepted payload, independent from the document's later edits or deletion.
public struct PlanningWorkspaceReceipt<Value: PlanningWorkspaceDocument>: Codable {
    public let userID: String
    public let operationID: UUID
    public let documentID: String
    public let fingerprint: String
    public let resolution: PlanningDocumentSaveResolution
    public let accepted: Value?

    public init(proposal: PlanningDocumentProposal<Value>, resolution: PlanningDocumentSaveResolution) throws {
        if resolution == .accepted { try proposal.validate() } else { try proposal.validateEnvelope() }
        userID = proposal.userID; operationID = proposal.operationID; documentID = proposal.updated.id
        fingerprint = try proposal.fingerprint(); self.resolution = resolution
        accepted = resolution == .accepted ? try PlanningDocumentRules.canonicalized(proposal.updated) : nil
    }

    public func validate(proposal: PlanningDocumentProposal<Value>) throws {
        guard userID == proposal.userID, operationID == proposal.operationID, documentID == proposal.updated.id,
              fingerprint == (try proposal.fingerprint()), resolution != .pending,
              (resolution == .accepted) == (accepted != nil) else { throw MealPlanChangeReceiptError.changed }
        if let accepted {
            guard try PlanningDocumentRules.fingerprint(accepted) == PlanningDocumentRules.fingerprint(proposal.updated) else {
                throw MealPlanChangeReceiptError.changed
            }
        }
    }
}
