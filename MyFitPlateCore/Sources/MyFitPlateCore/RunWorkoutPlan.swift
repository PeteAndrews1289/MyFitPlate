import Foundation

/// A structured running workout the live recorder can guide step by step.
public struct RunWorkoutPlan: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var subtitle: String
    public var steps: [RunWorkoutStep]
    public var repeatGroup: RunWorkoutRepeatGroup?
    public var outline: [RunWorkoutOutlineItem]?

    public init(id: String = UUID().uuidString, name: String, subtitle: String, steps: [RunWorkoutStep], repeatGroup: RunWorkoutRepeatGroup? = nil, outline: [RunWorkoutOutlineItem]? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.steps = steps
        self.repeatGroup = repeatGroup
        self.outline = outline
    }

    public static func builtinTemplates(metric: Bool) -> [RunWorkoutPlan] {
        [
            quarterRepeats(metric: metric),
            thirtyThirty(),
            tempoStarter()
        ]
    }

    public var estimatedDurationSeconds: Double {
        steps.reduce(0) { total, step in
            switch step.goal {
            case .duration(let seconds):
                return total + max(0, seconds)
            case .distance, .open:
                return total
            }
        }
    }

    public var totalDistanceMeters: Double {
        steps.reduce(0) { total, step in
            switch step.goal {
            case .distance(let meters):
                return total + max(0, meters)
            case .duration, .open:
                return total
            }
        }
    }

    public static func repeatTemplate(
        id: String = UUID().uuidString,
        name: String,
        warmupSeconds: Double,
        repetitions: Int,
        workGoal: RunWorkoutStep.Goal,
        recoverySeconds: Double,
        cooldownSeconds: Double,
        workTarget: RunWorkoutTarget? = nil
    ) -> RunWorkoutPlan {
        let safeRepetitions = max(1, min(50, repetitions))
        var steps: [RunWorkoutStep] = []

        if warmupSeconds > 0 {
            steps.append(RunWorkoutStep(
                id: "warmup",
                kind: .warmup,
                title: "Warm up",
                goal: .duration(seconds: warmupSeconds),
                target: RunWorkoutTarget(cue: "Easy start")
            ))
        }

        for rep in 1...safeRepetitions {
            steps.append(RunWorkoutStep(
                id: "work-\(rep)",
                kind: .hard,
                title: "Work",
                goal: workGoal,
                target: workTarget ?? RunWorkoutTarget(cue: "Controlled effort")
            ))

            if rep < safeRepetitions, recoverySeconds > 0 {
                steps.append(RunWorkoutStep(
                    id: "recover-\(rep)",
                    kind: .recovery,
                    title: "Recover",
                    goal: .duration(seconds: recoverySeconds),
                    target: RunWorkoutTarget(cue: "Easy jog or walk")
                ))
            }
        }

        if cooldownSeconds > 0 {
            steps.append(RunWorkoutStep(
                id: "cooldown",
                kind: .cooldown,
                title: "Cool down",
                goal: .duration(seconds: cooldownSeconds),
                target: RunWorkoutTarget(cue: "Easy finish")
            ))
        }

        return RunWorkoutPlan(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Intervals" : name,
            subtitle: "\(safeRepetitions) repeats",
            steps: steps
        )
    }

    private static func quarterRepeats(metric: Bool) -> RunWorkoutPlan {
        var steps: [RunWorkoutStep] = [
            RunWorkoutStep(
                id: "warmup",
                kind: .warmup,
                title: "Warm up",
                goal: .duration(seconds: 10 * 60),
                target: RunWorkoutTarget(cue: "Easy start")
            )
        ]
        for rep in 1...5 {
            steps.append(RunWorkoutStep(
                id: "rep-\(rep)",
                kind: .hard,
                title: "400 m repeat",
                goal: .distance(meters: 400),
                target: RunWorkoutTarget(cue: "Fast but controlled")
            ))
            if rep < 5 {
                steps.append(RunWorkoutStep(
                    id: "recover-\(rep)",
                    kind: .recovery,
                    title: "Recover",
                    goal: .duration(seconds: 90),
                    target: RunWorkoutTarget(cue: "Easy jog or walk")
                ))
            }
        }
        steps.append(RunWorkoutStep(
            id: "cooldown",
            kind: .cooldown,
            title: "Cool down",
            goal: .duration(seconds: 5 * 60),
            target: RunWorkoutTarget(cue: "Easy finish")
        ))

        return RunWorkoutPlan(
            id: "5x400m",
            name: "5 x 400 m",
            subtitle: metric ? "Speed session" : "Track-speed session",
            steps: steps
        )
    }

    private static func thirtyThirty() -> RunWorkoutPlan {
        var steps: [RunWorkoutStep] = [
            RunWorkoutStep(
                id: "warmup",
                kind: .warmup,
                title: "Warm up",
                goal: .duration(seconds: 8 * 60),
                target: RunWorkoutTarget(cue: "Easy start")
            )
        ]
        for rep in 1...10 {
            steps.append(RunWorkoutStep(
                id: "fast-\(rep)",
                kind: .hard,
                title: "Fast",
                goal: .duration(seconds: 30),
                target: RunWorkoutTarget(cue: "Quick turnover")
            ))
            steps.append(RunWorkoutStep(
                id: "easy-\(rep)",
                kind: .recovery,
                title: "Easy",
                goal: .duration(seconds: 30),
                target: RunWorkoutTarget(cue: "Float easy")
            ))
        }
        steps.append(RunWorkoutStep(
            id: "cooldown",
            kind: .cooldown,
            title: "Cool down",
            goal: .duration(seconds: 5 * 60),
            target: RunWorkoutTarget(cue: "Easy finish")
        ))

        return RunWorkoutPlan(
            id: "30-30-fartlek",
            name: "30/30 Fartlek",
            subtitle: "Fast/easy turnover",
            steps: steps
        )
    }

    private static func tempoStarter() -> RunWorkoutPlan {
        RunWorkoutPlan(
            id: "tempo-starter",
            name: "Tempo Starter",
            subtitle: "Controlled steady effort",
            steps: [
                RunWorkoutStep(
                    id: "warmup",
                    kind: .warmup,
                    title: "Warm up",
                    goal: .duration(seconds: 10 * 60),
                    target: RunWorkoutTarget(cue: "Easy start")
                ),
                RunWorkoutStep(
                    id: "tempo",
                    kind: .hard,
                    title: "Tempo",
                    goal: .duration(seconds: 20 * 60),
                    target: RunWorkoutTarget(cue: "Comfortably hard")
                ),
                RunWorkoutStep(
                    id: "cooldown",
                    kind: .cooldown,
                    title: "Cool down",
                    goal: .duration(seconds: 5 * 60),
                    target: RunWorkoutTarget(cue: "Easy finish")
                )
            ]
        )
    }
}

