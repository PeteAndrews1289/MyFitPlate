import SwiftUI

/// Quiz, then plan reveal, then (when no account exists yet) account creation. Before sign-up the
/// flow only keeps its answers on the device; a signed-in account that never finished setup hands
/// the accepted plan back to the root view to save.
struct OnboardingFlowView: View {
    enum Context {
        case beforeAccount
        case signedIn
    }

    enum StartingPoint {
        case quiz(OnboardingSurveyView.Step)
        case reveal
        case account
    }

    let context: Context
    let onClose: (() -> Void)?
    let onAcceptPlan: ((OnboardingProfileDraft) -> Void)?

    @State private var stage: Stage
    @State private var draft: OnboardingProfileDraft?
    @State private var quizStartStep: OnboardingSurveyView.Step
    @State private var didLogStart = false

    private enum Stage {
        case quiz
        case reveal
        case account
    }

    init(
        context: Context,
        prefill: OnboardingProfileDraft? = nil,
        startingPoint: StartingPoint = .quiz(.goal),
        onClose: (() -> Void)? = nil,
        onAcceptPlan: ((OnboardingProfileDraft) -> Void)? = nil
    ) {
        self.context = context
        self.onClose = onClose
        self.onAcceptPlan = onAcceptPlan
        _draft = State(initialValue: prefill)

        switch startingPoint {
        case .quiz(let step):
            _stage = State(initialValue: .quiz)
            _quizStartStep = State(initialValue: step)
        case .reveal:
            _stage = State(initialValue: prefill == nil ? .quiz : .reveal)
            _quizStartStep = State(initialValue: .goal)
        case .account:
            _stage = State(initialValue: prefill == nil ? .quiz : .account)
            _quizStartStep = State(initialValue: .goal)
        }
    }

    var body: some View {
        NavigationStack {
            stageContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let leadingAction {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(leadingAction.title, action: leadingAction.perform)
                                .accessibilityIdentifier(leadingAction.identifier)
                        }
                    }
                }
                .toolbar(leadingAction.map { _ in Visibility.visible } ?? .hidden, for: .navigationBar)
        }
        .onAppear(perform: logStartIfNeeded)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .quiz:
            OnboardingSurveyView(initialStep: quizStartStep, prefill: draft) { newDraft in
                draft = newDraft
                DIContainer.shared.analyticsManager?.logEvent(
                    ProductAnalytics.Event.onboardingPlanRevealed.rawValue,
                    parameters: nil
                )
                withAnimation(AppMotion.standard) { stage = .reveal }
            }
        case .reveal:
            if let draft {
                PlanRevealView(
                    draft: draft,
                    primaryActionTitle: context == .beforeAccount ? "Save my plan" : "Start my plan",
                    onContinue: { acceptPlan(draft) },
                    onEditAnswers: editAnswers
                )
            }
        case .account:
            if let draft {
                CreateAccountView(draft: draft)
            }
        }
    }

    private var leadingAction: (title: String, identifier: String, perform: () -> Void)? {
        switch (stage, context) {
        case (.quiz, .beforeAccount):
            guard let onClose else { return nil }
            return ("Close", "onboarding_close", onClose)
        case (.account, _):
            return ("Back", "create_account_back", { withAnimation(AppMotion.standard) { stage = .reveal } })
        default:
            return nil
        }
    }

    private func acceptPlan(_ draft: OnboardingProfileDraft) {
        switch context {
        case .beforeAccount:
            // Keep the answers on the device so a relaunch can resume from the plan.
            AccountSetupCoordinator.shared.store.saveDraft(draft)
            withAnimation(AppMotion.standard) { stage = .account }
        case .signedIn:
            onAcceptPlan?(draft)
        }
    }

    private func editAnswers() {
        quizStartStep = .goal
        withAnimation(AppMotion.standard) { stage = .quiz }
    }

    private func logStartIfNeeded() {
        guard context == .beforeAccount, !didLogStart else { return }
        didLogStart = true
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.onboardingStarted.rawValue, parameters: nil)
    }
}
