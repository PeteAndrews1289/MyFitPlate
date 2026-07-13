import SwiftUI
import MyFitPlateCore

// DESIGN.md rule 1: search is this screen's hero. The alternate logging paths are one
// compact, horizontally scrollable row of chips (~44pt) instead of a 2x3 grid of 82pt
// tiles (~280pt) — the user's saved and recent foods rise above the fold, where the
// actual logging happens.
struct FoodSearchActionGrid: View {
    let manualAction: () -> Void
    let quickAddAction: () -> Void
    let cameraAction: () -> Void
    let menuAction: () -> Void
    let barcodeAction: () -> Void
    let textAction: () -> Void
    let valueRadarAction: () -> Void
    let chainBuilderAction: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FoodSearchActionChip(title: "Fast Food", icon: "takeoutbag.and.cup.and.straw.fill", action: chainBuilderAction)
                FoodSearchActionChip(title: "Barcode", icon: "barcode.viewfinder", action: barcodeAction)
                FoodSearchActionChip(title: "Camera", icon: "camera.fill", action: cameraAction)
                FoodSearchActionChip(title: "Describe", icon: "text.bubble.fill", action: textAction)
                FoodSearchActionChip(title: "Menu", icon: "list.bullet.rectangle.portrait.fill", action: menuAction)
                FoodSearchActionChip(title: "Value Radar", icon: "chart.pie.fill", action: valueRadarAction)
                FoodSearchActionChip(title: "Quick macros", icon: "bolt.fill", action: quickAddAction)
                FoodSearchActionChip(title: "Manual", icon: "square.and.pencil", action: manualAction)
            }
        }
    }
}

struct FoodSearchActionChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.compact) {
                Image(systemName: icon)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)

                Text(title)
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSpacing.row)
            .frame(minHeight: 44)
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator.opacity(0.55), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("food_search_action_\(identifier)")
    }

    private var identifier: String {
        title
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
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