public struct RunWorkoutPlanRevision: Codable, Equatable, Identifiable {
    public let id: String
    public let plan: RunWorkoutPlan
    public let savedAt: Date
}

/// One mutable sync unit owns the workout and its favorite status. A deletion and
/// a favorite/edit from another device must conflict as whole versions; neither
/// field can independently remove the record required by the other.
public struct RunCloudWorkoutRecord: Codable, Equatable {
    public let schemaVersion: Int
    public let plan: RunWorkoutPlan
    public let isFavorite: Bool
    public init(plan: RunWorkoutPlan, isFavorite: Bool) {
        schemaVersion = 1; self.plan = plan; self.isFavorite = isFavorite
    }
    public func validate(key: String) throws {
        guard schemaVersion == 1, key == "plan/" + plan.id else { throw RunCloudError.invalid }
        try RunWorkoutPlanStore.validate(plan)
    }
}

public final class RunWorkoutPlanStore: ObservableObject {
    public enum SaveError: LocalizedError {
        case accountChanged, unreadableLibrary, changedSinceReview, invalidPlan(String), persistenceFailed
        public var errorDescription: String? {
            switch self {
            case .accountChanged: return "Your account changed. Reopen this workout in the correct account."
            case .unreadableLibrary: return "The saved workout library could not be read. It has been kept unchanged."
            case .changedSinceReview: return "This workout changed after you opened it. Your draft is kept; save a new copy or reopen the latest version."
            case .invalidPlan(let reason): return reason
            case .persistenceFailed: return "The workout could not be saved. Your draft is kept; try again."
            }
        }
    }

    private struct Receipt: Codable {
        let operationID: String
        let requestedPlan: RunWorkoutPlan
        let revisionID: String
    }
    private struct Library: Codable {
        let schema: Int
        var plans: [RunWorkoutPlan]
        var revisions: [RunWorkoutPlanRevision]
        var receipts: [Receipt]
        var favoritePlanIDs: [String]?
        init(plans: [RunWorkoutPlan] = []) {
            schema = 1
            self.plans = plans
            revisions = []
            receipts = []
        }
    }

    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol
    private let legacyStorageKey = "myfitplate.run_workout_plans"
    private var activeUserID: String?
    private var cloudChangeObserver: NSObjectProtocol?
    @Published private var storedCustomPlans: [RunWorkoutPlan] = []
    @Published public private(set) var lastSaveError: String?

    public var customPlans: [RunWorkoutPlan] {
        synchronizeAccountIfNeeded()
        return storedCustomPlans
    }

    public var favoritePlans: [RunWorkoutPlan] {
        synchronizeAccountIfNeeded()
        guard let library = try? readLibrary() else { return [] }
        let ids = Set(library.favoritePlanIDs ?? [])
        return library.plans.filter { ids.contains($0.id) }
    }

    public func isFavorite(id: String) -> Bool {
        synchronizeAccountIfNeeded()
        return (try? readLibrary().favoritePlanIDs?.contains(id)) ?? false
    }

    public func setFavorite(_ plan: RunWorkoutPlan, favorite: Bool, userID: String) throws {
        synchronizeAccountIfNeeded()
        guard activeUserID == userID, authService.currentUserID == userID else { throw SaveError.accountChanged }
        try Self.validate(plan)
        var library = try readLibrary()
        if let existing = library.plans.first(where: { $0.id == plan.id }), existing != plan { throw SaveError.changedSinceReview }
        if favorite, !library.plans.contains(where: { $0.id == plan.id }) {
            library.plans.insert(plan, at: 0)
            library.revisions.append(RunWorkoutPlanRevision(id: UUID().uuidString, plan: plan, savedAt: Date()))
        }
        var ids = Set(library.favoritePlanIDs ?? [])
        if favorite { ids.insert(plan.id) } else { ids.remove(plan.id) }
        library.favoritePlanIDs = ids.sorted()
        try persist(library, userID: userID)
    }

    public init(userDefaults: UserDefaults, authService: AuthServiceProtocol) {
        self.userDefaults = userDefaults
        self.authService = authService
        activeUserID = authService.currentUserID
        reload()
        cloudChangeObserver = NotificationCenter.default.addObserver(forName: .runLibrariesChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, note.object as? String == self.authService.currentUserID else { return }
            self.synchronizeAccountIfNeeded(); self.reload()
        }
    }
    deinit { if let cloudChangeObserver { NotificationCenter.default.removeObserver(cloudChangeObserver) } }

