import SwiftUI

private enum FeatureTourPreviewKind {
    case maia
    case camera
    case training
    case wellness
    case mealPlan
}

struct FeatureTourView: View {
    @Binding var isPresented: Bool
    @State private var selection: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct FeatureInfo {
        let preview: FeatureTourPreviewKind
        let iconName: String
        let eyebrow: String
        let title: String
        let description: String
        let detail: String
        let color: Color
    }

    private let features: [FeatureInfo] = [
        FeatureInfo(
            preview: .maia,
            iconName: "sparkles",
            eyebrow: "Ask and act",
            title: "Meet Maia",
            description: "Use AI guidance to ask about your day, log food conversationally, and compare practical next steps.",
            detail: "Maia uses the context you choose to share and labels estimates for review.",
            color: AppPalette.achievement
        ),
        FeatureInfo(
            preview: .camera,
            iconName: "camera.viewfinder",
            eyebrow: "Review first",
            title: "Snap and log",
            description: "Photograph a meal or nutrition label, then review the estimated calories, macros, and serving before logging.",
            detail: "Image results remain estimates until you confirm them.",
            color: AppPalette.caution
        ),
        FeatureInfo(
            preview: .training,
            iconName: "dumbbell.fill",
            eyebrow: "Train with context",
            title: "Plan the work",
            description: "Build training programs, track sets, review sessions, and keep the next workout close at hand.",
            detail: "Nutrition and recovery remain visible beside training progress.",
            color: AppPalette.effort
        ),
        FeatureInfo(
            preview: .wellness,
            iconName: "heart.text.square.fill",
            eyebrow: "Read the signals",
            title: "Debrief your day",
            description: "Bring nutrition, sleep, and recovery signals into one wellness debrief without hiding where each signal came from.",
            detail: "Scores summarize available data; they are guidance, not medical advice.",
            color: .accentPositive
        ),
        FeatureInfo(
            preview: .mealPlan,
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
                    .foregroundStyle(AppPalette.brandText)
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
                FeatureTourPreview(
                    kind: feature.preview,
                    iconName: feature.iconName,
                    tint: feature.color
                )

                AppScreenHeader(
                    eyebrow: feature.eyebrow,
                    title: feature.title,
                    subtitle: dynamicTypeSize.isAccessibilitySize
                        ? accessibilityDescription(for: feature)
                        : feature.description
                )

                if !dynamicTypeSize.isAccessibilitySize {
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
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
    }

    private func accessibilityDescription(for feature: FeatureInfo) -> String {
        switch feature.preview {
        case .maia:
            "Ask for one practical next step and review every action before it changes your log."
        case .camera:
            "Photograph a meal or label, then correct the estimate before logging."
        case .training:
            "Plan workouts, track sets, and review recovery in one place."
        case .wellness:
            "See which nutrition, sleep, and recovery signals support today's debrief."
        case .mealPlan:
            "Build an editable seven-day plan and grouped grocery list."
        }
    }
}

private struct FeatureTourPreview: View {
    let kind: FeatureTourPreviewKind
    let iconName: String
    let tint: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(spacing: AppSpacing.row) {
                Image(systemName: iconName)
                    .appFont(size: 21, weight: .bold)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(previewEyebrow)
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Text(previewTitle)
                        .appFont(size: 17, weight: .semibold)
                        .foregroundStyle(AppPalette.text)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)

                    Text(previewStatus)
                        .appFont(size: 11, weight: .bold)
                        .foregroundStyle(tint)
                        .padding(.horizontal, AppSpacing.compact)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.10), in: Capsule())
                }
            }

            Divider()

            if dynamicTypeSize.isAccessibilitySize {
                Text(accessibilitySummary)
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                previewContent
            }
        }
        .padding(AppSpacing.group)
        .frame(
            maxWidth: .infinity,
            minHeight: dynamicTypeSize.isAccessibilitySize ? 178 : 218,
            alignment: .topLeading
        )
        .background(
            AppPalette.surface,
            in: RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var accessibilitySummary: String {
        switch kind {
        case .maia: "Maia identifies a useful gap, explains why, and offers a reviewable action."
        case .camera: "Estimated identity, portion, and nutrition stay editable before logging."
        case .training: "The current exercise, set target, and completion control stay together."
        case .wellness: "Missing signals remain visible instead of being treated as zero."
        case .mealPlan: "Every generated day stays editable before it becomes your week."
        }
    }

    private var previewEyebrow: String {
        switch kind {
        case .maia: return "MAIA CONTEXT"
        case .camera: return "ESTIMATE REVIEW"
        case .training: return "UPPER A"
        case .wellness: return "TODAY'S SIGNALS"
        case .mealPlan: return "YOUR WEEK"
        }
    }

    private var previewTitle: String {
        switch kind {
        case .maia: return "A useful next move"
        case .camera: return "Chicken grain bowl"
        case .training: return "Set 3 of 12"
        case .wellness: return "Ready, with context"
        case .mealPlan: return "Dinner is handled"
        }
    }

    private var previewStatus: String {
        switch kind {
        case .maia: return "ACTION"
        case .camera: return "REVIEW"
        case .training: return "LIVE"
        case .wellness: return "DEBRIEF"
        case .mealPlan: return "7 DAYS"
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch kind {
        case .maia:
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text("Protein is the clearest gap. A yogurt bowl or chicken wrap fits the rest of today.")
                    .appFont(size: 15)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppSpacing.compact) {
                    previewChip("Compare meals", icon: "arrow.left.arrow.right")
                    previewChip("Log it", icon: "plus")
                }
            }

        case .camera:
            VStack(spacing: AppSpacing.row) {
                HStack(spacing: AppSpacing.group) {
                    Image(systemName: "viewfinder")
                        .appFont(size: 28, weight: .bold)
                        .foregroundStyle(tint)
                        .frame(width: 76, height: 66)
                        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        miniMetric(label: "Calories", value: "520")
                        miniMetric(label: "Protein", value: "38 g")
                        miniMetric(label: "Serving", value: "1 bowl")
                    }
                }

                Label("Estimate stays editable before it reaches your log.", systemImage: "slider.horizontal.3")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
            }

        case .training:
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dumbbell Bench Press")
                            .appFont(size: 17, weight: .semibold)
                            .foregroundStyle(AppPalette.text)
                        Text("8-12 reps")
                            .appFont(size: 11, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("2 / 4 sets")
                        .appFont(size: 11, weight: .bold)
                        .foregroundStyle(tint)
                }

                ProgressView(value: 0.5)
                    .tint(tint)

                HStack(spacing: AppSpacing.compact) {
                    trainingValue("55", label: "LB")
                    trainingValue("10", label: "REPS")
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle")
                        .appFont(size: 28, weight: .bold)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }

        case .wellness:
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                HStack(spacing: AppSpacing.compact) {
                    signalMetric("Sleep", value: "7h 42m", icon: "moon.fill")
                    signalMetric("Recovery", value: "Steady", icon: "heart.fill")
                    signalMetric("Fuel", value: "On track", icon: "fork.knife")
                }

                Label("Your score shows what changed and which signals are missing.", systemImage: "scope")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .mealPlan:
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { day in
                        VStack(spacing: 5) {
                            Text(["M", "T", "W", "T", "F", "S", "S"][day])
                                .appFont(size: 11, weight: .semibold)
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(day == 2 ? tint : tint.opacity(day < 5 ? 0.32 : 0.10))
                                .frame(width: 20, height: 20)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    Label("Chicken primavera", systemImage: "fork.knife")
                        .appFont(size: 15)
                        .foregroundStyle(AppPalette.text)
                    Spacer()
                    Text("610 cal")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                }

                Label("14 grocery items grouped by aisle", systemImage: "cart.fill")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(tint)
            }
        }
    }

    private func previewChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .appFont(size: 11, weight: .semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.compact)
            .frame(minHeight: 34)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private func miniMetric(label: String, value: String) -> some View {
        HStack(spacing: AppSpacing.compact) {
            Text(label)
                .appFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .appFont(size: 17, weight: .semibold)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
        }
    }

    private func trainingValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .appFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(size: 21, weight: .bold)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
        }
        .padding(.horizontal, AppSpacing.row)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }

    private func signalMetric(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .appFont(size: 17, weight: .semibold)
                .foregroundStyle(AppPalette.text)
                .lineLimit(2)
            Text(label)
                .appFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.compact)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
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
