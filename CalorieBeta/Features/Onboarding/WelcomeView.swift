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

                            Text("A food log you can trust, built for training days.")
                                .appFont(size: 16)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 44)

                    VStack(spacing: 12) {
                        WelcomeFeatureRow(icon: "square.and.arrow.down", title: "Switch without starting over", subtitle: "Import MyFitnessPal diary and weight history.", color: .brandPrimary)
                        WelcomeFeatureRow(icon: "checkmark.seal.fill", title: "Trust every entry", subtitle: "Barcode matches can be checked, corrected, and remembered.", color: .accentProtein)
                        WelcomeFeatureRow(icon: "figure.run", title: "Fuel your training", subtitle: "Maia links food, recovery, lifting, and runs.", color: .accentSignal)
                    }

                    VStack(spacing: 16) {
                        Button("Create account") {
                            showSignUpView = true
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Sign in") {
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
    var body: some View {
        Color.backgroundPrimary.ignoresSafeArea()
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
                .appFont(size: 18, weight: .bold)
                .foregroundColor(color)
                .frame(width: 42, height: 42)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
