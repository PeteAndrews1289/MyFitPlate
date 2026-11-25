import CryptoKit
import Foundation
import Combine
public enum WorkoutServiceError: Error, LocalizedError {
    case userNotLoggedIn
    case networkError(Error)
    case firestoreError(Error)
    case decodingError(Error)
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .userNotLoggedIn:
            return "You must be logged in to perform this action."
        case .networkError:
            return "Could not connect to the server. Please check your internet connection."
        case .firestoreError(let error):
            return "An error occurred with the database: \(error.localizedDescription)"
        case .decodingError:
            return "There was an issue processing the response from the server."
        case .apiError(let message):
            return message
        }
    }
}

public enum ProgramDeletionResult: Equatable {
    case deleted
    case clearedLocalOnly
    case userNotLoggedIn
    case missingProgramID
    case failed(String)

    public var didDelete: Bool {
        self == .deleted || self == .clearedLocalOnly
    }

    public var userMessage: String {
        switch self {
        case .deleted:
            return "Program deleted. Workout history was kept."
        case .clearedLocalOnly:
            return "Cleared the stuck active program. No saved cloud program was found to delete."
        case .userNotLoggedIn:
            return "Could not delete the program because you are not signed in."
        case .missingProgramID:
            return "Could not find the saved program record to delete."
        case .failed(let message):
            return "Could not delete the program: \(message)"
        }
    }
}

@MainActor
public class WorkoutService: ObservableObject, WorkoutServicing {
    @Published public var userRoutines: [WorkoutRoutine] = []
    @Published public var userPrograms: [WorkoutProgram] = []
    @Published public var preBuiltPrograms: [WorkoutProgram] = []
    @Published public private(set) var syncState: WorkoutSyncState = .synced
    @Published public private(set) var loadErrorMessage: String?
    @Published public private(set) var isLoadingPrograms = false
    @Published public private(set) var hasLoadedPrograms = false
    public var preferredProgramUnavailable: Bool {
        guard activeProgram == nil, let userID = listenerUserID,
              let preferred = defaults.string(forKey: Self.activeProgramIDStorageKey(for: userID)),
              !defaults.bool(forKey: Self.activeProgramClearedStorageKey(for: userID)) else { return false }
        return unreadableProgramIDs.contains(preferred) || isProgramLibraryFromCache
    }
    private var syncObserver: AnyCancellable?
    @Published public var activeProgram: WorkoutProgram? {
        didSet {
            if oldValue?.weekRescue?.id != activeProgram?.weekRescue?.id,
               let userID = DIContainer.shared.authService?.currentUserID {
                NotificationCenter.default.post(name: .mealPlanChanged, object: userID)
            }
        }
    }

