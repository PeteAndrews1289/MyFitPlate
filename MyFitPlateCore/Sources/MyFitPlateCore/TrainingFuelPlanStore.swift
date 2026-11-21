import Foundation
import Combine

@MainActor
public final class TrainingFuelPlanStore: ObservableObject {
    @Published public internal(set) var confirmedPlan: TrainingFuelConfirmedPlan?
    @Published public internal(set) var errorMessage: String?
    @Published public internal(set) var history: [TrainingFuelRevision] = []
    @Published public internal(set) var conflictingPlanIDs: [String] = []
    @Published public internal(set) var syncMessage: String?
    @Published public internal(set) var isSyncing = false
    let draftStore: EditorDraftStore
    let draftScope = "training-fuel-confirmed-plan"
    let libraryScope = "training-fuel-library-v1"
    var hasUnreadablePlan = false
    let userDefaults: UserDefaults
    let keyPrefix = "myfitplate.training_fuel_plan"
    let legacyKeyPrefix = "myfitplate.training_fuel_plan."
    var currentUserID: String?
    var checkpoint = TrainingFuelLibraryCheckpoint()
    let repository: TrainingFuelRepository?
    let auth: AuthServiceProtocol?
    var generation = UUID()
    var accountGeneration = UUID()
    var loaded = false
    var explicitSelection: String?

    public init(userDefaults: UserDefaults = .standard, draftStore: EditorDraftStore = EditorDraftStore(),
                repository: TrainingFuelRepository? = nil, auth: AuthServiceProtocol? = nil) {
        self.userDefaults = userDefaults; self.draftStore = draftStore; self.repository = repository; self.auth = auth
    }
    public var savedDraft: TrainingFuelPlanDraft? { checkpoint.draft }
    public var hasCloudSync: Bool { repository != nil }

    public func load(for userID: String?, now: Date = Date(), calendar: Calendar = .current) {
        guard auth == nil || auth?.currentUserID == userID else {
            confirmedPlan = nil; history = []; conflictingPlanIDs = []; errorMessage = TrainingFuelLibraryError.accountChanged.localizedDescription; return
        }
        if currentUserID == userID, loaded { publish(now: now, calendar: calendar); return }
        currentUserID = userID; accountGeneration = UUID(); generation = UUID(); loaded = false; explicitSelection = nil
        confirmedPlan = nil; history = []; conflictingPlanIDs = []; syncMessage = nil; isSyncing = false
        checkpoint = TrainingFuelLibraryCheckpoint(); hasUnreadablePlan = false; errorMessage = nil
        guard let userID, let key = storageKey(for: userID) else { return }
        do {
            if let saved = try draftStore.load(TrainingFuelLibraryCheckpoint.self, userID: userID, scope: libraryScope) {
                guard (1...2).contains(saved.value.schemaVersion) else { throw TrainingFuelLibraryError.unreadable }
                checkpoint = saved.value
                checkpoint.state = try TrainingFuelCloudState().merging(checkpoint.state)
                guard checkpoint.state.revisions.values.allSatisfy({ $0.plan.ownerID == nil || $0.plan.ownerID == userID }) else {
                    throw TrainingFuelLibraryError.accountChanged
                }
            } else {
                let legacy: TrainingFuelConfirmedPlan?
                if let saved = try draftStore.load(TrainingFuelConfirmedPlan.self, userID: userID, scope: draftScope) {
                    legacy = saved.value
                } else if let data = userDefaults.data(forKey: key) ?? legacyStorageKey(for: userID).flatMap({ userDefaults.data(forKey: $0) }) {
                    legacy = try JSONDecoder().decode(TrainingFuelConfirmedPlan.self, from: data)
                } else { legacy = nil }
                if var legacy {
                    let id = "migration:" + legacy.id
                    legacy.ownerID = userID; legacy.revisionID = id
                    checkpoint.state.revisions[id] = TrainingFuelRevision(id: id, parents: [], plan: legacy,
                        createdAt: legacy.confirmedAt, reason: "Preserved original plan; older food links are unknown")
                    checkpoint.selectedID = legacy.id; checkpoint.pending = true
                }
                // The library itself is the migration receipt. Original sources are retained for recovery.
                try draftStore.save(checkpoint, userID: userID, scope: libraryScope)
            }
            loaded = true; publish(now: now, calendar: calendar); queueSync()
        } catch {
            hasUnreadablePlan = true
            errorMessage = TrainingFuelLibraryError.unreadable.localizedDescription
        }
    }

