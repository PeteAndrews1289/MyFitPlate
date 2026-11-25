import Foundation

public struct PersonalReportPreferences: Codable, Equatable {
    public var showsWellnessComposite = false
    public var showsGamification = true
    public var showsBMI = false
    public init() {}
}

@MainActor
public enum PersonalReportPreferenceStore {
    public static func load(userID: String, store: EditorDraftStore = EditorDraftStore()) throws -> PersonalReportPreferences {
        try store.load(PersonalReportPreferences.self, userID: userID, scope: "personal-report-presentation-v1")?.value ?? .init()
    }
    public static func save(_ value: PersonalReportPreferences, userID: String, currentUserID: String?,
                            store: EditorDraftStore = EditorDraftStore()) throws {
        guard !userID.isEmpty, userID == currentUserID else { throw InsightEvidenceError.accountChanged }
        try store.save(value, userID: userID, scope: "personal-report-presentation-v1")
    }
}

public struct SleepRoutineNotes: Codable, Equatable {
    public var usesPreferredWindow = false
    public var preferredBedtimeMinutes = 22 * 60 + 30
    public var preferredWakeMinutes = 7 * 60
    public var nightNotes: [String: String] = [:]
    public init() {}
}

@MainActor
public enum SleepRoutineNoteStore {
    public static func load(userID: String, store: EditorDraftStore = EditorDraftStore()) throws -> SleepRoutineNotes {
        try store.load(SleepRoutineNotes.self, userID: userID, scope: "sleep-routine-notes-v1")?.value ?? .init()
    }
    public static func save(_ value: SleepRoutineNotes, userID: String, currentUserID: String?,
                            store: EditorDraftStore = EditorDraftStore()) throws {
        guard !userID.isEmpty, currentUserID == userID else { throw InsightEvidenceError.accountChanged }
        guard (0..<1440).contains(value.preferredBedtimeMinutes), (0..<1440).contains(value.preferredWakeMinutes),
              value.nightNotes.values.allSatisfy({ $0.count <= 500 }) else { throw InsightEvidenceError.invalid }
        try store.save(value, userID: userID, scope: "sleep-routine-notes-v1")
    }
}
