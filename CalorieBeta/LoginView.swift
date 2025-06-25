import SwiftUI
import FirebaseAuth
import Firebase

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var loginError = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Spacer()

                Text("Welcome Back!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 30)
                
                VStack(spacing: 16) {
                    RoundedTextField(placeholder: "Enter your email", text: $email, iconName: "envelope.fill", isEmail: true)
                    RoundedSecureField(placeholder: "Enter your password", text: $password, iconName: "lock.fill")
                }

                if !loginError.isEmpty {
                    Text(loginError)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.top, 10)
                }

                Spacer()
                
                Button(action: loginUser) {
                    Text("Login")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 30)
            .navigationBarHidden(true)
        }
    }
    
    private func loginUser() {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                loginError = error.localizedDescription
                return
            }

            if let user = authResult?.user {
                fetchUserData(user: user)
            }
        }
    }

    private func fetchUserData(user: FirebaseAuth.User) {
        let db = Firestore.firestore()
        db.collection("users").document(user.uid).getDocument { document, error in
            if let document = document, document.exists {
                if let data = document.data() {
                    presentationMode.wrappedValue.dismiss()
                }
            } else {
                loginError = "User data not found."
            }
        }
    }
}