    @MainActor public convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, authService: DIContainer.shared.authService)
    }

    /// The original expanded plan remains executable; revisions only describe future edits.
    public func revisions(forPlanID id: String) -> [RunWorkoutPlanRevision] {
        synchronizeAccountIfNeeded()
        return ((try? readLibrary())?.revisions ?? []).filter { $0.plan.id == id }
    }

    /// An exact review plus stable operation identity makes a replay acknowledge its first
    /// revision without overwriting a newer edit or inserting another template.
    @discardableResult
    public func saveReviewed(_ plan: RunWorkoutPlan, replacing expected: RunWorkoutPlan?,
                             operationID: String, userID: String, now: Date = Date()) throws -> RunWorkoutPlanRevision {
        synchronizeAccountIfNeeded()
        guard activeUserID == userID, authService.currentUserID == userID else { throw SaveError.accountChanged }
        try Self.validate(plan)
        guard !operationID.isEmpty else { throw SaveError.invalidPlan("Reopen the workout editor before saving.") }
        var library = try readLibrary()
        if let receipt = library.receipts.first(where: { $0.operationID == operationID }) {
            guard receipt.requestedPlan == plan,
                  let revision = library.revisions.first(where: { $0.id == receipt.revisionID }) else { throw SaveError.changedSinceReview }
            return revision
        }
        let current = library.plans.first { $0.id == plan.id }
        guard current == expected, expected.map({ $0.id == plan.id }) ?? true else { throw SaveError.changedSinceReview }
        if let current, !library.revisions.contains(where: { $0.plan == current }) {
            library.revisions.append(RunWorkoutPlanRevision(id: UUID().uuidString, plan: current, savedAt: now))
        }
        let revision = RunWorkoutPlanRevision(id: UUID().uuidString, plan: plan, savedAt: now)
        library.plans.removeAll { $0.id == plan.id }
        library.plans.insert(plan, at: 0)
        library.revisions.append(revision)
        library.receipts.append(Receipt(operationID: operationID, requestedPlan: plan, revisionID: revision.id))
        try persist(library, userID: userID)
        return revision
    }

    public static func validate(_ plan: RunWorkoutPlan) throws {
        guard !plan.id.isEmpty, !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              plan.name.count <= 120, (1...150).contains(plan.steps.count),
              Set(plan.steps.map(\.id)).count == plan.steps.count else {
            throw SaveError.invalidPlan("Add a workout name and 1–150 distinct steps.")
        }
        if let outline = plan.outline {
            guard plan.repeatGroup == nil, try RunWorkoutOutline.expanded(outline) == plan.steps else {
                throw SaveError.invalidPlan("The outline and executable steps disagree. Reopen the builder to review them.")
            }
        }
        if let group = plan.repeatGroup {
            guard !group.id.isEmpty, (1...50).contains(group.repetitions),
                  plan.steps.filter({ $0.kind == .hard || $0.kind == .recovery }) == group.expandedSteps else {
                throw SaveError.invalidPlan("The repeat group and session steps disagree. Reopen the builder to review them.")
            }
        }
        for (index, step) in plan.steps.enumerated() {
            let value: Double
            switch step.goal {
            case .duration(let seconds): value = seconds
            case .distance(let meters): value = meters
            case .open: value = 1 // Validation sentinel only; excluded from planned time/distance.
            }
            guard !step.id.isEmpty, value.isFinite, value > 0, value <= 100_000 else {
                throw SaveError.invalidPlan("Step \(index + 1) needs a positive, supported time or distance.")
            }
            if let target = step.target, target.fastestSecondsPerKm != nil || target.slowestSecondsPerKm != nil {
                guard let fast = target.fastestSecondsPerKm, let slow = target.slowestSecondsPerKm,
                      fast.isFinite, slow.isFinite, fast > 0, slow >= fast, slow <= 3600 else {
                    throw SaveError.invalidPlan("Step \(index + 1): the slowest pace must be at least the fastest pace.")
                }
            }
        }
        guard plan.estimatedDurationSeconds <= 86_400, plan.totalDistanceMeters <= 300_000 else {
            throw SaveError.invalidPlan("This workout exceeds the supported one-day or 300 km limits.")
        }
    }

    // Compatibility entry points preserve existing explicit duplicate-as-new behavior.
    // New editors use saveReviewed to prevent a retry being interpreted as a new copy.
    public func addPlan(_ plan: RunWorkoutPlan) {
        mutateCompatibility { library in
            var unique = plan
            if library.plans.contains(where: { $0.id == plan.id }) {
                unique = RunWorkoutPlan(id: UUID().uuidString, name: plan.name, subtitle: plan.subtitle, steps: plan.steps, repeatGroup: plan.repeatGroup, outline: plan.outline)
            }
            library.plans.insert(unique, at: 0)
        }
    }

    public func updatePlan(_ plan: RunWorkoutPlan) {
        mutateCompatibility { library in
            if let index = library.plans.firstIndex(where: { $0.id == plan.id }) { library.plans[index] = plan } else { library.plans.insert(plan, at: 0) }
        }
    }

    public func deletePlan(id: String) {
        mutateCompatibility { library in
            if let original = library.plans.first(where: { $0.id == id }), !library.revisions.contains(where: { $0.plan == original }) {
                library.revisions.append(RunWorkoutPlanRevision(id: UUID().uuidString, plan: original, savedAt: Date()))
            }
            library.plans.removeAll { $0.id == id }
            library.favoritePlanIDs?.removeAll { $0 == id }
        }
    }

    private func mutateCompatibility(_ mutate: (inout Library) -> Void) {
        synchronizeAccountIfNeeded()
        guard let userID = activeUserID else { return }
        do {
            var library = try readLibrary()
            mutate(&library)
            try persist(library, userID: userID)
        } catch { lastSaveError = error.localizedDescription }
    }

    public func cloudSnapshot(userID: String) throws -> [String: Data] {
        synchronizeAccountIfNeeded()
        guard activeUserID == userID, authService.currentUserID == userID else { throw RunCloudError.accountChanged }
        let library = try readLibrary()
        var values: [String: Data] = [:]
        let favorites = Set(library.favoritePlanIDs ?? [])
        guard favorites.isSubset(of: Set(library.plans.map(\.id))) else { throw SaveError.unreadableLibrary }
        for plan in library.plans {
            let record = RunCloudWorkoutRecord(plan: plan, isFavorite: favorites.contains(plan.id))
            let key = "plan/" + plan.id
            try record.validate(key: key); values[key] = try RunCloudCodec.encode(record)
        }
        for revision in library.revisions { values["revision/" + revision.id] = try RunCloudCodec.encode(revision) }
        for receipt in library.receipts { values["receipt/" + receipt.operationID] = try RunCloudCodec.encode(receipt) }
        return values
    }
    public func applyCloudSnapshot(_ values: [String: Data], expectedFingerprint: String, userID: String) throws {
        let old = try cloudSnapshot(userID: userID)
        guard try PlanFingerprint.make(old) == expectedFingerprint else { throw RunCloudError.changed }
        try RunCloudCodec.preserveImmutable(old: old, new: values)
        if old == values { return }
        var library = try readLibrary(); library.plans = []; library.revisions = []; library.receipts = []
        var favorites: [String] = []
        for (key, data) in values.sorted(by: { $0.key < $1.key }) {
            if key.hasPrefix("plan/") {
                let record = try RunCloudCodec.decode(RunCloudWorkoutRecord.self, data)
                try record.validate(key: key)
                library.plans.append(record.plan)
                if record.isFavorite { favorites.append(record.plan.id) }
            } else if key.hasPrefix("revision/") {
                let revision = try RunCloudCodec.decode(RunWorkoutPlanRevision.self, data)
                guard key == "revision/" + revision.id else { throw RunCloudError.invalid }
                try Self.validate(revision.plan); library.revisions.append(revision)
            } else if key.hasPrefix("receipt/") {
                let receipt = try RunCloudCodec.decode(Receipt.self, data)
                guard key == "receipt/" + receipt.operationID else { throw RunCloudError.invalid }
                library.receipts.append(receipt)
            } else { throw RunCloudError.invalid }
        }
        guard library.receipts.allSatisfy({ receipt in library.revisions.contains { $0.id == receipt.revisionID && $0.plan == receipt.requestedPlan } }),
              Set(favorites).isSubset(of: Set(library.plans.map(\.id))) else { throw RunCloudError.invalid }
        library.favoritePlanIDs = favorites
        try persist(library, userID: userID)
    }

    private func persist(_ library: Library, userID: String) throws {
        guard activeUserID == userID, authService.currentUserID == userID, let storageKey else { throw SaveError.accountChanged }
        let data = try JSONEncoder().encode(library)
        userDefaults.set(data, forKey: storageKey)
        guard userDefaults.data(forKey: storageKey) == data else { throw SaveError.persistenceFailed }
        storedCustomPlans = library.plans
        lastSaveError = nil
        NotificationCenter.default.post(name: .runLibrariesChanged, object: userID)
    }

    private func readLibrary() throws -> Library {
        guard let storageKey else { return Library() }
        let data = userDefaults.data(forKey: storageKey) ?? userDefaults.data(forKey: legacyStorageKey)
        guard let data else { return Library() }
        if let library = try? JSONDecoder().decode(Library.self, from: data), library.schema == 1 { return library }
        if let plans = try? JSONDecoder().decode([RunWorkoutPlan].self, from: data) { return Library(plans: plans) }
        throw SaveError.unreadableLibrary
    }

    private func reload() {
        storedCustomPlans = []
        guard activeUserID != nil else { return }
        do {
            let library = try readLibrary()
            // Keep the original legacy payload until a checked replacement is readable.
            if let storageKey, userDefaults.data(forKey: storageKey) == nil, let legacy = userDefaults.data(forKey: legacyStorageKey) {
                userDefaults.set(legacy, forKey: storageKey)
                if userDefaults.data(forKey: storageKey) == legacy { userDefaults.removeObject(forKey: legacyStorageKey) }
            }
            storedCustomPlans = library.plans
            lastSaveError = nil
        } catch { lastSaveError = error.localizedDescription }
    }

    private var storageKey: String? { AccountScopedStorageKey.make(prefix: legacyStorageKey, userID: activeUserID) }
    private func synchronizeAccountIfNeeded() {
        guard authService.currentUserID != activeUserID else { return }
        activeUserID = authService.currentUserID
        reload()
    }
}

