import SwiftUI

struct LandingPageView: View {
    @EnvironmentObject private var appState: AppState
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Spacer()

            MyFitPlateLaunchMark()
                .accessibilityHidden(true)

            AppScreenHeader(
                eyebrow: "MyFitPlate",
                title: errorMessage == nil ? "Preparing your day" : "We couldn't load your account",
                subtitle: errorMessage ?? "Loading your goals, recent meals, and training context."
            )

            if errorMessage == nil {
                ProgressView()
                    .tint(AppPalette.brand)
                    .accessibilityLabel("Loading account")
            } else {
                Button("Try again", action: loadData)
                    .buttonStyle(AppActionButtonStyle(.secondary))
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("account_loading_screen")
        .onAppear(perform: loadData)
    }

    private func loadData() {
        guard DIContainer.shared.authService.currentUserID != nil else {
            errorMessage = "Your sign-in is no longer available. Return to sign in and try again."
            appState.setUserLoggedIn(false)
            return
        }
        errorMessage = nil
    }
}

struct MyFitPlateLaunchMark: View {
    var body: some View {
        Text("MFP")
            .font(.system(size: 25, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.66, green: 0.90, blue: 0.77))
            .frame(width: 76, height: 76)
            .background(
                Color(red: 0.07, green: 0.24, blue: 0.18),
                in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
            )
    }
}
