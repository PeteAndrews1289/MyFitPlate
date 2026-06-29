import Foundation

public protocol CloudFunctionServiceProtocol: Sendable {
    func deleteUserData() async throws
    func callFunction(_ name: String, with data: [String: Any]) async throws -> Any?
}
