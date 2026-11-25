import SwiftUI
import MyFitPlateCore

struct FoodCaptureButton: View {
    let title: String
    let symbol: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).appTextRole(.control)
                Text(title).appTextRole(.caption)
            }
            .foregroundStyle(AppPalette.text)
            .frame(minWidth: 44, minHeight: 44)
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct YesterdayLogActions: View {
    let selectedMeal: String
    let mealItemCount: Int
    let mealCalories: Double
    let dayItemCount: Int
    let dayCalories: Double
    let onLogMeal: () -> Void
    let onLogDay: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Copy yesterday")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AppSpacing.compact) {
                        yesterdayMealButton
                        yesterdayDayButton
                    }
                } else {
                    HStack(spacing: AppSpacing.compact) {
                        yesterdayMealButton
                        yesterdayDayButton
                    }
                }
            }
        }
        .appSurface(.quiet, padding: AppSpacing.row)
    }

    @ViewBuilder
    private var yesterdayMealButton: some View {
        if mealItemCount > 0 {
            yesterdayButton(
                title: selectedMeal,
                detail: detailText(count: mealItemCount, calories: mealCalories),
                icon: "clock.arrow.circlepath",
                isEnabled: true,
                action: onLogMeal
            )
        }
    }

    private var yesterdayDayButton: some View {
        yesterdayButton(
            title: "Full day",
            detail: detailText(count: dayItemCount, calories: dayCalories),
            icon: "calendar.badge.plus",
            isEnabled: dayItemCount > 0,
            action: onLogDay
        )
    }

    private func detailText(count: Int, calories: Double) -> String {
        guard count > 0 else { return "No items" }
        return "\(count.formatted()) \(count == 1 ? "item" : "items") • \(Int(calories.rounded()).formatted()) cal"
    }

    private func yesterdayButton(title: String, detail: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .appTextRole(.body)
                    .foregroundStyle(isEnabled ? Color.secondary : Color.gray.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appTextRole(.body)
                        .foregroundStyle(isEnabled ? AppPalette.text : Color.secondary)
                        .lineLimit(1)

                    Text(detail)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 84,
                alignment: .leading
            )
            .padding(AppSpacing.row)
            .background(AppPalette.canvas.opacity(isEnabled ? 1 : 0.55), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
