import CryptoKit
import Foundation

public struct SavedEditorDraft<Value: Codable>: Codable {
    public let version: Int
    public let updatedAt: Date
    public let value: Value
}

/// Local, account-scoped editing checkpoints. Saving a draft never publishes a cloud change.
public final class EditorDraftStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyFitPlate/editor-drafts")
    }

    public func load<Value: Codable>(
        _ type: Value.Type, userID: String, scope: String
    ) throws -> SavedEditorDraft<Value>? {
        let url = try fileURL(userID: userID, scope: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let saved = try JSONDecoder().decode(SavedEditorDraft<Value>.self, from: Data(contentsOf: url))
        guard saved.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return saved
    }

    public func save<Value: Codable>(
        _ value: Value, userID: String, scope: String, now: Date = Date()
    ) throws {
        // Do not overwrite an unreadable or newer-format checkpoint on an automatic save.
        _ = try load(Value.self, userID: userID, scope: scope)
        let url = try fileURL(userID: userID, scope: scope)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saved = SavedEditorDraft(version: 1, updatedAt: now, value: value)
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
    }

    public func remove(userID: String, scope: String) throws {
        let url = try fileURL(userID: userID, scope: scope)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Local editor cleanup must match the exact frozen checkpoint, never just its scope.
    /// A newer draft remains available even when an older asynchronous save finishes.
    @discardableResult
    public func removeIfUnchanged<Value: Codable>(
        _ type: Value.Type, userID: String, scope: String, fingerprint: String
    ) throws -> Bool {
        guard let saved = try load(type, userID: userID, scope: scope),
              try PlanFingerprint.make(saved.value) == fingerprint else { return false }
        try remove(userID: userID, scope: scope)
        return true
    }

    public func removeAll(userID: String) throws {
        let folder = try accountDirectory(userID: userID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    /// Inventory one checkpoint type in one account. A decoded value is returned only
    /// when its claimed scope matches the actual hashed filename. Unrelated, unreadable,
    /// newer-format and mismatched records are left untouched.
    public func valuesMatchingScope<Value: Codable>(
        _ type: Value.Type, userID: String, scopeForValue: (Value) -> String
    ) throws -> [Value] {
        let folder = try accountDirectory(userID: userID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return files.compactMap { file in
            guard file.pathExtension == "json",
                  let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let data = try? Data(contentsOf: file),
                  let saved = try? JSONDecoder().decode(SavedEditorDraft<Value>.self, from: data), saved.version == 1,
                  let expected = try? fileURL(userID: userID, scope: scopeForValue(saved.value)),
                  expected.standardizedFileURL == file.standardizedFileURL else { return nil }
            return saved.value
        }
    }

    private func fileURL(userID: String, scope: String) throws -> URL {
        guard !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return try accountDirectory(userID: userID).appendingPathComponent(digest).appendingPathExtension("json")
    }

    private func accountDirectory(userID: String) throws -> URL {
        guard let key = AccountScopedStorageKey.make(prefix: "editor", userID: userID) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return directory.appendingPathComponent(key, isDirectory: true)
    }
}
