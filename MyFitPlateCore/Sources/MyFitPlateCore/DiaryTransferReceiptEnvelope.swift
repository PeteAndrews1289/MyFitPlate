import Foundation

/// Firestore's Date/Timestamp bridge is not a lossless round trip for every Double
/// date. Keep the immutable command and full snapshot receipt as opaque JSON bytes;
/// the small outer envelope contains only exact scalar identity/version fields.
public struct DiaryTransferReceiptEnvelope: Codable {
    public enum Kind: String, Codable { case accepted, cancelled }
    public let schemaVersion: Int
    public let userID: String
    public let operationID: UUID
    public let commandFingerprint: String
    public let kind: Kind
    public let payload: Data

    public init(receipt: DiaryTransferReceipt) throws {
        try receipt.validate()
        schemaVersion = 1; userID = receipt.command.userID; operationID = receipt.id
        commandFingerprint = receipt.commandFingerprint; kind = .accepted
        payload = try JSONEncoder().encode(receipt)
    }

    public init(cancellation: DiaryTransferCancellation) throws {
        try cancellation.validate(for: cancellation.command)
        schemaVersion = 1; userID = cancellation.command.userID; operationID = cancellation.command.id
        commandFingerprint = cancellation.commandFingerprint; kind = .cancelled
        payload = try JSONEncoder().encode(cancellation)
    }

    public func receipt(matching command: DiaryTransferCommand) throws -> DiaryTransferReceipt {
        try validateIdentity(command)
        guard kind == .accepted else { throw DiaryTransferError.cancelled }
        let receipt = try JSONDecoder().decode(DiaryTransferReceipt.self, from: payload)
        try receipt.validate()
        guard receipt.id == operationID, receipt.command.userID == userID,
              receipt.commandFingerprint == commandFingerprint else { throw DiaryTransferError.receiptMismatch }
        return receipt
    }

    public func cancellation(matching command: DiaryTransferCommand) throws -> DiaryTransferCancellation {
        try validateIdentity(command)
        guard kind == .cancelled else { throw DiaryTransferError.receiptMismatch }
        let cancellation = try JSONDecoder().decode(DiaryTransferCancellation.self, from: payload)
        try cancellation.validate(for: command)
        return cancellation
    }

    private func validateIdentity(_ command: DiaryTransferCommand) throws {
        try command.validate()
        guard schemaVersion == 1, userID == command.userID, operationID == command.id,
              commandFingerprint == (try command.fingerprint()), payload.count <= 500_000 else {
            throw DiaryTransferError.receiptMismatch
        }
    }
}
