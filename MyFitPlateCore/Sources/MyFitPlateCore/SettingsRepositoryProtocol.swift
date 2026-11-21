import Foundation
import Combine

public protocol SettingsRepositoryProtocol {
    func fetchAccountProfile(userID: String, requireServer: Bool, completion: @escaping (Result<[String: Any]?, Error>) -> Void)
    func fetchUserGoals(userID: String, completion: @escaping ([String: Any]?) -> Void)
    func saveOnboardingGoals(userID: String, data: [String: Any]) async throws
    func saveUserGoals(userID: String, data: [String: Any]) async throws
    func saveWeeklyTargetDecision(_ decision: WeeklyTargetDecision) async throws -> WeeklyTargetDecision
    func fetchWeeklyTargetDecisions(userID: String) async throws -> [WeeklyTargetDecision]
    func fetchLegacyWeeklyCompletion(userID: String) async throws -> Date?
    func saveGoalEditorChange(userID: String, baseline: GoalEditorDraft, data: [String: Any]) async throws
    func saveWaterGoalChange(userID: String, baseline: Double, goal: Double) async throws
    func saveFoodPreferencesChange(userID: String, baseline: FoodPreferencesDraft, draft: FoodPreferencesDraft) async throws
    func weightHistoryPublisher(userID: String) -> AnyPublisher<[(id: String, date: Date, weight: Double)], Error>
    func saveWeightEntry(userID: String, weight: Double, date: Date) async throws
    func saveWeightMeasurement(userID: String, entryID: String, weight: Double, date: Date) async throws -> Bool
    func deleteWeightEntry(userID: String, entryID: String) async throws
    func fetchWeightHistory(userID: String) async throws -> [(id: String, date: Date, weight: Double)]
    func fetchWeightHistoryForReview(userID: String) async throws -> [(id: String, date: Date, weight: Double)]
    func updateUserAsOnboarded(userID: String) async throws
    func createInitialUserData(userID: String, email: String, username: String) async throws
}

public extension SettingsRepositoryProtocol {
    func fetchLegacyWeeklyCompletion(userID: String) async throws -> Date? { nil }
    func fetchWeightHistoryForReview(userID: String) async throws -> [(id: String, date: Date, weight: Double)] {
        throw WeeklyTargetReviewError.unavailable
    }
    func saveWeeklyTargetDecision(_ decision: WeeklyTargetDecision) async throws -> WeeklyTargetDecision {
        throw WeeklyTargetReviewError.unavailable
    }
    func fetchWeeklyTargetDecisions(userID: String) async throws -> [WeeklyTargetDecision] {
        throw WeeklyTargetReviewError.unavailable
    }
    func saveFoodPreferencesChange(userID: String, baseline: FoodPreferencesDraft, draft: FoodPreferencesDraft) async throws {
        throw FoodPreferencesError.unavailable
    }
    func saveWaterGoalChange(userID: String, baseline: Double, goal: Double) async throws {
        throw GoalEditorError.unavailable
    }
    func saveWeightMeasurement(userID: String, entryID: String, weight: Double, date: Date) async throws -> Bool {
        try await saveWeightEntry(userID: userID, weight: weight, date: date)
        return true
    }
    func saveGoalEditorChange(userID: String, baseline: GoalEditorDraft, data: [String: Any]) async throws {
        throw GoalEditorError.unavailable
    }
    func saveOnboardingGoals(userID: String, data: [String: Any]) async throws {
        try await saveUserGoals(userID: userID, data: data)
    }

    func fetchAccountProfile(userID: String, requireServer: Bool, completion: @escaping (Result<[String: Any]?, Error>) -> Void) {
        fetchUserGoals(userID: userID) { completion(.success($0)) }
    }

    func accountProfile(userID: String) async throws -> [String: Any]? {
        try await withCheckedThrowingContinuation { continuation in
            fetchAccountProfile(userID: userID, requireServer: true) { continuation.resume(with: $0) }
        }
    }
}
