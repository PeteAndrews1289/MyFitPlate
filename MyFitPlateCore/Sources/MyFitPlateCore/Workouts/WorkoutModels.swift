import Combine
import CryptoKit
import Foundation
public enum ExerciseType: String, Codable, CaseIterable {
    case strength = "Strength"
    case cardio = "Cardio"
    case flexibility = "Flexibility"
}

public struct WorkoutProgram: Identifiable, Codable {
    public var id: String?
    public var userID: String
    public var name: String
    public var dateCreated: Date
    public var routines: [WorkoutRoutine]
    public var startDate: Date?
    public var scheduleAnchorDay: TrainingCalendarDay?
    public var daysOfWeek: [Int]?
    public var currentProgressIndex: Int? = 0
    public var progressEpoch: String?
    public var slotCompletionProofs: [WorkoutSlotCompletionProof]?
    public var lastSkipReceipt: WorkoutProgramSkipReceipt?
    /// Slot indices the user explicitly skipped (advanced past without training). Kept so the
    /// calendar can mark them "Skipped" — distinct from completed days, which have a session log.
    public var skippedIndices: [Int]? = nil
    /// Temporary, reversible changes saved with the program as one durable write.
    public var weekRescue: WeekRescueAdjustment?
    /// Nil preserves the exact legacy rotation. Authored blocks are adopted explicitly.
    public var trainingBlock: WorkoutProgramBlock?
    /// A new block is a separate saved instance; prior records remain with their original program.
    public var lineage: WorkoutProgramLineage?
    public var archivedAt: Date?
    public var catalogRelease: WorkoutCatalogRelease?
    public var generationProvenance: WorkoutAIGenerationProvenance?
    /// Dates already passed before a schedule edit; never recalculated from its new weekdays.
    public var slotDateSnapshots: [WorkoutSlotDateSnapshot]?

    public init(id: String? = nil, userID: String, name: String, dateCreated: Date = Date(), routines: [WorkoutRoutine] = [], startDate: Date? = nil, daysOfWeek: [Int]? = nil, currentProgressIndex: Int? = 0, skippedIndices: [Int]? = nil, trainingBlock: WorkoutProgramBlock? = nil, lineage: WorkoutProgramLineage? = nil) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dateCreated = dateCreated
        self.routines = routines
        self.startDate = startDate
        self.daysOfWeek = daysOfWeek
        self.currentProgressIndex = currentProgressIndex
        self.skippedIndices = skippedIndices
        self.trainingBlock = trainingBlock
        self.lineage = lineage
    }
}

public class WorkoutRoutine: Identifiable, ObservableObject, Codable, Hashable {
    public var id: String
    public var userID: String
    @Published public var name: String
    public var dateCreated: Date
    @Published public var exercises: [RoutineExercise]
    public var notes: String?

    public enum CodingKeys: String, CodingKey {
        case id, userID, name, dateCreated, exercises, notes
    }

    public init(id: String = UUID().uuidString, userID: String, name: String, dateCreated: Date, exercises: [RoutineExercise] = [], notes: String? = nil) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dateCreated = dateCreated
        self.exercises = exercises
        self.notes = notes
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let savedUserID = try container.decode(String.self, forKey: .userID)
        let savedName = try container.decode(String.self, forKey: .name)
        let savedDate = try container.decode(Date.self, forKey: .dateCreated)
        userID = savedUserID
        name = savedName
        dateCreated = savedDate
        if let savedID = try container.decodeIfPresent(String.self, forKey: .id) {
            id = savedID
        } else {
            // Early embedded routines had no ID. A stable identity keeps reloading the
            // same legacy plan from changing its routines or orphaning later history.
            let path = decoder.codingPath.map(\.stringValue).joined(separator: "/")
            let identity = [savedUserID, savedName, String(savedDate.timeIntervalSinceReferenceDate), path]
                .joined(separator: "\u{1f}")
            id = "legacy-" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        exercises = try container.decode([RoutineExercise].self, forKey: .exercises)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(exercises, forKey: .exercises)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: WorkoutRoutine, rhs: WorkoutRoutine) -> Bool {
        lhs.id == rhs.id
    }

