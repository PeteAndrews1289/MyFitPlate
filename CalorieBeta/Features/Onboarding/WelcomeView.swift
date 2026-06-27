import SwiftUI

struct WelcomeView: View {
    @State private var showLoginView = false
    @State private var showSignUpView = false

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image("mfp logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 122, height: 122)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)

                        VStack(spacing: 8) {
                            Text("MyFitPlate")
                                .appFont(size: 38, weight: .bold)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.center)

                            Text("Nutrition, training, hydration, and Maia coaching in one daily command center.")
                                .appFont(size: 16)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 44)

                    VStack(spacing: 12) {
                        WelcomeFeatureRow(icon: "fork.knife", title: "Log meals faster", subtitle: "Search, scan, describe, or use your camera.", color: .brandPrimary)
                        WelcomeFeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Understand your trends", subtitle: "Reports turn daily logs into useful guidance.", color: .orange)
                        WelcomeFeatureRow(icon: "sparkles", title: "Coach with Maia", subtitle: "Ask for meal ideas, macro help, and nutrition estimates.", color: .purple)
                    }

                    VStack(spacing: 16) {
                        Button("Create an Account") {
                            showSignUpView = true
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("I Already Have an Account") {
                            showLoginView = true
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Text("Your data stays tied to your account so your plan follows you.")
                            .appFont(size: 12)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 34)
            }
        }
        .sheet(isPresented: $showLoginView) {
            LoginView()
        }
        .sheet(isPresented: $showSignUpView) {
            SignUpView()
        }
    }
}

struct AnimatedBackgroundView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            
            // Glowing orbs for a dynamic mesh-like feel
            Circle()
                .fill(Color.brandPrimary.opacity(0.5))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animate ? 120 : -100, y: animate ? -200 : 150)
            
            Circle()
                .fill(Color.purple.opacity(0.5))
                .frame(width: 350, height: 350)
                .blur(radius: 90)
                .offset(x: animate ? -120 : 150, y: animate ? 250 : -100)
            
            Circle()
                .fill(Color.blue.opacity(0.4))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: animate ? 50 : -150, y: animate ? -100 : 100)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

private struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