    private var routineListener: Any?
    private var programListener: Any?
    private var listenerUserID: String?
    private let defaults: UserDefaults
    private var unreadableProgramIDs = Set<String>()
    private var isProgramLibraryFromCache = false
    private var programLibraryNotice: String?
    private var routineLibraryNotice: String?
    private static let legacyActiveProgramIDKey = "activeWorkoutProgramID"
    private static let legacyActiveProgramClearedKey = "activeWorkoutProgramCleared"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadPreBuiltPrograms()
        syncObserver = NotificationCenter.default.publisher(for: .workoutSyncStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSyncState() }
    }

    /// Plan overlays are also used by Home and Meal Plan, so load at account activation.
    public func activateAccount(_ userID: String?) {
        guard let userID, !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID else {
            resetAccountState()
            return
        }
        fetchRoutinesAndPrograms()
    }

    public func refreshSyncState() {
        guard let userID = DIContainer.shared.authService.currentUserID else { syncState = .synced; return }
        syncState = DIContainer.shared.workoutRepository.workoutSyncState(userID: userID)
    }

    public func retryPendingSaves() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        DIContainer.shared.workoutRepository.retryPendingWorkouts(userID: userID)
        if loadErrorMessage != nil || isLoadingPrograms { detachListener(); fetchRoutinesAndPrograms() }
        refreshSyncState()
    }

    // MARK: - Failure reporting

    /// Every data-layer failure in this service used to vanish into os.log only — a silently
    /// failing program write once froze progression for weeks with zero telemetry (v2.1).
    /// This funnel records a Crashlytics non-fatal for every failure, and tells the user via
    /// the global toast when the loss is theirs (an unsaved workout or program change).
    private func reportFailure(_ error: Error, operation: String, userMessage: String? = nil) {
        AppLog.workouts.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        DIContainer.shared.crashManager?.record(error: error, additionalUserInfo: ["operation": operation])
        if let userMessage {
            ToastManager.shared.showToast(message: userMessage)
        }
    }

    // MARK: - Fetching & Saving

    public func protectedBlockSlots(in program: WorkoutProgram) throws -> Set<Int> {
        guard let userID = DIContainer.shared.authService.currentUserID, userID == program.userID else {
            throw WorkoutBlockError.accountChanged
        }
        guard let draft = try WorkoutDraftStore().load(userID: userID) else { return [] }
        if let context = draft.programContext, context.programID == program.id { return [context.slotIndex] }
        if draft.needsProgramLinkReview, program.routines.contains(where: { $0.id == draft.routine.id }) {
            return [max(program.currentProgressIndex ?? 0, 0)]
        }
        return []
    }

    /// Authored block edits require an online compare-and-set. Ordinary workout
    /// completion retains its established local-outbox acceptance boundary.
    public func saveProgramBlock(expected: WorkoutProgram, block: WorkoutProgramBlock) async throws -> WorkoutProgram? {
        guard let userID = DIContainer.shared.authService.currentUserID, expected.userID == userID else {
            throw WorkoutBlockError.accountChanged
        }
        let protectedSlots = try protectedBlockSlots(in: expected)
        let saved = try await DIContainer.shared.workoutRepository.commitProgramBlock(
            userID: userID, expected: expected, block: block, protectedSlots: protectedSlots)
        guard DIContainer.shared.authService.currentUserID == userID, !Task.isCancelled else { throw WorkoutBlockError.accountChanged }
        publishBlockProgram(saved, programID: expected.id)
        refreshSyncState()
        return saved
    }

    public func resolveProgramBlock(expected: WorkoutProgram, block: WorkoutProgramBlock,
                                    cancelPending: Bool = false) async throws -> WorkoutBlockResolution? {
        guard let userID = DIContainer.shared.authService.currentUserID, expected.userID == userID else {
            throw WorkoutBlockError.accountChanged
        }
        let result = try await DIContainer.shared.workoutRepository.resolveProgramBlock(
            userID: userID, expected: expected, block: block, cancelPending: cancelPending)
        guard DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        if case .accepted(let program)? = result { publishBlockProgram(program, programID: expected.id) }
        return result
    }

    public func fetchLegacyMigrations(programID: String) async throws -> [WorkoutLegacyMigrationRecord] {
        guard let owner = DIContainer.shared.authService.currentUserID else { throw WorkoutMigrationError.accountChanged }
        let records = try await DIContainer.shared.workoutRepository.fetchLegacyMigrations(userID: owner, programID: programID)
        guard DIContainer.shared.authService.currentUserID == owner else { throw WorkoutMigrationError.accountChanged }
        return records
    }

    public func restoreLegacyMigration(_ command: WorkoutMigrationRollbackCommand) async throws -> WorkoutProgram? {
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutMigrationError.accountChanged }
        let slots = try protectedBlockSlots(in: command.expected())
        guard slots.isEmpty else { throw WorkoutMigrationError.activeWorkout }
        let saved = try await DIContainer.shared.workoutRepository.commitMigrationRollback(userID: command.userID, command: command, protectedSlots: slots)
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutMigrationError.accountChanged }
        publishBlockProgram(saved, programID: command.programID); refreshSyncState()
        return saved
    }

    public func resolveLegacyMigration(_ command: WorkoutMigrationRollbackCommand, cancelPending: Bool = false) async throws -> WorkoutMigrationRollbackResolution {
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutMigrationError.accountChanged }
        let result = try await DIContainer.shared.workoutRepository.resolveMigrationRollback(userID: command.userID, command: command, cancelPending: cancelPending)
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutMigrationError.accountChanged }
        if case .accepted(let saved) = result { publishBlockProgram(saved, programID: command.programID); refreshSyncState() }
        return result
    }

    public func createProgramSuccessor(_ command: WorkoutProgramSuccessorCommand) async throws -> WorkoutProgram? {
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutSuccessorError.accountChanged }
        let saved = try await DIContainer.shared.workoutRepository.createProgramSuccessor(userID: command.userID, command: command)
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutSuccessorError.accountChanged }
        publishSuccessor(saved, id: command.destinationProgramID)
        return saved
    }

    public func resolveProgramSuccessor(_ command: WorkoutProgramSuccessorCommand, cancelPending: Bool = false) async throws -> WorkoutProgramSuccessorResolution {
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutSuccessorError.accountChanged }
        let result = try await DIContainer.shared.workoutRepository.resolveProgramSuccessor(userID: command.userID, command: command, cancelPending: cancelPending)
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutSuccessorError.accountChanged }
        if case .accepted(let saved) = result { publishSuccessor(saved, id: command.destinationProgramID) }
        return result
    }

    /// Saving never switches the active plan. Activation separately confirms receipt,
    /// current canonical destination and absence of any recoverable workout draft.
    public func activateProgramSuccessor(_ command: WorkoutProgramSuccessorCommand,
                                         draftStore: WorkoutDraftStore = WorkoutDraftStore()) async throws -> WorkoutProgram {
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutSuccessorError.accountChanged }
        guard try draftStore.load(userID: command.userID) == nil else { throw WorkoutSuccessorError.activeWorkout }
        guard case .accepted(let current) = try await resolveProgramSuccessor(command), let current else {
            throw WorkoutSuccessorError.unavailable
        }
        guard DIContainer.shared.authService.currentUserID == command.userID else { throw WorkoutSuccessorError.accountChanged }
        guard current.archivedAt == nil else { throw WorkoutLibraryEditError.changed }
        guard try draftStore.load(userID: command.userID) == nil else { throw WorkoutSuccessorError.activeWorkout }
        selectActiveProgram(current, for: command.userID)
        return current
    }

    private func publishSuccessor(_ program: WorkoutProgram?, id: String) {
        if let program {
            if let index = userPrograms.firstIndex(where: { $0.id == id }) { userPrograms[index] = program } else { userPrograms.insert(program, at: 0) }
            if activeProgram?.id == id { activeProgram = program }
        } else {
            userPrograms.removeAll { $0.id == id }
            if activeProgram?.id == id { activeProgram = nil }
        }
    }

    private func publishBlockProgram(_ program: WorkoutProgram?, programID: String?) {
        if let program {
            if let index = userPrograms.firstIndex(where: { $0.id == program.id }) { userPrograms[index] = program }
            if activeProgram?.id == program.id { activeProgram = program }
        } else {
            userPrograms.removeAll { $0.id == programID }
            if activeProgram?.id == programID { activeProgram = nil }
        }
    }

    public func fetchWorkoutSessionLog(workoutID: String, sessionID: String) async -> Result<WorkoutSessionLog, Error> {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            return .failure(WorkoutServiceError.userNotLoggedIn)
        }
        do {
            let sessionLog = try await DIContainer.shared.workoutRepository.fetchWorkoutSessionLog(userID: userID, sessionID: sessionID)
            return .success(sessionLog)
        } catch {
            return .failure(error)
        }
    }

    public func fetchSessionLogs(for program: WorkoutProgram) async -> [WorkoutSessionLog] {
        if case .success(let logs) = await fetchSessionLogsResult(for: program) { return logs }
        return []
    }

    public func fetchSessionLogsResult(for program: WorkoutProgram) async -> Result<[WorkoutSessionLog], Error> {
        guard let userID = DIContainer.shared.authService.currentUserID else { return .failure(WorkoutServiceError.userNotLoggedIn) }
        // Query the lifetime window, then enforce explicit program provenance or a
        // bounded exact-routine legacy match. Similar old plans are not completions.
        let windowDays = Self.sessionLogWindowDays(for: program)
        do {
            let recent = try await DIContainer.shared.workoutRepository.fetchRecentSessionLogs(userID: userID, sinceDays: windowDays)
            guard DIContainer.shared.authService.currentUserID == userID else { return .failure(CancellationError()) }
            return .success(recent.filter { WorkoutRules.logBelongsToProgram($0, program: program) })
        } catch {
            reportFailure(error, operation: "fetch_session_logs")
            if DIContainer.shared.authService.currentUserID == userID {
                loadErrorMessage = "Workout history could not refresh. Your last loaded progress is still shown."
            }
            return .failure(error)
        }
    }

    /// How far back to pull history when reconciling a program's progress: its full lifetime plus a
    /// buffer, with a sane floor for brand-new programs.
    static func sessionLogWindowDays(for program: WorkoutProgram) -> Int {
        // A later schedule edit must not hide earlier explicit slot receipts.
        let start = min(program.dateCreated, program.startDate ?? program.dateCreated)
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(elapsed + 14, program.startDate == nil ? 400 : 120)
    }

    /// Fetches completed session logs from the last `days` days (used by the muscle recovery map,
    /// which needs the real per-exercise names rather than the routine summary in the daily log).
    public func fetchRecentSessionLogs(sinceDays days: Int) async -> [WorkoutSessionLog] {
        switch await fetchRecentSessionLogsResult(sinceDays: days) {
        case .success(let logs):
            return logs
        case .failure:
            return []
        }
    }

    /// Result-preserving variant for reports that must distinguish an empty history from a
    /// failed read instead of quietly presenting a data outage as zero training.
    public func fetchRecentSessionLogsResult(sinceDays days: Int) async -> Result<[WorkoutSessionLog], Error> {
        guard let userID = DIContainer.shared.authService.currentUserID else { return .success([]) }
        do {
            let logs = try await DIContainer.shared.workoutRepository.fetchRecentSessionLogs(
                userID: userID,
                sinceDays: days
            )
            guard DIContainer.shared.authService.currentUserID == userID else {
                return .failure(CancellationError())
            }
            return .success(logs)
        } catch {
            reportFailure(error, operation: "fetch_recent_session_logs")
            return .failure(error)
        }
    }

    public func fetchRoutinesAndPrograms() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            resetAccountState()
            return
        }
        refreshSyncState()
        DIContainer.shared.workoutRepository.retryPendingWorkouts(userID: userID)
        if listenerUserID == userID, routineListener != nil, programListener != nil {
            return
        }

        if let pListener = programListener { DIContainer.shared.workoutRepository.removeListener(pListener) }
        if let rListener = routineListener { DIContainer.shared.workoutRepository.removeListener(rListener) }
        programListener = nil
        routineListener = nil
        if listenerUserID != userID {
            userPrograms = []
            userRoutines = []
            activeProgram = nil
            hasLoadedPrograms = false
        }
        listenerUserID = userID
        unreadableProgramIDs = []
        programLibraryNotice = nil
        routineLibraryNotice = nil
        loadErrorMessage = nil
        isLoadingPrograms = true
        migrateLegacyActiveProgramStorageIfNeeded(for: userID)

        self.programListener = DIContainer.shared.workoutRepository.addProgramLibraryListener(userID: userID) { [weak self] result in
            guard let self,
                  self.listenerUserID == userID,
                  DIContainer.shared.authService.currentUserID == userID else { return }
            switch result {
            case .success(let snapshot):
                self.isLoadingPrograms = false
                self.hasLoadedPrograms = true
                self.programLibraryNotice = snapshot.notice(noun: "programs")
                self.loadErrorMessage = self.programLibraryNotice ?? self.routineLibraryNotice
                self.unreadableProgramIDs = snapshot.unreadableIDs
                self.isProgramLibraryFromCache = snapshot.isFromCache
                self.userPrograms = snapshot.values.sorted { $0.dateCreated > $1.dateCreated }
                self.restoreActiveProgram(for: userID)
            case .failure(let error):
                self.isLoadingPrograms = false
                self.programLibraryNotice = "Your plans could not refresh. Saved changes on this device are kept."
                self.loadErrorMessage = self.programLibraryNotice
                self.reportFailure(error, operation: "programs_snapshot_listener")
            }
        }

        self.routineListener = DIContainer.shared.workoutRepository.addRoutineLibraryListener(userID: userID) { [weak self] result in
            guard let self,
                  self.listenerUserID == userID,
                  DIContainer.shared.authService.currentUserID == userID else { return }
            switch result {
            case .success(let snapshot):
                self.userRoutines = snapshot.values.sorted { $0.dateCreated > $1.dateCreated }
                self.routineLibraryNotice = snapshot.notice(noun: "routines")
                self.loadErrorMessage = self.programLibraryNotice ?? self.routineLibraryNotice
            case .failure(let error):
                self.routineLibraryNotice = "Your routines could not refresh. Try again when connected."
                self.loadErrorMessage = self.programLibraryNotice ?? self.routineLibraryNotice
                self.reportFailure(error, operation: "routines_snapshot_listener")
            }
        }
    }

    deinit {
        let pListener = programListener
        let rListener = routineListener

        Task { @MainActor in
            if let pListener { DIContainer.shared.workoutRepository.removeListener(pListener) }
            if let rListener { DIContainer.shared.workoutRepository.removeListener(rListener) }
        }
    }

    public func setActiveProgram(_ program: WorkoutProgram) {
        guard let userID = DIContainer.shared.authService.currentUserID, program.userID == userID else { return }
        guard program.archivedAt == nil else {
            ToastManager.shared.showToast(message: "Restore this archived plan before making it active.")
            return
        }
        if program.lineage != nil, activeProgram?.id != program.id {
            do {
                guard try WorkoutDraftStore().load(userID: userID) == nil else {
                    ToastManager.shared.showToast(message: WorkoutSuccessorError.activeWorkout.localizedDescription)
                    return
                }
            } catch {
                ToastManager.shared.showToast(message: "Your saved workout could not be checked. Reopen it before switching blocks.")
                return
            }
        }
        selectActiveProgram(program, for: userID)
    }

    private func selectActiveProgram(_ program: WorkoutProgram, for userID: String) {
        activeProgram = program
        defaults.set(false, forKey: Self.activeProgramClearedStorageKey(for: userID))
        if let programID = program.id {
            defaults.set(programID, forKey: Self.activeProgramIDStorageKey(for: userID))
        }
    }

    public func clearActiveProgram() {
        activeProgram = nil
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        defaults.removeObject(forKey: Self.activeProgramIDStorageKey(for: userID))
        defaults.set(true, forKey: Self.activeProgramClearedStorageKey(for: userID))
    }

    public func saveReviewedProgramEdit(_ command: WorkoutProgramEditCommand) async throws -> WorkoutProgram? {
        guard let owner = DIContainer.shared.authService.currentUserID, owner == command.ownerID else { throw WorkoutBlockError.accountChanged }
        let status = try await DIContainer.shared.workoutRepository.resolveProgramEdit(userID: owner, command: command, cancelPending: false)
        guard DIContainer.shared.authService.currentUserID == owner else { throw WorkoutBlockError.accountChanged }
        if case .accepted(let program) = status { return program }
        if case .cancelled = status { throw WorkoutBlockError.cancelled }
        if let latest = userPrograms.first(where: { $0.id == command.programID }) ?? (activeProgram?.id == command.programID ? activeProgram : nil) {
            let result = try command.applying(to: latest)
            for slot in try protectedBlockSlots(in: latest) {
                guard latest.date(forSlot: slot) == result.date(forSlot: slot) else { throw WorkoutBlockError.progressChanged }
                if command.kind == .weekRescue {
                    guard try WorkoutBlockRules.fingerprint(latest.routine(forSlot: slot)) == WorkoutBlockRules.fingerprint(result.routine(forSlot: slot)) else { throw WorkoutBlockError.progressChanged }
                }
            }
        }
        let saved = try await DIContainer.shared.workoutRepository.commitProgramEdit(userID: owner, command: command)
        guard DIContainer.shared.authService.currentUserID == owner else { throw WorkoutBlockError.accountChanged }
        // The canonical listener publishes this checked save; an older callback must not
        // replace a program that changed again while the request was in flight.
        return saved
    }

    @discardableResult
    public func saveProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }

        do {
            var ordinaryProgram = program
            if let id = program.id,
               let canonical = userPrograms.first(where: { $0.id == id }) ?? (activeProgram?.id == id ? activeProgram : nil) {
                try WorkoutProgramEditRules.validateOrdinarySave(program, against: canonical)
                // Only the block transaction owns this field, including publication
                // before an ordinary locally accepted write has synchronized.
                ordinaryProgram.trainingBlock = canonical.trainingBlock
                ordinaryProgram.archivedAt = canonical.archivedAt
                let scheduleChanged = ordinaryProgram.startDate != canonical.startDate || ordinaryProgram.daysOfWeek != canonical.daysOfWeek
                ordinaryProgram = try WorkoutLibraryRules.preservingPassedDates(in: ordinaryProgram, from: canonical,
                    protectedSlots: scheduleChanged ? protectedBlockSlots(in: canonical) : [])
                if ordinaryProgram.progressEpoch != canonical.progressEpoch {
                    ordinaryProgram.currentProgressIndex = canonical.currentProgressIndex; ordinaryProgram.skippedIndices = canonical.skippedIndices
                } else {
                    ordinaryProgram.currentProgressIndex = max(ordinaryProgram.currentProgressIndex ?? 0, canonical.currentProgressIndex ?? 0)
                    let skipped = Set(ordinaryProgram.skippedIndices ?? []).union(canonical.skippedIndices ?? []).sorted()
                    ordinaryProgram.skippedIndices = skipped.isEmpty ? nil : skipped
                }
                ordinaryProgram.progressEpoch = canonical.progressEpoch; ordinaryProgram.slotCompletionProofs = canonical.slotCompletionProofs
                ordinaryProgram.lastSkipReceipt = canonical.lastSkipReceipt
            }
            var savedProgram = try await DIContainer.shared.workoutRepository.saveProgram(userID: userID, program: ordinaryProgram)
            guard DIContainer.shared.authService.currentUserID == userID else { return nil }
            if let id = savedProgram.id,
               let latest = userPrograms.first(where: { $0.id == id }) ?? (activeProgram?.id == id ? activeProgram : nil) {
                savedProgram.trainingBlock = latest.trainingBlock
                if savedProgram.progressEpoch != latest.progressEpoch {
                    savedProgram.currentProgressIndex = latest.currentProgressIndex; savedProgram.skippedIndices = latest.skippedIndices
                    savedProgram.progressEpoch = latest.progressEpoch; savedProgram.slotCompletionProofs = latest.slotCompletionProofs
                    savedProgram.lastSkipReceipt = latest.lastSkipReceipt
                }
            }
            if let index = userPrograms.firstIndex(where: { $0.id == savedProgram.id }) { userPrograms[index] = savedProgram } else { userPrograms.insert(savedProgram, at: 0) }
            if activeProgram?.id == savedProgram.id { activeProgram = savedProgram }
            refreshSyncState()

            if program.id == nil {
                DIContainer.shared.analyticsManager?.logEvent("program_created", parameters: nil)
            }
            return savedProgram
        } catch {
            reportFailure(
                error,
                operation: "save_program",
                userMessage: (error as? WorkoutBlockError)?.localizedDescription ?? "Couldn't save your program changes. Please try again."
            )
            return nil
        }
    }

    @discardableResult
    public func setProgramArchived(_ program: WorkoutProgram, archived: Bool) async -> Bool {
        guard let userID = DIContainer.shared.authService.currentUserID, program.userID == userID else { return false }
        do {
            let latest = userPrograms.first { $0.id == program.id } ?? program
            let linkedDraft = try !protectedBlockSlots(in: latest).isEmpty
            let updated = try WorkoutLibraryRules.archiving(latest, archived: archived,
                activeProgramID: activeProgram?.id, hasLinkedDraft: linkedDraft)
            let saved = try await DIContainer.shared.workoutRepository.saveProgramArchive(userID: userID, program: updated)
            guard DIContainer.shared.authService.currentUserID == userID else { return false }
            if let index = userPrograms.firstIndex(where: { $0.id == saved.id }) { userPrograms[index] = saved }
            if activeProgram?.id == saved.id { activeProgram = saved }
            refreshSyncState()
            return true
        } catch {
            ToastManager.shared.showToast(message: error.localizedDescription)
            return false
        }
    }

    /// Advances the program's pointer to `targetIndex`, marking every slot in between as skipped.
    /// Skipping never writes a session log, daily-log entry, or HealthKit sample, so it can't
    /// collide with the Apple Health strength-dedup logic. Updates `activeProgram` and persists.
    @discardableResult
    public func skipToIndex(_ targetIndex: Int, in program: WorkoutProgram) async -> WorkoutProgram? {
        guard let owner = DIContainer.shared.authService.currentUserID, program.userID == owner else { return nil }
        let latest = knownProgram(id: program.id ?? "") ?? program
        guard targetIndex > (latest.currentProgressIndex ?? 0), targetIndex <= latest.totalSlots else { return latest }
        do {
            let protected = try protectedBlockSlots(in: latest)
            guard !((latest.currentProgressIndex ?? 0)..<targetIndex).contains(where: { protected.contains($0) }) else { throw WorkoutLibraryEditError.activeWorkout }
            // A deliberate skip reviews authoritative history; ordinary completion remains
            // locally durable through the same workout outbox and does not require this read.
            let history = try await DIContainer.shared.workoutRepository.fetchCompleteWorkoutHistory(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { throw WorkoutBlockError.accountChanged }
            let proofs = progressProofLogs(history, in: latest)
            let command = try WorkoutProgramProgressCommand(program: latest, kind: .skip, targetIndex: targetIndex, proofSessionIDs: proofs.compactMap(\.id))
            let saved = try await DIContainer.shared.workoutRepository.enqueueProgramProgress(userID: owner, command: command, locallyVerifiedLogs: proofs)
            guard DIContainer.shared.authService.currentUserID == owner else { throw WorkoutBlockError.accountChanged }
            let visible = try publishProgressProjection(saved, command: command); refreshSyncState(); return visible
        } catch { reportFailure(error, operation: "skip_program_slots", userMessage: "The skip is not confirmed. Your workout history and current position are kept. \(error.localizedDescription)"); return nil }
    }

    /// Undo is an explicit epoch-fenced progress operation; any later completion wins.
    public func undoLastProgramSkip(in program: WorkoutProgram) async throws -> WorkoutProgram {
        guard let owner = DIContainer.shared.authService.currentUserID, owner == program.userID else { throw WorkoutBlockError.accountChanged }
        let latest = knownProgram(id: program.id ?? "") ?? program
        guard try protectedBlockSlots(in: latest).isEmpty else { throw WorkoutLibraryEditError.activeWorkout }
        let history = try await DIContainer.shared.workoutRepository.fetchCompleteWorkoutHistory(userID: owner)
        guard DIContainer.shared.authService.currentUserID == owner else { throw WorkoutBlockError.accountChanged }
        let minimum = latest.lastSkipReceipt?.originalProgress ?? latest.currentProgressIndex ?? 0
        let proofs = Array(WorkoutRules.sessionLogsBySlot(in: latest, sessionLogs: history).filter { $0.key >= minimum }.values)
        let command = try WorkoutProgramProgressCommand(program: latest, kind: .undoSkip, proofSessionIDs: proofs.compactMap(\.id))
        let saved = try await DIContainer.shared.workoutRepository.enqueueProgramProgress(userID: owner, command: command, locallyVerifiedLogs: proofs)
        guard DIContainer.shared.authService.currentUserID == owner else { throw WorkoutBlockError.accountChanged }
        let visible = try publishProgressProjection(saved, command: command); refreshSyncState(); return visible
    }
    public func pendingProgramProgress(in program: WorkoutProgram) throws -> [WorkoutProgramProgressCommand] {
        guard let owner = DIContainer.shared.authService.currentUserID, owner == program.userID, let id = program.id else { throw WorkoutBlockError.accountChanged }
        return try DIContainer.shared.workoutRepository.pendingProgramProgress(userID: owner, programID: id)
    }
    public func resolveProgramProgress(_ command: WorkoutProgramProgressCommand, cancelPending: Bool = false) async throws -> WorkoutProgramProgressResolution {
        guard DIContainer.shared.authService.currentUserID == command.ownerID else { throw WorkoutBlockError.accountChanged }
        let result = try await DIContainer.shared.workoutRepository.resolveProgramProgress(userID: command.ownerID, command: command, cancelPending: cancelPending)
        guard DIContainer.shared.authService.currentUserID == command.ownerID else { throw WorkoutBlockError.accountChanged }
        switch result {
        case .accepted(let program), .cancelled(let program): publishSuccessor(program, id: command.programID)
        case .pending: break
        }
        refreshSyncState(); return result
    }
    private func publishProgressProjection(_ saved: WorkoutProgram, command: WorkoutProgramProgressCommand) throws -> WorkoutProgram {
        let expected = try command.expected()
        if let latest = knownProgram(id: command.programID), latest.progressEpoch != expected.progressEpoch,
           latest.progressEpoch != saved.progressEpoch {
            guard command.kind == .completion else { throw WorkoutBlockError.progressChanged }
            let visible = try command.overlay(proposed: saved, on: latest)
            if visible.progressEpoch != latest.progressEpoch { publishSuccessor(visible, id: command.programID) }
            return visible
        }
        publishSuccessor(saved, id: command.programID)
        return saved
    }
    private func progressProofLogs(_ logs: [WorkoutSessionLog], in program: WorkoutProgram) -> [WorkoutSessionLog] {
        let first = max(program.currentProgressIndex ?? 0, 0)
        return Array(WorkoutRules.sessionLogsBySlot(in: program, sessionLogs: logs).filter { $0.key >= first }.values)
    }

    /// Skips just the current workout through the reviewed, durable progress path.
    @discardableResult
    public func skipCurrentWorkout(in program: WorkoutProgram) async -> WorkoutProgram? {
        await skipToIndex((program.currentProgressIndex ?? 0) + 1, in: program)
    }

    public func deleteProgram(_ program: WorkoutProgram) async -> ProgramDeletionResult {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            return .userNotLoggedIn
        }
        guard let programID = resolvedProgramID(for: program) else {
            clearActiveProgram()
            return .clearedLocalOnly
        }

        do {
            try await DIContainer.shared.workoutRepository.deleteProgram(userID: userID, programID: programID)
            guard DIContainer.shared.authService.currentUserID == userID else { return .userNotLoggedIn }
            removeDeletedProgramFromLocalState(programID: programID, fallbackName: program.name)
            return .deleted
        } catch {
            // No toast here: the ProgramDeletionResult carries the user-facing message.
            reportFailure(error, operation: "delete_program")
            return .failed(error.localizedDescription)
        }
    }

    public func saveRoutine(_ routine: WorkoutRoutine) async throws {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            throw WorkoutServiceError.userNotLoggedIn
        }

        do {
            try await DIContainer.shared.workoutRepository.saveRoutine(userID: userID, routine: routine)
            guard DIContainer.shared.authService.currentUserID == userID else { throw CancellationError() }
            if let index = userRoutines.firstIndex(where: { $0.id == routine.id }) { userRoutines[index] = routine } else { userRoutines.insert(routine, at: 0) }
            refreshSyncState()
        } catch {
            throw WorkoutServiceError.firestoreError(error)
        }
    }

    public func deleteRoutine(_ routine: WorkoutRoutine) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        Task {
            do {
                try await DIContainer.shared.workoutRepository.deleteRoutine(userID: userID, routineID: routine.id)
                guard DIContainer.shared.authService.currentUserID == userID else { return }
                self.userRoutines.removeAll { $0.id == routine.id }
                self.refreshSyncState()
            } catch {
                reportFailure(
                    error,
                    operation: "delete_routine",
                    userMessage: "Couldn't delete the routine. Please try again."
                )
            }
        }
    }

    @discardableResult
    public func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async -> Bool {
        guard let userID = DIContainer.shared.authService.currentUserID else { return false }
        do {
            try await DIContainer.shared.workoutRepository.saveWorkoutSessionLog(userID: userID, log: log)
            guard DIContainer.shared.authService.currentUserID == userID else { return false }
            refreshSyncState()
            return true
        } catch {
            reportFailure(
                error,
                operation: "save_workout_session_log",
                userMessage: "Couldn't save your workout to history. Check your connection."
            )
            return false
        }
    }

    /// Acknowledge the exact slot captured at session start. Replaying a frozen
    /// completion is harmless, and an early session cannot skip unfinished slots.
    /// The caller retains its completion draft until this acknowledgment is accepted.
    public func recordProgramCompletion(_ log: WorkoutSessionLog) async -> Bool {
        guard let context = log.programContext else { return true }
        guard let userID = DIContainer.shared.authService.currentUserID else { return false }
        guard let program = knownProgram(id: context.programID) else {
            // A deliberately deleted program must not trap an otherwise saved workout.
            // An unavailable/unreadable library is not evidence that it was deleted.
            return hasLoadedPrograms && !isProgramLibraryFromCache && !unreadableProgramIDs.contains(context.programID)
        }
        guard program.userID == userID, WorkoutRules.logBelongsToProgram(log, program: program) else { return false }
        let history: [WorkoutSessionLog]
        if program.progressEpoch == nil {
            guard case .success(let values) = await fetchSessionLogsResult(for: program) else { return false }
            history = values
        } else { history = [] }
        guard DIContainer.shared.authService.currentUserID == userID,
              let latest = knownProgram(id: context.programID), latest.userID == userID else { return false }
        do {
            guard let sessionID = log.id else { return false }
            let proofs = progressProofLogs(history + [log], in: latest)
            let command = try WorkoutProgramProgressCommand(program: latest, kind: .completion, sessionID: sessionID,
                proofSessionIDs: proofs.compactMap(\.id))
            let saved = try await DIContainer.shared.workoutRepository.enqueueProgramProgress(userID: userID, command: command,
                locallyVerifiedLogs: proofs + [log])
            guard DIContainer.shared.authService.currentUserID == userID else { return false }
            _ = try publishProgressProjection(saved, command: command); refreshSyncState(); return true
        } catch { reportFailure(error, operation: "record_program_completion"); return false }
    }

    public func reconcileProgramProgress(in program: WorkoutProgram, knownLogs: [WorkoutSessionLog]) async -> WorkoutProgram? {
        guard let owner = DIContainer.shared.authService.currentUserID, owner == program.userID, let id = program.id else { return nil }
        let latest = knownProgram(id: id) ?? program
        let map = WorkoutRules.sessionLogsBySlot(in: latest, sessionLogs: knownLogs)
        guard let receipt = map[max(latest.currentProgressIndex ?? 0, 0)], let sessionID = receipt.id else { return latest }
        do {
            let proofs = progressProofLogs(knownLogs, in: latest)
            let command = try WorkoutProgramProgressCommand(program: latest, kind: .completion, sessionID: sessionID, proofSessionIDs: proofs.compactMap(\.id))
            let saved = try await DIContainer.shared.workoutRepository.enqueueProgramProgress(userID: owner, command: command, locallyVerifiedLogs: proofs)
            guard DIContainer.shared.authService.currentUserID == owner else { return nil }
            return try publishProgressProjection(saved, command: command)
        } catch { reportFailure(error, operation: "reconcile_program_progress"); return nil }
    }

    private func knownProgram(id: String) -> WorkoutProgram? {
        if let program = userPrograms.first(where: { $0.id == id }) { return program }
        return activeProgram?.id == id ? activeProgram : nil
    }

    public func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog] {
        guard let userID = DIContainer.shared.authService.currentUserID else { return [] }

        do {
            return try await DIContainer.shared.workoutRepository.fetchHistory(userID: userID, exerciseName: exerciseName)
        } catch {
            reportFailure(error, operation: "fetch_exercise_history")
            return []
        }
    }

    public func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        do {
             let performance = try await DIContainer.shared.workoutRepository.fetchPreviousPerformance(userID: userID, exerciseName: exerciseName)
             guard DIContainer.shared.authService.currentUserID == userID, !Task.isCancelled else { return nil }
             return performance
        } catch {
            reportFailure(error, operation: "fetch_previous_performance")
            return nil
        }
    }

    // MARK: - AI Workout Generation (Refactored)

    public func generateAIWorkoutPlan(
        goal: String,
        daysPerWeek: Int,
        fitnessLevel: String,
        equipment: String,
        details: String,
        goalSettings: GoalSettings,
        maximumSessionMinutes: Int? = nil, gym: StrengthGymProfile? = nil, confirmedMovements: [String: String] = [:],
        preferredMovements: [String] = [], avoidedMovements: [String] = []
    ) async -> Result<WorkoutProgram, WorkoutServiceError> {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            return .failure(.userNotLoggedIn)
        }

        guard let requestedEquipment = WorkoutPlanningEquipment(request: equipment), (1...7).contains(daysPerWeek),
              maximumSessionMinutes == nil || (10...180).contains(maximumSessionMinutes ?? 0) else {
            return .failure(.apiError(WorkoutPlanningEligibilityError.invalid.localizedDescription))
        }
        do { try WorkoutAIContract.validateMovementChoices(preferred: preferredMovements, avoided: avoidedMovements) } catch { return .failure(.apiError(error.localizedDescription)) }
        let movementDetails = details + "\nPreferred exact movements (soft preference): " + preferredMovements.joined(separator: "; ")
            + ". Avoid entirely, including alternatives: " + avoidedMovements.joined(separator: "; ") + ". Do not diagnose injury or override an existing active program."
        let inventoryDetails: String
        if let gym {
            guard gym.isValid, confirmedMovements.allSatisfy({ WorkoutMovementCatalog.identity(for: $0.key) != nil && gym.equipment(for: $0.value) != nil }) else {
                return .failure(.apiError(WorkoutAIContractError.equipment(gym.name).localizedDescription))
            }
            let rows = confirmedMovements.keys.sorted().map { "\($0):equipmentProfileID=\(gym.id),equipmentImplementID=\(confirmedMovements[$0] ?? "")" }.joined(separator: "; ")
            inventoryDetails = movementDetails + "\nConfirmed actual gym \(gym.name), revision \(gym.revisionID). Use only these loaded movement→implement mappings and echo their exact IDs: " + rows
                + ". Floor-only movements need nil equipment IDs. No other machines, supports, bars or attachments are available."
        } else { inventoryDetails = movementDetails }
        guard let prompt = WorkoutRules.createAIWorkoutPrompt(
            goal: goal,
            daysPerWeek: daysPerWeek,
            fitnessLevel: fitnessLevel,
            equipment: equipment,
            details: inventoryDetails,
            age: goalSettings.age,
            gender: goalSettings.gender,
            primaryWeightGoal: goalSettings.goal,
            maximumSessionMinutes: maximumSessionMinutes, typedContract: true
        ) else {
            return .failure(.apiError("Failed to load internal exercise list."))
        }

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        // Use shared AIService
        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            model: "gpt-6-astra",
            maxTokens: 4000,
            temperature: 0.7,
            responseFormat: ["type": "json_object"], requestKind: .planning,
            retryCount: 1
        )

        guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == userID else {
            return .failure(.userNotLoggedIn)
        }
        switch result {
        case .success(let responseString):
            let parseResult = WorkoutRules.parseAIWorkoutResponse(responseString)
            switch parseResult {
            case .success(let decodedResponse):
                DIContainer.shared.analyticsManager?.logEvent("ai_workout_generated", parameters: [
                    "goal": goal,
                    "days_per_week": daysPerWeek,
                    "fitness_level": fitnessLevel
                ])

                do {
                    let program = try WorkoutAIContract.map(decodedResponse, userID: userID, daysPerWeek: daysPerWeek,
                        equipment: requestedEquipment, maximumSessionMinutes: maximumSessionMinutes, gym: gym, confirmedMovements: confirmedMovements, preferredMovements: preferredMovements, avoidedMovements: avoidedMovements)
                    return .success(program)
                } catch { return .failure(.apiError(error.localizedDescription)) }
            case .apiError(let message):
                return .failure(.apiError(message))
            case .decodingError(let error):
                AppLog.workouts.error("AI workout decode failed: \(error.localizedDescription, privacy: .public)")
                AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_ai_workout_response")
                return .failure(.decodingError(error))
            }
        case .failure(let error):
            return .failure(.apiError(error.localizedDescription))
        }
    }

    public func detachListener() {
        if let l = programListener { DIContainer.shared.workoutRepository.removeListener(l) }
        if let l = routineListener { DIContainer.shared.workoutRepository.removeListener(l) }
        programListener = nil
        routineListener = nil
    }

    private func loadPreBuiltPrograms() {
        self.preBuiltPrograms = WorkoutRules.generatePreBuiltPrograms()
    }

    /// Copies a pre-built program and saves it as a user program
    @discardableResult
    public func selectPreBuiltProgram(_ program: WorkoutProgram, startDate: Date = Date()) async -> WorkoutProgram? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }

        DIContainer.shared.analyticsManager?.logEvent("prebuilt_program_selected", parameters: ["program_name": program.name])

        let userProgramCopy = WorkoutRules.preparePreBuiltProgramForUser(
            program,
            userID: userID,
            startDate: startDate
        )

        let savedProgram = await saveProgram(userProgramCopy)
        if let savedProgram {
            setActiveProgram(savedProgram)
        }
        return savedProgram
    }

    private func restoreActiveProgram(for userID: String) {
        guard listenerUserID == userID,
              DIContainer.shared.authService.currentUserID == userID else { return }
        let programIDKey = Self.activeProgramIDStorageKey(for: userID)
        let clearedKey = Self.activeProgramClearedStorageKey(for: userID)

        guard !userPrograms.isEmpty else {
            activeProgram = nil
            // An empty offline cache is not proof the preferred program was deleted.
            return
        }

        if defaults.bool(forKey: clearedKey) {
            activeProgram = nil
            return
        }

        if let savedActiveProgramID = defaults.string(forKey: programIDKey),
           let savedActiveProgram = userPrograms.first(where: { $0.id == savedActiveProgramID }) {
            activeProgram = savedActiveProgram
            return
        }

        if let savedID = defaults.string(forKey: programIDKey), unreadableProgramIDs.contains(savedID) || isProgramLibraryFromCache {
            activeProgram = nil
            return
        }

        if let currentActiveProgramID = activeProgram?.id,
           let currentActiveProgram = userPrograms.first(where: { $0.id == currentActiveProgramID }) {
            activeProgram = currentActiveProgram
            return
        }

        activeProgram = userPrograms.first { $0.archivedAt == nil }
        if defaults.string(forKey: programIDKey) == nil, let firstProgramID = activeProgram?.id {
            defaults.set(firstProgramID, forKey: programIDKey)
        }
    }

    private func resetAccountState() {
        detachListener()
        listenerUserID = nil
        userPrograms = []
        userRoutines = []
        activeProgram = nil
        loadErrorMessage = nil
        isLoadingPrograms = false
        hasLoadedPrograms = false
        syncState = .synced
        unreadableProgramIDs = []
        isProgramLibraryFromCache = false
        programLibraryNotice = nil
        routineLibraryNotice = nil
    }

    private func migrateLegacyActiveProgramStorageIfNeeded(for userID: String) {
        let programIDKey = Self.activeProgramIDStorageKey(for: userID)
        let clearedKey = Self.activeProgramClearedStorageKey(for: userID)

        if defaults.object(forKey: programIDKey) == nil,
           let legacyProgramID = defaults.string(forKey: Self.legacyActiveProgramIDKey) {
            defaults.set(legacyProgramID, forKey: programIDKey)
        }
        if defaults.object(forKey: clearedKey) == nil,
           defaults.object(forKey: Self.legacyActiveProgramClearedKey) != nil {
            defaults.set(defaults.bool(forKey: Self.legacyActiveProgramClearedKey), forKey: clearedKey)
        }

        defaults.removeObject(forKey: Self.legacyActiveProgramIDKey)
        defaults.removeObject(forKey: Self.legacyActiveProgramClearedKey)
    }

    static func activeProgramIDStorageKey(for userID: String) -> String {
        "active_workout_program_id_\(accountDigest(userID))"
    }

    static func activeProgramClearedStorageKey(for userID: String) -> String {
        "active_workout_program_cleared_\(accountDigest(userID))"
    }

    private static func accountDigest(_ userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func resolvedProgramID(for program: WorkoutProgram) -> String? {
        if let programID = program.id,
           userPrograms.contains(where: { $0.id == programID }) {
            return programID
        }

        if let activeProgramID = activeProgram?.id,
           activeProgram?.name == program.name,
           userPrograms.contains(where: { $0.id == activeProgramID }) {
            return activeProgramID
        }

        if let matchingProgram = userPrograms.first(where: { savedProgram in
            savedProgram.name == program.name && Calendar.current.isDate(savedProgram.dateCreated, equalTo: program.dateCreated, toGranularity: .second)
        }) {
            return matchingProgram.id
        }

        return userPrograms.first(where: { $0.name == program.name })?.id ?? program.id
    }

    private func removeDeletedProgramFromLocalState(programID: String, fallbackName: String) {
        userPrograms.removeAll { savedProgram in
            if let savedProgramID = savedProgram.id {
                return savedProgramID == programID
            }
            return savedProgram.name == fallbackName
        }

        if activeProgram?.id == programID || activeProgram?.name == fallbackName {
            clearActiveProgram()
        }
    }
}

