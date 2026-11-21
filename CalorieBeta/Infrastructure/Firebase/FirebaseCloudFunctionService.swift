import Foundation
import MyFitPlateCore
import FirebaseFunctions
import FirebaseAuth

final class FirebaseCloudFunctionService: CloudFunctionServiceProtocol, @unchecked Sendable {
    func deleteUserData() async throws {
        guard let userID = Auth.auth().currentUser?.uid else { throw AccountDeletionError.missingCurrentUser }
        try await deleteUserData(expectedUserID: userID)
    }

    func deleteUserData(expectedUserID: String) async throws {
        guard Auth.auth().currentUser?.uid == expectedUserID else { throw AccountDeletionError.accountChanged }
        _ = try await Auth.auth().currentUser?.getIDToken(forcingRefresh: true)
        guard Auth.auth().currentUser?.uid == expectedUserID else { throw AccountDeletionError.accountChanged }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Functions.functions().httpsCallable("deleteUserData").call(["expectedUserID": expectedUserID]) { _, error in
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
            let callable = Functions.functions().httpsCallable(name)
            if name == "fatSecretProxy" {
                callable.timeoutInterval = 8
            }
            callable.call(data) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.data)
                }
            }
        }
    }
}
