import Foundation
import Combine

protocol SettingsRepositoryProtocol {
    func fetchUserGoals(userID: String, completion: @escaping ([String: Any]?) -> Void)
    func saveUserGoals(userID: String, data: [String: Any]) async throws
    func weightHistoryPublisher(userID: String) -> AnyPublisher<[(id: String, date: Date, weight: Double)], Error>
    func saveWeightEntry(userID: String, weight: Double, date: Date) async throws
    func deleteWeightEntry(userID: String, entryID: String) async throws
    func fetchWeightHistory(userID: String) async throws -> [(id: String, date: Date, weight: Double)]
    func updateUserAsOnboarded(userID: String) async throws
    func createInitialUserData(userID: String, email: String, username: String) async throws
}
