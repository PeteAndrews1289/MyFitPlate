import Foundation

public struct RunTrainingBlockLibrary: Codable {
    public var schemaVersion = 1
    public var blocks: [RunTrainingBlock] = []
    public var acceptedReviews: [String: String] = [:]
    public var abandonedAttempts: [RunBlockOutcome] = []
    public var brief: RunTrainingBlockBrief?
    public var pendingReview: RunTrainingBlockChange?
    public init() {}
}

/// One atomic account-scoped device document owns blocks and acceptance receipts.
/// Calendar commitments are projections, never a second independently saved schedule.
@MainActor public final class RunTrainingBlockStore {
    private let store: EditorDraftStore
    private let auth: AuthServiceProtocol
    private static let scope = "run-training-block-library-v1"
    public init(store: EditorDraftStore = EditorDraftStore(), auth: AuthServiceProtocol? = nil) {
        self.store = store; self.auth = auth ?? DIContainer.shared.authService
    }
    public func library(userID: String) throws -> RunTrainingBlockLibrary {
        try check(userID)
        let value = try store.load(RunTrainingBlockLibrary.self, userID: userID, scope: Self.scope)?.value ?? .init()
        guard value.schemaVersion == 1, value.blocks.allSatisfy({ $0.schemaVersion == 1 }),
              Set(value.blocks.map(\.id)).count == value.blocks.count else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    public func saveBrief(_ brief: RunTrainingBlockBrief, userID: String) throws {
        var value = try library(userID: userID); value.brief = brief; try save(value, userID: userID)
    }
    public func stage(_ review: RunTrainingBlockChange, userID: String) throws {
        var value = try library(userID: userID)
        guard review.ownerID == userID else { throw RunTrainingBlockError.accountChanged }
        guard value.blocks.first(where: { $0.id == review.after.id }) == review.before else { throw RunTrainingBlockError.changed }
        value.pendingReview = review; try save(value, userID: userID)
    }
    public func discardReview(id: String, userID: String) throws {
        var value = try library(userID: userID)
        guard value.pendingReview?.id == id else { throw RunTrainingBlockError.changed }
        value.pendingReview = nil; try save(value, userID: userID)
    }
    @discardableResult
    public func accept(_ review: RunTrainingBlockChange, userID: String, strengthDays: Set<TrainingCalendarDay>,
                       otherCommitments: [TrainingRunCommitment] = [], now: Date = Date()) throws -> RunTrainingBlock {
        var value = try library(userID: userID)
        guard review.ownerID == userID else { throw RunTrainingBlockError.accountChanged }
        let fingerprint = try PlanFingerprint.make(review)
        if let accepted = value.acceptedReviews[review.id] {
            guard accepted == fingerprint, let current = value.blocks.first(where: { $0.id == review.after.id }) else { throw RunTrainingBlockError.changed }
            return current
        }
        guard value.blocks.first(where: { $0.id == review.after.id }) == review.before,
              value.pendingReview?.id == review.id,
              try value.pendingReview.map(PlanFingerprint.make) == fingerprint else { throw RunTrainingBlockError.changed }
        let otherBlockRuns = value.blocks.filter { $0.id != review.after.id }.flatMap { block in block.slots.compactMap { block.commitment(for: $0) } }
        try RunTrainingBlockRules.validateChange(from: review.before, to: review.after,
            strengthDays: strengthDays, otherCommitments: otherCommitments + otherBlockRuns, now: now)
        value.blocks.removeAll { $0.id == review.after.id }; value.blocks.append(review.after)
        value.acceptedReviews[review.id] = fingerprint; value.pendingReview = nil
        try save(value, userID: userID)
        return review.after
    }
    public func commitments(userID: String) throws -> [TrainingRunCommitment] {
        try library(userID: userID).blocks.flatMap { block in block.slots.compactMap { block.commitment(for: $0) } }
    }
    public func recordStarted(context: RunScheduledContext, recordingID: String, userID: String, now: Date = Date()) throws {
        guard context.blockID != nil else { return }
        var value = try library(userID: userID)
        let (block, slot) = try position(context, library: value)
        guard !recordingID.isEmpty else { throw RunTrainingBlockError.invalid }
        if let outcome = value.blocks[block].slots[slot].outcome {
            guard outcome.recordingID == recordingID, outcome.prescription == context else { throw RunTrainingBlockError.completed }
            return
        }
        value.blocks[block].slots[slot].outcome = .init(state: .started, recordingID: recordingID, acceptedAt: now, prescription: context)
        value.blocks[block].revisionID = UUID().uuidString
        try save(value, userID: userID)
    }
    public func recordCompleted(run: Run, userID: String, now: Date = Date()) throws {
        guard let context = run.scheduledContext, context.blockID != nil else { return }
        var value = try library(userID: userID)
        let (block, slot) = try position(context, library: value)
        let recordingID = run.recordingID ?? run.id
        guard run.movingSeconds.isFinite, run.movingSeconds >= 0, run.distanceMeters.isFinite, run.distanceMeters >= 0,
              run.endDate >= run.startDate else { throw RunTrainingBlockError.invalid }
        if let old = value.blocks[block].slots[slot].outcome {
            guard old.state != .skipped, old.recordingID == recordingID, old.prescription == context else { throw RunTrainingBlockError.completed }
            if old.state == .recorded { return }
        }
        value.blocks[block].slots[slot].outcome = .init(state: .recorded, recordingID: recordingID, runID: run.id,
            acceptedAt: now, actualStart: run.startDate, movingSeconds: run.movingSeconds, distanceMeters: run.distanceMeters, prescription: context)
        value.blocks[block].revisionID = UUID().uuidString
        try save(value, userID: userID)
    }
    public func recordAbandoned(context: RunScheduledContext, recordingID: String, userID: String, now: Date = Date()) throws {
        guard context.blockID != nil else { return }
        var value = try library(userID: userID)
        let (block, slot) = try position(context, library: value)
        guard var outcome = value.blocks[block].slots[slot].outcome else { return }
        guard outcome.state == .started, outcome.recordingID == recordingID, outcome.prescription == context else { throw RunTrainingBlockError.completed }
        outcome.state = .abandoned; outcome.acceptedAt = now; value.abandonedAttempts.append(outcome)
        value.blocks[block].slots[slot].outcome = nil; value.blocks[block].revisionID = UUID().uuidString
        try save(value, userID: userID)
    }
    private func position(_ context: RunScheduledContext, library: RunTrainingBlockLibrary) throws -> (Int, Int) {
        guard let block = library.blocks.firstIndex(where: { $0.id == context.blockID && !$0.archived }),
              let slot = library.blocks[block].slots.firstIndex(where: { $0.id == context.slotID }),
              context.commitmentID == context.slotID,
              library.blocks[block].slots[slot].day == context.plannedDay,
              library.blocks[block].slots[slot].revisionID == context.revisionID,
              library.blocks[block].slots[slot].plan == context.plan else { throw RunTrainingBlockError.changed }
        return (block, slot)
    }
    public func cloudSnapshot(userID: String) throws -> [String: Data] {
        let library = try library(userID: userID)
        var values: [String: Data] = [:]
        for block in library.blocks { values["block/" + block.id] = try RunCloudCodec.encode(block) }
        for (id, receipt) in library.acceptedReviews { values["receipt/" + id] = try RunCloudCodec.encode(receipt) }
        for attempt in library.abandonedAttempts {
            values["abandoned/" + (try PlanFingerprint.make(attempt))] = try RunCloudCodec.encode(attempt)
        }
        return values
    }
    public func applyCloudSnapshot(_ values: [String: Data], expectedFingerprint: String, userID: String) throws {
        let old = try cloudSnapshot(userID: userID)
        guard try PlanFingerprint.make(old) == expectedFingerprint else { throw RunCloudError.changed }
        try RunCloudCodec.preserveImmutable(old: old, new: values)
        if old == values { return }
        var library = try library(userID: userID)
        let previous = library.blocks
        library.blocks = []; library.acceptedReviews = [:]; library.abandonedAttempts = []
        for (key, data) in values.sorted(by: { $0.key < $1.key }) {
            if key.hasPrefix("block/") {
                let block = try RunCloudCodec.decode(RunTrainingBlock.self, data)
                guard key == "block/" + block.id else { throw RunCloudError.invalid }
                try Self.validateCloudBlock(block)
                library.blocks.append(block)
            } else if key.hasPrefix("receipt/") {
                let id = String(key.dropFirst(8)), fingerprint = try RunCloudCodec.decode(String.self, data)
                guard !id.isEmpty, !fingerprint.isEmpty else { throw RunCloudError.invalid }
                library.acceptedReviews[id] = fingerprint
            } else if key.hasPrefix("abandoned/") {
                let attempt = try RunCloudCodec.decode(RunBlockOutcome.self, data)
                guard key == "abandoned/" + (try PlanFingerprint.make(attempt)) else { throw RunCloudError.invalid }
                try Self.validateCloudOutcome(attempt, state: .abandoned)
                library.abandonedAttempts.append(attempt)
            } else { throw RunCloudError.invalid }
        }
        for block in previous {
            guard let next = library.blocks.first(where: { $0.id == block.id }) else { throw RunCloudError.protectedEvidence }
            for slot in block.slots where slot.outcome != nil {
                guard let updated = next.slots.first(where: { $0.id == slot.id }), let existing = slot.outcome else { throw RunCloudError.protectedEvidence }
                var unchangedPrescription = updated; unchangedPrescription.outcome = existing
                guard unchangedPrescription == slot else { throw RunCloudError.protectedEvidence }
                if updated.outcome == nil, existing.state == .started,
                   library.abandonedAttempts.contains(where: { RunCloudResolutionRules.matchesAbandonment($0, started: existing) }) { continue }
                guard let outcome = updated.outcome else { throw RunCloudError.protectedEvidence }
                let finishesSameRun = existing.state == .started && outcome.state == .recorded
                    && existing.recordingID == outcome.recordingID && existing.prescription == outcome.prescription
                guard updated.day == slot.day, updated.plan == slot.plan,
                      outcome == existing || finishesSameRun else { throw RunCloudError.protectedEvidence }
            }
        }
        // A local review remains inspectable; its existing before-state check will
        // require a fresh review if another device changed the accepted block.
        try save(library, userID: userID)
    }

    /// Cloud bytes are untrusted input even when their revision hash is valid.
    /// Validate completed slots too; ordinary editing validation only examines future slots.
    private static func validateCloudBlock(_ block: RunTrainingBlock) throws {
        let calendar = Calendar.current, brief = block.brief
        guard block.schemaVersion == 1, !block.id.isEmpty, !block.revisionID.isEmpty,
              block.createdAt.timeIntervalSinceReferenceDate.isFinite,
              (4...8).contains(brief.weeks), let start = brief.start.date(calendar: calendar),
              TrainingCalendarDay(start, calendar: calendar) == brief.start,
              brief.recentWeeklyMinutes.isFinite, (20...900).contains(brief.recentWeeklyMinutes),
              brief.recentLongestMinutes.isFinite, (10...180).contains(brief.recentLongestMinutes),
              brief.recentLongestMinutes <= brief.recentWeeklyMinutes,
              (2...4).contains(brief.weekdays.count), Set(brief.weekdays).count == brief.weekdays.count,
              brief.weekdays.allSatisfy({ (1...7).contains($0) }), brief.weekdays.contains(brief.preferredLongWeekday),
              (1...32).contains(block.slots.count), Set(block.slots.map(\.id)).count == block.slots.count,
              block.weeklyMinuteCeilings.count == brief.weeks,
              block.weeklyMinuteCeilings.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw RunCloudError.invalid }
        if let target = brief.targetDay {
            guard let targetDate = target.date(calendar: calendar), TrainingCalendarDay(targetDate, calendar: calendar) == target,
                  let finalDay = calendar.date(byAdding: .day, value: brief.weeks * 7 - 1, to: start),
                  targetDate >= finalDay else { throw RunCloudError.invalid }
        }
        for slot in block.slots {
            guard !slot.id.isEmpty, !slot.revisionID.isEmpty, let date = slot.day.date(calendar: calendar),
                  TrainingCalendarDay(date, calendar: calendar) == slot.day,
                  let days = calendar.dateComponents([.day], from: start, to: date).day,
                  (0..<(brief.weeks * 7)).contains(days), slot.weekIndex == days / 7,
                  brief.weekdays.contains(calendar.component(.weekday, from: date)),
                  slot.plannedMinutes.isFinite, (8...180).contains(slot.plannedMinutes),
                  slot.plan.steps.allSatisfy({ if case .duration = $0.goal { return true }; return false }) else { throw RunCloudError.invalid }
            try RunWorkoutPlanStore.validate(slot.plan)
            if let outcome = slot.outcome {
                guard outcome.state != .abandoned else { throw RunCloudError.invalid }
                try validateCloudOutcome(outcome, state: outcome.state)
                if outcome.state != .skipped {
                    guard let prescription = outcome.prescription, prescription.blockID == block.id,
                          prescription.slotID == slot.id, prescription.commitmentID == slot.id,
                          prescription.plannedDay == slot.day, prescription.revisionID == slot.revisionID,
                          prescription.plan == slot.plan else { throw RunCloudError.invalid }
                }
            }
        }
        // This also checks duplicate future dates and bounded per-week workload.
        try RunTrainingBlockRules.validateChange(from: nil, to: block, strengthDays: [], otherCommitments: [], now: .distantFuture)
    }