public struct RunWorkoutTarget: Codable, Equatable {
    public var cue: String?
    public var fastestSecondsPerKm: Double?
    public var slowestSecondsPerKm: Double?

    public init(cue: String? = nil, fastestSecondsPerKm: Double? = nil, slowestSecondsPerKm: Double? = nil) {
        self.cue = cue
        self.fastestSecondsPerKm = fastestSecondsPerKm
        self.slowestSecondsPerKm = slowestSecondsPerKm
    }

    public static func paceRange(
        cue: String? = nil,
        fastestSecondsPerUnit: Double,
        slowestSecondsPerUnit: Double,
        metric: Bool
    ) -> RunWorkoutTarget {
        guard fastestSecondsPerUnit.isFinite,
              slowestSecondsPerUnit.isFinite,
              fastestSecondsPerUnit > 0,
              slowestSecondsPerUnit > 0 else {
            return RunWorkoutTarget(cue: cue)
        }

        let unitMultiplier = metric ? 1.0 : RunFormat.metersPerMile / 1000
        let fastest = min(fastestSecondsPerUnit, slowestSecondsPerUnit) / unitMultiplier
        let slowest = max(fastestSecondsPerUnit, slowestSecondsPerUnit) / unitMultiplier
        return RunWorkoutTarget(cue: cue, fastestSecondsPerKm: fastest, slowestSecondsPerKm: slowest)
    }

    public func displayText(metric: Bool) -> String? {
        var parts: [String] = []
        if let paceRange = paceRangeText(metric: metric) {
            parts.append("Target \(paceRange)")
        }
        if let cue = cue?.trimmingCharacters(in: .whitespacesAndNewlines), !cue.isEmpty {
            parts.append(cue)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func paceRangeText(metric: Bool) -> String? {
        guard let fastestSecondsPerKm,
              let slowestSecondsPerKm,
              fastestSecondsPerKm.isFinite,
              slowestSecondsPerKm.isFinite,
              fastestSecondsPerKm > 0,
              slowestSecondsPerKm >= fastestSecondsPerKm else { return nil }

        let unitMultiplier = metric ? 1.0 : RunFormat.metersPerMile / 1000
        guard slowestSecondsPerKm * unitMultiplier <= Double(Int32.max - 1) else { return nil }
        let fastest = Int((fastestSecondsPerKm * unitMultiplier).rounded())
        let slowest = Int((slowestSecondsPerKm * unitMultiplier).rounded())
        return String(
            format: "%d:%02d-%d:%02d %@",
            fastest / 60,
            fastest % 60,
            slowest / 60,
            slowest % 60,
            metric ? "/km" : "/mi"
        )
    }
}

public struct RunWorkoutStep: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable, CaseIterable {
        case warmup
        case hard
        case recovery
        case cooldown

        public var displayName: String {
            switch self {
            case .warmup: return "Warm up"
            case .hard: return "Work"
            case .recovery: return "Recovery"
            case .cooldown: return "Cool down"
            }
        }
    }

    public enum Goal: Codable, Equatable {
        case duration(seconds: Double)
        case distance(meters: Double)
        /// Continues until the runner explicitly advances; has no invented target.
        case open
    }

    public let id: String
    public var kind: Kind
    public var title: String
    public var goal: Goal
    public var target: RunWorkoutTarget?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        goal: Goal,
        target: RunWorkoutTarget? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.goal = goal
        self.target = target
    }

    public func goalText(metric: Bool) -> String {
        switch goal {
        case .duration(let seconds):
            return RunFormat.durationText(seconds: seconds)
        case .distance(let meters):
            return RunFormat.distanceText(meters: meters, metric: metric)
        case .open:
            return "Until you continue"
        }
    }

