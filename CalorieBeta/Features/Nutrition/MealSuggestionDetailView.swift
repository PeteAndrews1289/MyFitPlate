import MyFitPlateCore
import SwiftUI

struct MealSuggestionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let suggestion: MealSuggestion
    var pantryItemNames: [String] = []
    var remainingCalories: Double?
    var remainingProtein: Double?
    var remainingCarbs: Double?
    var remainingFats: Double?
    var onLog: (MealSuggestion) -> Void
    var onRegenerate: (() -> Void)?
    var isRegenerating = false

    private var macroRows: [MealSuggestionMacroFitRow.Model] {
        [
            MealSuggestionMacroFitRow.Model(
                title: "Calories",
                planned: safe(suggestion.calories),
                target: MealSuggestionReviewRules.safeTarget(remainingCalories),
                unit: "cal",
                color: AppPalette.energy,
                tolerance: 75
            ),
            MealSuggestionMacroFitRow.Model(
                title: "Protein",
                planned: safe(suggestion.protein),
                target: MealSuggestionReviewRules.safeTarget(remainingProtein),
                unit: "g",
                color: .accentProtein,
                tolerance: 8
            ),
            MealSuggestionMacroFitRow.Model(
                title: "Carbs",
                planned: safe(suggestion.carbs),
                target: MealSuggestionReviewRules.safeTarget(remainingCarbs),
                unit: "g",
                color: .accentCarbs,
                tolerance: 12
            ),
            MealSuggestionMacroFitRow.Model(
                title: "Fat",
                planned: safe(suggestion.fats),
                target: MealSuggestionReviewRules.safeTarget(remainingFats),
                unit: "g",
                color: .accentFats,
                tolerance: 6
            )
        ]
    }

    private var fitSummary: String {
        MealSuggestionReviewRules.fitSummary(
            calories: suggestion.calories,
            remainingCalories: remainingCalories
        )
    }

    private var pantrySummary: String {
        MealSuggestionReviewRules.pantrySummary(
            ingredients: suggestion.ingredients,
            pantryNames: pantryItemNames
        )
    }

    private var substitutionGuidance: [String] {
        MealSuggestionReviewRules.substitutionGuidance(
            calories: suggestion.calories,
            protein: suggestion.protein,
            carbs: suggestion.carbs,
            ingredients: suggestion.ingredients,
            pantryNames: pantryItemNames,
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein,
            remainingCarbs: remainingCarbs
        )
    }

    private var instructionSteps: [String] {
        MealSuggestionReviewRules.instructionSteps(suggestion.instructions)
    }

    var body: some View {
        AppSheetScaffold(
            title: "Meal Suggestion",
            subtitle: "Review Maia's estimate against today's remaining targets.",
            dismiss: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    suggestionHeader
                    nutritionSummary
                    macroFitSection
                    pantrySection
                    substitutionSection
                    instructionsSection
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.section)
                .padding(.bottom, AppSpacing.section)
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(isRegenerating)
        .accessibilityIdentifier("meal_suggestion_detail_screen")
    }

    private var suggestionHeader: some View {
        AppScreenHeader(
            eyebrow: "Maia Estimate",
            title: suggestion.mealName,
            subtitle: fitSummary
        ) {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .accessibilityHidden(true)
                Text("AI Estimate")
            }
            .appTextRole(.caption)
            .foregroundStyle(AppPalette.caution)
            .padding(.horizontal, AppSpacing.row)
            .padding(.vertical, AppSpacing.compact)
            .background(
                AppPalette.caution.opacity(0.10),
                in: Capsule()
            )
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("meal_suggestion_header")
    }

    private var nutritionSummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(label: "Calories", value: "\(formatted(suggestion.calories)) cal", accent: AppPalette.energy),
            AppMetricItem(label: "Protein", value: "\(formatted(suggestion.protein)) g", accent: .accentProtein),
            AppMetricItem(label: "Carbs", value: "\(formatted(suggestion.carbs)) g", accent: .accentCarbs),
            AppMetricItem(label: "Fat", value: "\(formatted(suggestion.fats)) g", accent: .accentFats)
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("meal_suggestion_nutrition_summary")
    }

    private var macroFitSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Macro Fit",
                subtitle: "Estimated serving compared with today's remaining targets."
            )

            VStack(spacing: 0) {
                ForEach(Array(macroRows.enumerated()), id: \.element.id) { index, row in
                    MealSuggestionMacroFitRow(model: row)

                    if index < macroRows.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            }
        }
        .accessibilityIdentifier("meal_suggestion_macro_fit")
    }

    private var pantrySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Pantry Fit", subtitle: pantrySummary)

            if !suggestion.ingredients.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestion.ingredients.enumerated()), id: \.offset) { index, ingredient in
                        MealSuggestionIngredientRow(
                            ingredient: ingredient,
                            isPantryMatch: ingredientUsesPantry(ingredient),
                            hasPantryContext: hasPantryContext
                        )

                        if index < suggestion.ingredients.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
            }
        }
        .accessibilityIdentifier("meal_suggestion_pantry_fit")
    }

    private var substitutionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Adjust Before Logging",
                subtitle: "Use the serving you actually prepare."
            )

            VStack(spacing: 0) {
                ForEach(Array(substitutionGuidance.enumerated()), id: \.offset) { index, note in
                    AppListRow(
                        icon: "slider.horizontal.3",
                        iconColor: AppPalette.brand,
                        title: note
                    )

                    if index < substitutionGuidance.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var instructionsSection: some View {
        if !instructionSteps.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Preparation",
                    subtitle: "Maia-generated steps; verify doneness and food safety yourself."
                )

                VStack(spacing: 0) {
                    ForEach(Array(instructionSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            Text((index + 1).formatted())
                                .appTextRole(.caption)
                                .foregroundStyle(AppPalette.brand)
                                .frame(width: 28, height: 28)
                                .background(
                                    AppPalette.brand.opacity(0.10),
                                    in: Circle()
                                )
                                .accessibilityHidden(true)

                            Text(step)
                                .appTextRole(.body)
                                .foregroundStyle(AppPalette.text)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppSpacing.group)
                        .padding(.vertical, AppSpacing.row)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Step \(index + 1), \(step)")

                        if index < instructionSteps.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
            }
            .accessibilityIdentifier("meal_suggestion_instructions")
        }
    }

    private var bottomActionBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    logButton
                    if onRegenerate != nil {
                        regenerateButton
                    }
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    if onRegenerate != nil {
                        regenerateButton
                    }
                    logButton
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppPalette.separator)
                .frame(height: 1)
        }
        .dynamicTypeSize(.xSmall ... .accessibility1)
    }

    private var logButton: some View {
        Button {
            onLog(suggestion)
            dismiss()
        } label: {
            Label("Log Estimate", systemImage: "plus.circle.fill")
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .disabled(isRegenerating)
        .accessibilityIdentifier("meal_suggestion_log")
    }

    private var regenerateButton: some View {
        Button {
            onRegenerate?()
        } label: {
            HStack(spacing: AppSpacing.compact) {
                if isRegenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(isRegenerating ? "Finding Another" : "Suggest Another")
            }
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .disabled(isRegenerating)
        .accessibilityIdentifier("meal_suggestion_regenerate")
    }

    private var hasPantryContext: Bool {
        pantryItemNames.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func ingredientUsesPantry(_ ingredient: String) -> Bool {
        MealSuggestionReviewRules.ingredientUsesPantry(
            ingredient,
            pantryNames: pantryItemNames
        )
    }

    private func safe(_ value: Double) -> Double {
        MealSuggestionReviewRules.safeValue(value)
    }

    private func formatted(_ value: Double) -> String {
        Int(safe(value).rounded()).formatted()
    }
}

private struct MealSuggestionMacroFitRow: View {
    struct Model: Identifiable {
        var id: String { title }
        let title: String
        let planned: Double
        let target: Double?
        let unit: String
        let color: Color
        let tolerance: Double
    }

    let model: Model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var delta: Double? {
        guard let target = model.target else { return nil }
        return model.planned - target
    }

    private var statusText: String {
        guard let delta else { return "No Target" }
        if abs(delta) <= model.tolerance { return "On Target" }
        return delta > 0
            ? "+\(Int(delta.rounded()).formatted()) \(model.unit)"
            : "-\(Int(abs(delta).rounded()).formatted()) \(model.unit)"
    }

    private var statusColor: Color {
        guard let delta else { return .secondary }
        return abs(delta) <= model.tolerance ? .accentPositive : AppPalette.caution
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    metricIdentity
                    statusLabel
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    metricIdentity
                    Spacer(minLength: AppSpacing.compact)
                    statusLabel
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.title), \(targetText), \(statusText)")
    }

    private var metricIdentity: some View {
        HStack(spacing: AppSpacing.row) {
            Circle()
                .fill(model.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(targetText)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var statusLabel: some View {
        Text(statusText)
            .appTextRole(.caption)
            .foregroundStyle(statusColor)
            .padding(.horizontal, AppSpacing.compact)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.10), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var targetText: String {
        guard let target = model.target else {
            return "\(Int(model.planned.rounded()).formatted()) \(model.unit) estimated"
        }
        return "\(Int(model.planned.rounded()).formatted()) of \(Int(target.rounded()).formatted()) \(model.unit)"
    }
}

private struct MealSuggestionIngredientRow: View {
    let ingredient: String
    let isPantryMatch: Bool
    let hasPantryContext: Bool

    private var tint: Color {
        isPantryMatch ? .accentPositive : .secondary
    }

    private var icon: String {
        guard hasPantryContext else { return "circle" }
        return isPantryMatch ? "checkmark.circle.fill" : "plus.circle"
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 17, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(ingredient)
                .appTextRole(.body)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ingredient)
        .accessibilityValue(
            hasPantryContext ? (isPantryMatch ? "Pantry match" : "Optional item") : "No pantry context"
        )
    }
}
