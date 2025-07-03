import SwiftUI
import FirebaseAuth
import Firebase

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var loginError = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 20) {
            
            Spacer()

            Text("Welcome Back!")
                .appFont(size: 34, weight: .bold)
                .foregroundColor(.textPrimary)
                .padding(.bottom, 30)
            
            VStack(spacing: 16) {
                TextField("Enter your email", text: $email)
                    .textFieldStyle(AppTextFieldStyle(iconName: "envelope.fill"))
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                SecureField("Enter your password", text: $password)
                    .textFieldStyle(AppTextFieldStyle(iconName: "lock.fill"))
            }

            if !loginError.isEmpty {
                Text(loginError)
                    .foregroundColor(.red)
                    .appFont(size: 12)
                    .padding(.top, 10)
            }

            Spacer()
            
            Button("Login") {
                loginUser()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 30)
        .background(Color.backgroundPrimary.edgesIgnoringSafeArea(.all))
        .navigationBarHidden(true)
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
