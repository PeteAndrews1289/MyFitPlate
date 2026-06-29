
import Foundation

public class PinnedNotesManager {
    public static let shared = PinnedNotesManager()
    private let userDefaults = UserDefaults.standard
    private let pinnedNotesKey = "pinnedExerciseNotes"

    private init() {}

    public func getPinnedNote(for exerciseName: String) -> String? {
        guard let notes = userDefaults.dictionary(forKey: pinnedNotesKey) as? [String: String] else {
            return nil
        }
        return notes[exerciseName]
    }

    public func setPinnedNote(for exerciseName: String, note: String) {
        var notes = userDefaults.dictionary(forKey: pinnedNotesKey) as? [String: String] ?? [:]
        notes[exerciseName] = note
        userDefaults.set(notes, forKey: pinnedNotesKey)
    }

    public func removePinnedNote(for exerciseName: String) {
        var notes = userDefaults.dictionary(forKey: pinnedNotesKey) as? [String: String] ?? [:]
        notes.removeValue(forKey: exerciseName)
        userDefaults.set(notes, forKey: pinnedNotesKey)
    }

    public func isNotePinned(for exerciseName: String) -> Bool {
        return getPinnedNote(for: exerciseName) != nil
    }
}
