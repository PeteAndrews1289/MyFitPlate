import Foundation
import MyFitPlateCore
import FirebaseFunctions

final class FirebaseCloudFunctionService: CloudFunctionServiceProtocol, @unchecked Sendable {
    func deleteUserData() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Functions.functions().httpsCallable("deleteUserData").call { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func callFunction(_ name: String, with data: [String: Any]) async throws -> Any? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            Functions.functions().httpsCallable(name).call(data) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.data)
                }
            }
        }
    }
}
