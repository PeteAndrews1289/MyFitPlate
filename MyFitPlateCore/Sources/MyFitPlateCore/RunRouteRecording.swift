import CryptoKit
import Foundation

/// The accepted GPS evidence for one recording. Segments never join across a pause,
/// recovery or rejected GPS anchor. Distance remains owned by RunSession, not this trace.
public struct RunRouteRecording: Codable, Equatable, Sendable {
    public static let maximumPoints = 25_000
    public static let maximumSegments = 4_096
    public let recordingID: String
    public private(set) var segments: [[RunLocationFix]]
    public private(set) var acceptedSequence: Int
    public private(set) var isTruncated: Bool
    public let earlierRouteUnavailable: Bool

    public init(recordingID: String, earlierRouteUnavailable: Bool = false) {
        self.recordingID = recordingID
        self.earlierRouteUnavailable = earlierRouteUnavailable
        segments = []
        acceptedSequence = 0
        isTruncated = false
    }

    public var pointCount: Int { segments.reduce(0) { $0 + $1.count } }
    public var hasDrawableRoute: Bool { segments.contains { $0.count > 1 } }
    public var hasGaps: Bool { earlierRouteUnavailable || isTruncated || segments.count > 1 }

    public mutating func append(_ fix: RunLocationFix, startsNewSegment: Bool) {
        guard Self.valid(fix), segments.last?.last.map({ fix.timestamp > $0.timestamp }) ?? true else { return }
        acceptedSequence += 1
        guard !isTruncated, pointCount < Self.maximumPoints,
              !startsNewSegment || segments.count < Self.maximumSegments else {
            isTruncated = true
            return
        }
        if startsNewSegment || segments.isEmpty { segments.append([fix]) } else { segments[segments.count - 1].append(fix) }
    }

    public func isValid(startDate: Date, endDate: Date) -> Bool {
        guard !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              startDate.timeIntervalSinceReferenceDate.isFinite, endDate.timeIntervalSinceReferenceDate.isFinite,
              endDate >= startDate, segments.count <= Self.maximumSegments,
              pointCount <= Self.maximumPoints, acceptedSequence >= pointCount,
              isTruncated || acceptedSequence == pointCount else { return false }
        var previous: Date?
        for segment in segments {
            guard !segment.isEmpty else { return false }
            for fix in segment {
                guard Self.valid(fix), fix.timestamp >= startDate, fix.timestamp <= endDate,
                      previous.map({ fix.timestamp > $0 }) ?? true else { return false }
                previous = fix.timestamp
            }
        }
        return true
    }

    private static func valid(_ fix: RunLocationFix) -> Bool {
        fix.latitude.isFinite && (-90...90).contains(fix.latitude)
            && fix.longitude.isFinite && (-180...180).contains(fix.longitude)
            && fix.horizontalAccuracy.isFinite && (0...RunSession.accuracyCutoffMeters).contains(fix.horizontalAccuracy)
            && fix.timestamp.timeIntervalSinceReferenceDate.isFinite
    }
}

/// A bounded private route cache protects a completed local run when Health is denied
/// or unavailable. It is excluded from backup, expires after 30 days, and retains at most
/// 20 runs per account. Metrics/history are never removed by cache eviction.
public final class RunRouteArchiveStore {
    public static let retentionSeconds: TimeInterval = 30 * 24 * 60 * 60
    public static let maximumRecordings = 20
    private static let lock = NSLock()
    private let directory: URL?
    private let now: () -> Date
    private struct Archive: Codable {
        let version: Int
        let startDate: Date
        let endDate: Date
        let route: RunRouteRecording
        let checksum: String
    }

    public convenience init() {
        self.init(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MyFitPlate/run-route-cache", isDirectory: true))
    }

    public init(directory: URL?, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    public func save(_ route: RunRouteRecording, run: Run, userID: String) throws {
        guard route.recordingID == (run.recordingID ?? run.id), route.isValid(startDate: run.startDate, endDate: run.endDate) else {
            throw CocoaError(.coderInvalidValue)
        }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let account = try accountURL(userID)
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try RunRouteFileProtection.excludeFromBackup(account)
        let archive = Archive(version: 1, startDate: run.startDate, endDate: run.endDate, route: route,
                              checksum: try RunRouteFileProtection.checksum(route))
        try RunRouteFileProtection.write(JSONEncoder().encode(archive), to: try fileURL(route.recordingID, account: account))
        try prune(account: account)
    }

    public func load(recordingID: String, userID: String) throws -> RunRouteRecording? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let account = try accountURL(userID)
        try prune(account: account)
        let file = try fileURL(recordingID, account: account)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let archive = try read(file)
        guard archive.route.recordingID == recordingID else { throw CocoaError(.coderReadCorrupt) }
        return archive.route
    }

    public func remove(recordingID: String, userID: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let file = try fileURL(recordingID, account: accountURL(userID))
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    public func removeAccountData(userID: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let account = try accountURL(userID)
        if FileManager.default.fileExists(atPath: account.path) { try FileManager.default.removeItem(at: account) }
    }

    private func read(_ file: URL) throws -> Archive {
        let archive = try JSONDecoder().decode(Archive.self, from: RunRouteFileProtection.read(file))
        guard archive.version == 1, archive.route.isValid(startDate: archive.startDate, endDate: archive.endDate),
              archive.checksum == (try RunRouteFileProtection.checksum(archive.route)) else { throw CocoaError(.coderReadCorrupt) }
        return archive
    }

    private func prune(account: URL) throws {
        guard FileManager.default.fileExists(atPath: account.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: account, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
        let cached = files.map { file -> (URL, Date) in
            // Corrupt cache entries still count toward the privacy/storage bound.
            // They contain no authoritative run metrics and cannot live forever.
            let date = (try? read(file).endDate)
                ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return (file, date)
        }.sorted { $0.1 > $1.1 }
        for (index, item) in cached.enumerated() where index >= Self.maximumRecordings || now().timeIntervalSince(item.1) > Self.retentionSeconds {
            try FileManager.default.removeItem(at: item.0)
        }
    }

    private func accountURL(_ userID: String) throws -> URL {
        guard let directory, directory.isFileURL,
              let key = AccountScopedStorageKey.make(prefix: "routes", userID: userID) else { throw CocoaError(.fileWriteNoPermission) }
        return directory.appendingPathComponent(key, isDirectory: true)
    }

    private func fileURL(_ recordingID: String, account: URL) throws -> URL {
        guard let key = AccountScopedStorageKey.make(prefix: "recording", userID: recordingID) else { throw CocoaError(.fileWriteNoPermission) }
        return account.appendingPathComponent(key).appendingPathExtension("json")
    }
}

enum RunRouteFileProtection {
    static let maximumBytes = 12 * 1_024 * 1_024

    static func checksum<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    static func read(_ file: URL) throws -> Data {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return try Data(contentsOf: file)
    }

    static func write(_ data: Data, to file: URL) throws {
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try excludeFromBackup(file)
    }

    static func excludeFromBackup(_ file: URL) throws {
        var file = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
}