    public func targetText(metric: Bool) -> String? {
        target?.displayText(metric: metric)
    }
}

public struct RunWorkoutProgress: Equatable {
    public let planName: String
    /// Zero-based index of the current step; equals `stepCount` when the plan is complete.
    public let currentStepIndex: Int
    public let stepCount: Int
    public let currentStep: RunWorkoutStep?
    public let stepElapsedSeconds: Double
    public let stepDistanceMeters: Double
    public let progressFraction: Double
    public let remainingSeconds: Double?
    public let remainingMeters: Double?

    public var isWorkoutComplete: Bool { currentStep == nil }
}

public struct RunWorkoutStepResult: Codable, Identifiable, Equatable {
    public enum CompletionReason: String, Codable { case manuallyCompleted, skipped }
    public var id: String { "\(stepIndex)-\(step.id)-\(Int(startedAtElapsedSeconds.rounded()))" }

    public let stepIndex: Int
    public var step: RunWorkoutStep
    public var startedAtElapsedSeconds: Double
    public var endedAtElapsedSeconds: Double
    public var startedAtDistanceMeters: Double
    public var endedAtDistanceMeters: Double
    public var isComplete: Bool
    public var completionReason: CompletionReason?

    public init(
        stepIndex: Int,
        step: RunWorkoutStep,
        startedAtElapsedSeconds: Double,
        endedAtElapsedSeconds: Double,
        startedAtDistanceMeters: Double,
        endedAtDistanceMeters: Double,
        isComplete: Bool,
        completionReason: CompletionReason? = nil
    ) {
        self.stepIndex = stepIndex
        self.step = step
        self.startedAtElapsedSeconds = startedAtElapsedSeconds
        self.endedAtElapsedSeconds = endedAtElapsedSeconds
        self.startedAtDistanceMeters = startedAtDistanceMeters
        self.endedAtDistanceMeters = endedAtDistanceMeters
        self.isComplete = isComplete
        self.completionReason = completionReason
    }

    public var elapsedSeconds: Double {
        max(0, endedAtElapsedSeconds - startedAtElapsedSeconds)
    }

    public var distanceMeters: Double {
        max(0, endedAtDistanceMeters - startedAtDistanceMeters)
    }

    public var paceSecondsPerKm: Double? {
        guard distanceMeters >= 10, elapsedSeconds > 0 else { return nil }
        return elapsedSeconds / (distanceMeters / 1000)
    }
}

public struct RunWorkoutResult: Codable, Identifiable, Equatable {
    public var id: String { runID }

    public var runID: String
    public var planID: String
    public var planName: String
    public var completedAt: Date
    public var steps: [RunWorkoutStepResult]
    public var goalRevisions: [RunWorkoutGoalRevision]?
    public var planSnapshot: RunWorkoutPlan?

    public init(
        runID: String,
        planID: String,
        planName: String,
        completedAt: Date,
        steps: [RunWorkoutStepResult],
        goalRevisions: [RunWorkoutGoalRevision]? = nil,
        planSnapshot: RunWorkoutPlan? = nil
    ) {
        self.runID = runID
        self.planID = planID
        self.planName = planName
        self.completedAt = completedAt
        self.steps = steps
        self.goalRevisions = goalRevisions
        self.planSnapshot = planSnapshot
    }
}

public final class RunWorkoutResultStore {
    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol
    private let legacyStorageKey = "myfitplate.run_workout_results"
    private static let lock = NSRecursiveLock()
    public private(set) var lastError: String?

    public init(userDefaults: UserDefaults, authService: AuthServiceProtocol) {
        self.userDefaults = userDefaults
        self.authService = authService
    }

