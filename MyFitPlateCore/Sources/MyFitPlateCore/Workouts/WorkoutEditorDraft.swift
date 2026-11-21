import Foundation

public struct ProgramEditorDraft: Codable {
    public var program: WorkoutProgram
    public var baseline: WorkoutProgram
    public var pendingRoutine: WorkoutRoutine?

    public init(program: WorkoutProgram, baseline: WorkoutProgram, pendingRoutine: WorkoutRoutine? = nil) {
        self.program = program
        self.baseline = baseline
        self.pendingRoutine = pendingRoutine
    }

    public func preparedForSave(latest: WorkoutProgram?) throws -> WorkoutProgram {
        if let latest { try WorkoutProgramEditRules.validateOrdinarySave(program, against: latest) }
        return preservingProgress(from: latest)
    }

    /// Editing a plan must not rewind workouts completed since the editor was opened.
    public func preservingProgress(from latest: WorkoutProgram?) -> WorkoutProgram {
        var result = program
        if let latest, latest.id == program.id, latest.userID == program.userID {
            result.currentProgressIndex = latest.currentProgressIndex
            result.skippedIndices = latest.skippedIndices
            // This legacy editor edits the rotation, not authored week overrides.
            result.trainingBlock = latest.trainingBlock
        }
        return result
    }
}

public enum WorkoutProgramEditRules {
    /// A pre-block draft can still contain useful name/schedule edits, but cannot
    /// rewrite the rotation now referenced by authored weeks. Keep it for review.
    public static func validateOrdinarySave(_ proposal: WorkoutProgram, against canonical: WorkoutProgram) throws {
        guard proposal.id == canonical.id, proposal.userID == canonical.userID else { throw WorkoutBlockError.accountChanged }
        guard canonical.trainingBlock != nil else { return }
        guard try WorkoutBlockRules.fingerprint(proposal.routines) == WorkoutBlockRules.fingerprint(canonical.routines) else {
            throw WorkoutBlockError.authoredRotationChanged
        }
    }
}

public struct RoutineEditorDraft: Codable {
    public var routine: WorkoutRoutine
    public var baseline: WorkoutRoutine

    public init(routine: WorkoutRoutine, baseline: WorkoutRoutine) {
        self.routine = routine
        self.baseline = baseline
    }
}
