import Combine
import Foundation

public struct MealCookingCheckpoint: Codable {
    public var completedStepIndexes: Set<Int> = []
    public var timerEndDate: Date?
    public var pausedTimerRemaining: TimeInterval = 0
    public var timerFinished = false
    public var lastTimerMinutes = 10
    public var additionalTimers: [NamedCookingTimer]?
    public var currentStepID: String?
    public var selectedRequirementIDs: Set<String>?
    public var stepIDs: [String]?
    /// Original positional evidence remains available after the legacy layout is translated.
    public var legacyCompletedStepIndexes: Set<Int>?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case completedStepIndexes, timerEndDate, pausedTimerRemaining, timerFinished, lastTimerMinutes, additionalTimers, currentStepID, selectedRequirementIDs, stepIDs, legacyCompletedStepIndexes
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(completedStepIndexes.sorted(), forKey: .completedStepIndexes)
        try box.encodeIfPresent(timerEndDate, forKey: .timerEndDate)
        try box.encode(pausedTimerRemaining, forKey: .pausedTimerRemaining)
        try box.encode(timerFinished, forKey: .timerFinished)
        try box.encode(lastTimerMinutes, forKey: .lastTimerMinutes)
        try box.encodeIfPresent(additionalTimers, forKey: .additionalTimers)
        try box.encodeIfPresent(currentStepID, forKey: .currentStepID)
        try box.encodeIfPresent(selectedRequirementIDs?.sorted(), forKey: .selectedRequirementIDs)
        try box.encodeIfPresent(stepIDs, forKey: .stepIDs)
        try box.encodeIfPresent(legacyCompletedStepIndexes?.sorted(), forKey: .legacyCompletedStepIndexes)
    }
}

public struct NamedCookingTimer: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var deadline: Date?
    public var pausedRemaining: TimeInterval
    public var finished: Bool
    public var stepID: String?
    public init(name: String, minutes: Int, now: Date = Date()) {
        id = UUID(); self.name = name; deadline = now.addingTimeInterval(MealPrepTimerRules.duration(minutes: minutes))
        pausedRemaining = 0; finished = false
    }
    public func remaining(now: Date = Date()) -> TimeInterval {
        deadline.map { MealPrepTimerRules.remaining(until: $0, now: now) } ?? pausedRemaining
    }
}

/// Local cooking progress belongs to the exact requirement/steps snapshot and account.
/// A clock continues across dismissal; this is an in-app timer, not a background alarm.
@MainActor
public final class MealCookingCheckpointSession: ObservableObject {
    @Published public private(set) var checkpoint = MealCookingCheckpoint()
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var restored = false
    public let userID: String?
    public let contextID: String
    private let store: EditorDraftStore
    private var unreadable = false
    private var expectedFingerprint: String?
    private var scope: String { "meal-cooking-\(contextID)" }

    public init(userID: String?, contextID: String, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.contextID = contextID; self.store = store
        guard contextID != "unreadable", let userID, DIContainer.shared.authService.currentUserID == userID else { return }
        do {
            if let saved = try store.load(MealCookingCheckpoint.self, userID: userID, scope: scope) {
                guard Self.isValid(saved.value) else { throw CocoaError(.coderReadCorrupt) }
                checkpoint = saved.value; restored = true; expectedFingerprint = try PlanFingerprint.make(saved.value)
                CookingTimerRegistry.shared.update(userID: userID, contextID: contextID, checkpoint: checkpoint)
            }
        } catch {
            unreadable = true; errorMessage = "Your previous cooking progress couldn't be opened. It has been kept on this device."
        }
    }

    public static func contextID(days: [MealPlanDay], starting date: Date? = nil) -> String {
        let basis = MealPlanCookingRules.requirements(from: days, starting: date).map { requirement in
            CookingBasis(id: requirement.id, date: requirement.date, name: requirement.name,
                ingredients: requirement.ingredients.map(MealCookingIngredient.init), instructions: requirement.instructions)
        }
        let start = Calendar.current.startOfDay(for: date ?? days.map(\.date).min() ?? Date())
        return (try? PlanFingerprint.make(CookingContext(start: start, requirements: basis))) ?? "unreadable"
    }

