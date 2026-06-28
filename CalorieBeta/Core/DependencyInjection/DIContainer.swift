import Foundation

@MainActor
class DIContainer: ObservableObject {
    static let shared = DIContainer()
    
    let authService: AuthServiceProtocol
    let databaseService: DatabaseServiceProtocol
    let nutritionRepository: NutritionRepositoryProtocol
    let workoutRepository: WorkoutRepositoryProtocol
    let groupRepository: GroupRepositoryProtocol
    let achievementRepository: AchievementRepositoryProtocol
    let settingsRepository: SettingsRepositoryProtocol
    let reportsRepository: ReportsRepositoryProtocol
    let postRepository: PostRepositoryProtocol
    
    // We will expand this to include AnalyticsServiceProtocol, etc.
    
    init(authService: AuthServiceProtocol = FirebaseAuthService(),
         databaseService: DatabaseServiceProtocol = FirestoreDatabaseService(),
         nutritionRepository: NutritionRepositoryProtocol = FirestoreNutritionRepository(),
         workoutRepository: WorkoutRepositoryProtocol = FirestoreWorkoutRepository(),
         groupRepository: GroupRepositoryProtocol = FirestoreGroupRepository(),
         achievementRepository: AchievementRepositoryProtocol = FirestoreAchievementRepository(),
         settingsRepository: SettingsRepositoryProtocol = FirestoreSettingsRepository(),
         reportsRepository: ReportsRepositoryProtocol = FirestoreReportsRepository(),
         postRepository: PostRepositoryProtocol = FirestorePostRepository()) {
        self.authService = authService
        self.databaseService = databaseService
        self.nutritionRepository = nutritionRepository
        self.workoutRepository = workoutRepository
        self.groupRepository = groupRepository
        self.achievementRepository = achievementRepository
        self.settingsRepository = settingsRepository
        self.reportsRepository = reportsRepository
        self.postRepository = postRepository
    }
}
