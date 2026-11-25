import Combine
import Foundation

public enum ExperimentMealSide: String, Codable, CaseIterable { case a = "A", b = "B" }

public struct MealExperimentObservation: Codable {
    public let sessionID: String
    public let sessionDate: Date
    public let energy: Int
    public let comfort: Int
    public let minutesBefore: Int
    public let confounders: [String]
    public let workingSets: Int
    public let volume: Double
    public let meanRPE: Double?
    public let note: String
    public var revisionID: String?
    public var recordedAt: Date?
    public var scaleVersion: Int?
    public var sourceProgramID: String?
    public var sourceSlot: Int?
    public var evidenceFingerprint: String?
    public var isComparable: Bool { confounders.isEmpty }
}

public struct MealExperimentTrial: Codable, Identifiable {
    public let id: String
    public let slot: Int
    public var date: Date
    public let side: ExperimentMealSide
    public var observation: MealExperimentObservation?
    public var skipped: Bool
    public var observationHistory: [MealExperimentObservation]?
    public var conflictingObservations: [MealExperimentObservation]?
}

public struct MealExperiment: Codable, Identifiable {
    public let id: String
    public let createdAt: Date
    public let programID: String
    public let routineID: String
    public let routineName: String
    public let exerciseNames: [String]
    public let plannedWorkingSets: Int
    public let mealA: FoodItem
    public let mealB: FoodItem
    public let minutesBefore: Int
    public var trials: [MealExperimentTrial]
    public var endedAt: Date?
    public var scaleVersion: Int?
    public var isFinished: Bool { endedAt != nil || trials.allSatisfy { $0.observation != nil || $0.skipped } }
    public func food(for side: ExperimentMealSide) -> FoodItem { side == .a ? mealA : mealB }
}

public struct MealExperimentSummary {
    public struct Group {
        public let count: Int
        public let energy: Double?
        public let comfort: Double?
        public let meanRPE: Double?
        public let volume: Double?
        public let effortCount: Int
        public var energyRange: ClosedRange<Double>?
        public var comfortRange: ClosedRange<Double>?
    }
    public let a: Group
    public let b: Group
    public let excluded: Int
    public var hasEnoughObservations: Bool { a.count >= 3 && b.count >= 3 }
    public var headline: String {
        guard hasEnoughObservations else { return "Still learning" }
        guard let energyA = a.energy, let energyB = b.energy, let comfortA = a.comfort, let comfortB = b.comfort else {
            return "Still learning"
        }
        let spread = [a.energyRange, b.energyRange, a.comfortRange, b.comfortRange].compactMap { $0.map { $0.upperBound - $0.lowerBound } }.max() ?? 0
        let difference = max(abs(energyA - energyB), abs(comfortA - comfortB))
        if spread >= 3 && difference < spread { return "Mixed observations" }
        return difference >= 0.5 ? "A pattern worth repeating" : "No clear preference yet"
    }
}

public enum MealExperimentError: LocalizedError {
    case invalidSetup, notEnoughSessions, wrongSession, duplicateSession, invalidRating, noAccount, unavailable, stale
    public var errorDescription: String? {
        switch self {
        case .invalidSetup: return "Choose two different familiar meals and a strength routine from your active program."
        case .notEnoughSessions: return "This plan needs at least six upcoming sessions of the same routine. Choose another routine or continue with a new program."
        case .wrongSession: return "Choose a completed session of this routine from after the comparison started."
        case .duplicateSession: return "That workout already has a check-in. Each workout can count only once."
        case .invalidRating: return "Rate energy and comfort from 1 to 5 and enter the meal timing."
        case .noAccount: return "Sign in to save your comparison."
        case .unavailable: return "Your saved comparison could not be read. It has been kept on this device. Try reopening the app."
        case .stale: return "This comparison changed. Reopen it before saving."
        }
    }
}

