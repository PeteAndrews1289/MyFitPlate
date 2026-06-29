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
    
    public let levelThresholds: [Int] = [0, 100, 250, 500, 1000, 2000, 5000]

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
        achievementDefinitions = [
            AchievementDefinition(id: "first_log", title: "First Steps", description: "Log your first meal or food item.", iconName: "figure.walk.arrival", criteriaType: .loggingStreak, criteriaValue: 1, pointsValue: 10),
            AchievementDefinition(id: "log_streak_3", title: "Getting Started", description: "Log food entries for 3 consecutive days.", iconName: "flame.fill", criteriaType: .loggingStreak, criteriaValue: 3, pointsValue: 20),
            AchievementDefinition(id: "log_streak_7", title: "Consistent Logger", description: "Log food entries for 7 consecutive days.", iconName: "calendar.badge.clock", criteriaType: .loggingStreak, criteriaValue: 7, pointsValue: 50),
            AchievementDefinition(id: "goal_setter", title: "Goal Setter", description: "Set your initial calorie and macro goals.", iconName: "target", criteriaType: .featureUsed, criteriaValue: 1, pointsValue: 15),
            AchievementDefinition(id: "calorie_target_hit", title: "Calorie Target Hit", description: "Meet your daily calorie goal.", iconName: "checkmark.circle.fill", criteriaType: .calorieGoalHitCount, criteriaValue: 1, pointsValue: 20),
            AchievementDefinition(id: "macro_master", title: "Macro Master", description: "Meet all 3 macro goals on the same day.", iconName: "chart.pie.fill", criteriaType: .macroGoalHitCount, criteriaValue: 1, pointsValue: 30),
            AchievementDefinition(id: "hydration_hero", title: "Hydration Hero", description: "Meet your daily water goal.", iconName: "drop.fill", criteriaType: .waterGoalHitCount, criteriaValue: 1, pointsValue: 15),
            AchievementDefinition(id: "on_the_weigh", title: "On the Weigh", description: "Log your weight for the first time.", iconName: "scalemass.fill", criteriaType: .featureUsed, criteriaValue: 1, pointsValue: 10),
            AchievementDefinition(id: "first_5_lbs", title: "First 5 Pounds", description: "Lose (or gain) your first 5 lbs.", iconName: "figure.walk.motion", criteriaType: .weightChange, criteriaValue: 5, pointsValue: 50),
            AchievementDefinition(id: "target_reached", title: "Target Reached", description: "Reach your set target weight.", iconName: "flag.checkered", criteriaType: .targetWeightReached, criteriaValue: 1, pointsValue: 100),
            AchievementDefinition(id: "scanner_pro", title: "Scanner Pro", description: "Log a food item using the barcode scanner.", iconName: "barcode.viewfinder", criteriaType: .barcodeScanUsed, criteriaValue: 1, pointsValue: 20),
            AchievementDefinition(id: "ai_chef", title: "AI Chef", description: "Log a recipe generated by the AI Chatbot.", iconName: "brain.head.profile", criteriaType: .aiRecipeLogged, criteriaValue: 1, pointsValue: 25),
            AchievementDefinition(id: "picture_perfect", title: "Picture Perfect", description: "Log a food item using image recognition.", iconName: "camera.viewfinder", criteriaType: .imageScanUsed, criteriaValue: 1, pointsValue: 25),
            AchievementDefinition(id: "first_workout", title: "Ready For Anything", description: "Complete your first workout.", iconName: "timer", criteriaType: .workoutsLogged, criteriaValue: 1, pointsValue: 10),
            AchievementDefinition(id: "workout_streak_3", title: "Working Up a Sweat", description: "Complete 3 workouts.", iconName: "guage", criteriaType: .workoutsLogged, criteriaValue: 3, pointsValue: 20),
            AchievementDefinition(id: "workout_streak_7", title: "Building Up", description: "Complete 7 workouts.", iconName: "guage.badge.plus", criteriaType: .workoutsLogged, criteriaValue: 7, pointsValue: 30),
            AchievementDefinition(id: "workout_streak_15", title: "Forming A Routine", description: "Complete 15 workouts.", iconName: "speedometer", criteriaType: .workoutsLogged, criteriaValue: 15, pointsValue: 40),
            AchievementDefinition(id: "novice_chef", title: "Novice Chef", description: "Create a recipe.", iconName: "doc", criteriaType: .recipesCreated, criteriaValue: 1, pointsValue: 10),
            AchievementDefinition(id: "apprentice_chef", title: "Apprentice Chef", description: "Create 10 recipes", iconName: "arrow.up.doc", criteriaType: .recipesCreated, criteriaValue: 10, pointsValue: 20),
            AchievementDefinition(id: "adept_chef", title: "Adept Chef", description: "Create 20 recipes", iconName: "doc.text", criteriaType: .recipesCreated, criteriaValue: 20, pointsValue: 30),
            AchievementDefinition(id: "expert_chef", title: "Expert Chef", description: "Create 30 recipes", iconName: "doc.append", criteriaType: .recipesCreated, criteriaValue: 30, pointsValue: 40),
        ]
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
                
                var newStatuses = self.createDefaultStatuses()
                for status in statuses {
                    newStatuses[status.achievementID] = status
                }
                self.userStatuses = newStatuses
                self.unlockedAchievementsCount = newStatuses.values.filter { $0.isUnlocked }.count
            })
    }
    
    private func createDefaultStatuses() -> [String: UserAchievementStatus] {
        var statuses: [String: UserAchievementStatus] = [:]
        for definition in achievementDefinitions {
            statuses[definition.id] = UserAchievementStatus(achievementID: definition.id)
        }
        return statuses
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
        var level = 1
        for (index, threshold) in levelThresholds.enumerated().reversed() {
            if points >= threshold {
                level = index + 1
                break
            }
        }
        return max(1, level)
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
        guard let calGoal = goals.calories else { return }
        if abs(dailyLog.totalCalories() - calGoal) <= 100.0 {
            updateChallengeProgress(for: userID, type: .calorieRange, amount: 1)
            if shouldCheck("calorie_target_hit") {
                unlockAchievement(userID: userID, achievementID: "calorie_target_hit")
            }
        }
        let macros = dailyLog.totalMacros()
        if abs(macros.protein - goals.protein) <= 10.0 { updateChallengeProgress(for: userID, type: .proteinGoalHit, amount: 1) }
        if shouldCheck("macro_master") { let pMet = abs(macros.protein - goals.protein) <= 10.0; let cMet = abs(macros.carbs - goals.carbs) <= 20.0; let fMet = abs(macros.fats - goals.fats) <= 5.0; if pMet && cMet && fMet { unlockAchievement(userID: userID, achievementID: "macro_master") } }
        if shouldCheck("hydration_hero"), let tracker = dailyLog.waterTracker { if tracker.totalOunces >= tracker.goalOunces { unlockAchievement(userID: userID, achievementID: "hydration_hero") } }
    }
    private func checkLoggingStreakAchievement(userID: String) { }
    private func checkWeightChangeAchievement(userID: String, goals: GoalSettings) { let id = "first_5_lbs"; guard shouldCheck(id), let def = getDefinition(id: id), let firstW = goals.weightHistory.first else { return }; let initialW = firstW.weight; let currentW = goals.weight; let change = abs(currentW - initialW); updateProgress(userID: userID, achievementID: id, progress: change); if change >= def.criteriaValue { unlockAchievement(userID: userID, achievementID: id) } }
    private func checkTargetWeightAchievement(userID: String, goals: GoalSettings) { let id = "target_reached"; guard shouldCheck(id), let target = goals.targetWeight else { return }; let current = goals.weight; if abs(current - target) <= 0.5 { unlockAchievement(userID: userID, achievementID: id) } }
    
    public func checkRecipeCountAchievements(userID: String) {
        Task {
            do {
                let recipeCount = try await DIContainer.shared.achievementRepository.fetchRecipeCount(userID: userID)
                let chefAchievementIDs = ["novice_chef", "apprentice_chef", "adept_chef", "expert_chef"]
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
                let workoutAchievementIDs = ["first_workout", "workout_streak_3", "workout_streak_7", "workout_streak_15"]
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
    
    private func shouldCheck(_ id: String) -> Bool { guard getDefinition(id: id) != nil else { return false }; return !(userStatuses[id]?.isUnlocked ?? false) }
    private func getDefinition(id: String) -> AchievementDefinition? { return achievementDefinitions.first { $0.id == id } }
    
    private func unlockAchievement(userID: String, achievementID: String) {
        guard shouldCheck(achievementID), let def = getDefinition(id: achievementID) else { return }
        
        var statusToUpdate: UserAchievementStatus
        if var existingStatus = userStatuses[achievementID] {
            if existingStatus.id == nil { existingStatus.id = achievementID }
            statusToUpdate = existingStatus
        } else {
            statusToUpdate = UserAchievementStatus(id: achievementID, achievementID: achievementID)
        }

        if !statusToUpdate.isUnlocked {
            statusToUpdate.isUnlocked = true
            statusToUpdate.unlockedDate = Date()
            statusToUpdate.currentProgress = def.criteriaValue
            statusToUpdate.lastProgressUpdate = Date()
            
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
        var status = userStatuses[achievementID] ?? UserAchievementStatus(id: achievementID, achievementID: achievementID)
        let capped = min(max(0, progress), def.criteriaValue)
        guard abs(capped - status.currentProgress) > 0.01 else { return }
        status.currentProgress = capped
        status.lastProgressUpdate = Date()
        if status.id == nil { status.id = achievementID }
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
        let weekFromNow = Date().addingTimeInterval(7 * 24 * 60 * 60)
        
        let potentialChallenges: [Challenge] = [
            Challenge(title: "Workout Warrior", description: "Log 3 separate workouts this week.", type: .workoutLogged, goal: 3, pointsValue: 75, expiresAt: weekFromNow),
            Challenge(title: "Protein Power", description: "Meet your daily protein goal 4 times.", type: .proteinGoalHit, goal: 4, pointsValue: 75, expiresAt: weekFromNow),
            Challenge(title: "Calorie Controller", description: "Stay within 100 calories of your goal for 3 days.", type: .calorieRange, goal: 3, pointsValue: 60, expiresAt: weekFromNow),
            Challenge(title: "Dedicated Dieter", description: "Log your food for all 7 days of the week.", type: .loggingStreak, goal: 7, pointsValue: 150, expiresAt: weekFromNow),
            Challenge(title: "Weekend Warrior", description: "Log at least one workout on Saturday or Sunday.", type: .workoutLogged, goal: 1, pointsValue: 40, expiresAt: weekFromNow),
            Challenge(title: "Five-a-Day", description: "Log at least 5 days in a row this week.", type: .loggingStreak, goal: 5, pointsValue: 100, expiresAt: weekFromNow),
            Challenge(title: "Macro-Minded", description: "Hit your protein goal 2 times in a row.", type: .proteinGoalHit, goal: 2, pointsValue: 50, expiresAt: weekFromNow),
            Challenge(title: "Active Start", description: "Log 2 workouts before Wednesday.", type: .workoutLogged, goal: 2, pointsValue: 50, expiresAt: weekFromNow)
        ]
        
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
                
                for var challenge in challenges {
                    challenge.progress += amount
                    
                    if challenge.progress >= challenge.goal {
                        challenge.isCompleted = true
                        let pointsValue = challenge.pointsValue
                        let challengeTitle = challenge.title
                        await MainActor.run {
                            self.awardPointsAndCheckLevel(userID: userID, points: pointsValue)
                            self.bannerService?.showBanner(title: "Challenge Complete!", message: challengeTitle, iconName: "star.fill", iconColor: .yellow)
                        }
                    }
                    
                    try await DIContainer.shared.achievementRepository.updateChallenge(userID: userID, challenge: challenge)
                }
            } catch {
                AppLog.app.error("Failed to update challenge progress: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
