import SwiftUI

struct WelcomeView: View {
    @State private var showLoginView = false
    @State private var onboardingPresentation: OnboardingPresentation?
    @State private var savedDraft: OnboardingProfileDraft?

    private enum OnboardingPresentation: Identifiable {
        case start
        case resume(OnboardingProfileDraft)

        var id: String {
            switch self {
            case .start: return "start"
            case .resume: return "resume"
            }
        }
    }

    private let features = [
        WelcomeFeature(
            icon: "target",
            title: "A plan built around you",
            subtitle: "Answer a few questions and get calorie and protein targets in about a minute.",
            color: AppPalette.brand
        ),
        WelcomeFeature(
            icon: "barcode.viewfinder",
            title: "Log in seconds",
            subtitle: "Search, scan a barcode, or snap a meal. You review every estimate before it's saved.",
            color: .accentProtein
        ),
        WelcomeFeature(
            icon: "square.and.arrow.down",
            title: "Bring your history",
            subtitle: "Import your MyFitnessPal diary and weight history after setup.",
            color: .accentSignal
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Nutrition for people who train",
                    title: "MyFitPlate",
                    subtitle: "Hit your targets, fuel your training, and trust the numbers you log."
                ) {
                    MyFitPlateLaunchMark()
                        .accessibilityHidden(true)
                }
                .padding(.top, AppSpacing.section)

                if let savedDraft {
                    resumeCard(savedDraft)
                }

                VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.element.title) { index, feature in
                        WelcomeFeatureRow(feature: feature)

                        if index < features.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .appSurface(.emphasized, padding: 0)

                Text("No account needed until you save your plan. Your nutrition, training, and wellness data then stay with your account on every device.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, AppSpacing.compact)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.bottom, AppSpacing.section)
        }
        .safeAreaInset(edge: .bottom) {
            WelcomeActions(
                getStarted: { onboardingPresentation = .start },
                signIn: { showLoginView = true }
            )
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .onAppear(perform: loadSavedDraft)
        .sheet(isPresented: $showLoginView) {
            LoginView()
        }
        .fullScreenCover(item: $onboardingPresentation, onDismiss: loadSavedDraft) { presentation in
            switch presentation {
            case .start:
                OnboardingFlowView(context: .beforeAccount, onClose: { onboardingPresentation = nil })
            case .resume(let draft):
                OnboardingFlowView(
                    context: .beforeAccount,
                    prefill: draft,
                    startingPoint: .reveal,
                    onClose: { onboardingPresentation = nil }
                )
            }
        }
    }

    private func resumeCard(_ draft: OnboardingProfileDraft) -> some View {
        let plan = OnboardingPlanRules.plan(for: draft)
        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppListRow(
                icon: "checkmark.seal.fill",
                iconColor: AppPalette.brandText,
                title: "Your plan is waiting",
                subtitle: "\(Int(plan.dailyCalories.rounded()).formatted()) calories and \(Int(plan.proteinGrams.rounded()).formatted()) g protein a day"
            )

            Button("Continue where you left off") {
                onboardingPresentation = .resume(draft)
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityIdentifier("welcome_resume_plan")
        }
        .appSurface(.interpreted)
    }

    private func loadSavedDraft() {
        savedDraft = AccountSetupCoordinator.shared.store.loadDraft()
    }
}

struct AnimatedBackgroundView: View {
    var body: some View {
        AppPalette.canvas.ignoresSafeArea()
    }
}

private struct WelcomeFeature {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
}

private struct WelcomeFeatureRow: View {
    let feature: WelcomeFeature

    var body: some View {
        AppListRow(
            icon: feature.icon,
            iconColor: feature.color,
            title: feature.title,
            subtitle: feature.subtitle
        )
    }
}

private struct WelcomeActions: View {
    let getStarted: () -> Void
    let signIn: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.compact) {
            Button(action: getStarted) {
                Label("Get started", systemImage: "arrow.right")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("welcome_get_started")

            Button("I already have an account", action: signIn)
                .buttonStyle(AppActionButtonStyle(.ghost))
                .accessibilityIdentifier("welcome_sign_in")
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
        .overlay(alignment: .top) { Divider() }
    }
}
