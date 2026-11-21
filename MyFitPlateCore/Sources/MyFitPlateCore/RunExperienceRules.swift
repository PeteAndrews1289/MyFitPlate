import Foundation

/// Quick goals accept whole minutes for compatibility, or an exact mm:ss target.
public enum RunQuickGoalRules {
    public static func durationSeconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let minutes = Int(parts[0]), (0...360).contains(minutes) else { return nil }
        let seconds: Int
        if parts.count == 2 {
            guard parts[1].count == 2, let value = Int(parts[1]), (0...59).contains(value) else { return nil }
            seconds = value
        } else { seconds = 0 }
        let total = minutes * 60 + seconds
        return (1...21_600).contains(total) ? Double(total) : nil
    }
}

public struct RunResultGroup: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let steps: [RunWorkoutStepResult]
    public var elapsedSeconds: Double { steps.reduce(0) { $0 + $1.elapsedSeconds } }
    public var distanceMeters: Double { steps.reduce(0) { $0 + $1.distanceMeters } }
}

public enum RunResultPresentation {
    /// Reuse the immutable complete prescription, applying only an exact, ordered
    /// accepted goal-revision chain to a fresh copy. Historical evidence is untouched.
    public static func repeatPlan(_ result: RunWorkoutResult, metric: Bool, newID: String = UUID().uuidString) -> RunWorkoutPlan? {
        guard let original = result.planSnapshot, original.id == result.planID,
              (try? RunWorkoutPlanStore.validate(original)) != nil else { return nil }
        let revisions = result.goalRevisions ?? []
        guard !revisions.isEmpty else { return original }
        guard original.steps.count == 1, revisions.count <= 100,
              Set(revisions.map(\.id)).count == revisions.count, !newID.isEmpty, newID != original.id else { return nil }
        var step = original.steps[0]
        var previousTime = 0.0, previousDistance = 0.0
        let observedTime = result.steps.map(\.endedAtElapsedSeconds).max() ?? 0
        let observedDistance = result.steps.map(\.endedAtDistanceMeters).max() ?? 0
        for revision in revisions {
            guard !revision.id.isEmpty, revision.stepID == step.id, revision.previousGoal == step.goal,
                  revision.revisedGoal != step.goal, RunWorkoutGoalRevision.sameKind(step.goal, revision.revisedGoal),
                  revision.activeSeconds.isFinite, revision.distanceMeters.isFinite,
                  revision.activeSeconds >= previousTime, revision.activeSeconds <= observedTime,
                  revision.distanceMeters >= previousDistance, revision.distanceMeters <= observedDistance,
                  RunWorkoutGoalRevision.isSupported(step.goal, beyondSeconds: revision.activeSeconds, beyondMeters: revision.distanceMeters),
                  RunWorkoutGoalRevision.isSupported(revision.revisedGoal, beyondSeconds: revision.activeSeconds, beyondMeters: revision.distanceMeters) else { return nil }
            step.goal = revision.revisedGoal; previousTime = revision.activeSeconds; previousDistance = revision.distanceMeters
        }
        guard result.steps.allSatisfy({ $0.stepIndex == 0 && $0.step.id == step.id && $0.step.goal == step.goal }) else { return nil }
        let name: String
        switch step.goal {
        case .duration(let seconds):
            name = seconds.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(seconds / 60)) min run" : "\(RunFormat.durationText(seconds: seconds)) run"
        case .distance(let meters): name = "\(RunFormat.distanceText(meters: meters, metric: metric)) run"
        case .open: return nil
        }
        let copy = RunWorkoutPlan(id: newID, name: name, subtitle: "Repeat · final reviewed goal", steps: [step])
        return (try? RunWorkoutPlanStore.validate(copy)) != nil ? copy : nil
    }

    /// Group only explicit outline paths or an actual work/recovery sequence;
    /// never coalesce arbitrary steps merely because their names match.
    public static func groups(_ result: RunWorkoutResult) -> [RunResultGroup] {
        var groups: [RunResultGroup] = []
        var repeatNumber = 0
        var repeatKey: String?
        for step in result.steps.sorted(by: { $0.stepIndex < $1.stepIndex }) {
            let path = step.step.id.split(separator: "/").dropLast()
            let key: String
            let title: String
            if let first = path.first {
                key = String(first)
                title = "Repeat \(String(first).split(separator: ".").last.map(String.init) ?? "")"
            } else if step.step.kind == .hard {
                repeatNumber += 1
                key = "effort.\(step.stepIndex)"
                repeatKey = key
                title = "Effort \(repeatNumber)"
            } else if step.step.kind == .recovery, let last = groups.last, last.id == repeatKey {
                key = last.id; title = last.title
            } else {
                key = "step.\(step.stepIndex)"; title = step.step.kind.displayName; repeatKey = nil
            }
            if let last = groups.last, last.id == key {
                groups[groups.count - 1] = RunResultGroup(id: key, title: last.title, steps: last.steps + [step])
            } else { groups.append(RunResultGroup(id: key, title: title, steps: [step])) }
        }
        return groups
    }

    public static func observedStepsDraft(_ result: RunWorkoutResult) -> RunWorkoutPlan? {
        guard !result.steps.isEmpty else { return nil }
        let steps = result.steps.sorted { $0.stepIndex < $1.stepIndex }.enumerated().map { index, value in
            RunWorkoutStep(id: "step-\(index)", kind: value.step.kind, title: value.step.title, goal: value.step.goal, target: value.step.target)
        }
        let plan = RunWorkoutPlan(name: "\(result.planName) copy", subtitle: "Observed steps only · review before starting", steps: steps)
        return (try? RunWorkoutPlanStore.validate(plan)) != nil ? plan : nil
    }
}

