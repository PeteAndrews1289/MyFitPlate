import MyFitPlateCore
import SwiftUI

struct MealSuggestionCardView: View {
    let suggestion: MealSuggestion?
    var onGenerate: () -> Void
    var onTap: () -> Void
    var onPrefs: () -> Void
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(
                title: "Maia Suggestion",
                subtitle: "An estimated meal shaped around today's remaining targets."
            ) {
                HStack(spacing: AppSpacing.compact) {
                    Button(action: onPrefs) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .disabled(isLoading)
                    .accessibilityLabel("Meal suggestion preferences")

                    Button(action: onGenerate) {
                        Image(systemName: "sparkles")
                    }
                    .buttonStyle(AppIconButtonStyle(.brand))
                    .disabled(isLoading)
                    .accessibilityLabel("Generate meal suggestion")
                }
            }
            .padding(AppSpacing.group)

            Divider()

            suggestionContent
        }
        .appSurface(.emphasized, padding: 0)
        .accessibilityIdentifier("meal_suggestion_card")
    }

    @ViewBuilder
    private var suggestionContent: some View {
        if isLoading {
            HStack(spacing: AppSpacing.row) {
                ProgressView()
                    .tint(AppPalette.brand)
                Text("Finding a Meal")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .center)
            .padding(AppSpacing.group)
            .accessibilityElement(children: .combine)
        } else if let suggestion {
            Button(action: onTap) {
                AppListRow(
                    icon: "fork.knife",
                    iconColor: .orange,
                    title: suggestion.mealName,
                    subtitle: nutritionLine(for: suggestion)
                ) {
                    Image(systemName: "chevron.right")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the estimated recipe and macro fit")
        } else {
            AppListRow(
                icon: "sparkles",
                iconColor: AppPalette.brand,
                title: "No Suggestion Yet",
                subtitle: "Generate an idea when you want help using today's remaining targets."
            )
        }
    }

    private func nutritionLine(for suggestion: MealSuggestion) -> String {
        "AI estimate · \(formatted(suggestion.calories)) cal · "
            + "P \(formatted(suggestion.protein)) g · "
            + "C \(formatted(suggestion.carbs)) g · "
            + "F \(formatted(suggestion.fats)) g"
    }

    private func formatted(_ value: Double) -> String {
        Int(MealSuggestionReviewRules.safeValue(value).rounded()).formatted()
    }
}
