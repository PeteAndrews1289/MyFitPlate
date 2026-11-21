import Foundation

public struct WorkoutSlotDateSnapshot: Codable, Equatable, Sendable {
    public let slotIndex: Int
    public let date: Date
    public let day: TrainingCalendarDay?
    public init(slotIndex: Int, date: Date, day: TrainingCalendarDay? = nil) { self.slotIndex = slotIndex; self.date = date; self.day = day }
}

public enum WorkoutLibraryEditError: Error, LocalizedError {
    case activeProgram, activeWorkout, scheduleFrequency, changed
    public var errorDescription: String? {
        switch self {
        case .activeProgram: "Choose a different active plan before archiving this one. Its progress and history are kept."
        case .activeWorkout: "Finish or discard the recoverable workout before changing this plan's schedule or archive status."
        case .scheduleFrequency: "This block is already in progress. Keep its number of training days, or create a separate next block for a new frequency."
        case .changed: "This plan changed. Reopen its latest version before making this change."
        }
    }
}

public enum WorkoutLibraryRules {
    public static func archiving(_ program: WorkoutProgram, archived: Bool, activeProgramID: String?,
                                 hasLinkedDraft: Bool = false, now: Date = Date()) throws -> WorkoutProgram {
        guard let id = program.id, !id.isEmpty, !id.contains("/"), id.utf8.count <= 1_500 else { throw WorkoutLibraryEditError.changed }
        if archived {
            guard program.id != activeProgramID else { throw WorkoutLibraryEditError.activeProgram }
            guard !hasLinkedDraft else { throw WorkoutLibraryEditError.activeWorkout }
        }
        var updated = program; updated.archivedAt = archived ? now : nil
        return updated
    }

    public static func preservingPassedDates(in proposal: WorkoutProgram, from latest: WorkoutProgram,
                                             protectedSlots: Set<Int> = [], calendar: Calendar = .current) throws -> WorkoutProgram {
        guard proposal.id == latest.id, proposal.userID == latest.userID else { throw WorkoutLibraryEditError.changed }
        var updated = proposal
        let changed = proposal.startDate != latest.startDate || proposal.daysOfWeek != latest.daysOfWeek
        var dates = Dictionary((latest.slotDateSnapshots ?? []).map { ($0.slotIndex, $0) }, uniquingKeysWith: { first, _ in first })
        if changed {
            guard protectedSlots.isEmpty else { throw WorkoutLibraryEditError.activeWorkout }
            updated.scheduleAnchorDay = proposal.startDate.map { TrainingCalendarDay($0, calendar: calendar) }
            let progress = max(latest.currentProgressIndex ?? 0, 0)
            guard progress == 0 || proposal.daysOfWeek?.count == latest.daysOfWeek?.count else { throw WorkoutLibraryEditError.scheduleFrequency }
            if let block = latest.trainingBlock, proposal.daysOfWeek?.count != block.sessionsPerWeek { throw WorkoutLibraryEditError.scheduleFrequency }
            for index in 0..<min(progress, latest.totalSlots) {
                if dates[index] == nil, let date = latest.date(forSlot: index, calendar: calendar) { dates[index] = WorkoutSlotDateSnapshot(slotIndex: index, date: date, day: TrainingCalendarDay(date, calendar: calendar)) }
            }
        }
        updated.slotDateSnapshots = dates.isEmpty ? nil : dates.sorted { $0.key < $1.key }.map(\.value)
        return updated
    }

    /// Ordinary document writes are monotonic in progress. A delayed schedule or
    /// title save cannot rewind a more recent completion or reinterpret passed dates.
    public static func mergingQueuedProgram(_ queued: WorkoutProgram, with latest: WorkoutProgram) throws -> WorkoutProgram {
        var updated = try preservingPassedDates(in: queued, from: latest)
        updated.currentProgressIndex = max(queued.currentProgressIndex ?? 0, latest.currentProgressIndex ?? 0)
        let skipped = Set(queued.skippedIndices ?? []).union(latest.skippedIndices ?? []).sorted()
        updated.skippedIndices = skipped.isEmpty ? nil : skipped
        if queued.progressEpoch != latest.progressEpoch {
            updated.currentProgressIndex = latest.currentProgressIndex; updated.skippedIndices = latest.skippedIndices
        }
        updated.progressEpoch = latest.progressEpoch
        updated.lastSkipReceipt = latest.lastSkipReceipt
        updated.slotCompletionProofs = latest.slotCompletionProofs
        updated.trainingBlock = latest.trainingBlock
        return updated
    }
}
