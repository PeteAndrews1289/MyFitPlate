import Foundation

public struct RunAudioPreferences: Codable, Equatable {
    public var steps = true
    public var splits = true
    public var pace = false
    public init() {}
}

/// Optional spoken pace prompts use a wider band than visual feedback and need
/// fifteen seconds of consistent fresh evidence. No prompt backlog is replayed.
public struct RunAudioCuePolicy {
    public enum Cue: Equatable { case easeBack, gentlyQuicker, paceUnavailable }
    private var stepID: String?
    private var candidate: Cue?
    private var candidateSince: Double?
    private var lastPromptAt: Double?
    private var unavailableWasSpoken = false

    public init() {}

    public mutating func resetPending() {
        candidate = nil
        candidateSince = nil
    }

    public mutating func evaluate(stepID: String?, target: RunWorkoutTarget?, pace: Double?,
                                  activeSeconds: Double, stepSeconds: Double, stepMeters: Double,
                                  isRunning: Bool, hasFreshSignal: Bool) -> Cue? {
        guard activeSeconds.isFinite, activeSeconds >= 0, isRunning else { resetPending(); return nil }
        if self.stepID != stepID {
            self.stepID = stepID
            resetPending()
            unavailableWasSpoken = false
        }
        guard let fastest = target?.fastestSecondsPerKm, let slowest = target?.slowestSecondsPerKm,
              fastest.isFinite, slowest.isFinite, fastest > 0, slowest >= fastest else { resetPending(); return nil }
        guard hasFreshSignal, let pace, pace.isFinite, pace > 0 else {
            resetPending()
            guard stepSeconds.isFinite, stepSeconds >= 30, !unavailableWasSpoken else { return nil }
            unavailableWasSpoken = true
            return .paceUnavailable
        }
        unavailableWasSpoken = false
        guard stepSeconds.isFinite, stepMeters.isFinite, stepSeconds >= 30, stepMeters >= 50 else { resetPending(); return nil }
        let cue: Cue?
        if pace < fastest - max(5, fastest * 0.02) { cue = .easeBack } else if pace > slowest + max(5, slowest * 0.02) { cue = .gentlyQuicker } else { cue = nil }
        guard let cue else { resetPending(); return nil }
        if candidate != cue { candidate = cue; candidateSince = activeSeconds; return nil }
        guard let candidateSince, activeSeconds - candidateSince >= 15,
              lastPromptAt.map({ activeSeconds - $0 >= 90 }) ?? true else { return nil }
        lastPromptAt = activeSeconds
        resetPending()
        return cue
    }
}
