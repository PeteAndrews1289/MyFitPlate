import MyFitPlateCore
import SwiftUI

/// The same value-only portion proposal is used before planning or consuming a recipe.
struct RecipePortionPicker: View {
    let recipe: Recipe
    @Binding var unit: RecipePortionUnit
    @Binding var amountText: String
    var identifier = "recipe_portion"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var amountFocused: Bool

    private var selection: RecipePortionSelection {
        RecipePortionSelection(unit: unit, amount: Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? .nan)
    }

    private var snapshot: RecipePortionSnapshot? { try? RecipePortionRules.snapshot(for: recipe, selection: selection) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Your portion", subtitle: "This amount applies to this meal. The saved batch stays unchanged.")
            if RecipePortionRules.availableUnits(for: recipe).count > 1 {
                Picker("Measure by", selection: $unit) {
                    ForEach(RecipePortionRules.availableUnits(for: recipe)) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier("\(identifier)_unit")
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(amountLabel).appTextRole(.body)
                    amountInput
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                    Text(amountLabel).appTextRole(.body)
                    Spacer(minLength: AppSpacing.compact)
                    amountInput
                }
            }
            if let snapshot {
                if let servings = snapshot.servingsEquivalent, let fraction = snapshot.batchFraction {
                    Text("\(servings.formatted(.number.precision(.fractionLength(0...3)))) servings · \((fraction * 100).formatted(.number.precision(.fractionLength(0...1))))% of the batch")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(identifier)_equivalent")
                }
                if let grams = snapshot.cookedGrams {
                    Text("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g cooked · measured batch \((recipe.cookedWeightGrams ?? 0).formatted(.number.precision(.fractionLength(0...1)))) g")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Enter a valid portion greater than zero.")
                    .appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("\(identifier)_error")
            }
            if recipe.nutritionBasis == nil {
                Text("The original nutrition basis is unconfirmed. This keeps its saved amount; confirm the batch yield in Edit recipe to use servings or cooked grams.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            } else if recipe.cookedWeightGrams == nil {
                Text("To use grams, measure the finished batch and add its cooked weight in Edit recipe. Raw ingredient weight is a different measure.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if amountFocused {
                    Spacer()
                    Button { amountFocused = false } label: {
                        Text("Done").appFont(size: 17, weight: .medium)
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .foregroundStyle(AppPalette.text)
                    .accessibilityIdentifier("\(identifier)_done")
                }
            }
        }
        .onChange(of: unit) { old, new in
            let oldSelection = RecipePortionSelection(unit: old, amount: selection.amount)
            guard let previous = try? RecipePortionRules.snapshot(for: recipe, selection: oldSelection) else { return }
            let amount: Double?
            switch new {
            case .servings: amount = previous.servingsEquivalent
            case .batchFraction: amount = previous.batchFraction
            case .cookedGrams: amount = previous.cookedGrams
            case .savedAmount: amount = previous.selection.amount
            }
            // Keep round-trippable input precision; display-only rounding must not become
            // the canonical amount when the user switches units repeatedly.
            if let amount { amountText = String(amount) }
        }
    }

    private var amountLabel: String {
        unit == .cookedGrams ? "Cooked amount" : unit == .batchFraction ? "Fraction of batch" : "Amount"
    }

    private var amountInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
            TextField("1", text: $amountText)
                .focused($amountFocused)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .appTextRole(.body).monospacedDigit()
                .frame(minWidth: 64, maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 110, minHeight: 44)
                .accessibilityLabel(unit.title)
                .accessibilityIdentifier("\(identifier)_amount")
            Text(unit.quantityUnit).appFont(size: 13).foregroundStyle(.secondary)
        }
    }
}