    public func deepCopy() -> WorkoutRoutine? {
        do {
            let data = try JSONEncoder().encode(self)
            return try JSONDecoder().decode(WorkoutRoutine.self, from: data)
        } catch {
            AppLog.workouts.error("Error deep copying workout routine: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

public struct RoutineExercise: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var name: String
    public var type: ExerciseType = .strength
    public var sets: [ExerciseSet] = []
    public var notes: String?
    public var restTimeInSeconds: Int = 60
    public var alternatives: [String]?
    public var targetSets: Int = 3
    public var targetReps: String = "8-12"
    /// The load step chosen when reviewing targets, in the app's stored weight unit (lb).
    /// Session history carries this preference forward without rewriting the program template.
    public var progressionIncrement: Double?
    public var progressionPolicy: WorkoutProgressionPolicy?
    public var movementIdentity: WorkoutMovementIdentity?
    /// Optional equipment and load convention. Legacy exercises retain their original values.
    public var loadEquipment: StrengthEquipment?

    /// Exercises that share the same non-nil id (and sit next to each other in the
    /// routine) form a superset: you alternate through them and only rest after the
    /// last one. Optional so routines saved before supersets existed decode unchanged.
    public var supersetGroupID: String?
    public var groupPlan: WorkoutExerciseGroup?
    public var substitution: WorkoutSubstitutionProvenance?
    public var cueSnapshot: WorkoutCueSnapshot?

    private enum CodingKeys: String, CodingKey {
        case id, name, type, sets, notes, restTimeInSeconds, alternatives
        case targetSets, targetReps, supersetGroupID, progressionIncrement, loadEquipment, progressionPolicy, movementIdentity, groupPlan, substitution, cueSnapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(ExerciseType.self, forKey: .type) ?? .strength
        sets = try container.decode([ExerciseSet].self, forKey: .sets)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        restTimeInSeconds = try container.decodeIfPresent(Int.self, forKey: .restTimeInSeconds) ?? 60
        alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives)
        // Legacy programs, saved routines, and history stored targets only on their sets.
        // Swift's synthesized decoder does not apply property defaults to missing keys.
        targetSets = try container.decodeIfPresent(Int.self, forKey: .targetSets)
            ?? (sets.isEmpty ? 3 : sets.count)
        targetReps = try container.decodeIfPresent(String.self, forKey: .targetReps)
            ?? sets.compactMap(\.target).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? "8-12"
        supersetGroupID = try container.decodeIfPresent(String.self, forKey: .supersetGroupID)
        groupPlan = try container.decodeIfPresent(WorkoutExerciseGroup.self, forKey: .groupPlan)
        substitution = try container.decodeIfPresent(WorkoutSubstitutionProvenance.self, forKey: .substitution)
        cueSnapshot = try container.decodeIfPresent(WorkoutCueSnapshot.self, forKey: .cueSnapshot)
        progressionIncrement = try container.decodeIfPresent(Double.self, forKey: .progressionIncrement)
        loadEquipment = try container.decodeIfPresent(StrengthEquipment.self, forKey: .loadEquipment)
        progressionPolicy = try container.decodeIfPresent(WorkoutProgressionPolicy.self, forKey: .progressionPolicy)
        movementIdentity = try container.decodeIfPresent(WorkoutMovementIdentity.self, forKey: .movementIdentity)
    }

    public init(id: String = UUID().uuidString, name: String, type: ExerciseType = .strength, sets: [ExerciseSet] = [], notes: String? = nil, restTimeInSeconds: Int = 60, alternatives: [String]? = nil, targetSets: Int = 3, targetReps: String = "8-12", supersetGroupID: String? = nil, loadEquipment: StrengthEquipment? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.sets = sets
        self.notes = notes
        self.restTimeInSeconds = restTimeInSeconds
        self.alternatives = alternatives
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.supersetGroupID = supersetGroupID
        self.loadEquipment = loadEquipment
    }
}

/// The role of a set within an exercise. Only working sets (`normal`/`drop`/`failure`)
/// count toward volume, 1RM, and PRs; `warmup` sets are excluded from that math.
public enum SetType: String, Codable, CaseIterable, Sendable {
    case warmup, normal, drop, failure

    public var shortLabel: String {
        switch self {
        case .warmup: return "W"
        case .normal: return ""
        case .drop: return "D"
        case .failure: return "F"
        }
    }
}

/// A single effort rating on a set. The user chooses in Settings whether they log
/// RPE or RIR; we store exactly what they entered plus which scale it was on (honest
/// to the app's trust ethos), and normalize to RPE only when analytics need one axis.
public struct SetEffort: Codable, Equatable, Sendable {
    public enum Scale: String, Codable, Sendable { case rpe, rir }
    public var scale: Scale
    public var value: Double

    public init(scale: Scale, value: Double) {
        self.scale = scale
        self.value = value
    }

    /// RPE-6…10 equivalent. RIR maps as RPE = 10 − RIR; both clamp to a sane band.
    public var normalizedRPE: Double {
        switch scale {
        case .rpe: return min(10, max(1, value))
        case .rir: return min(10, max(1, 10 - value))
        }
    }
}

public enum SupersetRules {
    /// Where an exercise sits inside its superset group.
    public struct Position: Equatable, Sendable {
        public let isInSuperset: Bool
        public let isFirstInGroup: Bool
        public let isLastInGroup: Bool
        /// "A", "B", … assigned per distinct group in order of appearance; nil when standalone.
        public let groupLabel: String?

        public static let standalone = Position(isInSuperset: false, isFirstInGroup: false, isLastInGroup: false, groupLabel: nil)
    }

    /// Superset positions for a routine. A group is a run of 2+ *adjacent* exercises that
    /// share the same non-nil `supersetGroupID`; a lone tagged exercise is treated as standalone.
    public static func positions(for exercises: [RoutineExercise]) -> [Position] {
        var labels: [String: String] = [:]
        var nextLabel = 0
        func label(for gid: String) -> String {
            if let existing = labels[gid] { return existing }
            let letter = String(UnicodeScalar(65 + (nextLabel % 26))!)
            labels[gid] = letter
            nextLabel += 1
            return letter
        }

        return exercises.indices.map { i in
            if let group = exercises[i].groupPlan, group.isValid,
               group.memberSlotIDs.allSatisfy({ id in exercises.contains { $0.id == id && $0.groupPlan == group } }) {
                return Position(isInSuperset: true, isFirstInGroup: group.memberSlotIDs.first == exercises[i].id,
                    isLastInGroup: group.memberSlotIDs.last == exercises[i].id, groupLabel: label(for: group.id))
            }
            guard let gid = exercises[i].supersetGroupID else { return Position.standalone }
            let prevSame = i > 0 && exercises[i - 1].supersetGroupID == gid
            let nextSame = i < exercises.count - 1 && exercises[i + 1].supersetGroupID == gid
            guard prevSame || nextSame else { return Position.standalone }
            return Position(
                isInSuperset: true,
                isFirstInGroup: !prevSame,
                isLastInGroup: !nextSame,
                groupLabel: label(for: gid)
            )
        }
    }
}

public struct ExerciseSet: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var isCompleted: Bool = false
    public var target: String?
    public var previousPerformance: String?
    public var isWarmup: Bool = false

    /// Richer set role (drop/failure). Optional so legacy docs — which only carried
    /// `isWarmup` — still decode; nil falls back to the `isWarmup` bridge below.
    public var setType: SetType?
    /// RPE or RIR as the user entered it. Optional/nil when they logged no effort.
    public var effort: SetEffort?
    public var prescription: WorkoutPrescription?
    /// Identifies an untouched generated preparation row; performed/manual rows remain authoritative.
    public var generatedWarmup: StrengthGeneratedWarmup?
    public var intervalTimer: WorkoutIntervalTimerState?
    public var isDeferred: Bool?

    public var reps: Int = 0
    public var weight: Double = 0.0
    public var distance: Double = 0.0
    public var durationInSeconds: Int = 0

    private enum CodingKeys: String, CodingKey {
        case id, isCompleted, target, previousPerformance, isWarmup, setType, effort, prescription, generatedWarmup, intervalTimer, isDeferred
        case reps, weight, distance, durationInSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        previousPerformance = try container.decodeIfPresent(String.self, forKey: .previousPerformance)
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        setType = try container.decodeIfPresent(SetType.self, forKey: .setType)
        effort = try container.decodeIfPresent(SetEffort.self, forKey: .effort)
        prescription = try container.decodeIfPresent(WorkoutPrescription.self, forKey: .prescription)
        generatedWarmup = try? container.decodeIfPresent(StrengthGeneratedWarmup.self, forKey: .generatedWarmup)
        intervalTimer = try? container.decodeIfPresent(WorkoutIntervalTimerState.self, forKey: .intervalTimer)
        isDeferred = try? container.decodeIfPresent(Bool.self, forKey: .isDeferred)
        reps = try container.decode(Int.self, forKey: .reps)
        weight = try container.decode(Double.self, forKey: .weight)
        // These fields were added when cardio joined the original strength-only sets.
        distance = try container.decodeIfPresent(Double.self, forKey: .distance) ?? 0
        durationInSeconds = try container.decodeIfPresent(Int.self, forKey: .durationInSeconds) ?? 0
    }

    /// Effective role, reconciling the new `setType` with the legacy `isWarmup` flag.
    public var resolvedSetType: SetType { setType ?? (isWarmup ? .warmup : .normal) }
    /// Working sets are everything that isn't a warmup; only these count in analytics.
    public var isWorkingSet: Bool { resolvedSetType != .warmup }

    /// Set the role and keep the legacy `isWarmup` flag in sync so older UI/queries stay correct.
    public mutating func setKind(_ kind: SetType) {
        setType = kind
        isWarmup = (kind == .warmup)
    }

    public init(id: String = UUID().uuidString, isCompleted: Bool = false, target: String? = nil, previousPerformance: String? = nil, isWarmup: Bool = false, setType: SetType? = nil, effort: SetEffort? = nil, prescription: WorkoutPrescription? = nil, generatedWarmup: StrengthGeneratedWarmup? = nil, reps: Int = 0, weight: Double = 0.0, distance: Double = 0.0, durationInSeconds: Int = 0) {
        self.id = id
        self.isCompleted = isCompleted
        self.target = target
        self.previousPerformance = previousPerformance
        self.isWarmup = isWarmup
        self.setType = setType
        self.effort = effort
        self.prescription = prescription
        self.generatedWarmup = generatedWarmup
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.durationInSeconds = durationInSeconds
    }
}

public enum WorkoutProgramLinkDecision: String, Codable, Equatable, Sendable {
    case standalone
    case program
}

/// The saved program instance and exact planned slot chosen when a session starts.
/// Optional on drafts/history so existing records keep their original identities and values.
public struct WorkoutProgramSessionContext: Codable, Equatable, Sendable {
    public let programID: String
    public let slotIndex: Int
    public let blockSession: WorkoutBlockSessionSnapshot?

