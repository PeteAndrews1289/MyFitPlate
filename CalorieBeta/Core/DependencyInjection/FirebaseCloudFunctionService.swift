import Foundation
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
}