    @discardableResult public func confirm(_ plan: TrainingFuelConfirmedPlan, for userID: String?) -> Bool {
        do {
            try requireOwner(userID)
            guard let userID else { throw TrainingFuelLibraryError.accountChanged }
            try append(plan, userID: userID, reason: plan.outcome == nil ? "Reviewed fuel plan" : "Session outcome")
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func requireOwner(_ userID: String?) throws {
        guard let userID, storageKey(for: userID) != nil,
              currentUserID == nil || currentUserID == userID else { throw TrainingFuelLibraryError.accountChanged }
        if !loaded { load(for: userID) }
        guard currentUserID == userID, loaded, !hasUnreadablePlan else { throw TrainingFuelLibraryError.unreadable }
        // Tests/previews may omit authentication; a configured real account must still match.
        if let auth, auth.currentUserID != userID { throw TrainingFuelLibraryError.accountChanged }
    }

    func append(_ plan: TrainingFuelConfirmedPlan, userID: String, reason: String, archivedAt: Date? = nil,
                resolving parents: [String]? = nil) throws {
        guard plan.calculation?.individualEstimate?.requiresReview != true else { throw TrainingFuelIndividualEstimateError.needsReview }
        let heads = checkpoint.state.heads(planID: plan.id)
        if parents == nil {
            guard heads.count <= 1, heads.first?.id == plan.revisionID || heads.isEmpty else { throw TrainingFuelLibraryError.changed }
        }
        let retainedClosure = parents == nil ? (archivedAt ?? heads.first?.archivedAt) : archivedAt
        var next = checkpoint
        var value = plan
        let id = UUID().uuidString
        value.ownerID = userID; value.revisionID = id
        next.state.revisions[id] = TrainingFuelRevision(id: id, parents: parents ?? heads.map(\.id), plan: value,
            archivedAt: retainedClosure, reason: reason)
        next.selectedID = retainedClosure == nil ? value.id : nil; next.editingNew = false; next.pending = true
        if next.draft?.id == value.id { next.draft = nil }
        try persist(next, userID: userID)
        confirmedPlan = retainedClosure == nil ? value : nil
        queueSync()
    }

    func persist(_ next: TrainingFuelLibraryCheckpoint, userID: String) throws {
        var versioned = next
        if versioned.state.revisions.values.contains(where: { $0.plan.draft.preference.personalInputs != nil }) { versioned.state.schemaVersion = 2 }
        if versioned.state.schemaVersion == 2 || versioned.draft?.preference.personalInputs != nil { versioned.schemaVersion = 2 }
        versioned.schemaVersion = max(versioned.schemaVersion, checkpoint.schemaVersion)
        try draftStore.save(versioned, userID: userID, scope: libraryScope)
        checkpoint = versioned; generation = UUID(); errorMessage = nil; publish()
    }

    func publish(now: Date = Date(), calendar: Calendar = .current) {
        history = checkpoint.state.current
        conflictingPlanIDs = checkpoint.state.conflicts
        let available = history.filter { $0.archivedAt == nil }
        if checkpoint.editingNew == true { confirmedPlan = nil; return }
        confirmedPlan = available.first(where: { $0.plan.id == explicitSelection })?.plan
            ?? available.first(where: { $0.plan.id == checkpoint.selectedID && shouldRetain($0.plan, at: now, calendar: calendar) })?.plan
            ?? available.filter { shouldRetain($0.plan, at: now, calendar: calendar) }
                .sorted { $0.plan.draft.scheduledAt < $1.plan.draft.scheduledAt }.first?.plan
        if checkpoint.pending { syncMessage = repository == nil ? "Saved on this device." : "Saved on this device. Waiting to sync." }
    }

    func queueSync() {
        guard repository != nil else { return }
        let account = accountGeneration
        Task { [weak self] in
            guard let self, self.accountGeneration == account else { return }
            await self.synchronize()
        }
    }

    public func synchronize() async {
        guard let repository, let owner = currentUserID, loaded, !hasUnreadablePlan, !isSyncing else { return }
        let account = accountGeneration
        isSyncing = true
        defer { if accountGeneration == account { isSyncing = false } }
        do {
            repeat {
                let version = generation
                let accepted = try await repository.merge(checkpoint.state, userID: owner)
                guard currentUserID == owner, accountGeneration == account else { return }
                var next = checkpoint
                guard accepted.revisions.values.allSatisfy({ $0.plan.ownerID == nil || $0.plan.ownerID == owner }) else {
                    throw TrainingFuelLibraryError.accountChanged
                }
                next.state = try checkpoint.state.merging(accepted)
                next.pending = generation != version
                try persist(next, userID: owner)
                if !next.pending { syncMessage = conflictingPlanIDs.isEmpty ? "Synced." : "Conflicting edits need review."; break }
            } while !Task.isCancelled
        } catch {
            guard currentUserID == owner, accountGeneration == account else { return }
            syncMessage = "Your plans are kept on this device. Sync will retry; no history was replaced."
        }
    }

    @discardableResult
    public func recordStrengthCompletion(
        routineID: String,
        routineName: String,
        completedAt: Date,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        for userID: String?,
        calendar: Calendar = .current,
        session: WorkoutSessionLog? = nil
    ) -> Bool {
        load(for: userID, now: completedAt, calendar: calendar)
        let matches = history.filter { $0.archivedAt == nil }.map(\.plan).filter { plan in
            TrainingFuelSessionOutcomeRules.matchesStrengthCompletion(
                plan: plan,
                routineID: routineID,
                routineName: routineName,
                completedAt: completedAt, session: session
            )
        }
        guard matches.count == 1, let plan = matches.first else { return false }
        return recordCompletion(
            plan: plan,
            source: .strengthWorkout,
            referenceID: session?.id ?? routineID,
            actualStartAt: session?.elapsedSeconds.map { completedAt.addingTimeInterval(-max(0, $0)) },
            actualEndAt: completedAt,
            today: today,
            goals: goals,
            userID: userID,
            calendar: calendar
        )
    }

    @discardableResult
    public func recordRunCompletion(
        _ run: Run,
        selectedPlanID: String?,
        source: TrainingFuelSessionOutcome.Source = .recordedRun,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        load(for: userID, now: run.endDate, calendar: calendar)
        let matches = history.filter { $0.archivedAt == nil }.map(\.plan).filter {
            TrainingFuelSessionOutcomeRules.matchesRunCompletion(plan: $0, run: run, selectedPlanID: selectedPlanID)
        }
        guard matches.count == 1, let plan = matches.first else { return false }
        return recordCompletion(
            plan: plan,
            source: source,
            referenceID: run.id,
            actualStartAt: run.startDate,
            actualEndAt: run.endDate,
            today: today,
            goals: goals,
            userID: userID,
            calendar: calendar
        )
    }

    @discardableResult
    public func recordProgramSkip(
        programID: String?,
        routineID: String,
        at date: Date = Date(),
        today: DailyLog?,
        for userID: String?,
        calendar: Calendar = .current,
        slotIndex: Int? = nil
    ) -> Bool {
        load(for: userID, now: date, calendar: calendar)
        let matches = history.filter { $0.archivedAt == nil }.map(\.plan).filter {
            TrainingFuelSessionOutcomeRules.matchesProgramSkip(plan: $0, programID: programID, routineID: routineID, slotIndex: slotIndex)
        }
        guard matches.count == 1, var plan = matches.first else { return false }
        plan.outcome = TrainingFuelSessionOutcome(
            status: .skipped,
            source: .programSkip,
            recordedAt: date,
            referenceID: routineID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: today)
        )
        return confirm(plan, for: userID)
    }

    @discardableResult
    public func markCurrentPlanCompleted(
        at date: Date = Date(),
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let plan = planForOutcome(userID: userID, at: date, calendar: calendar),
              plan.outcome == nil else { return false }
        return recordCompletion(
            plan: plan,
            source: .manualConfirmation,
            referenceID: plan.draft.sessionReferenceID,
            actualStartAt: nil,
            actualEndAt: date,
            today: today,
            goals: goals,
            userID: userID,
            calendar: calendar
        )
    }

    @discardableResult
    public func markCurrentPlanSkipped(
        at date: Date = Date(),
        today: DailyLog?,
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard var plan = planForOutcome(userID: userID, at: date, calendar: calendar),
              plan.outcome == nil else { return false }
        plan.outcome = TrainingFuelSessionOutcome(
            status: .skipped,
            source: .manualConfirmation,
            recordedAt: date,
            referenceID: plan.draft.sessionReferenceID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: today)
        )
        return confirm(plan, for: userID)
    }