public enum MealExperimentRules {
    public static func create(
        program: WorkoutProgram, routineID: String, mealA: FoodItem, mealB: FoodItem,
        minutesBefore: Int, startsWithA: Bool, protectedSlots: Set<Int> = [], now: Date = Date(), calendar: Calendar = .current
    ) throws -> MealExperiment {
        guard let programID = program.id, let routine = program.routines.first(where: { $0.id == routineID }),
              !routine.exercises.isEmpty, routine.exercises.allSatisfy({ $0.type == .strength }),
              normalized(mealA.name) != normalized(mealB.name), !normalized(mealA.name).isEmpty,
              !normalized(mealB.name).isEmpty, [mealA, mealB].allSatisfy({ $0.calories.isFinite && $0.calories > 0 }),
              (30...180).contains(minutesBefore) else { throw MealExperimentError.invalidSetup }
        let next = max(0, program.currentProgressIndex ?? 0)
        guard next < program.totalSlots else { throw MealExperimentError.notEnoughSessions }
        let upcoming = MealExperimentEvidenceRules.eligibleSlots(in: program, routineID: routineID,
            protectedSlots: protectedSlots, now: now, calendar: calendar).map { ($0.slot, $0.date) }
        guard upcoming.count >= 6 else { throw MealExperimentError.notEnoughSessions }
        // Counterbalance order rather than running every A session before every B session.
        let pattern: [ExperimentMealSide] = startsWithA ? [.a, .b, .b, .a, .a, .b] : [.b, .a, .a, .b, .b, .a]
        return MealExperiment(id: UUID().uuidString, createdAt: now, programID: programID,
                              routineID: routineID, routineName: routine.name,
                              exerciseNames: routine.exercises.map { normalized($0.name) },
                              plannedWorkingSets: routine.exercises.reduce(0) { total, exercise in
                                  total + (exercise.sets.isEmpty ? exercise.targetSets : exercise.sets.filter { !$0.isWarmup && $0.setType != .warmup }.count)
                              },
                              mealA: mealA, mealB: mealB, minutesBefore: minutesBefore,
                              trials: zip(upcoming.prefix(6), pattern).map { entry, side in
                                  MealExperimentTrial(id: UUID().uuidString, slot: entry.0, date: entry.1,
                                                      side: side, skipped: false)
                              })
    }

    public static func recording(
        in experiment: MealExperiment, trialID: String, session: WorkoutSessionLog, energy: Int, comfort: Int,
        minutesBefore: Int, confounders: [String], note: String = "", confirmedLegacySession: Bool = true, now: Date = Date()
    ) throws -> MealExperiment {
        guard let index = experiment.trials.firstIndex(where: { $0.id == trialID }), experiment.endedAt == nil,
              experiment.trials[index].observation == nil, !experiment.trials[index].skipped else { throw MealExperimentError.stale }
        guard let sessionID = session.id,
              MealExperimentEvidenceRules.matches(session, experiment: experiment, trial: experiment.trials[index],
                  allowLegacy: confirmedLegacySession, now: now),
              !session.completedExercises.isEmpty else { throw MealExperimentError.wrongSession }
        guard !experiment.trials.contains(where: { $0.observation?.sessionID == sessionID }) else {
            throw MealExperimentError.duplicateSession
        }
        guard (1...5).contains(energy), (1...5).contains(comfort), (0...360).contains(minutesBefore) else {
            throw MealExperimentError.invalidRating
        }
        var flags = confounders
        if abs(minutesBefore - experiment.minutesBefore) > 30 { flags.append("Meal timing changed") }
        let actualNames = Set(session.completedExercises.map { normalized($0.exerciseName) })
        if actualNames != Set(experiment.exerciseNames) { flags.append("Workout exercises changed") }
        let sets = session.completedExercises.flatMap(\.sets).filter { $0.isWorkingSet && $0.reps > 0 && $0.weight.isFinite && $0.weight >= 0 }
        guard !sets.isEmpty else { throw MealExperimentError.wrongSession }
        if abs(sets.count - experiment.plannedWorkingSets) > max(1, experiment.plannedWorkingSets / 4) {
            flags.append("Working set count changed")
        }
        if now.timeIntervalSince(session.date) > 172_800 { flags.append("Check-in more than two days later") }
        let efforts = sets.compactMap { $0.effort?.normalizedRPE }.filter { $0.isFinite && (1...10).contains($0) }
        var updated = experiment
        updated.trials[index].observation = MealExperimentObservation(
            sessionID: sessionID, sessionDate: session.date, energy: energy, comfort: comfort,
            minutesBefore: minutesBefore, confounders: Array(Set(flags)).sorted(), workingSets: sets.count,
            volume: sets.reduce(0) { $0 + Double($1.reps) * $1.weight }, meanRPE: average(efforts), note: String(note.prefix(300)),
            revisionID: UUID().uuidString, recordedAt: now, scaleVersion: 1,
            sourceProgramID: session.programContext?.programID, sourceSlot: session.programContext?.slotIndex,
            evidenceFingerprint: try WorkoutNextSessionRules.evidenceFingerprint(session))
        return updated
    }

