import CryptoKit
import Darwin
import Foundation

public struct SavedFastSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let ownerScope: String
    public let startTime: Date
    public let targetEndTime: Date
    public var endedAt: Date?
    public var revision: Int
    public let source: String
    public let legacyActivityID: String?

    public var isActive: Bool { endedAt == nil }
    public var durationHours: Int {
        let hours = (targetEndTime.timeIntervalSince(startTime) / 3_600).rounded()
        return hours.isFinite && (0...24).contains(hours) ? Int(hours) : 0
    }
    public var fastType: String { "\(durationHours):\(24 - durationHours) Fast" }
}

public struct FastingAccountSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public let ownerScope: String
    public var sessions: [SavedFastSession]
    public var activeSession: SavedFastSession? { sessions.first(where: \.isActive) }
    public var lastEndedSession: SavedFastSession? { sessions.filter { !$0.isActive }.max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) } }
}

public enum FastingStoreError: Error, LocalizedError, Equatable {
    case unavailable, invalidAccount, accountChanged, unreadable, invalidTime, alreadyActive, sessionChanged

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Fasting could not save on this device. Keep the app open and retry."
        case .invalidAccount, .accountChanged: "Sign back into the account that owns this fast to continue."
        case .unreadable: "Your saved fasting record could not be read. It has been kept unchanged."
        case .invalidTime: "Check your device date, time and fasting duration, then retry."
        case .alreadyActive: "You already have a saved fast. End it before starting another."
        case .sessionChanged: "This fast has changed. Open MyFitPlate to see its current state."
        }
    }
}

/// The app and Lock Screen use one durable, account-fenced record. ActivityKit is only
/// a projection. One advisory file lock serializes app/extension read-modify-write.
public struct FastingSessionStore: Sendable {
    private let directory: URL?

    private struct ActiveAccount: Codable { let ownerScope: String? }
    private struct LegacyClaim: Codable { let ownerScope: String; let sessionID: UUID }

    public init() {
        directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.peterandrews.CalorieBeta")?
            .appendingPathComponent("MyFitPlate/fasting-v1", isDirectory: true)
    }

    public init(directory: URL?) { self.directory = directory }

