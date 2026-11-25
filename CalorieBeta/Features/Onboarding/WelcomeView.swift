import SwiftUI

struct WelcomeView: View {
    @State private var showLoginView = false
    @State private var onboardingPresentation: OnboardingPresentation?
    @State private var savedDraft: OnboardingProfileDraft?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum OnboardingPresentation: Identifiable {
        case start
        case resume(OnboardingProfileDraft)
        var id: String {
            switch self {
            case .start: "start"
            case .resume: "resume"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                OnboardingBrandHeader()
                OnboardingHeadline(
                    eyebrow: "Food + training, together",
                    title: "Good food.\nStrong days.",
                    subtitle: "Plan your meals. Build your strength. Find what works for you."
                )
                if let savedDraft {
                    resumeCard(savedDraft)
                } else {
                    FirstLookPreview(kind: .day)
                }
                Label("Build your plan before creating an account.", systemImage: "lock.shield")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            OnboardingActionDock {
                Button {
                    if let savedDraft { onboardingPresentation = .resume(savedDraft) } else { onboardingPresentation = .start }
                } label: {
                    Label(savedDraft == nil ? "Build my plan" : "Continue my plan", systemImage: "arrow.right")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("welcome_get_started")
                Button("Already a member? Sign in") { showLoginView = true }
                    .buttonStyle(OnboardingTextButtonStyle())
                    .accessibilityIdentifier("welcome_sign_in")
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .onAppear(perform: loadSavedDraft)
        .sheet(isPresented: $showLoginView) { LoginView() }
        .fullScreenCover(item: $onboardingPresentation, onDismiss: loadSavedDraft) { presentation in
            switch presentation {
            case .start:
                OnboardingFlowView(context: .beforeAccount, onClose: { onboardingPresentation = nil })
            case .resume(let draft):
                OnboardingFlowView(context: .beforeAccount, prefill: draft, startingPoint: .reveal,
                                   onClose: { onboardingPresentation = nil })
            }
        }
    }

    private func resumeCard(_ draft: OnboardingProfileDraft) -> some View {
        let plan = OnboardingPlanRules.plan(for: draft)
        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("Your plan is waiting", systemImage: "checkmark.circle.fill")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.brandText)
            Text("\(Int(plan.dailyCalories.rounded()).formatted()) cal and \(Int(plan.proteinGrams.rounded()).formatted()) g protein a day")
                .appTextRole(.body)
            Button("Start fresh") {
                AccountSetupCoordinator.shared.store.clearDraft()
                OnboardingQuizProgressStore(userID: DIContainer.shared.authService.currentUserID).clear()
                savedDraft = nil
                onboardingPresentation = .start
            }
                .buttonStyle(OnboardingTextButtonStyle())
                .accessibilityIdentifier("welcome_start_fresh")
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("welcome_resume_plan")
    }

    private func loadSavedDraft() { savedDraft = AccountSetupCoordinator.shared.store.loadDraft() }
}

struct AnimatedBackgroundView: View {
    var body: some View { AppPalette.canvas.ignoresSafeArea() }
}

/// Shared first-run chrome keeps the welcome, forms and introduction visually connected.
struct OnboardingBrandHeader: View {
    var body: some View {
        HStack(spacing: AppSpacing.row) {
            MyFitPlateLaunchMark(compact: true).accessibilityHidden(true)
            Text("MyFitPlate").appTextRole(.control)
        }
    }
}

struct OnboardingHeadline: View {
    var eyebrow: String?
    let title: String
    let subtitle: String
    var role: AppTextRole = .display
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let eyebrow, !dynamicTypeSize.isAccessibilitySize {
                Text(eyebrow.uppercased()).appTextRole(.caption).tracking(1.1)
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(title).appTextRole(role).foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .task(id: title) { isTitleFocused = true }
            Text(subtitle).appTextRole(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingActionDock<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: AppSpacing.compact) { content }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.row)
            .background(AppPalette.canvas)
            .overlay(alignment: .top) { Divider() }
    }
}

enum FirstLookPreviewKind { case day, food, training, adapt }

/// A clearly labelled product illustration, using the same content tiles as the app.
/// It is deliberately not a fake interactive dashboard or a promise about the user's data.
struct FirstLookPreview: View {
    let kind: FirstLookPreviewKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack {
                Text(title).appTextRole(.control)
                Spacer(minLength: AppSpacing.compact)
                Text("Example").appTextRole(.caption).foregroundStyle(.secondary)
            }
            Divider()
            switch kind {
            case .day:
                contentRow(emoji: "🥗", title: "Lunch, logged", detail: "Chicken grain bowl", value: "520 cal · 38 g protein")
                Divider()
                contentRow(emoji: "🏋️", title: "Your next workout", detail: "Upper body", value: "35 min · 4 exercises")
            case .food:
                contentRow(emoji: "🥗", title: "Chicken grain bowl", detail: "Photo estimate · 1 bowl", value: "520 cal · 38 g protein")
                Label("Review the portion. Then make it yours.", systemImage: "slider.horizontal.3")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            case .training:
                contentRow(emoji: "🏋️", title: "Dumbbell bench press", detail: "Set 2 of 3", value: "55 lb × 10 reps")
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index < 2 ? AppPalette.effort : AppPalette.control).frame(height: 6)
                    }
                }.accessibilityHidden(true)
                Text("Your last session is right beside your next set.").appTextRole(.secondary).foregroundStyle(.secondary)
            case .adapt:
                Label("Only 20 minutes today?", systemImage: "clock")
                    .appTextRole(.sectionTitle)
                HStack(spacing: AppSpacing.row) {
                    Text("Full session").foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                    Text("A shorter plan").foregroundStyle(AppPalette.text)
                }.appTextRole(.body)
                Text("Preview the changes. Keep your progress.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var title: String {
        switch kind {
        case .day: "A day in MyFitPlate"
        case .food: "From photo to food log"
        case .training: "A little stronger, together"
        case .adapt: "Rescue my week"
        }
    }

    private var accessibilitySummary: String {
        switch kind {
        case .day: "Example day: a chicken grain bowl logged for lunch, followed by a 35-minute upper-body workout."
        case .food: "Example meal review: a chicken grain bowl estimated at 520 calories and 38 grams of protein. Adjust the portion before saving."
        case .training: "Example workout: dumbbell bench press, set 2 of 3, 55 pounds for 10 repetitions."
        case .adapt: "Example plan adjustment: preview a shorter workout when you have 20 minutes, while keeping your progress."
        }
    }

    private func contentRow(emoji: String, title: String, detail: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text(emoji).font(.system(size: 44))
                    .frame(width: 56, height: 60)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).appTextRole(.control)
                Text(detail).appTextRole(.secondary).foregroundStyle(.secondary)
                Text(value).appTextRole(.body).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct OnboardingTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 17, weight: .semibold)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.compact)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
            .foregroundStyle(AppPalette.text)
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.6 : 1)
    }
}
