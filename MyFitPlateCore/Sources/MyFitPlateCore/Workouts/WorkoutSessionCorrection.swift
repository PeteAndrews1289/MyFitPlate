import CryptoKit
import Foundation

public enum WorkoutDiaryReconciliation: String, Codable, Equatable {
    case updated, alreadyCurrent, missing, preservedOverride, failed
}
public extension Notification.Name {
    static let workoutSessionCorrected = Notification.Name("workoutSessionCorrected")
}

public enum WorkoutDiaryProjectionRules {
    public static func make(log: WorkoutSessionLog, name: String, elapsed: TimeInterval, weightPounds: Double) -> LoggedExercise {
        var calories = 0.0
        var activeSeconds = 0
        for exercise in log.completedExercises {
            let seconds = exercise.exercise.type == .strength ? exercise.sets.count * 60
                : exercise.sets.reduce(0) { $0 + max(0, $1.durationInSeconds ?? 0) }
            let met = exercise.exercise.type == .strength ? 5.0 : exercise.exercise.type == .cardio ? 8 : 2.5
            activeSeconds += seconds
            if weightPounds.isFinite, weightPounds > 0 { calories += met * 3.5 * weightPounds * 0.453592 / 200 * Double(seconds) / 60 }
        }
        let duration = elapsed.isFinite && elapsed > 0 ? elapsed : Double(activeSeconds)
        return LoggedExercise(id: log.id ?? "", name: name,
            durationMinutes: max(1, Int(min(max(0, duration), 86_400)) / 60),
            caloriesBurned: calories, date: log.date, source: "routine", workoutID: log.routineID, sessionID: log.id)
    }
    public static func matches(_ lhs: LoggedExercise, _ rhs: LoggedExercise) -> Bool {
        lhs.id == rhs.id && lhs.sessionID == rhs.sessionID && lhs.workoutID == rhs.workoutID && lhs.source == rhs.source
            && lhs.date == rhs.date && lhs.name == rhs.name && lhs.durationMinutes == rhs.durationMinutes
            && abs(lhs.caloriesBurned - rhs.caloriesBurned) < 0.0001
    }
}

public struct WorkoutCorrectionReceipt: Codable, Identifiable {
    public let id: String
    public let userID: String
    public let original: WorkoutSessionLog
    public let updated: WorkoutSessionLog
    public let createdAt: Date
    public var historyAccepted: Bool
    public var diaryResult: WorkoutDiaryReconciliation?
    public var abandonedAt: Date?
    public var isComplete: Bool { abandonedAt != nil || (historyAccepted && diaryResult != nil && diaryResult != .failed) }
}

