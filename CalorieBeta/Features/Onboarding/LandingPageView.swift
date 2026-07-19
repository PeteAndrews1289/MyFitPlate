import SwiftUI

struct LandingPageView: View {
    @EnvironmentObject private var appState: AppState
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Spacer()

            MyFitPlateLaunchMark(treatment: .launch)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("MYFITPLATE")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.launchForeground.opacity(0.82))

                Text(errorMessage == nil ? "Preparing your day" : "We couldn't load your account")
                    .appTextRole(.display)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(errorMessage ?? "Loading your goals, recent meals, and training context.")
                    .appTextRole(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if errorMessage == nil {
                ProgressView()
                    .tint(AppPalette.launchForeground)
                    .accessibilityLabel("Loading account")
            } else {
                Button("Try again", action: loadData)
                    .buttonStyle(AppActionButtonStyle(.primary))
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.launchBackground.ignoresSafeArea())
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
    enum Treatment {
        case standard
        case launch
    }

    let treatment: Treatment

    init(treatment: Treatment = .standard) {
        self.treatment = treatment
    }

    var body: some View {
        Text("MFP")
            .font(.system(size: 25, weight: .bold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .frame(width: 76, height: 76)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
            )
    }

    private var foregroundColor: Color {
        treatment == .launch ? AppPalette.launchBackground : AppPalette.launchForeground
    }

    private var backgroundColor: Color {
        treatment == .launch ? AppPalette.launchForeground : AppPalette.launchBackground
    }
}
