import SwiftUI

struct LandingPageView: View {
    @EnvironmentObject private var appState: AppState
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Spacer()

            Image("mfp logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
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
