import Foundation
import Combine


@MainActor
public class AchievementService: ObservableObject {
    @Published public var achievementDefinitions: [AchievementDefinition] = []
    @Published public var userStatuses: [String: UserAchievementStatus] = [:]
    @Published public var unlockedAchievementsCount: Int = 0
    @Published public var isLoading: Bool = false
    
    @Published public var userTotalAchievementPoints: Int = 0
    @Published public var userAchievementLevel: Int = 1
    @Published public var userXp: Int = 0
    @Published public var activeChallenges: [Challenge] = []
    @Published public var achievementSyncNotice: String?
    @Published public var pendingAwardCount = 0
    @Published public private(set) var legacyBalanceReceipt: LegacyAchievementBalanceReceipt?
    @Published public private(set) var legacyBalanceNotice: String?
    @Published public private(set) var hasConfirmedPointBalance = false
    private var legacyBalanceTask: Task<Void, Never>?
    private let awardStore: AchievementAwardStore
    private var awardDrainTask: Task<Void, Never>?
    private var accountGeneration = UUID()

    private var userStatusCancellable: AnyCancellable?
    private var userProfileCancellable: AnyCancellable?
    private var challengesCancellable: AnyCancellable?
    private var authCancellable: Any?
    private var currentUserID: String?
    private weak var dailyLogService: DailyLogService?
    private weak var goalSettings: GoalSettings?
    private weak var bannerService: BannerService?
    
    public let levelThresholds: [Int] = AchievementRules.defaultLevelThresholds

    public init(awardStore: AchievementAwardStore? = nil) {
        self.awardStore = awardStore ?? AchievementAwardStore()
        loadAchievementDefinitions()
        setupAuthListener()
    }

    deinit {
        userStatusCancellable?.cancel()
        userProfileCancellable?.cancel()
        challengesCancellable?.cancel()
    }

    public func setupDependencies(dailyLogService: DailyLogService, goalSettings: GoalSettings, bannerService: BannerService) {
        self.dailyLogService = dailyLogService
        self.goalSettings = goalSettings
        self.bannerService = bannerService
        dailyLogService.achievementService = self
        if let userID = self.currentUserID {
            self.fetchUserStatuses(userID: userID)
            self.listenToUserProfile(userID: userID)
            self.listenToActiveChallenges(for: userID)
            self.generateWeeklyChallenges(for: userID)
        }
    }

    public func activateAccount(_ userID: String?) {
        guard currentUserID != userID else { return }

        userStatusCancellable?.cancel()
        userProfileCancellable?.cancel()
        challengesCancellable?.cancel()
        currentUserID = userID
        isLoading = false
        userStatuses = [:]
        unlockedAchievementsCount = 0
        userTotalAchievementPoints = 0
        userAchievementLevel = 1
        userXp = 0
        activeChallenges = []
        awardDrainTask?.cancel(); awardDrainTask = nil; accountGeneration = UUID()
        achievementSyncNotice = nil; pendingAwardCount = 0
        legacyBalanceTask?.cancel(); legacyBalanceTask = nil
        legacyBalanceReceipt = nil; legacyBalanceNotice = nil; hasConfirmedPointBalance = false
        if userID != nil { retryPendingAwards() }

        if let userID,
           dailyLogService != nil,
           goalSettings != nil,
           bannerService != nil {
            fetchUserStatuses(userID: userID)
            listenToUserProfile(userID: userID)
            listenToActiveChallenges(for: userID)
            generateWeeklyChallenges(for: userID)
        }
    }
    
    private func setupAuthListener() {
        authCancellable = DIContainer.shared.authService.observeAuthState { [weak self] uid in
            Task { @MainActor in
                guard let self = self else { return }
                self.activateAccount(uid)
            }
        }
    }

    private func loadAchievementDefinitions() {
        achievementDefinitions = AchievementRules.defaultDefinitions()
    }