    public init(programID: String, slotIndex: Int, blockSession: WorkoutBlockSessionSnapshot? = nil) {
        self.programID = programID
        self.slotIndex = slotIndex
        self.blockSession = blockSession
    }
}

public struct WorkoutSessionLog: Identifiable, Codable {
    public var id: String?
    public var date: Date
    public var routineID: String
    public var completedExercises: [CompletedExercise]
    public var aiInsights: [WorkoutAnalysisInsight]?
    public var programContext: WorkoutProgramSessionContext?
    public var programLinkDecision: WorkoutProgramLinkDecision?
    public var elapsedSeconds: TimeInterval?
    public var recordedDurationSeconds: TimeInterval? {
        guard let elapsedSeconds, (0...86_400).contains(elapsedSeconds) else { return nil }
        return elapsedSeconds
    }
    public var projectionBodyWeightPounds: Double?
    public var generatedDiaryExercise: LoggedExercise?
    public var correctionRevisionID: String?

    public init(id: String? = nil, date: Date, routineID: String, completedExercises: [CompletedExercise], aiInsights: [WorkoutAnalysisInsight]? = nil, programContext: WorkoutProgramSessionContext? = nil, programLinkDecision: WorkoutProgramLinkDecision? = nil) {
        self.id = id
        self.date = date
        self.routineID = routineID
        self.completedExercises = completedExercises
        self.aiInsights = aiInsights
        self.programContext = programContext
        self.programLinkDecision = programLinkDecision
    }
}

public extension WorkoutSessionLog {
    func displayName(routines: [WorkoutRoutine], programs: [WorkoutProgram]) -> String {
        if let recorded = generatedDiaryExercise?.name, !recorded.isEmpty { return recorded }
        if let routine = routines.first(where: { $0.id == routineID }) { return routine.name }
        if let context = programContext, let program = programs.first(where: { $0.id == context.programID }),
           let routine = program.routine(forSlot: context.slotIndex), routine.id == routineID { return routine.name }
        let movements = completedExercises.prefix(2).map(\.exerciseName).joined(separator: ", ")
        return movements.isEmpty ? "Strength workout" : movements
    }

