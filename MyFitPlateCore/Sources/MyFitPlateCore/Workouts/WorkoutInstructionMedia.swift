import CryptoKit
import Foundation

public struct WorkoutInstructionMedia: Codable, Identifiable {
    public enum Permission: String, Codable, CaseIterable, Identifiable {
        case ownerRecording, licensed, permissionGranted
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .ownerRecording: "I made this recording"
            case .licensed: "I hold a license for this use"
            case .permissionGranted: "The owner granted permission"
            }
        }
    }
    public var id: String
    public var version: Int
    public var movementKey: String
    public var filename: String
    public var contentSHA256: String
    public var attribution: String
    public var permission: Permission
    public var permissionNotes: String
    public var captionTranscript: String
    public var importedAt: Date
}

/// Account-owned offline assets. No external URL or fabricated demo is claimed by this library.
@MainActor public final class WorkoutInstructionMediaStore {
    private let drafts: EditorDraftStore
    private let root: URL
    public init(drafts: EditorDraftStore = EditorDraftStore(), directory: URL? = nil) {
        self.drafts = drafts
        root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyFitPlate/workout-instruction-media", isDirectory: true)
    }
    public static func movementKey(_ exercise: RoutineExercise) -> String {
        let source = exercise.movementIdentity.map { "\($0.ownerID ?? "catalog")|\($0.movementID)|\($0.variantID)" }
            ?? "legacy|\(WorkoutSetMath.normalizedName(exercise.name))"
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func directory(userID: String) -> URL {
        let key = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(key, isDirectory: true)
    }
    /// Called only by the existing confirmed account-deletion cleanup ledger; authentication
    /// has already been removed. The owner hash is identical to import/read paths.
    public func removeAccountData(for userID: String) throws {
        guard !userID.isEmpty else { throw WorkoutBlockError.accountChanged }
        let url = directory(userID: userID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    public func media(for exercise: RoutineExercise, userID: String) throws -> WorkoutInstructionMedia? {
        guard !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        let key = Self.movementKey(exercise)
        let result = try drafts.load(WorkoutInstructionMedia.self, userID: userID, scope: "instruction-media-\(key)")?.value
        guard result == nil || (result?.version == 1 && result?.movementKey == key) else { throw WorkoutBlockError.unsupported }
        return result
    }
    public func fileURL(_ media: WorkoutInstructionMedia, userID: String) throws -> URL {
        guard DIContainer.shared.authService.currentUserID == userID, !media.filename.isEmpty,
              media.version == 1, media.contentSHA256.count == 64,
              media.contentSHA256.allSatisfy({ $0.isHexDigit }),
              URL(fileURLWithPath: media.filename).lastPathComponent == media.filename,
              media.filename == media.contentSHA256 + "." + URL(fileURLWithPath: media.filename).pathExtension,
              ["mp4", "mov", "m4v"].contains(URL(fileURLWithPath: media.filename).pathExtension) else { throw WorkoutBlockError.accountChanged }
        let url = directory(userID: userID).appendingPathComponent(media.filename)
        guard FileManager.default.fileExists(atPath: url.path), url.resolvingSymlinksInPath() == url.standardizedFileURL else { throw WorkoutBlockError.unavailable }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, (1...30_000_000).contains(size.intValue) else { throw WorkoutBlockError.invalid }
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard actual == media.contentSHA256 else { throw WorkoutBlockError.changed }
        return url
    }
    public func importVideo(_ data: Data, extension fileExtension: String, exercise: RoutineExercise, userID: String,
                            attribution: String, permission: WorkoutInstructionMedia.Permission,
                            permissionNotes: String, captionTranscript: String) throws -> WorkoutInstructionMedia {
        guard !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        guard (1...30_000_000).contains(data.count), ["mp4", "mov", "m4v"].contains(fileExtension.lowercased()),
              !attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !captionTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              attribution.count <= 500, permissionNotes.count <= 2_000, captionTranscript.count <= 20_000 else { throw WorkoutBlockError.invalid }
        let signature = data.count >= 8 ? String(data: data.subdata(in: 4..<8), encoding: .ascii) : nil
        guard signature == "ftyp" || (fileExtension.lowercased() == "mov" && ["moov", "mdat", "wide"].contains(signature ?? "")) else { throw WorkoutBlockError.invalid }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let filename = "\(digest).\(fileExtension.lowercased())"
        let directory = directory(userID: userID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        #endif
        let metadata = WorkoutInstructionMedia(id: UUID().uuidString, version: 1, movementKey: Self.movementKey(exercise), filename: filename,
            contentSHA256: digest, attribution: attribution, permission: permission, permissionNotes: permissionNotes,
            captionTranscript: captionTranscript, importedAt: Date())
        try drafts.save(metadata, userID: userID, scope: "instruction-media-\(metadata.movementKey)")
        return metadata
    }
}

/// Bundled licensed assets are immutable app resources, never part of an account's imported files.
public struct WorkoutBuiltinInstructionMedia: Codable, Identifiable, Sendable {
    public var id: String
    public var version: Int
    public var canonicalName: String
    public var movementID: String
    public var variantID: String
    public var resourceName: String
    public var fileExtension: String
    public var contentSHA256: String
    public var author: String
    public var sourceURL: URL
    public var licenseName: String
    public var licenseURL: URL
    public var captionTranscript: String
    public var isValid: Bool {
        version == 1 && !id.isEmpty && !canonicalName.isEmpty && !movementID.isEmpty && !variantID.isEmpty
            && !resourceName.isEmpty && resourceName == URL(fileURLWithPath: resourceName).lastPathComponent
            && ["mp4", "mov", "m4v"].contains(fileExtension)
            && contentSHA256.count == 64 && contentSHA256.allSatisfy(\.isHexDigit)
            && !author.isEmpty && !licenseName.isEmpty && !captionTranscript.isEmpty
            && sourceURL.scheme == "https" && licenseURL.scheme == "https"
    }
}
public struct WorkoutBuiltinInstructionCatalog: Codable {
    public var version: Int
    public var entries: [WorkoutBuiltinInstructionMedia]
    public var isValid: Bool {
        version == 1 && entries.allSatisfy(\.isValid) && Set(entries.map(\.id)).count == entries.count
            && Set(entries.map { "\($0.movementID)|\($0.variantID)" }).count == entries.count
    }
    public static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.isValid else { throw WorkoutBlockError.invalid }
        return catalog
    }
    public func media(for exercise: RoutineExercise) -> WorkoutBuiltinInstructionMedia? {
        guard isValid else { return nil }
        if let identity = exercise.movementIdentity {
            guard identity.ownerID == nil else { return nil }
            return entries.first { $0.movementID == identity.movementID && $0.variantID == identity.variantID }
        }
        // No aliases/fuzzy substitution for a name-only legacy exercise.
        return entries.first { $0.canonicalName == exercise.name }
    }
}
