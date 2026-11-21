import Foundation

/// A submitted manual run is immutable until its full local record is accepted.
/// This is a save receipt, not an automatic draft of an unsubmitted form.
public struct TreadmillRunSubmission: Codable, Equatable {
    public let completion: RunRecordingCompletion
    public let metric: Bool
    public let distanceInput: String
    public let minutesInput: String
    public let secondsInput: String

    public init(run: Run, weightLbs: Double, metric: Bool, distanceInput: String, minutesInput: String, secondsInput: String) {
        completion = RunRecordingCompletion(run: run, weightLbs: weightLbs)
        self.metric = metric
        self.distanceInput = distanceInput
        self.minutesInput = minutesInput
        self.secondsInput = secondsInput
    }

    fileprivate var isValid: Bool {
        let run = completion.run
        guard completion.weightLbs.isFinite, completion.weightLbs > 0,
              RunFallbackStore.isValid(run), RunSaveReviewRules.canSave(run),
              run.source == .recorded, run.isIndoor, run.saveReview != nil,
              [distanceInput, minutesInput, secondsInput].allSatisfy({ !$0.isEmpty && $0.count <= 64 }),
              let distance = Double(distanceInput.replacingOccurrences(of: ",", with: ".")),
              distance.isFinite, distance >= 0, distance <= (metric ? 80 : 50),
              let minutes = Int(minutesInput), let seconds = Int(secondsInput),
              (0...360).contains(minutes), (0..<60).contains(seconds),
              (1...21_600).contains(minutes * 60 + seconds),
              abs(run.distanceMeters - distance * (metric ? 1000 : RunFormat.metersPerMile)) < 0.001,
              run.movingSeconds == Double(minutes * 60 + seconds) else { return false }
        return true
    }
}

public final class TreadmillRunSubmissionStore {
    public static let scope = "run.treadmill.submitted.v1"
    private static let lock = NSLock()
    private let drafts: EditorDraftStore
    public init(drafts: EditorDraftStore = EditorDraftStore()) { self.drafts = drafts }

    public func load(userID: String) throws -> TreadmillRunSubmission? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try read(userID: userID)
    }

    public func prepare(_ submission: TreadmillRunSubmission, userID: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard submission.isValid else { throw CocoaError(.coderInvalidValue) }
        if let existing = try read(userID: userID) {
            guard existing == submission else { throw CocoaError(.fileWriteFileExists) }
            return
        }
        try drafts.save(submission, userID: userID, scope: Self.scope)
    }

    /// A late completion can only clear the exact submission it saved.
    @discardableResult
    public func complete(_ submission: TreadmillRunSubmission, userID: String) throws -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try drafts.removeIfUnchanged(TreadmillRunSubmission.self, userID: userID,
            scope: Self.scope, fingerprint: PlanFingerprint.make(submission))
    }

    private func read(userID: String) throws -> TreadmillRunSubmission? {
        guard let saved = try drafts.load(TreadmillRunSubmission.self, userID: userID, scope: Self.scope) else { return nil }
        guard saved.value.isValid else { throw CocoaError(.coderReadCorrupt) }
        return saved.value
    }
}
