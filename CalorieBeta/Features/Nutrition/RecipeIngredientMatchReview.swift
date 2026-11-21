import MyFitPlateCore
import SwiftUI

struct RecipeIngredientMatchReview: View {
    let sourceText: String
    let onConfirmed: (FoodItem) -> Void
    private let suggestion: RecipeIngredientMatchSuggestion
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var amountReviewed = false
    @FocusState private var editingAmount: Bool

    init(sourceText: String, selectedFood: FoodItem, onConfirmed: @escaping (FoodItem) -> Void) {
        self.sourceText = sourceText
        self.onConfirmed = onConfirmed
        let suggestion = RecipeIngredientMatchRules.suggestion(sourceText: sourceText, selectedFood: selectedFood)
        self.suggestion = suggestion
        _amountText = State(initialValue: (suggestion.food.quantityValue ?? 1)
            .formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3))))
    }

    private var reviewedFood: FoodItem? {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return RecipeIngredientMatchRules.reviewedAmount(amount, for: suggestion.food)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(title: "Original ingredient", subtitle: "This text stays in the recipe until you confirm the replacement.")
                        Text(sourceText).appTextRole(.body).textSelection(.enabled)
                            .accessibilityIdentifier("recipe_match_original")
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(title: "Matched food", subtitle: suggestion.food.name)
                        Text(suggestion.explanation).appTextRole(.secondary)
                            .foregroundStyle(suggestion.sourceAmountMatched ? .secondary : AppPalette.caution)
                            .accessibilityIdentifier("recipe_match_explanation")
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                            TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                                .focused($editingAmount).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                                .accessibilityLabel("Matched ingredient amount")
                                .accessibilityIdentifier("recipe_match_amount")
                            Text(suggestion.food.servingUnit ?? "selected amount").appTextRole(.secondary)
                        }
                        if let food = reviewedFood {
                            Text("\(food.calories.formatted(.number.precision(.fractionLength(0...1)))) cal · P \(food.protein.formatted(.number.precision(.fractionLength(0...1)))) g · C \(food.carbs.formatted(.number.precision(.fractionLength(0...1)))) g · F \(food.fats.formatted(.number.precision(.fractionLength(0...1)))) g")
                                .appTextRole(.secondary)
                                .accessibilityIdentifier("recipe_match_nutrition")
                        } else {
                            Text("Enter an amount greater than zero, up to 1,000,000.")
                                .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        }
                        if !suggestion.sourceAmountMatched {
                            Toggle("I've checked this amount against the original ingredient", isOn: $amountReviewed)
                                .frame(minHeight: 44).accessibilityIdentifier("recipe_match_amount_reviewed")
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal).padding(.vertical, AppSpacing.group)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recipe_match_review")
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Review ingredient").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("recipe_match_cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingAmount = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let food = reviewedFood, suggestion.sourceAmountMatched || amountReviewed else { return }
                    onConfirmed(food); dismiss()
                } label: {
                    Text("Confirm ingredient").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(reviewedFood == nil || !suggestion.sourceAmountMatched && !amountReviewed)
                .accessibilityIdentifier("recipe_match_confirm")
                .padding(.horizontal, AppSpacing.screenHorizontal).padding(.vertical, AppSpacing.row)
                .background(AppPalette.canvas)
            }
        }
    }
}
