
import Foundation

@MainActor
public final class PinnedNotesManager: @unchecked Sendable {
    public static let shared = PinnedNotesManager(
        userDefaults: .standard,
        authService: DIContainer.shared.authService
    )

    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol
    private let lock = NSLock()
    private let legacyPinnedNotesKey = "pinnedExerciseNotes"

    public init(
        userDefaults: UserDefaults,
        authService: AuthServiceProtocol
    ) {
        self.userDefaults = userDefaults
        self.authService = authService
    }

    public func getPinnedNote(for exerciseName: String) -> String? {
        guard let pinnedNotesKey = currentStorageKey() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        migrateLegacyStorageIfNeeded(to: pinnedNotesKey)
        guard let notes = userDefaults.dictionary(forKey: pinnedNotesKey) as? [String: String] else { return nil }
        return notes[exerciseName]
    }

    public func setPinnedNote(for exerciseName: String, note: String) {
        guard let pinnedNotesKey = currentStorageKey() else { return }
        lock.lock()
        defer { lock.unlock() }
        migrateLegacyStorageIfNeeded(to: pinnedNotesKey)
        var notes = userDefaults.dictionary(forKey: pinnedNotesKey) as? [String: String] ?? [:]
        notes[exerciseName] = note
        userDefaults.set(notes, forKey: pinnedNotesKey)
    }

    public func removePinnedNote(for exerciseName: String) {
        guard let pinnedNotesKey = currentStorageKey() else { return }
        lock.lock()
        defer { lock.unlock() }
        migrateLegacyStorageIfNeeded(to: pinnedNotesKey)
        var notes = userDefaults.dictionary(forKey: pinnedNotesKey) as? [String: String] ?? [:]
        notes.removeValue(forKey: exerciseName)
        if notes.isEmpty {
            userDefaults.removeObject(forKey: pinnedNotesKey)
        } else {
            userDefaults.set(notes, forKey: pinnedNotesKey)
        }
    }

    public func isNotePinned(for exerciseName: String) -> Bool {
        getPinnedNote(for: exerciseName) != nil
    }

    private func currentStorageKey() -> String? {
        AccountScopedStorageKey.make(
            prefix: "pinnedExerciseNotes",
            userID: authService.currentUserID
        )
    }

    private func migrateLegacyStorageIfNeeded(to storageKey: String) {
        guard let legacyNotes = userDefaults.dictionary(forKey: legacyPinnedNotesKey) as? [String: String] else {
            return
        }

        var accountNotes = userDefaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        for (exercise, note) in legacyNotes where accountNotes[exercise] == nil {
            accountNotes[exercise] = note
        }
        if !accountNotes.isEmpty {
            userDefaults.set(accountNotes, forKey: storageKey)
        }
        userDefaults.removeObject(forKey: legacyPinnedNotesKey)
    }
}
