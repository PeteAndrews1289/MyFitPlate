import Foundation

protocol CloudFunctionServiceProtocol: Sendable {
    func deleteUserData() async throws
}
