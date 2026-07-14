import SwiftUI

struct WelcomeView: View {
    @State private var showLoginView = false
    @State private var showSignUpView = false

    private let features = [
        WelcomeFeature(
            icon: "square.and.arrow.down",
            title: "Bring your history",
            subtitle: "Import MyFitnessPal diary and weight data after setup.",
            color: AppPalette.brand
        ),
        WelcomeFeature(
            icon: "checkmark.seal.fill",
            title: "Know what to trust",
            subtitle: "Review food sources, correct nutrition, and keep the better match.",
            color: .accentProtein
        ),
        WelcomeFeature(
            icon: "figure.run",
            title: "Fuel the work",
            subtitle: "Connect meals, recovery, lifting, and runs in one daily view.",
            color: .accentSignal
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Nutrition you can inspect",
                    title: "MyFitPlate",
                    subtitle: "A food log you can trust, built for people who train."
                ) {
                    Image("mfp logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                        .accessibilityHidden(true)
                }
                .padding(.top, AppSpacing.section)

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(
                        title: "Start with evidence",
                        subtitle: "Your plan stays useful because every signal has a source."
                    )

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
                }

                Text("Your nutrition, training, and wellness data stay attached to your account so your plan follows you between devices.")
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
                createAccount: { showSignUpView = true },
                signIn: { showLoginView = true }
            )
        }
        .background(AppPalette.canvas.ignoresSafeArea())
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
    let createAccount: () -> Void
    let signIn: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    createButton
                    signInButton
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    signInButton
                    createButton
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
        .overlay(alignment: .top) { Divider() }
    }

    private var createButton: some View {
        Button(action: createAccount) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Create account")
            } else {
                Label("Create account", systemImage: "person.badge.plus")
            }
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .accessibilityIdentifier("welcome_create_account")
    }

    private var signInButton: some View {
        Button(action: signIn) {
            Text("Sign in")
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .accessibilityIdentifier("welcome_sign_in")
    }
}
