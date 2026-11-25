import Foundation

/// A Lock Screen action names the exact rest it skips. A delayed intent cannot cancel
/// a subsequent rest, another workout, or a different account's recovery draft.
public struct WorkoutRestSkipStore {
    private static let maximumAge: TimeInterval = 24 * 60 * 60
    private let directory: URL?

    private struct Receipt: Codable {
        let restID: UUID
        let requestedAt: Date
    }

    public init() {
        directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.peterandrews.CalorieBeta")?
            .appendingPathComponent("MyFitPlate/workout-rest-skips", isDirectory: true)
    }

    /// An explicit nil never falls back to another container or an unscoped preference.
    public init(directory: URL?) {
        self.directory = directory
    }

    @discardableResult
    public func request(restID: UUID, now: Date = Date()) -> Bool {
        guard let directory, directory.isFileURL, now.timeIntervalSinceReferenceDate.isFinite else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            removeExpiredRequests(now: now)
            let data = try JSONEncoder().encode(Receipt(restID: restID, requestedAt: now))
            // Separate UUID files avoid cross-process read/modify/write races. Returning
            // success requires the complete tombstone to have been written and renamed.
            try data.write(to: fileURL(restID: restID, in: directory), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Keep an idempotent tombstone until expiry. Removing it during recovery could
    /// revive the skipped rest if the app terminates before it saves the cleared draft.
    public func wasRequested(restID: UUID, now: Date = Date()) -> Bool {
        guard let directory, directory.isFileURL, now.timeIntervalSinceReferenceDate.isFinite else { return false }
        let url = fileURL(restID: restID, in: directory)
        guard let receipt = receipt(at: url), receipt.restID == restID else { return false }
        let age = now.timeIntervalSince(receipt.requestedAt)
        guard age.isFinite, age >= -60, age <= Self.maximumAge else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    private func removeExpiredRequests(now: Date) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                      options: .skipsHiddenFiles) else { return }
        for url in files where url.pathExtension == "json" {
            guard let identity = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            guard let stored = receipt(at: url), stored.restID == identity,
                  (-60...Self.maximumAge).contains(now.timeIntervalSince(stored.requestedAt)) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
        }
    }

    private func fileURL(restID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(restID.uuidString).appendingPathExtension("json")
    }

    private func receipt(at url: URL) -> Receipt? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Receipt.self, from: data)
    }
}
