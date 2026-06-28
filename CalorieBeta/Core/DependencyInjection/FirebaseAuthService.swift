import Foundation
import FirebaseAuth

class FirebaseAuthService: AuthServiceProtocol {
    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }
    
    func observeAuthState(listener: @escaping (String?) -> Void) -> Any {
        return Auth.auth().addStateDidChangeListener { _, user in
            listener(user?.uid)
        }
    }
    
    func removeObserver(_ handle: Any) {
        if let handle = handle as? AuthStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
}
