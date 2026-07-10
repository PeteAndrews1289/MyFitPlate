import SwiftUI

struct MealSuggestionDetailView: View {
    @Environment(\.dismiss) var dismiss

    let suggestion: MealSuggestion
    var pantryItemNames: [String] = []
    var remainingCalories: Double?
    var remainingProtein: Double?
    var remainingCarbs: Double?
    var remainingFats: Double?
    var onLog: (MealSuggestion) -> Void
    var onRegenerate: (() -> Void)?
    var isRegenerating: Bool = false

    private var normalizedPantryNames: [String] {
        pantryItemNames
            .map(normalizedIngredient)
            .filter { $0.count >= 3 }
    }

    private var matchedIngredients: [String] {
        suggestion.ingredients.filter(ingredientUsesPantry)
    }

    private var optionalIngredients: [String] {
        suggestion.ingredients.filter { !ingredientUsesPantry($0) }
    }

    private var macroRows: [MealSuggestionMacroFitRow.Model] {
        [
            MealSuggestionMacroFitRow.Model(
                title: "Calories",
                planned: suggestion.calories,
                target: remainingCalories,
                unit: "cal",
                color: .orange,
                tolerance: 75
            ),
            MealSuggestionMacroFitRow.Model(
                title: "Protein",
                planned: suggestion.protein,
                target: remainingProtein,
                unit: "g",
                color: .accentProtein,
                tolerance: 8
            ),
            MealSuggestionMacroFitRow.Model(
                title: "Carbs",
                planned: suggestion.carbs,
                target: remainingCarbs,
                unit: "g",
                color: .accentCarbs,
                tolerance: 12
            ),
            MealSuggestionMacroFitRow.Model(
                title: "Fats",
                planned: suggestion.fats,
                target: remainingFats,
                unit: "g",
                color: .accentFats,
                tolerance: 6
            )
        ]
    }

    private var fitSummary: String {
        guard let remainingCalories else {
            return "Review the estimate and adjust portions before logging."
        }

        let delta = suggestion.calories - remainingCalories
        if abs(delta) <= 75 {
            return "Fits your remaining calories closely."
        }

        if delta < 0 {
            return "\(Int(abs(delta).rounded()).formatted()) cal under your remaining target."
        }

        return "\(Int(delta.rounded()).formatted()) cal over your remaining target; adjust portions if you need a tighter day."
    }

    private var pantrySummary: String {
        guard !suggestion.ingredients.isEmpty else {
            return "Maia did not return ingredient detail for this estimate."
        }

        guard !pantryItemNames.isEmpty else {
            return "No pantry context was used; treat this as a general meal idea."
        }

        if optionalIngredients.isEmpty {
            return "Everything Maia listed appears to match your pantry."
        }

        return "\(matchedIngredients.count) pantry match\(matchedIngredients.count == 1 ? "" : "es"), \(optionalIngredients.count) optional item\(optionalIngredients.count == 1 ? "" : "s")."
    }

    private var substitutionGuidance: [String] {
        var guidance: [String] = []

        if let remainingCalories, suggestion.calories > remainingCalories + 100 {
            guidance.append("Lower calories by reducing oil, cheese, nuts, sauces, or the starch portion.")
        }

        if let remainingProtein, suggestion.protein + 8 < remainingProtein, remainingProtein >= 15 {
            guidance.append("Add a protein anchor: Greek yogurt, egg whites, tuna, tofu, lean meat, or a protein shake.")
        }

        if let remainingCarbs, suggestion.carbs > remainingCarbs + 15 {
            guidance.append("Swap part of the starch for vegetables or berries.")
        }

        if !optionalIngredients.isEmpty && !pantryItemNames.isEmpty {
            guidance.append("Swap optional items for similar pantry staples before logging.")
        }

        if guidance.isEmpty {
            guidance.append("Looks close enough to log; adjust portions if your actual serving changes.")
        }

        return guidance
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroSection
                    macroFitSection
                    pantrySection
                    substitutionSection
                    instructionsSection
                    logButton
                    if onRegenerate != nil {
                        regenerateButton
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Meal suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.orange)
                    .frame(width: 42, height: 42)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.mealName)
                        .appFont(size: 24, weight: .heavy)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(fitSummary)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                MealSuggestionMetricPill(title: "Cal", value: formatted(suggestion.calories), color: .orange)
                MealSuggestionMetricPill(title: "P", value: "\(formatted(suggestion.protein))g", color: .accentProtein)
                MealSuggestionMetricPill(title: "C", value: "\(formatted(suggestion.carbs))g", color: .accentCarbs)
                MealSuggestionMetricPill(title: "F", value: "\(formatted(suggestion.fats))g", color: .accentFats)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var macroFitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Macro fit", systemImage: "target")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)