    public func listenToUserProfile(userID: String) {
        guard currentUserID == userID else { return }
        userProfileCancellable?.cancel()
        userProfileCancellable = DIContainer.shared.achievementRepository.userProfilePublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let self, self.currentUserID == userID else { return }
                if let profile = profile {
                    self.userTotalAchievementPoints = profile.points
                    self.userAchievementLevel = profile.level
                    self.hasConfirmedPointBalance = true
                    self.retryLegacyBalanceReceipt()
                } else if !self.hasConfirmedPointBalance {
                    self.legacyBalanceNotice = "The point balance has not been confirmed. Existing points are not reset."
                }
            }
    }

    public func retryLegacyBalanceReceipt() {
        guard let owner = currentUserID, legacyBalanceTask == nil, legacyBalanceReceipt == nil else { return }
        let generation = accountGeneration
        legacyBalanceTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.accountGeneration == generation { self.legacyBalanceTask = nil } }
            do {
                let receipt = try await DIContainer.shared.achievementRepository.preserveLegacyPointBalance(userID: owner)
                guard self.currentUserID == owner, self.accountGeneration == generation else { return }
                try receipt.validate(ownerID: owner)
                self.legacyBalanceReceipt = receipt; self.legacyBalanceNotice = nil
            } catch {
                guard self.currentUserID == owner, self.accountGeneration == generation else { return }
                self.legacyBalanceNotice = "The opening-balance receipt could not be confirmed. Your point balance is unchanged. Retry when connected."
            }
        }
    }

    public func fetchUserStatuses(userID: String) {
        guard !userID.isEmpty, self.currentUserID == userID else { return }
        isLoading = true
        userStatusCancellable?.cancel()
        userStatusCancellable = DIContainer.shared.achievementRepository.userStatusesPublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self, self.currentUserID == userID else { return }
                self.isLoading = false
                if case .failure = completion { self.achievementSyncNotice = "Milestone history could not be read. Existing awards are kept." }
            }, receiveValue: { [weak self] statuses in
                guard let self, self.currentUserID == userID else { return }
                self.isLoading = false
                
                if statuses.isEmpty {
                    self.userStatuses.merge(self.createDefaultStatuses()) { existing, fallback in existing.isUnlocked ? existing : fallback }
                    self.unlockedAchievementsCount = self.userStatuses.values.filter(\.isUnlocked).count
                    return
                }
                
                let newStatuses = AchievementRules.mergedStatuses(
                    definitions: self.achievementDefinitions,
                    fetchedStatuses: statuses
                )
                self.userStatuses.merge(newStatuses) { existing, refreshed in existing.isUnlocked && !refreshed.isUnlocked ? existing : refreshed }
                self.unlockedAchievementsCount = self.userStatuses.values.filter { $0.isUnlocked }.count
            })
    }
    
    private func createDefaultStatuses() -> [String: UserAchievementStatus] {
        AchievementRules.mergedStatuses(definitions: achievementDefinitions, fetchedStatuses: [])
    }
    
    private func updateStatusInFirestore(userID: String, status: UserAchievementStatus) {
        guard !userID.isEmpty, self.currentUserID == userID else { return }
        Task {
            do {
                try await DIContainer.shared.achievementRepository.saveUserStatus(userID: userID, status: status)
            } catch {
                AppLog.app.error("Failed to save achievement status \(status.achievementID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func awardPointsAndCheckLevel(userID: String, points: Int) {
        guard currentUserID == userID else { return }
        Task {
            do {
                let result = try await DIContainer.shared.achievementRepository.awardPointsAndCheckLevel(userID: userID, points: points, levelThresholds: self.levelThresholds)
                await MainActor.run {
                    guard self.currentUserID == userID else { return }
                    self.userTotalAchievementPoints = result.newPoints
                    self.userAchievementLevel = result.newLevel
                }
            } catch {
                AppLog.app.error("Failed to award points: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func calculateLevel(for points: Int) -> Int {
        AchievementRules.level(for: points, thresholds: levelThresholds)
    }

    public func checkAchievementsOnLogUpdate(userID: String, logDate: Date, dayKey: String? = nil) {
        guard currentUserID == userID, let goals = goalSettings, let logService = dailyLogService,
              let day = DiaryDayContext(userID: userID, date: logDate, dayKey: dayKey) else { return }
        logService.fetchLogInternal(for: userID, day: day) { [weak self] result in
            Task { @MainActor in
                guard let self, self.currentUserID == userID, case .success(let log) = result else { return }
                if let food = log.meals.flatMap(\.foodItems).first(where: Self.eligibleFood) {
                    self.checkAcceptedFood(userID: userID, food: food, date: log.date, source: "diary", dayKey: log.id)
                }
                self.checkDailyGoalsAchieved(userID: userID, dailyLog: log, goals: goals)
                self.checkLoggingStreakAchievement(userID: userID, ending: LoggingHabitRules.civilDate(for: log) ?? log.date)
            }
        }
    }

    public func checkAcceptedFood(userID: String, food: FoodItem, date: Date, source: String, dayKey: String? = nil) {
        guard currentUserID == userID, Self.eligibleFood(food), let dayKey = dayKey ?? DiaryDayContext.dayKey(for: date),
              let fingerprint = try? PlanFingerprint.make(food) else { return }
        let evidence = AchievementAwardEvidence(kind: "food_entry", sourceID: dayKey, sourceFingerprint: fingerprint,
            recordedAt: food.timestamp ?? date, explanation: "Accepted food: \(food.name)", facts: ["foodID": food.id])
        unlockAchievement(userID: userID, achievementID: "first_log", evidence: evidence)
        let feature: String?
        switch source.lowercased() {
        case "barcode", "barcode_scan", "barcode_scanner": feature = "scanner_pro"
        case "image", "image_scan", "image_recognition", "photo", "meal_photo", "camera", "ai_image": feature = "picture_perfect"
        case "ai_chat", "ai_recipe", "ai_chatbot", "maia_action_meal", "ai_suggestion": feature = "ai_chef"
        default:
            switch food.sourceMetadata?.sourceType {
            case .aiImage: feature = "picture_perfect"
            case .aiChat: feature = "ai_chef"
            default: feature = nil
            }
        }
        if let feature {
            unlockAchievement(userID: userID, achievementID: feature, evidence: AchievementAwardEvidence(kind: "food_entry",
                sourceID: dayKey, sourceFingerprint: fingerprint, recordedAt: food.timestamp ?? date,
                explanation: "Accepted \(source) food: \(food.name)", facts: ["foodID": food.id, "featureAchievement": feature, "source": source]))
        }
    }

    /// Legacy callers without an accepted source identity cannot prove a milestone.
    public func checkFeatureUsedAchievement(userID: String, featureType: AchievementCriteriaType) { }

    public func checkAchievementsOnWeightUpdate(userID: String) {
        guard currentUserID == userID else { return }
        Task { @MainActor in
            do {
                let weights = try await DIContainer.shared.settingsRepository.fetchWeightHistoryForReview(userID: userID)
                    .filter { !$0.id.isEmpty && $0.weight.isFinite && $0.weight > 0 && $0.date <= Date() }
                    .sorted { $0.date < $1.date }
                guard self.currentUserID == userID, let first = weights.first, let latest = weights.last else { return }
                let facts = ["weight": String(latest.weight), "initialWeight": String(first.weight), "initialID": first.id,
                             "targetWeight": self.goalSettings?.targetWeight.map { String($0) } ?? ""]
                let fingerprint = try PlanFingerprint.make(facts)
                self.unlockAchievement(userID: userID, achievementID: "on_the_weigh", evidence: AchievementAwardEvidence(kind: "weight_entry",
                    sourceID: latest.id, sourceFingerprint: fingerprint, recordedAt: latest.date,
                    explanation: "A saved weight measurement", facts: facts))
                let change = abs(latest.weight - first.weight)
                self.updateProgress(userID: userID, achievementID: "first_5_lbs", progress: change)
                let evidence = AchievementAwardEvidence(kind: "weight_change", sourceID: latest.id, sourceFingerprint: fingerprint,
                    recordedAt: latest.date, explanation: "Saved measurements from \(first.date.formatted(date: .abbreviated, time: .omitted)) to \(latest.date.formatted(date: .abbreviated, time: .omitted))", facts: facts)
                if first.id != latest.id, change >= 5 { self.unlockAchievement(userID: userID, achievementID: "first_5_lbs", evidence: evidence) }
                if let target = self.goalSettings?.targetWeight, target.isFinite, target > 0,
                   AchievementRules.hasReachedTargetWeight(currentWeight: latest.weight, targetWeight: target) {
                    self.unlockAchievement(userID: userID, achievementID: "target_reached", evidence: evidence)
                }
            } catch { self.reportEvidenceFailure(userID: userID) }
        }
    }

    public func checkAchievementsOnGoalSet(userID: String) {
        guard currentUserID == userID else { return }
        Task { @MainActor in
            do {
                guard let saved = try await DIContainer.shared.settingsRepository.accountProfile(userID: userID), self.currentUserID == userID else { return }
                let values = ["calories", "protein", "carbs", "fats"].compactMap { key -> (String, Double)? in
                    guard let value = saved[key] as? Double, value.isFinite, value > 0 else { return nil }; return (key, value)
                }
                guard values.count == 4 else { return }
                let targets = Dictionary(uniqueKeysWithValues: values)
                self.unlockAchievement(userID: userID, achievementID: "goal_setter", evidence: AchievementAwardEvidence(kind: "saved_goals",
                    sourceID: userID, sourceFingerprint: try PlanFingerprint.make(targets), recordedAt: Date(),
                    explanation: "Saved calorie and macro targets", facts: targets.mapValues { String($0) }))
            } catch { self.reportEvidenceFailure(userID: userID) }
        }
    }

    private static func eligibleFood(_ food: FoodItem) -> Bool {
        !food.id.isEmpty && !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && food.calories.isFinite && food.calories >= 0 && food.servingWeight.isFinite && food.servingWeight > 0
    }

    private func checkDailyGoalsAchieved(userID: String, dailyLog: DailyLog, goals: GoalSettings) {
        guard let dayKey = dailyLog.id ?? DiaryDayContext.dayKey(for: dailyLog.date) else { return }
        let hasFood = dailyLog.meals.flatMap(\.foodItems).contains(where: Self.eligibleFood)
        let evaluation = AchievementRules.evaluateDailyGoals(dailyLog: dailyLog,
            targets: AchievementRules.DailyGoalTargets(calorieGoal: goals.calories, protein: goals.protein, carbs: goals.carbs, fats: goals.fats))
        let facts = ["calories": String(goals.calories ?? 0), "protein": String(goals.protein), "carbs": String(goals.carbs), "fats": String(goals.fats)]
        guard let fingerprint = try? PlanFingerprint.make(dailyLog) else { return }
        let evidence = AchievementAwardEvidence(kind: "diary_goals", sourceID: dayKey, sourceFingerprint: fingerprint,
            recordedAt: dailyLog.date, explanation: "Recorded diary totals against the saved targets", facts: facts)
        if hasFood, (goals.calories ?? 0) > 0, evaluation.calorieHit {
            updateChallengeProgress(for: userID, type: .calorieRange, amount: 1)
            unlockAchievement(userID: userID, achievementID: "calorie_target_hit", evidence: evidence)
        }
        if hasFood, goals.protein > 0, evaluation.proteinHit { updateChallengeProgress(for: userID, type: .proteinGoalHit, amount: 1) }
        if hasFood, goals.protein > 0, goals.carbs > 0, goals.fats > 0, evaluation.macroMasterHit {
            unlockAchievement(userID: userID, achievementID: "macro_master", evidence: evidence)
        }
        if (dailyLog.waterTracker?.goalOunces ?? 0) > 0, evaluation.hydrationHit {
            unlockAchievement(userID: userID, achievementID: "hydration_hero", evidence: evidence)
        }
    }

    private func checkLoggingStreakAchievement(userID: String, ending: Date) {
        Task { @MainActor in
            do {
                let end = Calendar.current.startOfDay(for: ending)
                guard let start = Calendar.current.date(byAdding: .day, value: -6, to: end) else { return }
                // Fetch a small timezone margin, then qualify canonical civil IDs.
                let queryStart = Calendar.current.date(byAdding: .day, value: -2, to: start) ?? start
                let queryEnd = Calendar.current.date(byAdding: .day, value: 3, to: end) ?? end
                let logs = try await DIContainer.shared.nutritionRepository.fetchDailyHistory(userID: userID, startDate: queryStart, endDate: queryEnd)
                guard self.currentUserID == userID else { return }
                let days = Set(logs.filter { $0.meals.flatMap(\.foodItems).contains(where: Self.eligibleFood) }
                    .compactMap { LoggingHabitRules.civilDate(for: $0) })
                var count = 0, keys: [String] = []
                for offset in 0..<7 {
                    guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: end), days.contains(date),
                          let key = DiaryDayContext.dayKey(for: date) else { break }
                    count += 1; keys.append(key)
                }
                let evidence = AchievementAwardEvidence(kind: "logging_days", sourceID: keys.first ?? "none",
                    sourceFingerprint: try PlanFingerprint.make(keys), recordedAt: ending,
                    explanation: "\(count) consecutive diary days with food entries", facts: ["dayKeys": keys.joined(separator: ",")])
                for id in ["log_streak_3", "log_streak_7"] {
                    self.updateProgress(userID: userID, achievementID: id, progress: Double(count))
                    if let definition = self.getDefinition(id: id), Double(count) >= definition.criteriaValue {
                        self.unlockAchievement(userID: userID, achievementID: id, evidence: evidence)
                    }
                }
            } catch { self.reportEvidenceFailure(userID: userID) }
        }
    }

    private func reportEvidenceFailure(userID: String) {
        guard currentUserID == userID else { return }
        achievementSyncNotice = "Milestone evidence could not be checked. Your progress and saved activity are unchanged."
    }

    public func checkRecipeCountAchievements(userID: String) {
        guard currentUserID == userID else { return }
        Task {
            do {
                let recipeCount = try await DIContainer.shared.achievementRepository.fetchRecipeCount(userID: userID)
                guard self.currentUserID == userID else { return }
                let chefAchievementIDs = AchievementRules.chefAchievementIDs
                for id in chefAchievementIDs {
                    guard let def = getDefinition(id: id) else { continue }
                    updateProgress(userID: userID, achievementID: id, progress: Double(recipeCount))
                    if shouldCheck(id), Double(recipeCount) >= def.criteriaValue {
                        unlockAchievement(userID: userID, achievementID: id, evidence: AchievementAwardEvidence(kind: "server_recipe_count",
                            sourceID: "recipes", sourceFingerprint: "server-count:\(recipeCount)", recordedAt: Date(),
                            explanation: "\(recipeCount) saved recipes confirmed by the server", facts: ["count": String(recipeCount)]))
                    }
                }
            } catch {
                AppLog.recipes.error("Failed to fetch recipe count for achievements: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func checkWorkoutCountAchievements(userID: String) {
        guard currentUserID == userID else { return }
        Task {
            do {
                let workoutCount = try await DIContainer.shared.achievementRepository.fetchWorkoutCount(userID: userID)
                guard self.currentUserID == userID else { return }
                let workoutAchievementIDs = AchievementRules.workoutAchievementIDs
                for id in workoutAchievementIDs {
                    guard let def = getDefinition(id: id) else { continue }
                    updateProgress(userID: userID, achievementID: id, progress: Double(workoutCount))
                    if shouldCheck(id), Double(workoutCount) >= def.criteriaValue {
                        unlockAchievement(userID: userID, achievementID: id, evidence: AchievementAwardEvidence(kind: "server_workout_count",
                            sourceID: "workoutSessionLogs", sourceFingerprint: "server-count:\(workoutCount)", recordedAt: Date(),
                            explanation: "\(workoutCount) saved workouts confirmed by the server", facts: ["count": String(workoutCount)]))
                    }
                }
            } catch {
                AppLog.workouts.error("Failed to fetch workout count for achievements: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func shouldCheck(_ id: String) -> Bool {
        AchievementRules.shouldCheck(id, definitions: achievementDefinitions, statuses: userStatuses)
    }
    private func getDefinition(id: String) -> AchievementDefinition? { return achievementDefinitions.first { $0.id == id } }
    
    private func unlockAchievement(userID: String, achievementID: String, evidence: AchievementAwardEvidence) {
        guard currentUserID == userID, shouldCheck(achievementID), let definition = getDefinition(id: achievementID) else { return }
        do {
            let command = try AchievementAwardCommand(ownerID: userID, definition: definition, evidence: evidence)
            _ = try awardStore.stage(command, currentUserID: DIContainer.shared.authService.currentUserID)
            retryPendingAwards()
        } catch { achievementSyncNotice = error.localizedDescription }
    }

    public func retryPendingAwards() {
        guard let userID = currentUserID, DIContainer.shared.authService.currentUserID == userID else { return }
        let commands: [AchievementAwardCommand]
        do { commands = try awardStore.pending(userID: userID); pendingAwardCount = commands.count } catch {
            achievementSyncNotice = "Saved milestone requests could not be read. They are kept unchanged."; return
        }
        guard awardDrainTask == nil else { return }
        guard !commands.isEmpty else { achievementSyncNotice = nil; return }
        let generation = accountGeneration
        achievementSyncNotice = "Saving \(commands.count) milestone\(commands.count == 1 ? "" : "s")…"
        awardDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.accountGeneration == generation { self.awardDrainTask = nil } }
            do {
                // Attempt each exact request once, including a successor promoted
                // after retirement, with a small fixed upper bound per drain.
                var attempted = Set<String>()
                var retiredAny = false
                while attempted.count < self.achievementDefinitions.count * 2,
                      let command = try self.awardStore.pending(userID: userID).first(where: { candidate in
                          guard let key = try? PlanFingerprint.make(candidate) else { return false }
                          return !attempted.contains(key)
                      }) {
                    attempted.insert(try PlanFingerprint.make(command))
                    guard !Task.isCancelled, self.currentUserID == userID, self.accountGeneration == generation,
                          DIContainer.shared.authService.currentUserID == userID else { return }
                    let result: AchievementAwardResult
                    do {
                        result = try await DIContainer.shared.achievementRepository.acceptAward(command, levelThresholds: self.levelThresholds)
                    } catch {
                        guard !Task.isCancelled, self.currentUserID == userID, self.accountGeneration == generation,
                              DIContainer.shared.authService.currentUserID == userID else { return }
                        if AchievementAwardError.identifying(error) == .evidenceNoLongerEligible {
                            try self.awardStore.retireObsoleteEvidence(command, currentUserID: userID)
                            retiredAny = true
                        } else if Self.stopsAwardQueue(error) { throw error }
                        continue
                    }
                    guard !Task.isCancelled, self.currentUserID == userID, self.accountGeneration == generation,
                          DIContainer.shared.authService.currentUserID == userID else { return }
                    self.userStatuses[command.achievementID] = result.status
                    self.userTotalAchievementPoints = result.totalPoints; self.userAchievementLevel = result.level
                    self.unlockedAchievementsCount = self.userStatuses.values.filter(\.isUnlocked).count
                    try self.awardStore.acknowledge(command, currentUserID: userID)
                    self.pendingAwardCount = try self.awardStore.pending(userID: userID).count
                    if result.awardedNow, let definition = self.getDefinition(id: command.achievementID) {
                        self.bannerService?.showBanner(title: "Achievement Unlocked!", message: definition.title,
                            iconName: definition.iconName, iconColor: AppPalette.achievement)
                        HapticManager.instance.notification(.success)
                    }
                }
                self.pendingAwardCount = try self.awardStore.pending(userID: userID).count
                self.achievementSyncNotice = self.pendingAwardCount == 0
                    ? (retiredAny ? "Outdated milestone requests were retired. Only confirmed milestones added points." : nil)
                    : "Some milestone sources could not be confirmed. Their requests are kept for retry; accepted points are safe."
            } catch {
                guard self.currentUserID == userID, self.accountGeneration == generation else { return }
                self.pendingAwardCount = (try? self.awardStore.pending(userID: userID).count) ?? self.pendingAwardCount
                self.achievementSyncNotice = "Milestone saving is pending. Retry safely; points are awarded only once."
            }
        }
    }

    private static func stopsAwardQueue(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let award = AchievementAwardError.identifying(error) {
            switch award {
            case .invalid, .accountChanged: return true
            case .unavailable, .evidenceUnavailable, .evidenceNoLongerEligible: return false
            }
        }
        let failure = error as NSError
        return (failure.domain == "FIRFirestoreErrorDomain" || failure.domain == "FirestoreErrorDomain")
            && [7, 16].contains(failure.code)
    }

    private func updateProgress(userID: String, achievementID: String, progress: Double) {
        guard currentUserID == userID,
              shouldCheck(achievementID),
              let def = getDefinition(id: achievementID) else { return }
        guard let status = AchievementRules.progressStatus(
            existingStatus: userStatuses[achievementID],
            definition: def,
            progress: progress
        ) else { return }
        self.userStatuses[achievementID] = status
        updateStatusInFirestore(userID: userID, status: status)
    }

    public func listenToActiveChallenges(for userID: String) {
        guard currentUserID == userID else { return }
        challengesCancellable?.cancel()
        challengesCancellable = DIContainer.shared.achievementRepository.activeChallengesPublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] challenges in
                guard let self, self.currentUserID == userID else { return }
                self.activeChallenges = challenges
            })
    }

    public func generateWeeklyChallenges(for userID: String) {
        guard currentUserID == userID else { return }
        let potentialChallenges = AchievementRules.potentialWeeklyChallenges(currentDate: Date())
        
        let challengesToSet = Array(potentialChallenges.shuffled().prefix(5))
        Task {
            do {
                try await DIContainer.shared.achievementRepository.generateWeeklyChallenges(userID: userID, challengesToSet: challengesToSet)
            } catch {
                AppLog.app.error("Failed to generate weekly challenges: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func updateChallengeProgress(for userID: String, type: ChallengeType, amount: Double) {
        guard currentUserID == userID else { return }
        Task {
            do {
                let challenges = try await DIContainer.shared.achievementRepository.fetchActiveChallenges(userID: userID, type: type)
                guard self.currentUserID == userID else { return }
                
                for challenge in challenges {
                    let updatedChallenge = AchievementRules.challengeAfterAddingProgress(challenge, amount: amount)

                    if updatedChallenge.isCompleted {
                        let pointsValue = updatedChallenge.pointsValue
                        let challengeTitle = updatedChallenge.title
                        await MainActor.run {
                            guard self.currentUserID == userID else { return }
                            self.awardPointsAndCheckLevel(userID: userID, points: pointsValue)
                            self.bannerService?.showBanner(title: "Challenge Complete!", message: challengeTitle, iconName: "star.fill", iconColor: AppPalette.achievement)
                        }
                    }

                    guard self.currentUserID == userID else { return }
                    try await DIContainer.shared.achievementRepository.updateChallenge(userID: userID, challenge: updatedChallenge)
                }
            } catch {
                AppLog.app.error("Failed to update challenge progress: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