    public static func addingPair(to experiment: MealExperiment, program: WorkoutProgram, protectedSlots: Set<Int> = [], now: Date = Date(), calendar: Calendar = .current) throws -> MealExperiment {
        guard experiment.endedAt == nil, experiment.isFinished, program.id == experiment.programID else { throw MealExperimentError.stale }
        let first = max((experiment.trials.map(\.slot).max() ?? -1) + 1, program.currentProgressIndex ?? 0)
        guard first < program.totalSlots else { throw MealExperimentError.notEnoughSessions }
        let slots = (first..<program.totalSlots).compactMap { slot -> (Int, Date)? in
            guard !protectedSlots.contains(slot), !(program.skippedIndices ?? []).contains(slot),
                  !(program.slotCompletionProofs ?? []).contains(where: { $0.slotIndex == slot }),
                  program.routine(forSlot: slot)?.id == experiment.routineID,
                  let date = program.date(forSlot: slot, calendar: calendar), date >= calendar.startOfDay(for: now) else { return nil }
            return (slot, date)
        }
        guard slots.count >= 2 else { throw MealExperimentError.notEnoughSessions }
        var updated = experiment
        let sides: [ExperimentMealSide] = experiment.trials.last?.side == .a ? [.b, .a] : [.a, .b]
        updated.trials += zip(slots.prefix(2), sides).map { slot, side in
            MealExperimentTrial(id: UUID().uuidString, slot: slot.0, date: slot.1, side: side, skipped: false)
        }
        return updated
    }

    public static func summary(_ experiment: MealExperiment) -> MealExperimentSummary {
        var seenSessions = Set<String>()
        let uniqueTrials = experiment.trials.filter { trial in
            guard let observation = trial.observation else { return false }
            return seenSessions.insert(observation.sessionID).inserted
        }
        func group(_ side: ExperimentMealSide) -> MealExperimentSummary.Group {
            let values = uniqueTrials.filter { $0.side == side && ($0.conflictingObservations ?? []).isEmpty }.compactMap(\.observation).filter(\.isComparable)
            let effort = values.compactMap(\.meanRPE)
            return MealExperimentSummary.Group(count: values.count, energy: average(values.map { Double($0.energy) }),
                                               comfort: average(values.map { Double($0.comfort) }), meanRPE: average(effort),
                                               volume: average(values.map(\.volume)), effortCount: effort.count,
                                               energyRange: MealExperimentEvidenceRules.range(values.map { Double($0.energy) }),
                                               comfortRange: MealExperimentEvidenceRules.range(values.map { Double($0.comfort) }))
        }
        return MealExperimentSummary(a: group(.a), b: group(.b), excluded: experiment.trials.filter { $0.observation.map { !$0.isComparable } == true || !($0.conflictingObservations ?? []).isEmpty }.count)
    }

    private static func normalized(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
}

@MainActor
public final class MealExperimentStore: ObservableObject {
    @Published public private(set) var experiments: [MealExperiment] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var syncMessage: String?
    @Published public private(set) var isSyncing = false
    public private(set) var userID: String?
    private let storage: EditorDraftStore
    private let repository: MealExperimentRepository?
    private var checkpoint = MealExperimentCheckpoint(state: MealExperimentCloudState(), pending: false)
    private var canWrite = false
    private var generation = UUID()
    private var accountGeneration = UUID()
    private let scope = "familiar-meal-comparisons-v2"
    private let legacyScope = "familiar-meal-comparisons-v1"

    public init(storage: EditorDraftStore = EditorDraftStore(), repository: MealExperimentRepository? = nil) {
        self.storage = storage
        self.repository = repository
    }
    public var active: MealExperiment? { experiments.first(where: { !$0.isFinished }) }
    public var hasCloudSync: Bool { repository != nil }

    public func activateAccount(_ userID: String?) {
        guard self.userID != userID || !canWrite else { return }
        self.userID = userID
        accountGeneration = UUID()
        generation = UUID()
        isSyncing = false
        experiments = []
        checkpoint = MealExperimentCheckpoint(state: MealExperimentCloudState(), pending: false)
        errorMessage = nil
        syncMessage = nil
        canWrite = false
        guard let userID, !userID.isEmpty else { return }
        do {
            if let saved = try storage.load(MealExperimentCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = saved.value
            } else if let legacy = try storage.load([MealExperiment].self, userID: userID, scope: legacyScope) {
                for value in legacy.value { checkpoint.state.update(value, now: legacy.updatedAt) }
                checkpoint.pending = true
                try storage.save(checkpoint, userID: userID, scope: scope)
            }
            experiments = checkpoint.state.experiments
            canWrite = true
            if checkpoint.pending, repository != nil { syncMessage = "Saved on this device. Waiting to sync." }
            let account = accountGeneration
            Task { [weak self] in
                guard let self, self.accountGeneration == account else { return }
                await self.synchronize()
            }
        } catch { errorMessage = MealExperimentError.unavailable.localizedDescription }
    }