/// One atomic file per correction keeps original values and a replayable partial-save receipt.
/// It never edits a program or advances a pointer.
public final class WorkoutCorrectionStore {
    private let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyFitPlate/workout-corrections")
    }
    private func accountDirectory(_ userID: String) -> URL {
        directory.appendingPathComponent(AccountScopedStorageKey.make(prefix: "corrections", userID: userID) ?? "signed-out")
    }
    public func save(_ receipt: WorkoutCorrectionReceipt) throws {
        let folder = accountDirectory(receipt.userID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(to: folder.appendingPathComponent(receipt.id).appendingPathExtension("json"), options: .atomic)
    }
    public func pending(sessionID: String, userID: String) throws -> WorkoutCorrectionReceipt? {
        let folder = accountDirectory(userID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(WorkoutCorrectionReceipt.self, from: Data(contentsOf: $0)) }
            .filter { $0.userID == userID && $0.updated.id == sessionID && !$0.isComplete }
            .sorted { $0.createdAt < $1.createdAt }.first
    }
    public func removeAll(userID: String) throws {
        guard AccountScopedStorageKey.make(prefix: "corrections", userID: userID) != nil else { throw CocoaError(.fileWriteNoPermission) }
        let folder = accountDirectory(userID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}

public enum WorkoutCorrectionError: Error { case invalid, conflict, accountChanged, historyUnavailable }

public enum WorkoutCorrectionRevisionRules {
    public static func fingerprint(_ log: WorkoutSessionLog) throws -> Data {
        var value = log
        value.aiInsights = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Firestore stores timestamps against the Unix epoch; millisecond precision
        // avoids a false conflict from Date's differing reference-epoch roundoff.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let milliseconds = date.timeIntervalSince1970 * 1_000
            guard milliseconds.isFinite, abs(milliseconds) < Double(Int64.max) else { throw WorkoutCorrectionError.invalid }
            var container = encoder.singleValueContainer()
            try container.encode(Int64(milliseconds.rounded()))
        }
        return Data(SHA256.hash(data: try encoder.encode(value)))
    }
}

@MainActor
public final class WorkoutCorrectionCoordinator {
    private let store: WorkoutCorrectionStore
    private let repository: WorkoutRepositoryProtocol
    private let diary: DailyLogService
    private let auth: AuthServiceProtocol
    public init(store: WorkoutCorrectionStore = WorkoutCorrectionStore(), repository: WorkoutRepositoryProtocol,
                diary: DailyLogService, auth: AuthServiceProtocol) {
        self.store = store; self.repository = repository; self.diary = diary; self.auth = auth
    }

    public func prepare(original: WorkoutSessionLog, updated: WorkoutSessionLog, userID: String) throws -> WorkoutCorrectionReceipt {
        guard auth.currentUserID == userID, let sessionID = original.id, !sessionID.isEmpty,
              updated.id == sessionID, Calendar.current.isDate(original.date, inSameDayAs: updated.date),
              updated.date <= Date(), updated.completedExercises.allSatisfy({ exercise in
                  exercise.sets.allSatisfy { set in
                      set.weight.isFinite && (0...10_000).contains(set.weight) && (0...10_000).contains(set.reps)
                          && (exercise.exercise.type != .strength || set.reps > 0)
                          && (set.distance.map { $0.isFinite && $0 >= 0 } ?? true)
                          && (set.durationInSeconds.map { (0...86_400).contains($0) } ?? true)
                  }
              }), updated.elapsedSeconds.map({ $0.isFinite && (0...86_400).contains($0) }) ?? true else { throw WorkoutCorrectionError.invalid }
        if let pending = try store.pending(sessionID: sessionID, userID: userID) { return pending }
        var frozen = updated
        frozen.programContext = original.programContext; frozen.programLinkDecision = original.programLinkDecision
        frozen.aiInsights = nil
        let commandID = UUID().uuidString
        frozen.correctionRevisionID = commandID
        if let weight = original.projectionBodyWeightPounds, let prior = original.generatedDiaryExercise {
            frozen.generatedDiaryExercise = WorkoutDiaryProjectionRules.make(log: frozen, name: prior.name,
                elapsed: frozen.elapsedSeconds ?? original.elapsedSeconds ?? 0, weightPounds: weight)
        }
        let receipt = WorkoutCorrectionReceipt(id: commandID, userID: userID, original: original, updated: frozen,
            createdAt: Date(), historyAccepted: false, diaryResult: nil)
        try store.save(receipt)
        return receipt
    }

    public func resume(_ input: WorkoutCorrectionReceipt) async throws -> WorkoutCorrectionReceipt {
        var receipt = input
        guard auth.currentUserID == receipt.userID else { throw WorkoutCorrectionError.accountChanged }
        guard let sessionID = receipt.updated.id, !sessionID.isEmpty, receipt.original.id == sessionID else { throw WorkoutCorrectionError.invalid }
        if receipt.isComplete { return receipt }
        if receipt.historyAccepted {
            let latest = try await repository.fetchWorkoutSessionLog(userID: receipt.userID, sessionID: sessionID)
            guard auth.currentUserID == receipt.userID else { throw WorkoutCorrectionError.accountChanged }
            guard latest.correctionRevisionID == receipt.id else { throw WorkoutCorrectionError.conflict }
        }
        if !receipt.historyAccepted {
            let latest = try await repository.fetchWorkoutSessionLog(userID: receipt.userID, sessionID: sessionID)
            guard auth.currentUserID == receipt.userID else { throw WorkoutCorrectionError.accountChanged }
            if latest.correctionRevisionID != receipt.id {
                guard try WorkoutCorrectionRevisionRules.fingerprint(latest) == WorkoutCorrectionRevisionRules.fingerprint(receipt.original) else { throw WorkoutCorrectionError.conflict }
                try await repository.commitWorkoutCorrection(userID: receipt.userID, expected: receipt.original, updated: receipt.updated)
            }
            guard auth.currentUserID == receipt.userID else { throw WorkoutCorrectionError.accountChanged }
            receipt.historyAccepted = true
            try store.save(receipt)
            NotificationCenter.default.post(name: .workoutSessionCorrected, object: receipt.userID)
        }
        if receipt.diaryResult == nil || receipt.diaryResult == .failed {
            receipt.diaryResult = await diary.reconcileWorkoutExercise(for: receipt.userID, sessionID: sessionID,
                originalDate: receipt.original.date, expected: receipt.original.generatedDiaryExercise,
                updated: receipt.updated.generatedDiaryExercise)
            guard auth.currentUserID == receipt.userID else { throw WorkoutCorrectionError.accountChanged }
            try store.save(receipt)
        }
        return receipt
    }

    /// Keep a newer saved revision, retaining the rejected proposal as an archive.
    public func abandon(_ input: WorkoutCorrectionReceipt) throws -> WorkoutCorrectionReceipt {
        guard auth.currentUserID == input.userID else { throw WorkoutCorrectionError.accountChanged }
        var archived = input
        archived.abandonedAt = Date()
        try store.save(archived)
        return archived
    }

}