    func programPosition(in programs: [WorkoutProgram]) -> String {
        if programLinkDecision == .standalone { return "Standalone workout" }
        guard let context = programContext else { return "No recorded program" }
        let name = programs.first(where: { $0.id == context.programID })?.name ?? "Program"
        let position = "Session \(context.slotIndex + 1)"
        return [name, context.blockSession?.weekName, position].compactMap { $0 }.joined(separator: " · ")
    }
}

extension Duration {
    public var formattedWorkoutTime: String {
        if self > .zero && self < .seconds(1) { return "<1 sec" }
        let units: Set<UnitsFormatStyle.Unit> = self < .seconds(60) ? [.seconds] : [.hours, .minutes]
        return formatted(.units(allowed: units, width: .abbreviated))
    }
}

public struct CompletedExercise: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var exerciseName: String
    public var exercise: RoutineExercise
    public var sets: [CompletedSet]
    public var date: Date { return Date() }

    public init(id: String = UUID().uuidString, exerciseName: String, exercise: RoutineExercise, sets: [CompletedSet]) {
        self.id = id
        self.exerciseName = exerciseName
        self.exercise = exercise
        self.sets = sets
    }
}

public struct CompletedSet: Identifiable, Codable {
    public var id: String = UUID().uuidString
    public var reps: Int
    public var weight: Double
    public var distance: Double?
    public var durationInSeconds: Int?

    /// Persisted set role. Optional so pre-existing history (which never stored it) decodes;
    /// legacy sets resolve to `.normal` and stay counted, exactly as before.
    public var setType: SetType?
    /// Persisted effort (RPE/RIR) as entered.
    public var effort: SetEffort?

    public var resolvedSetType: SetType { setType ?? .normal }
    /// Only working sets count toward volume, 1RM, and PRs.
    public var isWorkingSet: Bool { resolvedSetType != .warmup }

    public init(id: String = UUID().uuidString, reps: Int, weight: Double, distance: Double? = nil, durationInSeconds: Int? = nil, setType: SetType? = nil, effort: SetEffort? = nil) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.distance = distance
        self.durationInSeconds = durationInSeconds
        self.setType = setType
        self.effort = effort
    }
}