    private struct CookingContext: Codable {
        let start: Date
        let requirements: [CookingBasis]
    }

    private struct CookingBasis: Codable {
        let id: String
        let date: Date
        let name: String
        let ingredients: [MealCookingIngredient]
        let instructions: String?
    }

    public func remaining(now: Date = Date()) -> TimeInterval {
        if let deadline = checkpoint.timerEndDate { return MealPrepTimerRules.remaining(until: deadline, now: now) }
        return checkpoint.pausedTimerRemaining
    }

    public var isRunning: Bool { checkpoint.timerEndDate != nil }

    public func refreshFromDisk() {
        guard !unreadable, let userID, DIContainer.shared.authService.currentUserID == userID else { return }
        do {
            guard let saved = try store.load(MealCookingCheckpoint.self, userID: userID, scope: scope)?.value else { return }
            guard Self.isValid(saved) else { throw CocoaError(.coderReadCorrupt) }
            let fingerprint = try PlanFingerprint.make(saved)
            if fingerprint != expectedFingerprint { checkpoint = saved; expectedFingerprint = fingerprint }
        } catch { errorMessage = "A saved cooking update could not be read. Your current progress is kept." }
    }

    private static func isValid(_ value: MealCookingCheckpoint) -> Bool {
        let timers = value.additionalTimers ?? []
        guard value.pausedTimerRemaining.isFinite, value.pausedTimerRemaining >= 0,
              value.timerEndDate.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              value.completedStepIndexes.allSatisfy({ $0 >= 0 }),
              value.legacyCompletedStepIndexes?.allSatisfy({ $0 >= 0 }) ?? true,
              (1...120).contains(value.lastTimerMinutes), timers.count <= 12,
              Set(timers.map(\.id)).count == timers.count,
              timers.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.pausedRemaining.isFinite && $0.pausedRemaining >= 0
                  && ($0.deadline.map { $0.timeIntervalSince1970.isFinite } ?? true) }) else { return false }
        guard let ids = value.stepIDs else { return true }
        return ids.allSatisfy { !$0.isEmpty } && Set(ids).count == ids.count
            && value.completedStepIndexes.allSatisfy { ids.indices.contains($0) }
    }

    /// Binds checks to stable step identities before the screen uses its current layout.
    /// A legacy check belongs only to the first recipe occurrence it actually displayed;
    /// identical meals never acquire inferred completion. Timers and selected prep stay intact.
    @discardableResult public func reconcileStepLayout(steps: [CookingSessionStep], legacyStepIDs: [String]) -> Bool {
        let ids = steps.map(\.id)
        let originalIDs = checkpoint.stepIDs ?? legacyStepIDs
        guard ids.allSatisfy({ !$0.isEmpty }), originalIDs.allSatisfy({ !$0.isEmpty }),
              Set(ids).count == ids.count, Set(originalIDs).count == originalIDs.count,
              checkpoint.completedStepIndexes.allSatisfy({ originalIDs.indices.contains($0) }) else {
            errorMessage = "Previous cooking checks couldn't be matched safely. They are kept on this device; timers remain available."
            return false
        }
        let completed = Set(checkpoint.completedStepIndexes.map { originalIDs[$0] })
        guard completed.isSubset(of: Set(ids)) else {
            errorMessage = "Some previous cooking steps are unavailable. Their progress is kept; reopen the original prep session."
            return false
        }
        guard checkpoint.stepIDs != ids else { return true }
        var next = checkpoint
        if next.stepIDs == nil, ids != originalIDs, !next.completedStepIndexes.isEmpty {
            next.legacyCompletedStepIndexes = next.completedStepIndexes
        }
        next.stepIDs = ids
        next.completedStepIndexes = Set(ids.indices.filter { completed.contains(ids[$0]) })
        return persist(next)
    }

    @discardableResult
    public func toggleStep(_ index: Int, stepCount: Int) -> Bool {
        guard (0..<stepCount).contains(index) else { return false }
        var next = checkpoint
        if next.completedStepIndexes.contains(index) { next.completedStepIndexes.remove(index) } else { next.completedStepIndexes.insert(index) }
        return persist(next)
    }

    @discardableResult public func toggleGuidedStep(_ index: Int, steps: [CookingSessionStep], advanceWhenComplete: Bool = false) -> Bool {
        guard steps.indices.contains(index) else { return false }
        guard checkpoint.stepIDs.map({ $0 == steps.map(\.id) }) ?? true else {
            errorMessage = "Cooking steps changed. Refresh before changing their progress."; return false
        }
        var next = checkpoint
        let complete = Set(next.completedStepIndexes.filter { steps.indices.contains($0) }.map { steps[$0].id })
        next.currentStepID = steps[index].id
        if complete.contains(steps[index].id) {
            var removed = Set([steps[index].id])
            var previous = -1
            while previous != removed.count {
                previous = removed.count
                removed.formUnion(steps.filter { !Set($0.prerequisites).isDisjoint(with: removed) }.map(\.id))
            }
            next.completedStepIndexes = next.completedStepIndexes.filter { steps.indices.contains($0) && !removed.contains(steps[$0].id) }
        } else {
            guard CookingSessionRules.canComplete(steps[index], completed: complete) else { errorMessage = "Complete this recipe's earlier step first, or review the recipe order."; return false }
            next.completedStepIndexes.insert(index)
            if advanceWhenComplete {
                let visible = steps.indices.filter {
                    next.selectedRequirementIDs?.contains(steps[$0].requirementID) ?? true
                }
                let remaining = visible.filter { !next.completedStepIndexes.contains($0) }
                if let following = remaining.first(where: { $0 > index }) ?? remaining.first {
                    next.currentStepID = steps[following].id
                }
            }
        }
        return persist(next)
    }

    @discardableResult public func selectRequirements(_ ids: Set<String>, available: Set<String>) -> Bool {
        guard ids.isSubset(of: available) else { return false }
        var next = checkpoint; next.selectedRequirementIDs = ids; return persist(next)
    }

    @discardableResult
    public func startTimer(minutes: Int, now: Date = Date()) -> Bool {
        var next = checkpoint
        next.lastTimerMinutes = MealPrepTimerRules.clampedMinutes(minutes)
        next.timerEndDate = now.addingTimeInterval(MealPrepTimerRules.duration(minutes: next.lastTimerMinutes))
        next.pausedTimerRemaining = 0; next.timerFinished = false
        return persist(next)
    }

    @discardableResult
    public func pauseTimer(now: Date = Date()) -> Bool {
        var next = checkpoint
        next.pausedTimerRemaining = remaining(now: now); next.timerEndDate = nil
        next.timerFinished = next.pausedTimerRemaining == 0
        return persist(next)
    }

    @discardableResult
    public func resumeTimer(now: Date = Date()) -> Bool {
        guard checkpoint.timerEndDate == nil, checkpoint.pausedTimerRemaining > 0 else { return false }
        var next = checkpoint
        next.timerEndDate = now.addingTimeInterval(next.pausedTimerRemaining)
        next.pausedTimerRemaining = 0; next.timerFinished = false
        return persist(next)
    }

    @discardableResult
    public func clearTimer() -> Bool {
        var next = checkpoint; next.timerEndDate = nil; next.pausedTimerRemaining = 0; next.timerFinished = false
        return persist(next)
    }

    @discardableResult
    public func finishExpiredTimer(now: Date = Date()) -> Bool {
        guard checkpoint.timerEndDate != nil, remaining(now: now) <= 0 else { return false }
        var next = checkpoint; next.timerEndDate = nil; next.pausedTimerRemaining = 0; next.timerFinished = true
        return persist(next)
    }

    @discardableResult
    public func addNamedTimer(name: String, minutes: Int, stepID: String? = nil, now: Date = Date()) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return false }
        guard (checkpoint.additionalTimers ?? []).count < 12 else {
            errorMessage = "Remove a timer before adding another. You can keep up to 12 cooking timers."
            return false
        }
        var next = checkpoint
        var timer = NamedCookingTimer(name: trimmed, minutes: minutes, now: now); timer.stepID = stepID
        next.additionalTimers = (next.additionalTimers ?? []) + [timer]
        return persist(next)
    }

    @discardableResult
    public func changeNamedTimer(id: UUID, remove: Bool = false, now: Date = Date()) -> Bool {
        var next = checkpoint
        guard var timers = next.additionalTimers, let index = timers.firstIndex(where: { $0.id == id }) else { return false }
        if remove { timers.remove(at: index) } else if timers[index].deadline != nil {
            timers[index].pausedRemaining = timers[index].remaining(now: now); timers[index].deadline = nil
            timers[index].finished = timers[index].pausedRemaining <= 0
        } else if timers[index].pausedRemaining > 0 {
            timers[index].deadline = now.addingTimeInterval(timers[index].pausedRemaining); timers[index].pausedRemaining = 0
        }
        next.additionalTimers = timers
        return persist(next)
    }

    @discardableResult
    public func finishExpiredNamedTimers(now: Date = Date()) -> Bool {
        var next = checkpoint
        guard var timers = next.additionalTimers else { return false }
        var changed = false
        for index in timers.indices where timers[index].deadline != nil && timers[index].remaining(now: now) <= 0 {
            timers[index].deadline = nil; timers[index].pausedRemaining = 0; timers[index].finished = true; changed = true
        }
        guard changed else { return false }
        next.additionalTimers = timers; return persist(next)
    }

    @discardableResult public func selectStep(_ id: String) -> Bool {
        var next = checkpoint; next.currentStepID = id; return persist(next)
    }

    @discardableResult public func adjustTimer(seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard seconds.isFinite, abs(seconds) <= 7_200 else { return false }
        var next = checkpoint
        let value = min(86_400, max(0, remaining(now: now) + seconds))
        if next.timerEndDate != nil { next.timerEndDate = value > 0 ? now.addingTimeInterval(value) : nil } else { next.pausedTimerRemaining = value }
        next.timerFinished = value == 0; return persist(next)
    }

    @discardableResult public func adjustNamedTimer(id: UUID, seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard seconds.isFinite, abs(seconds) <= 7_200 else { return false }
        var next = checkpoint
        guard var timers = next.additionalTimers, let index = timers.firstIndex(where: { $0.id == id }) else { return false }
        let remaining = min(86_400, max(0, timers[index].remaining(now: now) + seconds))
        if timers[index].deadline != nil { timers[index].deadline = remaining > 0 ? now.addingTimeInterval(remaining) : nil } else { timers[index].pausedRemaining = remaining }
        timers[index].finished = remaining == 0; next.additionalTimers = timers; return persist(next)
    }

    private func persist(_ next: MealCookingCheckpoint) -> Bool {
        guard !unreadable, contextID != "unreadable", let userID,
              DIContainer.shared.authService.currentUserID == userID else {
            if !unreadable { errorMessage = "Sign back into the account that opened this cooking plan to keep your progress." }
            return false
        }
        do {
            guard Self.isValid(next) else { throw CocoaError(.coderInvalidValue) }
            let current = try store.load(MealCookingCheckpoint.self, userID: userID, scope: scope)?.value
            guard current.map(Self.isValid) ?? true else { throw CocoaError(.coderReadCorrupt) }
            guard try current.map(PlanFingerprint.make) == expectedFingerprint else {
                errorMessage = "Cooking changed in another view. Reopen or refresh before trying this action again."; refreshFromDisk(); return false
            }
            try store.save(next, userID: userID, scope: scope)
            checkpoint = next; expectedFingerprint = try PlanFingerprint.make(next); errorMessage = nil
            CookingTimerRegistry.shared.update(userID: userID, contextID: contextID, checkpoint: next)
            return true
        } catch {
            errorMessage = "Couldn't keep this cooking change on the device. Your previous progress is still here."
            return false
        }
    }
}