    public func save(_ experiment: MealExperiment, for expectedUserID: String) throws {
        guard userID == expectedUserID, !expectedUserID.isEmpty else { throw MealExperimentError.noAccount }
        guard canWrite else { throw MealExperimentError.unavailable }
        if let latest = experiments.first(where: { $0.id == experiment.id }) {
            // An old editor must not remove a check-in received while it was open.
            for trial in latest.trials where trial.observation != nil {
                guard let proposed = experiment.trials.first(where: { $0.id == trial.id }),
                      let previous = trial.observation, let current = proposed.observation,
                      MealExperimentEvidenceRules.identity(previous) == MealExperimentEvidenceRules.identity(current)
                        || (proposed.observationHistory ?? []).contains(where: { MealExperimentEvidenceRules.identity($0) == MealExperimentEvidenceRules.identity(previous) }) else {
                    throw MealExperimentError.stale
                }
                for conflict in trial.conflictingObservations ?? [] {
                    let retained = (proposed.conflictingObservations ?? []) + (proposed.observationHistory ?? []) + [current]
                    guard retained.contains(where: { MealExperimentEvidenceRules.identity($0) == MealExperimentEvidenceRules.identity(conflict) }) else { throw MealExperimentError.stale }
                }
            }
        } else {
            guard active == nil, checkpoint.state.deletedExperimentIDs?[experiment.id] == nil,
                  experiment.createdAt > (checkpoint.state.deletedBefore ?? .distantPast) else { throw MealExperimentError.stale }
        }
        var next = checkpoint
        next.state.update(experiment)
        next.pending = true
        try persist(next, userID: expectedUserID)
        queueSync()
    }

    public func delete(experimentID: String, for expectedUserID: String) throws {
        guard userID == expectedUserID, !expectedUserID.isEmpty else { throw MealExperimentError.noAccount }
        guard canWrite, experiments.contains(where: { $0.id == experimentID }) else { throw MealExperimentError.unavailable }
        var next = checkpoint
        next.state.delete(experimentID: experimentID)
        next.pending = true
        try persist(next, userID: expectedUserID)
        queueSync()
    }

    public func deleteAll(for expectedUserID: String) throws {
        guard userID == expectedUserID, !expectedUserID.isEmpty else { throw MealExperimentError.noAccount }
        guard canWrite else { throw MealExperimentError.unavailable }
        var next = checkpoint
        next.state.deleteAll()
        next.pending = true
        try persist(next, userID: expectedUserID)
        try? storage.remove(userID: expectedUserID, scope: legacyScope)
        queueSync()
    }

    private func persist(_ next: MealExperimentCheckpoint, userID: String) throws {
        try storage.save(next, userID: userID, scope: scope)
        checkpoint = next
        experiments = next.state.experiments
        generation = UUID()
    }

    private func queueSync() {
        syncMessage = repository == nil ? nil : "Saved on this device. Waiting to sync."
        let account = accountGeneration
        Task { [weak self] in
            guard let self, self.accountGeneration == account else { return }
            await self.synchronize()
        }
    }

    public func synchronize() async {
        guard let repository, let owner = userID, canWrite, !isSyncing else { return }
        let account = accountGeneration
        isSyncing = true
        defer { if accountGeneration == account { isSyncing = false } }
        do {
            repeat {
                let version = generation
                let accepted = try await repository.merge(checkpoint.state, userID: owner)
                guard userID == owner, accountGeneration == account else { return }
                let changedDuringSave = generation != version
                let merged = checkpoint.state.merging(accepted)
                try persist(MealExperimentCheckpoint(state: merged, pending: changedDuringSave), userID: owner)
                if !changedDuringSave { break }
            } while !Task.isCancelled
            syncMessage = checkpoint.pending ? "Saved on this device. Waiting to sync." : "Synced with your account."
        } catch {
            guard userID == owner, accountGeneration == account else { return }
            syncMessage = checkpoint.pending ? "Saved on this device. Could not sync; retry when connected."
                : "Could not check account sync. Retry when connected; your local comparisons are kept."
        }
    }
}
