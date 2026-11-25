import Foundation

public protocol CloudFunctionServiceProtocol: Sendable {
    func deleteUserData() async throws
    func deleteUserData(expectedUserID: String) async throws
    func callFunction(_ name: String, with data: [String: Any]) async throws -> Any?
}

public extension CloudFunctionServiceProtocol {
    func deleteUserData(expectedUserID: String) async throws { try await deleteUserData() }
}
