import SwiftUI

struct FeatureTourView: View {
    @Binding var isPresented: Bool
    @State private var selection: Int

    private struct FeatureInfo {
        let iconName: String
        let eyebrow: String
        let title: String
        let description: String
        let detail: String
        let color: Color
    }

    private let features: [FeatureInfo] = [
        FeatureInfo(
            iconName: "sparkles",
            eyebrow: "Ask and act",
            title: "Meet Maia",
            description: "Use AI guidance to ask about your day, log food conversationally, and compare practical next steps.",
            detail: "Maia uses the context you choose to share and labels estimates for review.",
            color: AppPalette.achievement
        ),
        FeatureInfo(
            iconName: "camera.viewfinder",
            eyebrow: "Review first",
            title: "Snap and log",
            description: "Photograph a meal or nutrition label, then review the estimated calories, macros, and serving before logging.",
            detail: "Image results remain estimates until you confirm them.",
            color: AppPalette.caution
        ),
        FeatureInfo(
            iconName: "dumbbell.fill",
            eyebrow: "Train with context",
            title: "Plan the work",
            description: "Build training programs, track sets, review sessions, and keep the next workout close at hand.",
            detail: "Nutrition and recovery remain visible beside training progress.",
            color: AppPalette.effort
        ),
        FeatureInfo(
            iconName: "heart.text.square.fill",
            eyebrow: "Read the signals",
            title: "Debrief your day",
            description: "Bring nutrition, sleep, and recovery signals into one wellness debrief without hiding where each signal came from.",
            detail: "Scores summarize available data; they are guidance, not medical advice.",
            color: .accentPositive
        ),
        FeatureInfo(
            iconName: "calendar.badge.clock",
            eyebrow: "Look ahead",
            title: "Plan meals together",
            description: "Create a seven-day meal plan and turn it into a grocery list shaped around your goals and preferences.",
            detail: "Every generated plan stays editable before it becomes your week.",
            color: .accentSignal
        )
    ]

    init(isPresented: Binding<Bool>, initialSelection: Int = 0) {
        _isPresented = isPresented
        _selection = State(initialValue: min(max(initialSelection, 0), 4))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("First look")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)
                    Text("\(selection + 1) of \(features.count)")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Button("Skip") { isPresented = false }
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.brand)
                    .accessibilityIdentifier("feature_tour_skip")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.row)

            ProgressView(value: Double(selection + 1), total: Double(features.count))
                .tint(AppPalette.brand)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.bottom, AppSpacing.row)

            Divider()

            TabView(selection: $selection) {
                ForEach(features.indices, id: \.self) { index in
                    featurePage(features[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(AppMotion.standard, value: selection)
        }
        .safeAreaInset(edge: .bottom) {
            FeatureTourActions(
                selection: $selection,
                count: features.count,
                finish: { isPresented = false }
            )
        }
        .background(AppPalette.canvas.ignoresSafeArea())
    }

    private func featurePage(_ feature: FeatureInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                Image(systemName: feature.iconName)
                    .appTextRole(.display)
                    .foregroundStyle(feature.color)
                    .frame(width: 80, height: 80)
                    .background(feature.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
                    .accessibilityHidden(true)

                AppScreenHeader(
                    eyebrow: feature.eyebrow,
                    title: feature.title,
                    subtitle: feature.description
                )

                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(feature.color)
                        .accessibilityHidden(true)
                    Text(feature.detail)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appSurface(.quiet)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
    }
}

private struct FeatureTourActions: View {
    @Binding var selection: Int
    let count: Int
    let finish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    nextButton
                    if selection > 0 { backButton }
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    if selection > 0 { backButton }
                    nextButton
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
        .overlay(alignment: .top) { Divider() }
    }

    private var nextButton: some View {
        Button {
            if selection == count - 1 {
                finish()
            } else {
                withAnimation(AppMotion.standard) { selection += 1 }
            }
        } label: {
            Text(nextTitle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .accessibilityLabel(nextTitle)
        .accessibilityIdentifier("feature_tour_next")
    }

    private var nextTitle: String {
        selection == count - 1 ? "Open MyFitPlate" : "Next"
    }

    private var backButton: some View {
        Button("Back") {
            withAnimation(AppMotion.standard) { selection -= 1 }
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
    }
}
