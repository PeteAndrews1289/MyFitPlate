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
        let catalogTimeout: TimeInterval? = switch name {
        case "fatSecretProxy": 8
        case "healthCanadaFoodSearch", "nihSupplementSearch", "nihSupplementBarcodeLookup": 12
        default: nil
        }
        // These catalogs require an authenticated Firebase user on the server.
        // Public catalogs can return while the user is signed out.
        if catalogTimeout != nil, Auth.auth().currentUser == nil {
            throw NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.unauthenticated.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Sign in to search this food source."])
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            let callable = Functions.functions().httpsCallable(name)
            if let catalogTimeout { callable.timeoutInterval = catalogTimeout }
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