    public static func ownerScope(userID: String?) -> String? {
        guard let userID, !userID.isEmpty else { return nil }
        return SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func activateAccount(userID: String?) throws {
        try locked { directory in
            try write(ActiveAccount(ownerScope: Self.ownerScope(userID: userID)), to: directory.appendingPathComponent("active-account.json"))
        }
    }

    public func load(ownerScope: String) throws -> FastingAccountSnapshot {
        try locked { directory in try read(ownerScope: ownerScope, directory: directory) }
    }

    /// Called only after confirmed account deletion. Other accounts and their active
    /// marker remain intact; malformed shared metadata is never blindly erased.
    public func removeAccount(userID: String) throws -> [String] {
        guard let scope = Self.ownerScope(userID: userID) else { throw FastingStoreError.invalidAccount }
        return try locked { directory in
            let claimsURL = directory.appendingPathComponent("legacy-claims.json")
            var claims: [String: LegacyClaim] = [:]
            if FileManager.default.fileExists(atPath: claimsURL.path) {
                guard let data = try? Data(contentsOf: claimsURL), let decoded = try? JSONDecoder().decode([String: LegacyClaim].self, from: data) else {
                    throw FastingStoreError.unreadable
                }
                claims = decoded
            }
            let ownedLegacyIDs = claims.filter { $0.value.ownerScope == scope }.map(\.key)
            let marker = directory.appendingPathComponent("active-account.json")
            if FileManager.default.fileExists(atPath: marker.path) {
                guard let data = try? Data(contentsOf: marker), let active = try? JSONDecoder().decode(ActiveAccount.self, from: data) else {
                    throw FastingStoreError.unreadable
                }
                if active.ownerScope == scope { try write(ActiveAccount(ownerScope: nil), to: marker) }
            }
            if !ownedLegacyIDs.isEmpty { try write(claims.filter { $0.value.ownerScope != scope }, to: claimsURL) }
            let accountFile = file(scope, directory: directory)
            if FileManager.default.fileExists(atPath: accountFile.path) { try FileManager.default.removeItem(at: accountFile) }
            return ownedLegacyIDs
        }
    }

    @discardableResult
    public func start(ownerScope: String, hours: Int, now: Date = Date(), source: String = "app") throws -> SavedFastSession {
        guard (1..<24).contains(hours), valid(now), valid(now.addingTimeInterval(Double(hours) * 3_600)) else { throw FastingStoreError.invalidTime }
        return try locked { directory in
            try requireActive(ownerScope, directory: directory)
            var snapshot = try read(ownerScope: ownerScope, directory: directory)
            guard snapshot.activeSession == nil else { throw FastingStoreError.alreadyActive }
            let session = SavedFastSession(id: UUID(), ownerScope: ownerScope, startTime: now,
                targetEndTime: now.addingTimeInterval(Double(hours) * 3_600), revision: 1, source: source, legacyActivityID: nil)
            snapshot.sessions.append(session)
            try write(snapshot, to: file(ownerScope, directory: directory))
            return session
        }
    }

    @discardableResult
    public func end(ownerScope: String, sessionID: UUID, expectedRevision: Int, now: Date = Date()) throws -> SavedFastSession {
        guard valid(now) else { throw FastingStoreError.invalidTime }
        guard expectedRevision > 0, expectedRevision < Int.max else { throw FastingStoreError.sessionChanged }
        return try locked { directory in
            try requireActive(ownerScope, directory: directory)
            var snapshot = try read(ownerScope: ownerScope, directory: directory)
            guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else { throw FastingStoreError.sessionChanged }
            let saved = snapshot.sessions[index]
            // A duplicate End never changes the first accepted end time, even after another fast starts.
            if !saved.isActive, saved.revision == expectedRevision + 1 { return saved }
            guard saved.isActive, saved.revision == expectedRevision else { throw FastingStoreError.sessionChanged }
            guard now >= saved.startTime else { throw FastingStoreError.invalidTime }
            snapshot.sessions[index].endedAt = now
            snapshot.sessions[index].revision += 1
            try write(snapshot, to: file(ownerScope, directory: directory))
            return snapshot.sessions[index]
        }
    }

    /// Older activities had no account identity. The app calls this only after a user
    /// explicitly chooses to recover that displayed timer into their signed-in account.
    @discardableResult
    public func recoverLegacy(ownerScope: String, activityID: String, startTime: Date, targetEndTime: Date, now: Date = Date()) throws -> SavedFastSession {
        guard !activityID.isEmpty, valid(startTime), valid(targetEndTime), valid(now), startTime <= now,
              targetEndTime > startTime, (targetEndTime.timeIntervalSince(startTime) / 3_600) < 24 else { throw FastingStoreError.invalidTime }
        return try locked { directory in
            try requireActive(ownerScope, directory: directory)
            var snapshot = try read(ownerScope: ownerScope, directory: directory)
            if let recovered = snapshot.sessions.first(where: { $0.legacyActivityID == activityID }) { return recovered }
            guard snapshot.activeSession == nil else { throw FastingStoreError.alreadyActive }
            let claimsURL = directory.appendingPathComponent("legacy-claims.json")
            var claims: [String: LegacyClaim] = [:]
            if FileManager.default.fileExists(atPath: claimsURL.path) {
                guard let data = try? Data(contentsOf: claimsURL), let saved = try? JSONDecoder().decode([String: LegacyClaim].self, from: data) else {
                    throw FastingStoreError.unreadable
                }
                claims = saved
            }
            if let claim = claims[activityID], claim.ownerScope != ownerScope { throw FastingStoreError.accountChanged }
            let claim = claims[activityID] ?? LegacyClaim(ownerScope: ownerScope, sessionID: UUID())
            claims[activityID] = claim
            try write(claims, to: claimsURL)
            let session = SavedFastSession(id: claim.sessionID, ownerScope: ownerScope, startTime: startTime,
                targetEndTime: targetEndTime, revision: 1, source: "legacy-activity", legacyActivityID: activityID)
            snapshot.sessions.append(session)
            try write(snapshot, to: file(ownerScope, directory: directory))
            return session
        }
    }

    private func locked<T>(_ body: (URL) throws -> T) throws -> T {
        guard let directory, directory.isFileURL else { throw FastingStoreError.unavailable }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { throw FastingStoreError.unavailable }
        let descriptor = open(directory.appendingPathComponent("state.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw FastingStoreError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw FastingStoreError.unavailable }
        defer { flock(descriptor, LOCK_UN) }
        return try body(directory)
    }

    private func requireActive(_ scope: String, directory: URL) throws {
        guard validScope(scope) else { throw FastingStoreError.invalidAccount }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("active-account.json")),
              let active = try? JSONDecoder().decode(ActiveAccount.self, from: data), active.ownerScope == scope else { throw FastingStoreError.accountChanged }
    }

    private func read(ownerScope: String, directory: URL) throws -> FastingAccountSnapshot {
        guard validScope(ownerScope) else { throw FastingStoreError.invalidAccount }
        let url = file(ownerScope, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return FastingAccountSnapshot(ownerScope: ownerScope, sessions: []) }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(FastingAccountSnapshot.self, from: data),
              snapshot.schemaVersion == 1, snapshot.ownerScope == ownerScope,
              Set(snapshot.sessions.map(\.id)).count == snapshot.sessions.count,
              snapshot.sessions.filter(\.isActive).count <= 1,
              snapshot.sessions.allSatisfy({ session in
                  session.ownerScope == ownerScope && session.revision > 0 && valid(session.startTime) && valid(session.targetEndTime)
                      && session.targetEndTime > session.startTime && session.targetEndTime.timeIntervalSince(session.startTime) < 24 * 3_600
                      && (session.endedAt.map { valid($0) && $0 >= session.startTime } ?? true)
              }) else { throw FastingStoreError.unreadable }
        return snapshot
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try JSONEncoder().encode(value)
            #if os(iOS) || os(watchOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
        } catch { throw FastingStoreError.unavailable }
    }

    private func file(_ scope: String, directory: URL) -> URL { directory.appendingPathComponent("fasts-\(scope).json") }
    private func validScope(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
    private func valid(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite && date >= .distantPast && date <= .distantFuture }
}
