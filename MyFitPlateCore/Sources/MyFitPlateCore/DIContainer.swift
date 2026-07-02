import Foundation

@MainActor
public class DIContainer: ObservableObject {
    public static let shared = DIContainer()
    
    public var authService: AuthServiceProtocol!
    public var databaseService: DatabaseServiceProtocol!
    public var nutritionRepository: NutritionRepositoryProtocol!
    public var workoutRepository: WorkoutRepositoryProtocol!
    public var groupRepository: GroupRepositoryProtocol!
    public var achievementRepository: AchievementRepositoryProtocol!
    public var settingsRepository: SettingsRepositoryProtocol!
    public var reportsRepository: ReportsRepositoryProtocol!
    public var postRepository: PostRepositoryProtocol!
    public var cloudFunctionService: CloudFunctionServiceProtocol!
    public var accountDeletionService: AccountDeletionServicing!
    public var aiService: AIServiceProtocol!
    public var analyticsManager: AnalyticsManagerProtocol!
    public var crashManager: CrashManagerProtocol!
    public var featureFlagService: FeatureFlagServiceProtocol!
    /// Optional: the shared community barcode-correction pool. Nil when Firebase isn't
    /// configured (tests, previews) — lookups just skip the community step.
    public var communityBarcodeStore: CommunityBarcodeStoreProtocol?

    private init() {}
    
    public func configure(
        authService: AuthServiceProtocol,
        databaseService: DatabaseServiceProtocol,
        nutritionRepository: NutritionRepositoryProtocol,
        workoutRepository: WorkoutRepositoryProtocol,
        groupRepository: GroupRepositoryProtocol,
        achievementRepository: AchievementRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol,
        reportsRepository: ReportsRepositoryProtocol,
        postRepository: PostRepositoryProtocol,
        cloudFunctionService: CloudFunctionServiceProtocol,
        accountDeletionService: AccountDeletionServicing,
        analyticsManager: AnalyticsManagerProtocol,
        crashManager: CrashManagerProtocol,
        featureFlagService: FeatureFlagServiceProtocol,
        aiService: AIServiceProtocol
    ) {
        self.authService = authService
        self.databaseService = databaseService
        self.nutritionRepository = nutritionRepository
        self.workoutRepository = workoutRepository
        self.groupRepository = groupRepository
        self.achievementRepository = achievementRepository
        self.settingsRepository = settingsRepository
        self.reportsRepository = reportsRepository
        self.postRepository = postRepository
        self.cloudFunctionService = cloudFunctionService
        self.aiService = aiService
        self.analyticsManager = analyticsManager
        self.crashManager = crashManager
        self.featureFlagService = featureFlagService
        self.accountDeletionService = accountDeletionService
    }
}
