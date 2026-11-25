import Foundation
import Combine

public struct DeletedAccountCleanupReceipt: Codable {
    public let version: Int
    public let id: UUID
    public let userID: String
    public var remainingDomains: [String]
}

/// Kept outside EditorDraftStore, since deleting that account's drafts is itself a cleanup step.
public final class DeletedAccountCleanupStore {
    private let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyFitPlate/deleted-account-cleanup")
    }
    public func pending() throws -> [DeletedAccountCleanupReceipt] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { url in
                let receipt = try decode(Data(contentsOf: url))
                guard try path(receipt.userID).lastPathComponent == url.lastPathComponent else { throw CocoaError(.coderReadCorrupt) }
                return receipt
            }
    }
    public func save(_ receipt: DeletedAccountCleanupReceipt) throws {
        let url = try path(receipt.userID)
        if FileManager.default.fileExists(atPath: url.path) { _ = try decode(Data(contentsOf: url)) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }
    public func remove(_ receipt: DeletedAccountCleanupReceipt) throws {
        let url = try path(receipt.userID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func decode(_ data: Data) throws -> DeletedAccountCleanupReceipt {
        let value = try JSONDecoder().decode(DeletedAccountCleanupReceipt.self, from: data)
        guard value.version == 1, !value.userID.isEmpty,
              Set(value.remainingDomains).count == value.remainingDomains.count else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    private func path(_ userID: String) throws -> URL {
        guard let key = AccountScopedStorageKey.make(prefix: "deleted", userID: userID) else { throw CocoaError(.fileWriteInvalidFileName) }
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }
}

@MainActor
public final class DeletedAccountCleanupCoordinator: ObservableObject {
    @Published public private(set) var errorMessage: String?
    private let store: DeletedAccountCleanupStore
    private var volatileReceipts: [String: DeletedAccountCleanupReceipt] = [:]
    public init(store: DeletedAccountCleanupStore = DeletedAccountCleanupStore()) { self.store = store }

    @discardableResult
    public func attempt(for userID: String, domains: [String], operation: (String, String) throws -> Void) -> Bool {
        guard !userID.isEmpty else { return false }
        let fallback = volatileReceipts[userID] ?? DeletedAccountCleanupReceipt(
            version: 1, id: UUID(), userID: userID, remainingDomains: domains
        )
        volatileReceipts[userID] = fallback
        do {
            let saved = try store.pending().first { $0.userID == userID }
            var receipt = saved ?? fallback
            volatileReceipts[userID] = receipt
            // Never begin cleanup while its captured owner/remaining work cannot be retained.
            try store.save(receipt)
            var failed = false
            for domain in receipt.remainingDomains {
                do {
                    try operation(userID, domain)
                    var acknowledged = receipt
                    acknowledged.remainingDomains.removeAll { $0 == domain }
                    try store.save(acknowledged)
                    receipt = acknowledged; volatileReceipts[userID] = acknowledged
                } catch { failed = true }
            }
            if !failed, receipt.remainingDomains.isEmpty {
                try store.remove(receipt)
                volatileReceipts[userID] = nil; errorMessage = nil
                return true
            }
            errorMessage = "Your server account was removed. Some data on this device still needs cleanup; retry safely."
        } catch {
            errorMessage = "Your server account was removed. Local cleanup could not be kept or completed. Keep the app open and retry."
        }
        NotificationCenter.default.post(name: .deletedAccountLocalCleanupNeedsRetry, object: nil)
        return false
    }

    @discardableResult
    public func retryPending(operation: (String, String) throws -> Void) -> Bool {
        do {
            let receipts = try store.pending()
            var owners: [String: [String]] = [:]
            for receipt in receipts {
                guard owners[receipt.userID] == nil else { throw CocoaError(.coderReadCorrupt) }
                owners[receipt.userID] = receipt.remainingDomains
            }
            for (owner, value) in volatileReceipts where owners[owner] == nil { owners[owner] = value.remainingDomains }
            var succeeded = true
            var lastFailure: String?
            for (owner, domains) in owners.prefix(25) where !attempt(for: owner, domains: domains, operation: operation) {
                succeeded = false
                lastFailure = errorMessage
            }
            if owners.count > 25 { succeeded = false; lastFailure = "More local cleanup is pending. Retry to continue." }
            errorMessage = succeeded ? nil : (lastFailure ?? "Some data on this device still needs cleanup; retry safely.")
            return succeeded
        } catch {
            errorMessage = "A local cleanup receipt could not be opened. It has been kept on this device."
            NotificationCenter.default.post(name: .deletedAccountLocalCleanupNeedsRetry, object: nil)
            return false
        }
    }
}

public extension Notification.Name {
    static let deletedAccountLocalCleanupNeedsRetry = Notification.Name("MyFitPlate.DeletedAccountLocalCleanupNeedsRetry")
}
