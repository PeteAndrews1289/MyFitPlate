import SwiftUI

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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                Text(title)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color.backgroundSecondary.opacity(0.78), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copy yesterday")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 10) {
                yesterdayButton(
                    title: selectedMeal,
                    detail: detailText(count: mealItemCount, calories: mealCalories),
                    icon: "clock.arrow.circlepath",
                    isEnabled: mealItemCount > 0,
                    action: onLogMeal
                )

                yesterdayButton(
                    title: "Full day",
                    detail: detailText(count: dayItemCount, calories: dayCalories),
                    icon: "calendar.badge.plus",
                    isEnabled: dayItemCount > 0,
                    action: onLogDay
                )
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailText(count: Int, calories: Double) -> String {
        guard count > 0 else { return "No items" }
        return "\(count.formatted()) \(count == 1 ? "item" : "items") • \(Int(calories.rounded()).formatted()) cal"
    }

    private func yesterdayButton(title: String, detail: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(isEnabled ? Color(UIColor.secondaryLabel) : Color(UIColor.tertiaryLabel))
                    .frame(width: 30, height: 30)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(isEnabled ? .textPrimary : Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    Text(detail)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(12)
            .background(Color.backgroundPrimary.opacity(isEnabled ? 0.78 : 0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