    @discardableResult
    public func refreshDeferredRecovery(
        today: DailyLog,
        goals: TodayFuelPlanGoals,
        at date: Date = Date(),
        for userID: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard var plan = planForOutcome(userID: userID, at: date, calendar: calendar),
              plan.requiresRecoveryDiaryRefresh(calendar: calendar),
              let outcome = plan.outcome,
              calendar.isDate(today.date, inSameDayAs: outcome.actualEndAt ?? outcome.recordedAt) else {
            return false
        }
        let recoveryPlan = TrainingFuelDeferredRecoveryRules.makePlan(
            for: plan,
            today: today,
            goals: goals,
            completedAt: outcome.actualEndAt ?? outcome.recordedAt,
            calendar: calendar
        )
        plan.outcome = TrainingFuelSessionOutcome(
            status: outcome.status,
            source: outcome.source,
            recordedAt: outcome.recordedAt,
            actualStartAt: outcome.actualStartAt,
            actualEndAt: outcome.actualEndAt,
            referenceID: outcome.referenceID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: today),
            recoveryPlan: recoveryPlan,
            recoveryDiaryIsAuthoritative: true
        )
        return confirm(plan, for: userID)
    }

    @discardableResult public func clear(for userID: String? = nil) -> Bool {
        do {
            let owner = userID ?? currentUserID
            try requireOwner(owner)
            guard let owner, let plan = confirmedPlan else { return false }
            try append(plan, userID: owner, reason: "Closed plan; food and session history kept", archivedAt: Date())
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private func storageKey(for userID: String?) -> String? {
        AccountScopedStorageKey.make(prefix: keyPrefix, userID: userID)
    }

    private func legacyStorageKey(for userID: String?) -> String? {
        guard let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else { return nil }
        return legacyKeyPrefix + userID
    }

    private func planForOutcome(
        userID: String?,
        at date: Date,
        calendar: Calendar
    ) -> TrainingFuelConfirmedPlan? {
        load(for: userID, now: date, calendar: calendar)
        return confirmedPlan
    }

    func recordCompletion(
        plan: TrainingFuelConfirmedPlan,
        source: TrainingFuelSessionOutcome.Source,
        referenceID: String?,
        actualStartAt: Date?,
        actualEndAt: Date,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        userID: String?,
        calendar: Calendar
    ) -> Bool {
        var updated = plan
        let needsFreshRecoveryPlan = plan.draft.preference.wantsPostSessionFuel &&
            (
                plan.allocations.contains(where: { $0.phase == .afterTraining }) == false ||
                !calendar.isDate(actualEndAt, inSameDayAs: plan.draft.scheduledAt)
            )
        let hasMatchingDiary = today.map {
            calendar.isDate($0.date, inSameDayAs: actualEndAt)
        } ?? false
        let recoveryPlan = needsFreshRecoveryPlan && hasMatchingDiary
            ? TrainingFuelDeferredRecoveryRules.makePlan(
                for: plan,
                today: today,
                goals: goals,
                completedAt: actualEndAt,
                calendar: calendar
            )
            : nil
        updated.outcome = TrainingFuelSessionOutcome(
            status: .completed,
            source: source,
            recordedAt: actualEndAt,
            actualStartAt: actualStartAt,
            actualEndAt: actualEndAt,
            referenceID: referenceID,
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: hasMatchingDiary ? today : nil),
            recoveryPlan: recoveryPlan,
            recoveryDiaryIsAuthoritative: needsFreshRecoveryPlan ? hasMatchingDiary : true
        )
        return confirm(updated, for: userID)
    }

    func shouldRetain(
        _ plan: TrainingFuelConfirmedPlan,
        at now: Date,
        calendar: Calendar
    ) -> Bool {
        if calendar.isDate(plan.draft.scheduledAt, inSameDayAs: now) {
            return true
        }
        let end = plan.outcome?.actualEndAt ?? plan.estimatedEndAt
        return now >= plan.draft.scheduledAt && now <= end.addingTimeInterval(2 * 60 * 60)
    }
}