    private static func validateCloudOutcome(_ outcome: RunBlockOutcome, state: RunBlockOutcome.State) throws {
        guard outcome.state == state, outcome.acceptedAt.timeIntervalSinceReferenceDate.isFinite else { throw RunCloudError.invalid }
        if state == .skipped {
            guard outcome.recordingID == nil, outcome.runID == nil, outcome.actualStart == nil,
                  outcome.movingSeconds == nil, outcome.distanceMeters == nil, outcome.prescription == nil else { throw RunCloudError.invalid }
            return
        }
        guard let recording = outcome.recordingID, !recording.isEmpty, let prescription = outcome.prescription,
              let blockID = prescription.blockID, !blockID.isEmpty,
              let slotID = prescription.slotID, !slotID.isEmpty, prescription.commitmentID == slotID,
              let revision = prescription.revisionID, !revision.isEmpty,
              let date = prescription.plannedDay.date(), TrainingCalendarDay(date) == prescription.plannedDay else { throw RunCloudError.invalid }
        try RunWorkoutPlanStore.validate(prescription.plan)
        if state == .recorded {
            guard let runID = outcome.runID, !runID.isEmpty,
                  let start = outcome.actualStart, start.timeIntervalSinceReferenceDate.isFinite, start <= outcome.acceptedAt,
                  let seconds = outcome.movingSeconds, seconds.isFinite, seconds >= 0,
                  let meters = outcome.distanceMeters, meters.isFinite, meters >= 0 else { throw RunCloudError.invalid }
        } else {
            guard outcome.runID == nil, outcome.actualStart == nil, outcome.movingSeconds == nil, outcome.distanceMeters == nil else { throw RunCloudError.invalid }
        }
    }

    private func check(_ userID: String) throws {
        guard !userID.isEmpty, auth.currentUserID == userID else { throw RunTrainingBlockError.accountChanged }
    }
    private func save(_ value: RunTrainingBlockLibrary, userID: String) throws {
        try check(userID); try store.save(value, userID: userID, scope: Self.scope)
        NotificationCenter.default.post(name: .runLibrariesChanged, object: userID)
    }
}
