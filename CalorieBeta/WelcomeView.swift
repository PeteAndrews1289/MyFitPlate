import SwiftUI

struct WelcomeView: View {
    @State private var showLoginView = false
    @State private var showSignUpView = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            Image("mfp logo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .padding(.bottom, 20)

            Text("Welcome to MyFitPlate")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Track your food, reach your goals.")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            Spacer()
            Spacer()

            VStack(spacing: 16) {
                Button(action: { showSignUpView = true }) {
                    Text("Create an Account")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }

                Button(action: { showLoginView = true }) {
                    Text("I Already Have an Account")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(colorScheme == .dark ? Color(.systemGray5) : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor, lineWidth: 2)
                        )
                        .foregroundColor(Color.accentColor)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .background(colorScheme == .dark ? Color.black : Color(.systemGray6))
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showLoginView) {
            LoginView()
        }
        .sheet(isPresented: $showSignUpView) {
            SignUpView()
        }
    }
}
