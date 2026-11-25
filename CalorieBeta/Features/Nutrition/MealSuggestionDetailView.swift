import MyFitPlateCore
import SwiftUI

struct MealSuggestionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsMacroDetails = false
    @State private var isLogging = false
    @State private var saveError: String?

    let suggestion: MealSuggestion
    var pantryItemNames: [String] = []
    var remainingCalories: Double?
    var remainingProtein: Double?
    var remainingCarbs: Double?
    var remainingFats: Double?
    var onLog: (MealSuggestion, @escaping (Bool) -> Void) -> Void
    var onRegenerate: (() -> Void)?
    var isRegenerating = false
    var destinationSummary: String?
    var savedError: String?
    var reviewControls: AnyView?
    var isLogEnabled = true

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
            subtitle: destinationSummary ?? "Review Maia's estimate against today's remaining targets.",
            dismiss: { if !isLogging { dismiss() } }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    suggestionHeader
                    nutritionSummary
                    if let reviewControls { reviewControls }
                    feasibilitySection
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
        .interactiveDismissDisabled(isRegenerating || isLogging)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_suggestion_detail_screen")
    }

    private var suggestionHeader: some View {
        AppScreenHeader(eyebrow: "Maia estimate", title: suggestion.mealName, subtitle: fitSummary)
            .accessibilityIdentifier("meal_suggestion_header")
    }

    private var nutritionSummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(label: "Calories", value: "\(formatted(suggestion.calories)) cal", accent: AppPalette.energy),
            AppMetricItem(label: "Protein", value: "\(formatted(suggestion.protein)) g", accent: .accentProtein),
            AppMetricItem(label: "Carbs", value: "\(formatted(suggestion.carbs)) g", accent: .accentCarbs),
            AppMetricItem(label: "Fat", value: "\(formatted(suggestion.fats)) g", accent: .accentFats)
        ])
        .appSurface(.interpreted)
        .accessibilityIdentifier("meal_suggestion_nutrition_summary")
    }

    private var feasibilitySection: some View {
        let evidence = suggestion.feasibility ?? MealSuggestionFeasibilityRules.generatedEvidence(for: suggestion)
        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let minutes = evidence.prepMinutes {
                Label("About \(minutes) min · Maia prep estimate", systemImage: "clock").appTextRole(.secondary)
            } else { Text("Preparation time has not been estimated.").appTextRole(.secondary) }
            Text("One proposed serving. Ingredient amounts and nutrition remain estimates until matched to actual products or your recipe.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Ingredient quantities and sources") {
                ForEach(evidence.ingredients) { ingredient in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ingredient.description).appTextRole(.secondary)
                        Text(ingredient.isResolved ? "Linked food: \(ingredient.source)" : "Maia estimate · \(ingredient.quantityText == nil ? "quantity not specified" : "proposed amount, not a verified conversion")")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }.appTextRole(.secondary)
        }.appSurface(.quiet).accessibilityIdentifier("meal_suggestion_feasibility")
    }

    private var macroFitSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Macro Fit",
                subtitle: "Estimated serving compared with today's remaining targets."
            )

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text(accessibilityMacroSummary)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    DisclosureGroup(isExpanded: $showsMacroDetails) {
                        macroFitRows
                            .padding(.top, AppSpacing.compact)
                    } label: {
                        Text(showsMacroDetails ? "Hide macro details" : "Review all macro details")
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.brandText)
                    }
                }
                .appSurface(.quiet)
            } else {
                macroFitRows
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
        .accessibilityIdentifier("meal_suggestion_macro_fit")
    }

    private var macroFitRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(macroRows.enumerated()), id: \.element.id) { index, row in
                MealSuggestionMacroFitRow(model: row)

                if index < macroRows.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }

    private var accessibilityMacroSummary: String {
        let values = macroRows.prefix(2).map { row in
            guard let target = row.target else {
                return "\(row.title) \(Int(row.planned.rounded())) \(row.unit)"
            }
            return "\(row.title) \(Int(row.planned.rounded())) of \(Int(target.rounded())) \(row.unit)"
        }
        return values.joined(separator: " · ")
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
                                .foregroundStyle(AppPalette.brandText)
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
        VStack(spacing: AppSpacing.compact) {
            if let visibleError = savedError ?? saveError {
                Text(visibleError)
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("meal_suggestion_save_error")
            }
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
            guard !isLogging else { return }
            isLogging = true
            saveError = nil
            onLog(suggestion) { accepted in
                isLogging = false
                if accepted {
                    dismiss()
                } else {
                    saveError = "Couldn't save this meal. Your suggestion is still here; try again."
                }
            }
        } label: {
            Label(isLogging ? "Saving…" : "Log estimate", systemImage: "plus.circle.fill")
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .disabled(isRegenerating || isLogging || !isLogEnabled)
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
        .disabled(isRegenerating || isLogging)
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

/// The review owns the destination, full suggestion and retry identity before a log starts.
/// Every entry point uses the existing diary save session; this view never writes food itself.
struct SavedMealSuggestionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var goalSettings: GoalSettings
    @ObservedObject var review: MealReviewSaveSession
    var pantryItemNames: [String] = []
    var remainingCalories: Double?
    var remainingProtein: Double?
    var remainingCarbs: Double?
    var remainingFats: Double?
    var onRegenerate: (() -> Void)?
    var isRegenerating = false
    var onAccepted: (() -> Void)?
    var onDiscarded: (() -> Void)?
    @State private var confirmsDiscard = false
    @State private var showingFoodPreferences = false
    @State private var recipeDraft: Recipe?

    var body: some View {
        if let suggestion = review.checkpoint.mealSuggestion {
            MealSuggestionDetailView(
                suggestion: suggestion, pantryItemNames: pantryItemNames,
                remainingCalories: review.checkpoint.trainingFuelTarget.map { Double($0.calories) } ?? remainingCalories,
                remainingProtein: review.checkpoint.trainingFuelTarget.map { Double($0.proteinGrams) } ?? remainingProtein,
                remainingCarbs: review.checkpoint.trainingFuelTarget.map { Double($0.carbGrams) } ?? remainingCarbs,
                remainingFats: review.checkpoint.trainingFuelTarget == nil ? remainingFats : nil,
                onLog: { _, completion in
                    review.save(using: dailyLogService) { accepted in
                        completion(accepted)
                        if accepted { onAccepted?() }
                    }
                },
                onRegenerate: review.isLocked ? nil : onRegenerate,
                isRegenerating: isRegenerating,
                destinationSummary: "\(review.mealName) · \(review.checkpoint.draft.dayContext?.dayKey ?? review.date.formatted(date: .abbreviated, time: .omitted))",
                savedError: review.errorMessage,
                reviewControls: AnyView(reviewControls),
                isLogEnabled: review.isSubmitted || ingredientAssessment?.canAccept != false
            )
            .sheet(item: $recipeDraft) { recipe in CreateRecipeView(initialDraft: recipe) }
            .sheet(isPresented: $showingFoodPreferences) { SuggestionPreferencesView(goalSettings: goalSettings) }
            .confirmationDialog("Discard this meal suggestion?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard suggestion", role: .destructive) {
                    if review.discard() { onDiscarded?(); dismiss() }
                }
            } message: { Text("Only this unsubmitted suggestion is removed. Your saved food logs stay intact.") }
        } else {
            Text("This saved review could not be opened. Its checkpoint is kept on this device.").padding()
        }
    }

    private var ingredientAssessment: MealConstraintAssessment? {
        review.ingredientAssessment(profile: goalSettings.effectiveMealConstraintProfile)
    }

    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if review.isSubmitted {
                Label("Save awaiting confirmation", systemImage: "arrow.clockwise")
                    .appTextRole(.control)
                Text("Retry uses these exact foods and this destination, even if you browse another day.")
                    .appTextRole(.secondary)
            } else {
                if let budget = review.pendingBudgetReview {
                    Text("Remaining on \(budget.day.dayKey): \(Int(budget.remaining.calories)) cal · \(Int(budget.remaining.protein))g protein · \(Int(budget.remaining.carbs))g carbs · \(Int(budget.remaining.fats))g fat")
                        .appTextRole(.secondary).accessibilityIdentifier("meal_suggestion_changed_budget")
                    if review.checkpoint.suggestionBudget?.acceptsAboveBudget != true || review.checkpoint.suggestionBudget?.sameEvidence(as: budget) != true {
                        Button("I reviewed this; log above the remaining targets") { _ = review.acceptChangedSuggestionBudget() }
                            .accessibilityIdentifier("meal_suggestion_accept_changed_budget")
                    } else { Text("Reviewed. Log estimate checks this day again before saving.").appTextRole(.caption) }
                }
                Menu("Suggestion options", systemImage: "ellipsis") {
                if onRegenerate != nil {
                    Menu("Change this idea") {
                        ForEach(MealSuggestionAlternativeReason.allCases, id: \.rawValue) { reason in
                            Button(reason.title) { if review.requestAlternative(reason) { onRegenerate?() } }
                        }
                    }.accessibilityIdentifier("meal_suggestion_alternatives")
                }
                if review.checkpoint.alternativeHistory?.isEmpty == false {
                    Button("Return to the previous idea") { _ = review.restorePreviousSuggestion() }
                        .accessibilityIdentifier("meal_suggestion_previous")
                }
                if ingredientAssessment?.canAccept != false {
                    Button("Review as a reusable recipe") {
                        guard review.userID == DIContainer.shared.authService.currentUserID else { return }
                        recipeDraft = review.checkpoint.mealSuggestion?.recipeDraft
                    }
                        .accessibilityIdentifier("meal_suggestion_recipe")
                }
                Button("Change food preferences") { showingFoodPreferences = true }
                    .accessibilityIdentifier("meal_suggestion_preferences")
                    Button("Discard suggestion", role: .destructive) { confirmsDiscard = true }
                        .accessibilityIdentifier("meal_suggestion_discard")
                }.appTextRole(.secondary).tint(AppPalette.text).frame(minHeight: 44)
                    .accessibilityIdentifier("meal_suggestion_options")
                if let assessment = ingredientAssessment, !assessment.canAccept {
                    Text("Ingredient review").appTextRole(.control)
                    ForEach(assessment.issues) { issue in
                        Text(issue.message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    }
                    if assessment.needsPersonalReview {
                        Button("I reviewed the ingredients and product labels") {
                            _ = review.confirmIngredientReview(profile: goalSettings.effectiveMealConstraintProfile)
                        }.accessibilityIdentifier("meal_suggestion_confirm_ingredients")
                    }
                } else if review.checkpoint.ingredientReview != nil {
                    Label("Personal ingredient review saved", systemImage: "checkmark.circle")
                        .appTextRole(.secondary).accessibilityIdentifier("meal_suggestion_ingredients_reviewed")
                }
                if review.restoredReview {
                    Text("Resumed saved suggestion").appTextRole(.secondary)
                }
                if review.checkpoint.trainingFuelTarget != nil {
                    Button("Log without the fuel link") { _ = review.removeFuelContext() }
                        .accessibilityIdentifier("meal_suggestion_detach_fuel")
                }

            }
        }
        .disabled(review.isSaving || isRegenerating)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_suggestion_saved_review")
    }
}