// Helpers
public struct AIProgramResponse: Codable {
    public let programName: String
    public let routines: [AIRoutine]
    public let schemaVersion: Int?
    public init(programName: String, routines: [AIRoutine], schemaVersion: Int? = nil) {
        self.programName = programName; self.routines = routines; self.schemaVersion = schemaVersion
    }
}
public struct AIRoutine: Codable {
    public let name: String
    public let exercises: [AIExercise]
    public init(name: String, exercises: [AIExercise]) { self.name = name; self.exercises = exercises }
}
public struct AIExercise: Codable {
    public let name: String
    public let type: ExerciseType
    public let sets: [AISet]
    public let alternatives: [String]?
    public let movementID: String?
    public let variantID: String?
    public let progressionPolicy: WorkoutProgressionPolicy?
    public let equipmentProfileID: String?
    public let equipmentImplementID: String?
    public let restSeconds: Int?
    public init(name: String, type: ExerciseType, sets: [AISet], alternatives: [String]?, movementID: String? = nil,
                variantID: String? = nil, progressionPolicy: WorkoutProgressionPolicy? = nil,
                equipmentProfileID: String? = nil, equipmentImplementID: String? = nil, restSeconds: Int? = nil) {
        self.name = name; self.type = type; self.sets = sets; self.alternatives = alternatives
        self.movementID = movementID; self.variantID = variantID; self.progressionPolicy = progressionPolicy
        self.equipmentProfileID = equipmentProfileID; self.equipmentImplementID = equipmentImplementID; self.restSeconds = restSeconds
    }
}
public struct AISet: Codable {
    public let target: String
    public let prescription: WorkoutPrescription?
    public init(target: String, prescription: WorkoutPrescription? = nil) { self.target = target; self.prescription = prescription }
}

// Missing Extension for Array Chunking
public extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
