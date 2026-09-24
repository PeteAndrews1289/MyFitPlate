import SwiftUI

/// Shows the targets a quiz draft produces before anything is saved. The numbers come from the
/// same rules `GoalSettings` applies, so the plan someone accepts is the plan their account gets.
struct PlanRevealView: View {
    let draft: OnboardingProfileDraft
    let primaryActionTitle: String
    let onContinue: () -> Void
    let onEditAnswers: () -> Void

    @AppStorage(BodyUnits.preferenceKey) private var useMetric = Locale.current.measurementSystem != .us
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var plan: OnboardingPlan {
        OnboardingPlanRules.plan(for: draft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Your plan",
                    title: "Your plan is ready",
                    subtitle: "Built from your answers. You can change any part of it later in Settings."
                )

                dailyTarget
                projectionCard
                methodCard

                Text("These are estimates to guide you, not medical advice.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .safeAreaInset(edge: .bottom) {
            actions
        }
        .background(AppPalette.canvas.ignoresSafeArea())
    }

    private var dailyTarget: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Daily target")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    calorieValue
                    calorieUnit
                }
                VStack(alignment: .leading, spacing: 2) {
                    calorieValue
                    calorieUnit
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Self.whole(plan.dailyCalories)) calories a day")

            AppMetricStrip(items: [
                AppMetricItem(label: "Protein", value: "\(Self.whole(plan.proteinGrams)) g", accent: AppPalette.protein),
                AppMetricItem(label: "Carbs", value: "\(Self.whole(plan.carbsGrams)) g", accent: AppPalette.carbohydrate),
                AppMetricItem(label: "Fat", value: "\(Self.whole(plan.fatGrams)) g", accent: AppPalette.fat)
            ])
        }
        .appSurface(.emphasized)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan_reveal_daily_target")
    }

    private var calorieValue: some View {
        Text(Self.whole(plan.dailyCalories))
            .appTextRole(.display)
            .foregroundStyle(AppPalette.text)
            .monospacedDigit()
    }

    private var calorieUnit: some View {
        Text("calories a day")
            .appTextRole(.control)
            .foregroundStyle(.secondary)
    }

    private var projectionCard: some View {
        let content = projectionContent
        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label(content.title, systemImage: content.icon)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(content.detail)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if plan.isMinimumCalorieFloorApplied, plan.projection != .noEstimate {
                Text(minimumFloorNote)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.interpreted)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan_reveal_projection")
    }

    private var projectionContent: (icon: String, title: String, detail: String) {
        switch plan.projection {
        case let .reachTarget(date, _):
            return (
                "calendar",
                "Reach \(weightText(draft.targetWeightLbs)) around \(date.formatted(.dateTime.month(.wide).year()))",
                "\(paceSentence) Your targets update as your weight changes."
            )
        case let .milestone(date, _, change):
            let direction = change < 0 ? "lighter" : "heavier"
            return (
                "flag",
                "About \(weightText(abs(change))) \(direction) by \(date.formatted(.dateTime.month(.abbreviated).day()))",
                "\(paceSentence) Reaching \(weightText(draft.targetWeightLbs)) takes longer, and your targets update as your weight changes."
            )
        case .maintain:
            return (
                "equal.circle",
                "Hold steady around \(weightText(draft.currentWeightLbs))",
                "Your target matches what you burn on a typical day, so your weight should stay about the same."
            )
        case .atTarget:
            return (
                "checkmark.circle",
                "You're already at your target",
                "This plan is built to help you stay there."
            )
        case .noEstimate:
            return (
                "info.circle",
                "Your plan starts at the minimum",
                "\(minimumFloorNote) That leaves no reliable pace to estimate a date yet."
            )
        }
    }

    private var methodCard: some View {
        VStack(spacing: 0) {
            AppListRow(
                icon: "function",
                iconColor: AppPalette.brandText,
                title: "Energy estimate",
                subtitle: "Mifflin-St Jeor with your activity level: about \(Self.whole(plan.maintenanceCalories)) calories a day to maintain."
            )
            Divider().padding(.leading, 68)
            if draft.goal != .maintain {
                AppListRow(
                    icon: "gauge.with.dots.needle.33percent",
                    iconColor: AppPalette.brandText,
                    title: "Your pace",
                    subtitle: paceRowSubtitle
                )
                Divider().padding(.leading, 68)
            }
            AppListRow(
                icon: "chart.pie",
                iconColor: AppPalette.brandText,
                title: "Macro split",
                subtitle: "30% protein, 50% carbs, and 20% fat. You can adjust it in Settings."
            )
            Divider().padding(.leading, 68)
            AppListRow(
                icon: "arrow.triangle.2.circlepath",
                iconColor: AppPalette.brandText,
                title: "Keeps up with you",
                subtitle: "Weigh-ins update your targets. Once you've logged for a few weeks, adaptive targets can follow your real trend."
            )
        }
        .appSurface(.emphasized, padding: 0)
    }

    private var actions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    continueButton
                    editButton
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    editButton
                    continueButton
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
        .overlay(alignment: .top) { Divider() }
    }

    private var continueButton: some View {
        Button(primaryActionTitle, action: onContinue)
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("plan_reveal_continue")
    }

    private var editButton: some View {
        Button("Edit answers", action: onEditAnswers)
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityIdentifier("plan_reveal_edit")
    }

    private var minimumFloorNote: String {
        let floor = draft.sex.lowercased() == "male" ? "1,500" : "1,200"
        return "MyFitPlate never sets a target below \(floor) calories a day."
    }

    /// Uses the achieved pace, which can be slower than the chosen one at the calorie floor.
    private var paceSentence: String {
        let weekly = abs(plan.weeklyChangeLbs)
        let pace = GoalSettingsRules.weeklyChangeText(lbs: weekly, metric: useMetric)
        switch (draft.goal, weekly) {
        case (.gain, ..<0.4):
            return "That's about \(pace), a lean pace that limits fat gain."
        case (.gain, ...0.6):
            return "That's about \(pace), a steady pace for building muscle."
        case (.gain, _):
            return "That's about \(pace), a fast pace that adds some extra fat."
        case (_, ...0.6):
            return "That's about \(pace), a steady pace most people can keep up."
        case (_, ...1.1):
            return "That's about \(pace), a common pace for steady progress."
        default:
            return "That's about \(pace), a fast pace. Watch your hunger, sleep, and training energy."
        }
    }

    private var paceRowSubtitle: String {
        let difference = Self.whole(abs(plan.dailyCalories - plan.maintenanceCalories))
        let direction = draft.goal == .gain ? "above" : "below"
        let chosen = GoalSettingsRules.weeklyChangeText(lbs: draft.weeklyChangeLbs, metric: useMetric)
        return "\(chosen.prefix(1).uppercased() + chosen.dropFirst()): about \(difference) calories a day \(direction) maintenance. You can change it in Settings."
    }

    private func weightText(_ lbs: Double) -> String {
        let value = BodyUnits.weightDisplayValue(lbs: lbs, metric: useMetric)
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(BodyUnits.weightUnit(metric: useMetric))"
    }

    private static func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}
