import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class AchievementService: ObservableObject {
    @Published var achievementDefinitions: [AchievementDefinition] = []
    @Published var userStatuses: [String: UserAchievementStatus] = [:]
    @Published var unlockedAchievementsCount: Int = 0
    @Published var isLoading: Bool = false
    
    @Published var userTotalAchievementPoints: Int = 0
    @Published var userAchievementLevel: Int = 1
    
    @Published var activeChallenges: [Challenge] = []

    private let db = Firestore.firestore()
    private var userStatusListener: ListenerRegistration?
    private var userProfileListener: ListenerRegistration?
    private var challengesListener: ListenerRegistration?
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    private var currentUserID: String?
    private weak var dailyLogService: DailyLogService?
    private weak var goalSettings: GoalSettings?
    private weak var bannerService: BannerService?
    
    let levelThresholds: [Int] = [0, 100, 250, 500, 1000, 2000, 5000]

    init() {
        loadAchievementDefinitions()
        setupAuthListener()
    }

    deinit {
        userStatusListener?.remove()
        userProfileListener?.remove()
        challengesListener?.remove()
        if let handle = authStateListenerHandle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    func setupDependencies(dailyLogService: DailyLogService, goalSettings: GoalSettings, bannerService: BannerService) {
        self.dailyLogService = dailyLogService
        self.goalSettings = goalSettings
        self.bannerService = bannerService
        dailyLogService.achievementService = self
        if let userID = self.currentUserID {
            self.fetchUserStatuses(userID: userID)
            self.listenToUserProfile(userID: userID)
            self.listenToActiveChallenges(for: userID)
        }
    }
    
    private func setupAuthListener() {
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            guard let self = self else { return }
             Task { @MainActor in
                 if let user = user {
                     if self.currentUserID != user.uid {
                         self.currentUserID = user.uid
                         if self.dailyLogService != nil && self.goalSettings != nil && self.bannerService != nil {
                             self.fetchUserStatuses(userID: user.uid)
                             self.listenToUserProfile(userID: user.uid)
                             self.listenToActiveChallenges(for: user.uid)
                             self.generateWeeklyChallenges(for: user.uid)
                         }
                     }
                 } else {
                     self.currentUserID = nil
                     self.userStatusListener?.remove()
                     self.userProfileListener?.remove()
                     self.challengesListener?.remove()
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
        ]
    }

    func listenToUserProfile(userID: String) {
        userProfileListener?.remove()
        userProfileListener = db.collection("users").document(userID)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self, let document = documentSnapshot else { return }
                DispatchQueue.main.async {
                    self.userTotalAchievementPoints = document.data()?["totalAchievementPoints"] as? Int ?? 0
                    self.userAchievementLevel = document.data()?["userLevel"] as? Int ?? 1
                }
            }
    }

    func fetchUserStatuses(userID: String) {
        guard !userID.isEmpty, self.currentUserID == userID else { return }
        isLoading = true
        let ref = db.collection("users").document(userID).collection("achievementStatus")
        userStatusListener?.remove()
        userStatusListener = ref.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            Task { @MainActor in
                self.isLoading = false
                if err != nil { return }
                guard let docs = snap?.documents else {
                    self.userStatuses = self.createDefaultStatuses()
                    self.unlockedAchievementsCount = 0
                    return
                }
                var newStatuses = self.createDefaultStatuses()
                for doc in docs {
                    do {
                        var status = try doc.data(as: UserAchievementStatus.self)
                        status.id = doc.documentID
                        newStatuses[status.achievementID] = status
                    } catch {}
                }
                self.userStatuses = newStatuses
                self.unlockedAchievementsCount = newStatuses.values.filter { $0.isUnlocked }.count
            }
        }
    }
    
    private func createDefaultStatuses() -> [String: UserAchievementStatus] {
        var statuses: [String: UserAchievementStatus] = [:]
        for definition in achievementDefinitions {
            statuses[definition.id] = UserAchievementStatus(achievementID: definition.id)
        }
        return statuses
    }
    
    private func updateStatusInFirestore(userID: String, status: UserAchievementStatus) {
        guard !userID.isEmpty, self.currentUserID == userID, let statusDocID = status.id else { return }
        let ref = db.collection("users").document(userID).collection("achievementStatus").document(statusDocID)
        do {
            try ref.setData(from: status, merge: true)
        } catch {}
    }

    private func awardPointsAndCheckLevel(userID: String, points: Int) {
        let userRef = db.collection("users").document(userID)
        db.runTransaction { (transaction, errorPointer) -> Any? in
            let userDocument: DocumentSnapshot
            do {
                try userDocument = transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            let oldPoints = userDocument.data()?["totalAchievementPoints"] as? Int ?? 0
            let newPoints = oldPoints + points
            
            var newLevel = 1
            for (index, threshold) in self.levelThresholds.enumerated().reversed() {
                if newPoints >= threshold {
                    newLevel = index + 1
                    break
                }
            }
            if newLevel < 1 { newLevel = 1 }

            transaction.updateData(["totalAchievementPoints": newPoints, "userLevel": newLevel], forDocument: userRef)
            return nil
        } completion: { (object, error) in
            if error == nil {
                DispatchQueue.main.async {
                   self.userTotalAchievementPoints = self.userTotalAchievementPoints + points
                   self.userAchievementLevel = self.calculateLevel(for: self.userTotalAchievementPoints)
                }
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

    func checkAchievementsOnLogUpdate(userID: String, logDate: Date) {
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

    func checkAchievementsOnWeightUpdate(userID: String) { guard currentUserID == userID, let goals = goalSettings else { return }; Task { @MainActor in self.checkFirstWeightLogAchievement(userID: userID); self.checkWeightChangeAchievement(userID: userID, goals: goals); self.checkTargetWeightAchievement(userID: userID, goals: goals) } }
    func checkAchievementsOnGoalSet(userID: String) { guard currentUserID == userID else { return }; Task { @MainActor in self.unlockAchievement(userID: userID, achievementID: "goal_setter") } }
    
    func checkFeatureUsedAchievement(userID: String, featureType: AchievementCriteriaType) {
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
    private func checkTargetWeightAchievement(userID: String, goals: GoalSettings) { let id = "target_reached"; guard shouldCheck(id), let def = getDefinition(id: id), let target = goals.targetWeight else { return }; let current = goals.weight; if abs(current - target) <= 0.5 { unlockAchievement(userID: userID, achievementID: id) } }
    
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
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
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

    func listenToActiveChallenges(for userID: String) {
        let challengesRef = db.collection("users").document(userID).collection("activeChallenges")
        challengesListener?.remove()
        challengesListener = challengesRef.whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                guard let documents = querySnapshot?.documents else {
                    self.activeChallenges = []
                    return
                }

                var newChallenges: [Challenge] = []
                for doc in documents {
                    do {
                        let challenge = try doc.data(as: Challenge.self)
                        newChallenges.append(challenge)
                    } catch {
                    }
                }
                self.activeChallenges = newChallenges
            }
    }

    func generateWeeklyChallenges(for userID: String) {
        let challengesRef = db.collection("users").document(userID).collection("activeChallenges")
        challengesRef.whereField("expiresAt", isGreaterThan: Timestamp(date: Date())).getDocuments { [weak self] snapshot, error in
            guard let self = self, (snapshot?.documents.isEmpty ?? true) else { return }

            let weekFromNow = Timestamp(date: Date().addingTimeInterval(7 * 24 * 60 * 60))
            
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
            let batch = self.db.batch()
            for challenge in challengesToSet {
                let newDocRef = challengesRef.document()
                do {
                    try batch.setData(from: challenge, forDocument: newDocRef)
                } catch {
                }
            }
            batch.commit { err in
            }
        }
    }

    func updateChallengeProgress(for userID: String, type: ChallengeType, amount: Double) {
        let challengesRef = db.collection("users").document(userID).collection("activeChallenges")
        challengesRef
            .whereField("type", isEqualTo: type.rawValue)
            .whereField("isCompleted", isEqualTo: false)
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .getDocuments { [weak self] snapshot, error in
                guard let self = self, let documents = snapshot?.documents, !documents.isEmpty else { return }

                for document in documents {
                    do {
                        var challenge = try document.data(as: Challenge.self)
                        challenge.progress += amount
                        
                        if challenge.progress >= challenge.goal {
                            challenge.isCompleted = true
                            self.awardPointsAndCheckLevel(userID: userID, points: challenge.pointsValue)
                            self.bannerService?.showBanner(title: "Challenge Complete!", message: challenge.title, iconName: "star.fill", iconColor: .yellow)
                        }
                        
                        try challengesRef.document(document.documentID).setData(from: challenge, merge: true)
                    } catch {
                    }
                }
            }
    }
}
