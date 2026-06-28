import Foundation

protocol DatabaseServiceProtocol: Sendable {
    func loadDarkModePreference(userID: String) async throws -> Bool
    func saveDarkModePreference(userID: String, isEnabled: Bool) async throws
    func recordLastLogin(userID: String) async throws
    func deleteUserAllData(userID: String) async throws
}
