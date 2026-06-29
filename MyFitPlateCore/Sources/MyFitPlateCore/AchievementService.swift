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

    private var userStatusCancellable: AnyCancellable?
    private var userProfileCancellable: AnyCancellable?
    private var challengesCancellable: AnyCancellable?
    private var authCancellable: Any?
    private var currentUserID: String?
    private weak var dailyLogService: DailyLogService?
    private weak var goalSettings: GoalSettings?
    private weak var bannerService: BannerService?
    
    public let levelThresholds: [Int] = AchievementRules.defaultLevelThresholds

    public init() {
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
    
    private func setupAuthListener() {
        authCancellable = DIContainer.shared.authService.observeAuthState { [weak self] uid in
            Task { @MainActor in
                guard let self = self else { return }
                if let uid = uid {
                    if self.currentUserID != uid {
                        self.currentUserID = uid
                        if self.dailyLogService != nil && self.goalSettings != nil && self.bannerService != nil {
                            self.fetchUserStatuses(userID: uid)
                            self.listenToUserProfile(userID: uid)
                            self.listenToActiveChallenges(for: uid)
                            self.generateWeeklyChallenges(for: uid)
                        }
                    }
                } else {
                    self.currentUserID = nil
                    self.userStatusCancellable?.cancel()
                    self.userProfileCancellable?.cancel()
                    self.challengesCancellable?.cancel()
                    self.userStatuses = [:]
                    self.unlockedAchievementsCount = 0
                    self.userTotalAchievementPoints = 0
                    self.userAchievementLevel = 1
                    self.activeChallenges = []
                }
            }
        }
    }

    private func loadAchievementDefinitions() {
        achievementDefinitions = AchievementRules.defaultDefinitions()
    }

    public func listenToUserProfile(userID: String) {
        userProfileCancellable?.cancel()
        userProfileCancellable = DIContainer.shared.achievementRepository.userProfilePublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let self = self else { return }
                if let profile = profile {
                    self.userTotalAchievementPoints = profile.points
                    self.userAchievementLevel = profile.level
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
                self?.isLoading = false
            }, receiveValue: { [weak self] statuses in
                guard let self = self else { return }
                self.isLoading = false
                
                if statuses.isEmpty {
                    self.userStatuses = self.createDefaultStatuses()
                    self.unlockedAchievementsCount = 0
                    return
                }
                
                let newStatuses = AchievementRules.mergedStatuses(
                    definitions: self.achievementDefinitions,
                    fetchedStatuses: statuses
                )
                self.userStatuses = newStatuses
                self.unlockedAchievementsCount = newStatuses.values.filter { $0.isUnlocked }.count
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
        Task {
            do {
                let result = try await DIContainer.shared.achievementRepository.awardPointsAndCheckLevel(userID: userID, points: points, levelThresholds: self.levelThresholds)
                await MainActor.run {
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

    public func checkAchievementsOnLogUpdate(userID: String, logDate: Date) {
         guard currentUserID == userID, let goals = goalSettings, let logService = dailyLogService else { return }
         logService.fetchLog(for: userID, date: logDate) { [weak self] (result: Result<DailyLog, Error>) in
              guard let self = self else { return }
              Task { @MainActor in
                   switch result {
                   case .success(let dailyLog):
                        self.checkFirstLogAchievement(userID: userID)
                        self.checkDailyGoalsAchieved(userID: userID, dailyLog: dailyLog, goals: goals)
                        self.checkLoggingStreakAchievement(userID: userID)
                   case .failure(_):
                        break
                   }
              }
         }
    }

    public func checkAchievementsOnWeightUpdate(userID: String) { guard currentUserID == userID, let goals = goalSettings else { return }; Task { @MainActor in self.checkFirstWeightLogAchievement(userID: userID); self.checkWeightChangeAchievement(userID: userID, goals: goals); self.checkTargetWeightAchievement(userID: userID, goals: goals) } }
    public func checkAchievementsOnGoalSet(userID: String) { guard currentUserID == userID else { return }; Task { @MainActor in self.unlockAchievement(userID: userID, achievementID: "goal_setter") } }
    
    public func checkFeatureUsedAchievement(userID: String, featureType: AchievementCriteriaType) {
        guard currentUserID == userID, let def = achievementDefinitions.first(where: { $0.criteriaType == featureType }) else { return }
        Task { @MainActor in
            self.unlockAchievement(userID: userID, achievementID: def.id)
        }
    }
    
    private func checkFirstLogAchievement(userID: String) { let id="first_log"; guard shouldCheck(id) else { return }; unlockAchievement(userID: userID, achievementID: id) }
    private func checkFirstWeightLogAchievement(userID: String) { let id="on_the_weigh"; guard shouldCheck(id) else { return }; unlockAchievement(userID: userID, achievementID: id) }
    private func checkDailyGoalsAchieved(userID: String, dailyLog: DailyLog, goals: GoalSettings) {
        let evaluation = AchievementRules.evaluateDailyGoals(
            dailyLog: dailyLog,
            targets: AchievementRules.DailyGoalTargets(
                calorieGoal: goals.calories,
                protein: goals.protein,
                carbs: goals.carbs,
                fats: goals.fats
            )
        )
        if evaluation.calorieHit {
            updateChallengeProgress(for: userID, type: .calorieRange, amount: 1)
            if shouldCheck("calorie_target_hit") {
                unlockAchievement(userID: userID, achievementID: "calorie_target_hit")
            }
        }
        if evaluation.proteinHit { updateChallengeProgress(for: userID, type: .proteinGoalHit, amount: 1) }
        if shouldCheck("macro_master"), evaluation.macroMasterHit { unlockAchievement(userID: userID, achievementID: "macro_master") }
        if shouldCheck("hydration_hero"), evaluation.hydrationHit { unlockAchievement(userID: userID, achievementID: "hydration_hero") }
    }
    private func checkLoggingStreakAchievement(userID: String) { }
    private func checkWeightChangeAchievement(userID: String, goals: GoalSettings) { let id = "first_5_lbs"; guard shouldCheck(id), let def = getDefinition(id: id), let firstW = goals.weightHistory.first else { return }; let change = AchievementRules.weightChangeProgress(initialWeight: firstW.weight, currentWeight: goals.weight); updateProgress(userID: userID, achievementID: id, progress: change); if change >= def.criteriaValue { unlockAchievement(userID: userID, achievementID: id) } }
    private func checkTargetWeightAchievement(userID: String, goals: GoalSettings) { let id = "target_reached"; guard shouldCheck(id), let target = goals.targetWeight else { return }; if AchievementRules.hasReachedTargetWeight(currentWeight: goals.weight, targetWeight: target) { unlockAchievement(userID: userID, achievementID: id) } }
    
    public func checkRecipeCountAchievements(userID: String) {
        Task {
            do {
                let recipeCount = try await DIContainer.shared.achievementRepository.fetchRecipeCount(userID: userID)
                let chefAchievementIDs = AchievementRules.chefAchievementIDs
                for id in chefAchievementIDs {
                    guard let def = getDefinition(id: id) else { continue }
                    updateProgress(userID: userID, achievementID: id, progress: Double(recipeCount))
                    if shouldCheck(id), Double(recipeCount) >= def.criteriaValue {
                        unlockAchievement(userID: userID, achievementID: id)
                    }
                }
            } catch {
                AppLog.recipes.error("Failed to fetch recipe count for achievements: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func checkWorkoutCountAchievements(userID: String) {
        Task {
            do {
                let workoutCount = try await DIContainer.shared.achievementRepository.fetchWorkoutCount(userID: userID)
                let workoutAchievementIDs = AchievementRules.workoutAchievementIDs
                for id in workoutAchievementIDs {
                    guard let def = getDefinition(id: id) else { continue }
                    updateProgress(userID: userID, achievementID: id, progress: Double(workoutCount))
                    if shouldCheck(id), Double(workoutCount) >= def.criteriaValue {
                        unlockAchievement(userID: userID, achievementID: id)
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
    
    private func unlockAchievement(userID: String, achievementID: String) {
        guard shouldCheck(achievementID), let def = getDefinition(id: achievementID) else { return }

        if let statusToUpdate = AchievementRules.unlockedStatus(existingStatus: userStatuses[achievementID], definition: def) {
            self.userStatuses[achievementID] = statusToUpdate
            self.unlockedAchievementsCount = self.userStatuses.values.filter{$0.isUnlocked}.count
            
            updateStatusInFirestore(userID: userID, status: statusToUpdate)
            awardPointsAndCheckLevel(userID: userID, points: def.pointsValue)
            
            bannerService?.showBanner(title: "Achievement Unlocked!", message: def.title, iconName: def.iconName, iconColor: .yellow)
            HapticManager.instance.notification(.success)
        }
    }
    
    private func updateProgress(userID: String, achievementID: String, progress: Double) {
        guard shouldCheck(achievementID), let def = getDefinition(id: achievementID) else { return }
        guard let status = AchievementRules.progressStatus(
            existingStatus: userStatuses[achievementID],
            definition: def,
            progress: progress
        ) else { return }
        self.userStatuses[achievementID] = status
        updateStatusInFirestore(userID: userID, status: status)
    }

    public func listenToActiveChallenges(for userID: String) {
        challengesCancellable?.cancel()
        challengesCancellable = DIContainer.shared.achievementRepository.activeChallengesPublisher(userID: userID)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] challenges in
                self?.activeChallenges = challenges
            })
    }

    public func generateWeeklyChallenges(for userID: String) {
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
        Task {
            do {
                let challenges = try await DIContainer.shared.achievementRepository.fetchActiveChallenges(userID: userID, type: type)
                
                for challenge in challenges {
                    let updatedChallenge = AchievementRules.challengeAfterAddingProgress(challenge, amount: amount)

                    if updatedChallenge.isCompleted {
                        let pointsValue = updatedChallenge.pointsValue
                        let challengeTitle = updatedChallenge.title
                        await MainActor.run {
                            self.awardPointsAndCheckLevel(userID: userID, points: pointsValue)
                            self.bannerService?.showBanner(title: "Challenge Complete!", message: challengeTitle, iconName: "star.fill", iconColor: .yellow)
                        }
                    }

                    try await DIContainer.shared.achievementRepository.updateChallenge(userID: userID, challenge: updatedChallenge)
                }
            } catch {
                AppLog.app.error("Failed to update challenge progress: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