public enum RunComparisonRules {
    public enum Effort: String, CaseIterable { case steady, structured }
    public static func effort(_ run: Run) -> Effort {
        (run.workoutResult?.steps.count ?? 0) > 1 ? .structured : .steady
    }
    /// Comparisons are observational, require the same indoor/outdoor setting and
    /// session type, and exclude the same recording even after Health reidentifies it.
    public static func eligible(for run: Run, among history: [Run]) -> [Run] {
        guard run.distanceMeters >= 500, run.averagePaceSecondsPerKm != nil else { return [] }
        return history.filter { other in
            RunReviewStore.identity(other) != RunReviewStore.identity(run)
                && other.startDate < run.startDate && other.isIndoor == run.isIndoor
                && effort(other) == effort(run) && other.averagePaceSecondsPerKm != nil
                && other.distanceMeters >= run.distanceMeters * 0.8 && other.distanceMeters <= run.distanceMeters * 1.2
        }.sorted { $0.startDate > $1.startDate }
    }
    public static func easyRuns(_ runs: [Run]) -> [Run] {
        runs.filter { run in
            guard let result = run.workoutResult, !result.steps.isEmpty else { return false }
            return result.steps.allSatisfy { step in
                let cue = step.step.target?.cue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                return step.step.kind != .hard || ["easy", "easy run", "easy effort", "easy jog", "easy jog or walk", "conversational", "comfortable conversational effort"].contains(cue)
            }
        }
    }
}

public enum RunPauseCorrectionRules {
    public struct Review: Equatable {
        public let activeSeconds: Double
        public let excludedSeconds: Double
        public let timeline: RunPauseTimeline
    }
    /// This is a MyFitPlate timing overlay. Original GPS distance, route, step
    /// receipts and Health evidence are immutable. Recovery gaps cannot be erased.
    public static func review(original: Run, timeline: RunPauseTimeline) -> Review? {
        guard original.source == .recorded, original.pauseTimeline?.completeness == .complete,
              timeline.completeness == .complete, timeline.openPause == nil,
              timeline.intervals.allSatisfy({ $0.endDate > $0.startDate }),
              original.startDate < original.endDate else { return nil }
        let elapsed = original.endDate.timeIntervalSince(original.startDate)
        // A partial timeline permits validating its union before deriving the exact active clock.
        let partial = RunPauseTimeline(completeness: .partial, intervals: timeline.intervals)
        guard let intervals = partial.validatedUnionIntervals(startDate: original.startDate, endDate: original.endDate, activeSeconds: 0) else { return nil }
        let excluded = intervals.reduce(0) { $0 + $1.duration }
        let active = elapsed - excluded
        guard active >= 1, active.isFinite,
              timeline.validatedUnionIntervals(startDate: original.startDate, endDate: original.endDate, activeSeconds: active) != nil else { return nil }
        let requiredGaps = original.pauseTimeline?.intervals.filter { $0.origin == .recoveryGap } ?? []
        guard requiredGaps.allSatisfy({ timeline.intervals.contains($0) }) else { return nil }
        // New gaps must not be mislabeled as a measured recovery event.
        guard timeline.intervals.filter({ $0.origin == .recoveryGap }).allSatisfy({ requiredGaps.contains($0) }) else { return nil }
        return Review(activeSeconds: active, excludedSeconds: excluded, timeline: timeline)
    }
}

public struct RunRoutePaceSlice: Identifiable, Equatable {
    public let id: Int
    public let fixes: [RunLocationFix]
    public let secondsPerKm: Double
}

public enum RunRoutePaceOverlay {
    /// Short windows of accepted route evidence, never bridged across segment,
    /// bad-fix, pause or sensor-gap boundaries. This is an estimate, not an effort score.
    public static func slices(_ segments: [[RunLocationFix]]) -> [RunRoutePaceSlice] {
        var result: [RunRoutePaceSlice] = []
        for segment in segments {
            var window: [RunLocationFix] = []
            var meters = 0.0
            func appendWindow() {
                guard let first = window.first, let last = window.last, meters >= 5,
                      last.timestamp > first.timestamp else { return }
                result.append(RunRoutePaceSlice(id: result.count, fixes: window,
                    secondsPerKm: last.timestamp.timeIntervalSince(first.timestamp) / meters * 1000))
            }
            for fix in segment {
                guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= RunSession.accuracyCutoffMeters,
                      fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90, abs(fix.longitude) <= 180 else {
                    appendWindow(); window = []; meters = 0; continue
                }
                if let previous = window.last {
                    let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
                    let distance = RunSession.haversineMeters(lat1: previous.latitude, lon1: previous.longitude, lat2: fix.latitude, lon2: fix.longitude)
                    guard seconds > 0, seconds <= 15, distance.isFinite,
                          distance / seconds <= RunSession.maxPlausibleSpeedMetersPerSecond else {
                        appendWindow(); window = [fix]; meters = 0; continue
                    }
                    meters += distance
                }
                window.append(fix)
                if let first = window.first, fix.timestamp.timeIntervalSince(first.timestamp) >= 20 {
                    appendWindow(); window = [fix]; meters = 0
                }
            }
            appendWindow()
        }
        return result
    }
}