    @MainActor public convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, authService: DIContainer.shared.authService)
    }

    public func result(forRunID runID: String) -> RunWorkoutResult? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let userID = authService.currentUserID else { return nil }
        do { return try loadResults(userID: userID)[runID] } catch { lastError = error.localizedDescription; return nil }
    }

    /// Accepted step receipts are immutable. A retry may acknowledge identical data,
    /// never replace a different completed result or a corrupt unreadable library.
    public func saveChecked(_ result: RunWorkoutResult, userID: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard authService.currentUserID == userID, !result.runID.isEmpty, !result.planID.isEmpty,
              result.completedAt.timeIntervalSinceReferenceDate.isFinite else { throw CocoaError(.fileWriteNoPermission) }
        var results = try loadResults(userID: userID)
        if let existing = results[result.runID] {
            guard existing == result else { throw CocoaError(.fileWriteFileExists) }
            return
        }
        results[result.runID] = result
        try saveResults(results, userID: userID)
        lastError = nil
    }

    @discardableResult public func save(_ result: RunWorkoutResult) -> Bool {
        guard let userID = authService.currentUserID else { return false }
        do { try saveChecked(result, userID: userID); return true } catch { lastError = error.localizedDescription; return false }
    }

    @discardableResult public func deleteResult(forRunID runID: String) -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let userID = authService.currentUserID else { return false }
        do {
            var results = try loadResults(userID: userID)
            results.removeValue(forKey: runID)
            try saveResults(results, userID: userID)
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    private func loadResults(userID: String) throws -> [String: RunWorkoutResult] {
        guard authService.currentUserID == userID,
              let key = AccountScopedStorageKey.make(prefix: legacyStorageKey, userID: userID) else { throw CocoaError(.fileReadNoPermission) }
        guard let data = userDefaults.data(forKey: key) ?? userDefaults.data(forKey: legacyStorageKey) else { return [:] }
        let results = try JSONDecoder().decode([String: RunWorkoutResult].self, from: data)
        guard results.allSatisfy({ $0.key == $0.value.runID }) else { throw CocoaError(.coderReadCorrupt) }
        if userDefaults.data(forKey: key) == nil {
            userDefaults.set(data, forKey: key)
            guard userDefaults.data(forKey: key) == data else { throw CocoaError(.fileWriteUnknown) }
            userDefaults.removeObject(forKey: legacyStorageKey)
        }
        return results
    }

    private func saveResults(_ results: [String: RunWorkoutResult], userID: String) throws {
        guard authService.currentUserID == userID,
              let key = AccountScopedStorageKey.make(prefix: legacyStorageKey, userID: userID) else { throw CocoaError(.fileWriteNoPermission) }
        let data = try JSONEncoder().encode(results)
        userDefaults.set(data, forKey: key)
        guard userDefaults.data(forKey: key) == data else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// Stateful guidance tracker layered over RunSession's live elapsed time and distance.
public final class RunWorkoutTracker {
    public struct Snapshot: Codable, Equatable {
        public let plan: RunWorkoutPlan
        public let completedSteps: [RunWorkoutStepResult]
        public let currentStepIndex: Int
        public let stepStartElapsedSeconds: Double
        public let stepStartDistanceMeters: Double
        public let observedElapsedSeconds: Double
        public let observedDistanceMeters: Double
        public var goalRevisions: [RunWorkoutGoalRevision]?
    }

    public let plan: RunWorkoutPlan
    public private(set) var completedSteps: [RunWorkoutStepResult] = []
    public private(set) var goalRevisions: [RunWorkoutGoalRevision] = []

    private var currentStepIndex = 0
    private var stepStartElapsedSeconds: Double = 0
    private var stepStartDistanceMeters: Double = 0
    private var observedElapsedSeconds: Double = 0
    private var observedDistanceMeters: Double = 0

    public init(plan: RunWorkoutPlan) {
        self.plan = plan
    }

    public convenience init?(snapshot: Snapshot) {
        guard Self.valid(snapshot: snapshot) else { return nil }
        self.init(plan: snapshot.plan)
        completedSteps = snapshot.completedSteps
        currentStepIndex = snapshot.currentStepIndex
        stepStartElapsedSeconds = snapshot.stepStartElapsedSeconds
        stepStartDistanceMeters = snapshot.stepStartDistanceMeters
        observedElapsedSeconds = snapshot.observedElapsedSeconds
        observedDistanceMeters = snapshot.observedDistanceMeters
        goalRevisions = snapshot.goalRevisions ?? []
    }

    public func snapshot() -> Snapshot {
        Snapshot(plan: plan, completedSteps: completedSteps, currentStepIndex: currentStepIndex,
                 stepStartElapsedSeconds: stepStartElapsedSeconds, stepStartDistanceMeters: stepStartDistanceMeters,
                 observedElapsedSeconds: observedElapsedSeconds, observedDistanceMeters: observedDistanceMeters,
                 goalRevisions: goalRevisions.isEmpty ? nil : goalRevisions)
    }

    /// Only unfinished one-goal sessions can change. The target must remain beyond
    /// the recorded position; completing a goal and then extending it is a new goal,
    /// not a retroactive rewrite of the achieved boundary.
    @discardableResult
    public func reviseCurrentGoal(expectedStepID: String, expectedGoal: RunWorkoutStep.Goal,
                                  newGoal: RunWorkoutStep.Goal, operationID: String,
                                  elapsedSeconds: Double, distanceMeters: Double) -> Bool {
        if let accepted = goalRevisions.first(where: { $0.id == operationID }) {
            return accepted.stepID == expectedStepID && accepted.previousGoal == expectedGoal && accepted.revisedGoal == newGoal
        }
        guard !operationID.isEmpty, goalRevisions.count < 100, plan.steps.count == 1,
              elapsedSeconds.isFinite, distanceMeters.isFinite,
              elapsedSeconds >= observedElapsedSeconds, distanceMeters >= observedDistanceMeters else { return false }
        _ = advance(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)
        guard currentStepIndex == 0 else { return false }
        let step = effectiveStep(at: 0)
        guard step.id == expectedStepID, step.goal == expectedGoal, newGoal != expectedGoal,
              RunWorkoutGoalRevision.sameKind(expectedGoal, newGoal),
              RunWorkoutGoalRevision.isSupported(newGoal, beyondSeconds: observedElapsedSeconds, beyondMeters: observedDistanceMeters) else { return false }
        goalRevisions.append(RunWorkoutGoalRevision(id: operationID, stepID: step.id, previousGoal: expectedGoal,
            revisedGoal: newGoal, activeSeconds: observedElapsedSeconds, distanceMeters: observedDistanceMeters))
        return true
    }

    private func effectiveStep(at index: Int) -> RunWorkoutStep {
        Self.effectiveStep(plan: plan, index: index, revisions: goalRevisions)
    }

    private static func effectiveStep(plan: RunWorkoutPlan, index: Int, revisions: [RunWorkoutGoalRevision]) -> RunWorkoutStep {
        var step = plan.steps[index]
        if let latest = revisions.last(where: { $0.stepID == step.id }) { step.goal = latest.revisedGoal }
        return step
    }

    @discardableResult
    public func advance(elapsedSeconds: Double, distanceMeters: Double) -> [RunWorkoutStep] {
        guard elapsedSeconds.isFinite, distanceMeters.isFinite,
              elapsedSeconds >= observedElapsedSeconds, elapsedSeconds <= Double(Int32.max - 1),
              distanceMeters >= observedDistanceMeters else { return [] }
        var completed: [RunWorkoutStep] = []
        var cursorElapsed = observedElapsedSeconds
        var cursorDistance = observedDistanceMeters

        while currentStepIndex < plan.steps.count {
            let step = effectiveStep(at: currentStepIndex)
            guard let boundary = boundary(for: step, fromElapsed: cursorElapsed, fromDistance: cursorDistance,
                                          toElapsed: elapsedSeconds, toDistance: distanceMeters) else { break }

            completedSteps.append(stepResult(
                stepIndex: currentStepIndex,
                step: step,
                endedAtElapsedSeconds: boundary.elapsed,
                endedAtDistanceMeters: boundary.distance,
                isComplete: true
            ))
            completed.append(step)
            currentStepIndex += 1
            stepStartElapsedSeconds = boundary.elapsed
            stepStartDistanceMeters = boundary.distance
            cursorElapsed = boundary.elapsed
            cursorDistance = boundary.distance
        }

        observedElapsedSeconds = elapsedSeconds
        observedDistanceMeters = distanceMeters
        return completed
    }

    public func progress(elapsedSeconds: Double, distanceMeters: Double) -> RunWorkoutProgress {
        _ = advance(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)

        guard currentStepIndex < plan.steps.count else {
            return RunWorkoutProgress(
                planName: plan.name,
                currentStepIndex: plan.steps.count,
                stepCount: plan.steps.count,
                currentStep: nil,
                stepElapsedSeconds: 0,
                stepDistanceMeters: 0,
                progressFraction: 1,
                remainingSeconds: nil,
                remainingMeters: nil
            )
        }

        let step = effectiveStep(at: currentStepIndex)
        let stepElapsed = max(0, observedElapsedSeconds - stepStartElapsedSeconds)
        let stepDistance = max(0, observedDistanceMeters - stepStartDistanceMeters)

        switch step.goal {
        case .duration(let seconds):
            let target = seconds.isFinite ? max(0, seconds) : 0
            return RunWorkoutProgress(
                planName: plan.name,
                currentStepIndex: currentStepIndex,
                stepCount: plan.steps.count,
                currentStep: step,
                stepElapsedSeconds: stepElapsed,
                stepDistanceMeters: stepDistance,
                progressFraction: seconds.isFinite ? Self.fraction(stepElapsed, target) : 0,
                remainingSeconds: seconds.isFinite ? max(0, target - stepElapsed) : nil,
                remainingMeters: nil
            )
        case .distance(let meters):
            let target = meters.isFinite ? max(0, meters) : 0
            return RunWorkoutProgress(
                planName: plan.name,
                currentStepIndex: currentStepIndex,
                stepCount: plan.steps.count,
                currentStep: step,
                stepElapsedSeconds: stepElapsed,
                stepDistanceMeters: stepDistance,
                progressFraction: meters.isFinite ? Self.fraction(stepDistance, target) : 0,
                remainingSeconds: nil,
                remainingMeters: meters.isFinite ? max(0, target - stepDistance) : nil
            )
        case .open:
            return RunWorkoutProgress(planName: plan.name, currentStepIndex: currentStepIndex, stepCount: plan.steps.count,
                currentStep: step, stepElapsedSeconds: stepElapsed, stepDistanceMeters: stepDistance,
                progressFraction: 0, remainingSeconds: nil, remainingMeters: nil)
        }
    }

    /// Exact expected step identity prevents a late tap from skipping a step that
    /// just advanced automatically. A manual open goal completes; a timed/distance
    /// skip stays explicitly incomplete in its immutable result and recovery snapshot.
    @discardableResult
    public func advanceManually(expectedStepID: String, elapsedSeconds: Double, distanceMeters: Double) -> Bool {
        guard elapsedSeconds.isFinite, distanceMeters.isFinite,
              elapsedSeconds >= observedElapsedSeconds, distanceMeters >= observedDistanceMeters else { return false }
        _ = advance(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)
        guard currentStepIndex < plan.steps.count, plan.steps[currentStepIndex].id == expectedStepID else { return false }
        let step = effectiveStep(at: currentStepIndex)
        let open = step.goal == .open
        var receipt = stepResult(stepIndex: currentStepIndex, step: step, endedAtElapsedSeconds: observedElapsedSeconds,
            endedAtDistanceMeters: observedDistanceMeters, isComplete: open)
        receipt.completionReason = open ? .manuallyCompleted : .skipped
        completedSteps.append(receipt)
        currentStepIndex += 1
        stepStartElapsedSeconds = observedElapsedSeconds
        stepStartDistanceMeters = observedDistanceMeters
        return true
    }

    public func result(
        runID: String,
        completedAt: Date = Date(),
        elapsedSeconds: Double,
        distanceMeters: Double
    ) -> RunWorkoutResult? {
        _ = advance(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)

        var stepResults = completedSteps
        if currentStepIndex < plan.steps.count {
            let step = effectiveStep(at: currentStepIndex)
            let stepElapsed = max(0, observedElapsedSeconds - stepStartElapsedSeconds)
            let stepDistance = max(0, observedDistanceMeters - stepStartDistanceMeters)
            if stepElapsed > 0 || stepDistance > 0 {
                stepResults.append(stepResult(
                    stepIndex: currentStepIndex,
                    step: step,
                    endedAtElapsedSeconds: observedElapsedSeconds,
                    endedAtDistanceMeters: observedDistanceMeters,
                    isComplete: false
                ))
            }
        }

        guard !stepResults.isEmpty else { return nil }
        return RunWorkoutResult(
            runID: runID,
            planID: plan.id,
            planName: plan.name,
            completedAt: completedAt,
            steps: stepResults,
            goalRevisions: goalRevisions.isEmpty ? nil : goalRevisions,
            planSnapshot: plan
        )
    }

    /// Interpolate the crossed boundary within this observation, then carry the
    /// remainder into subsequent steps. Delayed callbacks must not extend intervals.
    private func boundary(for step: RunWorkoutStep, fromElapsed: Double, fromDistance: Double,
                          toElapsed: Double, toDistance: Double) -> (elapsed: Double, distance: Double)? {
        switch step.goal {
        case .duration(let seconds):
            guard seconds.isFinite else { return nil }
            let elapsed = stepStartElapsedSeconds + max(0, seconds)
            guard elapsed.isFinite, toElapsed >= elapsed else { return nil }
            let fraction = toElapsed > fromElapsed ? Self.fraction(elapsed - fromElapsed, toElapsed - fromElapsed) : 0
            return (elapsed, fromDistance + (toDistance - fromDistance) * fraction)
        case .distance(let meters):
            guard meters.isFinite else { return nil }
            let distance = stepStartDistanceMeters + max(0, meters)
            guard distance.isFinite, toDistance >= distance else { return nil }
            let fraction = toDistance > fromDistance ? Self.fraction(distance - fromDistance, toDistance - fromDistance) : 0
            return (fromElapsed + (toElapsed - fromElapsed) * fraction, distance)
        case .open:
            return nil
        }
    }

    private static func valid(snapshot: Snapshot) -> Bool {
        guard snapshot.plan.steps.count <= 10_000,
              (0...snapshot.plan.steps.count).contains(snapshot.currentStepIndex),
              snapshot.completedSteps.count == snapshot.currentStepIndex,
              [snapshot.stepStartElapsedSeconds, snapshot.stepStartDistanceMeters,
               snapshot.observedElapsedSeconds, snapshot.observedDistanceMeters].allSatisfy({ $0.isFinite && $0 >= 0 }),
              snapshot.observedElapsedSeconds <= Double(Int32.max - 1),
              snapshot.stepStartElapsedSeconds <= snapshot.observedElapsedSeconds,
              snapshot.stepStartDistanceMeters <= snapshot.observedDistanceMeters else { return false }
        let revisions = snapshot.goalRevisions ?? []
        guard revisions.count <= 100, Set(revisions.map(\.id)).count == revisions.count else { return false }
        if !revisions.isEmpty {
            guard snapshot.plan.steps.count == 1 else { return false }
            var goal = snapshot.plan.steps[0].goal
            var previousRevisionTime = 0.0
            var previousRevisionDistance = 0.0
            for revision in revisions {
                guard !revision.id.isEmpty, revision.stepID == snapshot.plan.steps[0].id, revision.previousGoal == goal,
                      RunWorkoutGoalRevision.sameKind(goal, revision.revisedGoal), revision.revisedGoal != goal,
                      revision.activeSeconds.isFinite, revision.distanceMeters.isFinite,
                      revision.activeSeconds >= previousRevisionTime, revision.distanceMeters >= previousRevisionDistance,
                      revision.activeSeconds <= snapshot.observedElapsedSeconds, revision.distanceMeters <= snapshot.observedDistanceMeters,
                      RunWorkoutGoalRevision.isSupported(goal, beyondSeconds: revision.activeSeconds, beyondMeters: revision.distanceMeters),
                      RunWorkoutGoalRevision.isSupported(revision.revisedGoal, beyondSeconds: revision.activeSeconds, beyondMeters: revision.distanceMeters) else { return false }
                goal = revision.revisedGoal
                previousRevisionTime = revision.activeSeconds
                previousRevisionDistance = revision.distanceMeters
            }
        }
        var previousElapsed = 0.0
        var previousDistance = 0.0
        for (index, result) in snapshot.completedSteps.enumerated() {
            guard result.stepIndex == index, result.step == effectiveStep(plan: snapshot.plan, index: index, revisions: revisions),
                  result.isComplete || result.completionReason == .skipped,
                  result.completionReason != .manuallyCompleted || (result.step.goal == .open && result.isComplete),
                  result.completionReason != .skipped || !result.isComplete,
                  result.startedAtElapsedSeconds == previousElapsed, result.startedAtDistanceMeters == previousDistance,
                  result.endedAtElapsedSeconds.isFinite, result.endedAtDistanceMeters.isFinite,
                  result.endedAtElapsedSeconds >= previousElapsed, result.endedAtDistanceMeters >= previousDistance,
                  result.endedAtElapsedSeconds <= snapshot.observedElapsedSeconds,
                  result.endedAtDistanceMeters <= snapshot.observedDistanceMeters else { return false }
            previousElapsed = result.endedAtElapsedSeconds
            previousDistance = result.endedAtDistanceMeters
        }
        return snapshot.stepStartElapsedSeconds == previousElapsed && snapshot.stepStartDistanceMeters == previousDistance
    }

    private static func fraction(_ value: Double, _ target: Double) -> Double {
        guard target > 0 else { return 1 }
        return min(1, max(0, value / target))
    }

    private func stepResult(
        stepIndex: Int,
        step: RunWorkoutStep,
        endedAtElapsedSeconds: Double,
        endedAtDistanceMeters: Double,
        isComplete: Bool
    ) -> RunWorkoutStepResult {
        RunWorkoutStepResult(
            stepIndex: stepIndex,
            step: step,
            startedAtElapsedSeconds: stepStartElapsedSeconds,
            endedAtElapsedSeconds: endedAtElapsedSeconds,
            startedAtDistanceMeters: stepStartDistanceMeters,
            endedAtDistanceMeters: endedAtDistanceMeters,
            isComplete: isComplete
        )
    }
}

/// A typed repeated pair. Execution keeps using the bounded expanded steps so an old
/// active recording never changes when the editable group changes in the library.
public struct RunWorkoutRepeatGroup: Codable, Equatable, Identifiable {
    public let id: String
    public var repetitions: Int
    public var workGoal: RunWorkoutStep.Goal
    public var recoveryGoal: RunWorkoutStep.Goal
    public var includeFinalRecovery: Bool
    public var workTarget: RunWorkoutTarget?

    public init(id: String = UUID().uuidString, repetitions: Int, workGoal: RunWorkoutStep.Goal,
                recoveryGoal: RunWorkoutStep.Goal, includeFinalRecovery: Bool = false, workTarget: RunWorkoutTarget? = nil) {
        self.id = id
        self.repetitions = repetitions
        self.workGoal = workGoal
        self.recoveryGoal = recoveryGoal
        self.includeFinalRecovery = includeFinalRecovery
        self.workTarget = workTarget
    }

    public var expandedSteps: [RunWorkoutStep] {
        var steps: [RunWorkoutStep] = []
        for repetition in 1...max(1, min(50, repetitions)) {
            steps.append(RunWorkoutStep(id: "\(id).work.\(repetition)", kind: .hard, title: "Work \(repetition)", goal: workGoal, target: workTarget))
            let recoveryValue: Double
            switch recoveryGoal {
            case .duration(let seconds): recoveryValue = seconds
            case .distance(let meters): recoveryValue = meters
            case .open: recoveryValue = 1
            }
            if recoveryValue > 0, repetition < repetitions || includeFinalRecovery {
                steps.append(RunWorkoutStep(id: "\(id).recovery.\(repetition)", kind: .recovery, title: "Recover", goal: recoveryGoal,
                    target: RunWorkoutTarget(cue: "Easy jog or walk")))
            }
        }
        return steps
    }
}

public extension RunWorkoutPlan {
    static func repeated(id: String = UUID().uuidString, name: String, warmupSeconds: Double,
                         group: RunWorkoutRepeatGroup, cooldownSeconds: Double) -> RunWorkoutPlan {
        var steps: [RunWorkoutStep] = []
        if warmupSeconds > 0 {
            steps.append(RunWorkoutStep(id: "\(id).warmup", kind: .warmup, title: "Warm up", goal: .duration(seconds: warmupSeconds)))
        }
        steps += group.expandedSteps
        if cooldownSeconds > 0 {
            steps.append(RunWorkoutStep(id: "\(id).cooldown", kind: .cooldown, title: "Cool down", goal: .duration(seconds: cooldownSeconds)))
        }
        return RunWorkoutPlan(id: id, name: name, subtitle: "\(group.repetitions) repeats", steps: steps, repeatGroup: group)
    }
}
