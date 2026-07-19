import Foundation

/// A structured running workout the live recorder can guide step by step.
public struct RunWorkoutPlan: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var subtitle: String
    public var steps: [RunWorkoutStep]

    public init(id: String = UUID().uuidString, name: String, subtitle: String, steps: [RunWorkoutStep]) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.steps = steps
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
            case .distance:
                return total
            }
        }
    }

    public var totalDistanceMeters: Double {
        steps.reduce(0) { total, step in
            switch step.goal {
            case .distance(let meters):
                return total + max(0, meters)
            case .duration:
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

public final class RunWorkoutPlanStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol
    private let legacyStorageKey = "myfitplate.run_workout_plans"
    private var activeUserID: String?
    private var isRestoring = false

    @Published private var storedCustomPlans: [RunWorkoutPlan] = [] {
        didSet {
            if !isRestoring { saveToDefaults() }
        }
    }

    public var customPlans: [RunWorkoutPlan] {
        synchronizeAccountIfNeeded()
        return storedCustomPlans
    }

    public init(userDefaults: UserDefaults, authService: AuthServiceProtocol) {
        self.userDefaults = userDefaults
        self.authService = authService
        activeUserID = authService.currentUserID
        loadFromDefaults()
    }

    @MainActor
    public convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, authService: DIContainer.shared.authService)
    }

    public func addPlan(_ plan: RunWorkoutPlan) {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil else { return }
        var uniquePlan = plan
        if storedCustomPlans.contains(where: { $0.id == uniquePlan.id }) {
            uniquePlan = RunWorkoutPlan(
                id: UUID().uuidString,
                name: plan.name,
                subtitle: plan.subtitle,
                steps: plan.steps
            )
        }
        storedCustomPlans.insert(uniquePlan, at: 0)
    }

    public func updatePlan(_ plan: RunWorkoutPlan) {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil else { return }
        guard let index = storedCustomPlans.firstIndex(where: { $0.id == plan.id }) else {
            addPlan(plan)
            return
        }
        storedCustomPlans[index] = plan
    }

    public func deletePlan(id: String) {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil else { return }
        storedCustomPlans.removeAll { $0.id == id }
    }

    private func loadFromDefaults() {
        isRestoring = true
        defer { isRestoring = false }
        storedCustomPlans = []
        guard let storageKey else { return }
        migrateLegacyStorageIfNeeded(to: storageKey)
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RunWorkoutPlan].self, from: data) else { return }
        storedCustomPlans = decoded
    }

    private func saveToDefaults() {
        guard let storageKey,
              let data = try? JSONEncoder().encode(storedCustomPlans) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private var storageKey: String? {
        AccountScopedStorageKey.make(
            prefix: legacyStorageKey,
            userID: activeUserID
        )
    }

    private func synchronizeAccountIfNeeded() {
        let currentUserID = authService.currentUserID
        guard currentUserID != activeUserID else { return }
        activeUserID = currentUserID
        loadFromDefaults()
    }

    private func migrateLegacyStorageIfNeeded(to storageKey: String) {
        if userDefaults.data(forKey: storageKey) == nil,
           let legacyData = userDefaults.data(forKey: legacyStorageKey) {
            userDefaults.set(legacyData, forKey: storageKey)
        }
        userDefaults.removeObject(forKey: legacyStorageKey)
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
    public var id: String { "\(stepIndex)-\(step.id)-\(Int(startedAtElapsedSeconds.rounded()))" }

    public let stepIndex: Int
    public var step: RunWorkoutStep
    public var startedAtElapsedSeconds: Double
    public var endedAtElapsedSeconds: Double
    public var startedAtDistanceMeters: Double
    public var endedAtDistanceMeters: Double
    public var isComplete: Bool

    public init(
        stepIndex: Int,
        step: RunWorkoutStep,
        startedAtElapsedSeconds: Double,
        endedAtElapsedSeconds: Double,
        startedAtDistanceMeters: Double,
        endedAtDistanceMeters: Double,
        isComplete: Bool
    ) {
        self.stepIndex = stepIndex
        self.step = step
        self.startedAtElapsedSeconds = startedAtElapsedSeconds
        self.endedAtElapsedSeconds = endedAtElapsedSeconds
        self.startedAtDistanceMeters = startedAtDistanceMeters
        self.endedAtDistanceMeters = endedAtDistanceMeters
        self.isComplete = isComplete
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

    public init(
        runID: String,
        planID: String,
        planName: String,
        completedAt: Date,
        steps: [RunWorkoutStepResult]
    ) {
        self.runID = runID
        self.planID = planID
        self.planName = planName
        self.completedAt = completedAt
        self.steps = steps
    }
}

public final class RunWorkoutResultStore {
    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol
    private let legacyStorageKey = "myfitplate.run_workout_results"
    private let lock = NSLock()

    public init(userDefaults: UserDefaults, authService: AuthServiceProtocol) {
        self.userDefaults = userDefaults
        self.authService = authService
    }

    @MainActor
    public convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, authService: DIContainer.shared.authService)
    }

    public func result(forRunID runID: String) -> RunWorkoutResult? {
        lock.lock()
        defer { lock.unlock() }
        return loadResults()[runID]
    }

    public func save(_ result: RunWorkoutResult) {
        lock.lock()
        defer { lock.unlock() }
        guard storageKey != nil else { return }
        var results = loadResults()
        results[result.runID] = result
        saveResults(results)
    }

    public func deleteResult(forRunID runID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard storageKey != nil else { return }
        var results = loadResults()
        results.removeValue(forKey: runID)
        saveResults(results)
    }

    private func loadResults() -> [String: RunWorkoutResult] {
        guard let storageKey else { return [:] }
        migrateLegacyStorageIfNeeded(to: storageKey)
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: RunWorkoutResult].self, from: data) else { return [:] }
        return decoded
    }

    private func saveResults(_ results: [String: RunWorkoutResult]) {
        guard let storageKey,
              let data = try? JSONEncoder().encode(results) else { return }
        if results.isEmpty {
            userDefaults.removeObject(forKey: storageKey)
        } else {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    private var storageKey: String? {
        AccountScopedStorageKey.make(
            prefix: legacyStorageKey,
            userID: authService.currentUserID
        )
    }

    private func migrateLegacyStorageIfNeeded(to storageKey: String) {
        if userDefaults.data(forKey: storageKey) == nil,
           let legacyData = userDefaults.data(forKey: legacyStorageKey) {
            userDefaults.set(legacyData, forKey: storageKey)
        }
        userDefaults.removeObject(forKey: legacyStorageKey)
    }
}

/// Stateful guidance tracker layered over RunSession's live elapsed time and distance.
public final class RunWorkoutTracker {
    public let plan: RunWorkoutPlan
    public private(set) var completedSteps: [RunWorkoutStepResult] = []

    private var currentStepIndex = 0
    private var stepStartElapsedSeconds: Double = 0
    private var stepStartDistanceMeters: Double = 0

    public init(plan: RunWorkoutPlan) {
        self.plan = plan
    }

    @discardableResult
    public func advance(elapsedSeconds: Double, distanceMeters: Double) -> [RunWorkoutStep] {
        var completed: [RunWorkoutStep] = []

        while currentStepIndex < plan.steps.count {
            let step = plan.steps[currentStepIndex]
            let stepElapsed = max(0, elapsedSeconds - stepStartElapsedSeconds)
            let stepDistance = max(0, distanceMeters - stepStartDistanceMeters)

            guard Self.isComplete(step: step, elapsedSeconds: stepElapsed, distanceMeters: stepDistance) else {
                break
            }

            completedSteps.append(stepResult(
                stepIndex: currentStepIndex,
                step: step,
                endedAtElapsedSeconds: elapsedSeconds,
                endedAtDistanceMeters: distanceMeters,
                isComplete: true
            ))
            completed.append(step)
            currentStepIndex += 1
            stepStartElapsedSeconds = elapsedSeconds
            stepStartDistanceMeters = distanceMeters
        }

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

        let step = plan.steps[currentStepIndex]
        let stepElapsed = max(0, elapsedSeconds - stepStartElapsedSeconds)
        let stepDistance = max(0, distanceMeters - stepStartDistanceMeters)

        switch step.goal {
        case .duration(let seconds):
            let target = max(0, seconds)
            return RunWorkoutProgress(
                planName: plan.name,
                currentStepIndex: currentStepIndex,
                stepCount: plan.steps.count,
                currentStep: step,
                stepElapsedSeconds: stepElapsed,
                stepDistanceMeters: stepDistance,
                progressFraction: Self.fraction(stepElapsed, target),
                remainingSeconds: max(0, target - stepElapsed),
                remainingMeters: nil
            )
        case .distance(let meters):
            let target = max(0, meters)
            return RunWorkoutProgress(
                planName: plan.name,
                currentStepIndex: currentStepIndex,
                stepCount: plan.steps.count,
                currentStep: step,
                stepElapsedSeconds: stepElapsed,
                stepDistanceMeters: stepDistance,
                progressFraction: Self.fraction(stepDistance, target),
                remainingSeconds: nil,
                remainingMeters: max(0, target - stepDistance)
            )
        }
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
            let step = plan.steps[currentStepIndex]
            let stepElapsed = max(0, elapsedSeconds - stepStartElapsedSeconds)
            let stepDistance = max(0, distanceMeters - stepStartDistanceMeters)
            if stepElapsed > 0 || stepDistance > 0 {
                stepResults.append(stepResult(
                    stepIndex: currentStepIndex,
                    step: step,
                    endedAtElapsedSeconds: elapsedSeconds,
                    endedAtDistanceMeters: distanceMeters,
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
            steps: stepResults
        )
    }

    private static func isComplete(step: RunWorkoutStep, elapsedSeconds: Double, distanceMeters: Double) -> Bool {
        switch step.goal {
        case .duration(let seconds):
            return elapsedSeconds >= max(0, seconds)
        case .distance(let meters):
            return distanceMeters >= max(0, meters)
        }
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