            VStack(spacing: 10) {
                ForEach(macroRows) { row in
                    MealSuggestionMacroFitRow(model: row)
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var pantrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pantry fit", systemImage: pantryItemNames.isEmpty ? "cabinet" : "cabinet.fill")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)

            Text(pantrySummary)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            if !suggestion.ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(suggestion.ingredients, id: \.self) { ingredient in
                        MealSuggestionIngredientRow(
                            ingredient: ingredient,
                            isPantryMatch: ingredientUsesPantry(ingredient),
                            hasPantryContext: !pantryItemNames.isEmpty
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var substitutionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Adjust before logging", systemImage: "slider.horizontal.3")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(substitutionGuidance, id: \.self) { note in
                    Label(note, systemImage: "arrow.triangle.2.circlepath")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var instructionsSection: some View {
        if !suggestion.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Instructions", systemImage: "list.bullet.clipboard")
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(suggestion.instructions)
                    .appFont(size: 14)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var logButton: some View {
        Button {
            onLog(suggestion)
            dismiss()
        } label: {
            Label("Log estimate", systemImage: "plus.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, 4)
    }

    private var regenerateButton: some View {
        Button {
            onRegenerate?()
        } label: {
            HStack(spacing: 8) {
                if isRegenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(isRegenerating ? "Finding another idea…" : "Suggest another")
                    .appFont(size: 15, weight: .bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.backgroundSecondary.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundColor(.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(isRegenerating)
    }

    private func ingredientUsesPantry(_ ingredient: String) -> Bool {
        let normalized = normalizedIngredient(ingredient)
        guard normalized.count >= 3 else { return false }
        return normalizedPantryNames.contains { pantryName in
            normalized.contains(pantryName) || pantryName.contains(normalized)
        }
    }

    private func normalizedIngredient(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func formatted(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}

private struct MealSuggestionMetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(size: 10, weight: .bold)
                .foregroundColor(color)
            Text(value)
                .appFont(size: 13, weight: .heavy)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var delta: Double? {
        guard let target = model.target else { return nil }
        return model.planned - target
    }

    private var statusText: String {
        guard let delta else { return "No target" }
        if abs(delta) <= model.tolerance { return "On target" }
        return delta > 0
            ? "+\(Int(delta.rounded()).formatted()) \(model.unit)"
            : "-\(Int(abs(delta.rounded())).formatted()) \(model.unit)"
    }

    private var statusColor: Color {
        guard let delta else { return Color(UIColor.secondaryLabel) }
        return abs(delta) <= model.tolerance ? .accentPositive : .orange
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.color.opacity(0.16))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(String(model.title.prefix(1)))
                        .appFont(size: 12, weight: .heavy)
                        .foregroundColor(model.color)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(targetText)
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer()

            Text(statusText)
                .appFont(size: 12, weight: .heavy)
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.10), in: Capsule())
        }
    }

    private var targetText: String {
        guard let target = model.target else {
            return "\(Int(model.planned.rounded()).formatted()) \(model.unit)"
        }
        return "\(Int(model.planned.rounded()).formatted()) / \(Int(target.rounded()).formatted()) \(model.unit)"
    }
}

private struct MealSuggestionIngredientRow: View {
    let ingredient: String
    let isPantryMatch: Bool
    let hasPantryContext: Bool

    private var tint: Color {
        isPantryMatch ? .accentPositive : Color(UIColor.secondaryLabel)
    }

    private var icon: String {
        guard hasPantryContext else { return "circle" }
        return isPantryMatch ? "checkmark.circle.fill" : "plus.circle"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(tint)
                .frame(width: 18)
            Text(ingredient)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
