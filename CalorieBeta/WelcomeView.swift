import SwiftUI

struct WelcomeView: View {
    @State private var showLoginView = false
    @State private var showSignUpView = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            Image("mfp logo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .padding(.bottom, 20)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

            Text("Welcome to MyFitPlate")
                .appFont(size: 34, weight: .bold)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)

            Text("Track your food, reach your goals.")
                .appFont(size: 24, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel)) // Corrected usage
                .padding(.top, 8)
            
            Spacer()
            Spacer()

            VStack(spacing: 16) {
                Button("Create an Account") {
                    showSignUpView = true
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("I Already Have an Account") {
                    showLoginView = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .background(Color.backgroundPrimary.edgesIgnoringSafeArea(.all))
        .sheet(isPresented: $showLoginView) {
            LoginView()
        }
        .sheet(isPresented: $showSignUpView) {
            SignUpView()
        }
    }
}
