import CryptoKit
import Foundation

/// Keeps completed run metrics available when Apple Health rejects a write. Raw route
/// coordinates are deliberately excluded; Health remains the primary workout store.
public final class RunFallbackStore: @unchecked Sendable {
    public static let shared = RunFallbackStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let maximumRuns = 100

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    @discardableResult
    public func save(_ run: Run, for userID: String) -> Bool {
        guard !userID.isEmpty else { return false }
        var localRun = run
        localRun.source = .recorded
        localRun.hasRoute = false

        lock.lock()
        defer { lock.unlock() }

        var runs = decodedRuns(for: userID)
        runs.removeAll { $0.id == localRun.id }
        runs.append(localRun)
        runs.sort { $0.startDate > $1.startDate }
        runs = Array(runs.prefix(maximumRuns))

        guard let data = try? JSONEncoder().encode(runs) else { return false }
        defaults.set(data, forKey: storageKey(for: userID))
        return true
    }

    public func runs(since: Date, for userID: String) -> [Run] {
        guard !userID.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return decodedRuns(for: userID).filter { $0.startDate >= since }
    }

    public func clear(for userID: String) {
        guard !userID.isEmpty else { return }
        lock.lock()
        defaults.removeObject(forKey: storageKey(for: userID))
        lock.unlock()
    }

    private func decodedRuns(for userID: String) -> [Run] {
        guard let data = defaults.data(forKey: storageKey(for: userID)),
              let runs = try? JSONDecoder().decode([Run].self, from: data) else {
            return []
        }
        return runs
    }

    private func storageKey(for userID: String) -> String {
        let digest = SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "run_fallback_\(digest)"
    }
}
